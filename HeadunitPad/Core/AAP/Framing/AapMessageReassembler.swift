//
//  AapMessageReassembler.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AapMessageReassembler.kt
//

import Foundation

public enum AapReassemblyError: Error, CustomStringConvertible {
    case invalidChannel(Int)
    case routingChanged(Int)

    public var description: String {
        switch self {
        case .invalidChannel(let ch):
            return "Invalid AAP channel \(ch)"
        case .routingChanged(let ch):
            return "AAP fragment routing changed on channel \(ch)"
        }
    }
}

public final class AapMessageReassembler {
    public static let maxMessageBytes = 8 * 1024 * 1024
    private static let maxReservedBytes = 16 * 1024 * 1024

    private final class Run {
        let first: AapMessage
        let total: Int
        let video: Bool
        var bytes: Data?
        var used: Int = 0
        var discarded: Bool = false
        var typeBytes: Int = 0
        var type: Int = 0

        init(first: AapMessage, total: Int, video: Bool, bytes: Data?) {
            self.first = first
            self.total = total
            self.video = video
            self.bytes = bytes
        }

        func observeType(fragment: AapMessage) {
            var offset = 0
            while typeBytes < 2 && offset < fragment.size && offset < fragment.data.count {
                type = (type << 8) | (Int(fragment.data[offset]) & 0xFF)
                offset += 1
                typeBytes += 1
            }
        }
    }

    private var runs: [Run?]
    private var reserved: Int = 0

    public var onDroppedVideoPayload: (() -> Void)?
    public var onDroppedMediaData: ((Int) -> Void)?
    public var onDrop: ((String) -> Void)?

    public init(
        onDroppedVideoPayload: (() -> Void)? = nil,
        onDroppedMediaData: ((Int) -> Void)? = nil,
        onDrop: ((String) -> Void)? = nil
    ) {
        self.runs = [Run?](repeating: nil, count: 256)
        self.onDroppedVideoPayload = onDroppedVideoPayload
        self.onDroppedMediaData = onDroppedMediaData
        self.onDrop = onDrop
    }

    public func accept(fragment: AapMessage, declaredTotal: Int) throws -> AapMessage? {
        let channel = fragment.channel
        guard channel >= 0 && channel < runs.count else {
            throw AapReassemblyError.invalidChannel(channel)
        }

        let flags = fragment.flags
        let first = AapMessageFraming.carriesMessageType(flags)
        let last = AapMessageFraming.isLast(flags)

        // TLS can consume a control record without producing a new service message.
        // Empty continuations still belong to their run, including a legal empty LAST.
        if first && fragment.size == 0 {
            return nil
        }

        if first {
            release(channel: channel, abandoned: true)
            if last {
                if fragment.size < 2 {
                    return drop(channel: channel, reason: "message has no complete type")
                }
                return fragment
            }

            // Preserve the streamed video path only when FIRST has enough prefix for its
            // downstream parser: type (2), possible timestamp (8), start code (4), and a byte beyond it (1).
            let isVideoChannel = UInt8(channel) == Channel.ID_VID
            let isControl = (flags & AapMessageFraming.FLAG_BIT_CONTROL) != 0
            let video = isVideoChannel && !isControl && (fragment.type == 0 || fragment.type == 1) && fragment.size >= 15

            let bytes: Data? = video ? nil : Data()
            runs[channel] = Run(first: fragment, total: declaredTotal, video: video, bytes: bytes)
        }

        guard let run = runs[channel] else {
            return nil // An orphan has no type; never interpret its bytes.
        }

        // FIRST/LAST change across the run; CONTROL/ENCRYPTED must not.
        if (flags & 0x0c) != (run.first.flags & 0x0c) {
            release(channel: channel)
            throw AapReassemblyError.routingChanged(channel)
        }

        run.observeType(fragment: fragment)

        if run.discarded {
            if last { release(channel: channel) }
            return nil
        }

        if first && (declaredTotal < 2 || declaredTotal > Self.maxMessageBytes || fragment.size > declaredTotal) {
            return discard(channel: channel, run: run, last: last, reason: "invalid message length \(declaredTotal)")
        }

        if run.video {
            if last { release(channel: channel) }
            return AapMessage(
                channel: channel,
                flags: fragment.flags,
                type: run.first.type,
                dataOffset: fragment.dataOffset,
                size: fragment.size,
                data: fragment.data
            )
        }

        if fragment.size > run.total - run.used {
            return discard(channel: channel, run: run, last: last, reason: "fragments exceed declared size")
        }

        let required = run.used + fragment.size
        guard var previous = run.bytes else {
            return discard(channel: channel, run: run, last: last, reason: "reassembly buffer missing")
        }

        if required > previous.count {
            let nextGrowth = max(required, max(1024, previous.count * 2))
            let maxAllowedByBudget = previous.count + Self.maxReservedBytes - reserved
            let capacity = min(run.total, min(nextGrowth, maxAllowedByBudget))

            if capacity < required {
                return discard(channel: channel, run: run, last: last, reason: "reassembly budget exhausted")
            }

            previous.count = capacity
            reserved += (capacity - previous.count)
            run.bytes = previous
        }

        let slice = fragment.data.prefix(fragment.size)
        if run.used + slice.count <= (run.bytes?.count ?? 0) {
            run.bytes?.replaceSubrange(run.used..<(run.used + slice.count), with: slice)
        } else {
            run.bytes?.append(slice)
        }
        run.used += fragment.size

        if !last { return nil }
        if run.used != run.total {
            return discard(channel: channel, run: run, last: last, reason: "incomplete message")
        }

        guard let completeBytes = run.bytes else { return nil }
        release(channel: channel)

        let msgType = (Int(completeBytes[0]) << 8) | Int(completeBytes[1])
        return AapMessage(
            channel: channel,
            flags: UInt8((flags | 3) & 0xFF),
            type: msgType,
            dataOffset: 2,
            size: run.used,
            data: completeBytes
        )
    }

    private func discard(channel: Int, run: Run, last: Bool, reason: String) -> AapMessage? {
        releaseBytes(run: run)
        run.discarded = true
        onDrop?("\(reason) on channel \(channel)")
        if last { release(channel: channel) }
        return nil
    }

    private func drop(channel: Int, reason: String) -> AapMessage? {
        release(channel: channel)
        onDrop?("\(reason) on channel \(channel)")
        return nil
    }

    private func release(channel: Int, abandoned: Bool = false) {
        guard let run = runs[channel] else { return }
        runs[channel] = nil
        releaseBytes(run: run)

        if (!run.discarded && !abandoned) || run.typeBytes != 2 || (run.first.flags & AapMessageFraming.FLAG_BIT_CONTROL) != 0 {
            return
        }

        let isVideoChannel = UInt8(channel) == Channel.ID_VID
        let isAudioChannel = Channel.isAudio(UInt8(channel))

        if run.discarded && isVideoChannel && (run.type == 0 || run.type == 1) {
            onDroppedVideoPayload?()
        }
        if (isAudioChannel || isVideoChannel) && run.type == 0 {
            onDroppedMediaData?(channel)
        }
    }

    private func releaseBytes(run: Run) {
        if let b = run.bytes {
            reserved -= b.count
        }
        run.bytes = nil
    }

    public func reset() {
        for ch in 0..<runs.count {
            release(channel: ch, abandoned: true)
        }
        reserved = 0
    }
}
