//
//  VideoFrameBus.swift
//  HeadunitPad
//
//  PubSub bus for decoded video frames. Caches parameter sets (H.264 SPS/PPS
//  and HEVC VPS/SPS/PPS) as well as the latest keyframe to bootstrap newly connected renderers.
//

import Foundation

public final class VideoFrameBus {
    public typealias Sink = (Data) -> Void

    public static let shared = VideoFrameBus()

    private let lock = NSLock()
    private var sinks: [UUID: Sink] = [:]
    private var latestVps: Data?
    private var latestSps: Data?
    private var latestPps: Data?
    private var latestKeyframe: Data?

    private init() {}

    @discardableResult
    public func subscribe(_ sink: @escaping Sink) -> UUID {
        let id = UUID()
        let bootstrap = currentBootstrapFrame()
        lock.lock()
        sinks[id] = sink
        lock.unlock()

        if let bootstrap {
            sink(bootstrap)
        }
        return id
    }

    public func unsubscribe(_ id: UUID) {
        lock.lock()
        sinks.removeValue(forKey: id)
        lock.unlock()
    }

    public func publish(frame: Data) {
        updateCodecCaches(with: frame)

        lock.lock()
        let callbacks = Array(sinks.values)
        lock.unlock()

        for callback in callbacks {
            callback(frame)
        }
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        latestVps = nil
        latestSps = nil
        latestPps = nil
        latestKeyframe = nil
    }

    private func currentBootstrapFrame() -> Data? {
        lock.lock()
        defer { lock.unlock() }

        var bootstrap = Data()
        if let latestVps {
            bootstrap.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
            bootstrap.append(latestVps)
        }
        if let latestSps {
            bootstrap.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
            bootstrap.append(latestSps)
        }
        if let latestPps {
            bootstrap.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
            bootstrap.append(latestPps)
        }

        if let latestKeyframe {
            bootstrap.append(latestKeyframe)
        }

        return bootstrap.isEmpty ? nil : bootstrap
    }

    private func updateCodecCaches(with frame: Data) {
        let nalUnits = splitAnnexBNALUnits(frame)
        guard !nalUnits.isEmpty else { return }

        var newVps: Data?
        var newSps: Data?
        var newPps: Data?
        var isKeyframe = false

        for nal in nalUnits {
            guard let header = nal.first else { continue }
            // AVC check
            let avcType = header & 0x1F
            if avcType == 7 { newSps = nal }
            if avcType == 8 { newPps = nal }
            if avcType == 5 { isKeyframe = true }

            // HEVC check
            let hevcType = (header & 0x7E) >> 1
            if hevcType == 32 { newVps = nal }
            if hevcType == 33 { newSps = nal }
            if hevcType == 34 { newPps = nal }
            if (16...21).contains(hevcType) { isKeyframe = true }
        }

        lock.lock()
        if let newVps { latestVps = newVps }
        if let newSps { latestSps = newSps }
        if let newPps { latestPps = newPps }
        if isKeyframe {
            latestKeyframe = frame
        }
        lock.unlock()
    }

    private func splitAnnexBNALUnits(_ data: Data) -> [Data] {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return [] }

        func startCodeLength(at i: Int) -> Int {
            if i + 3 <= bytes.count,
               bytes[i] == 0,
               bytes[i + 1] == 0,
               bytes[i + 2] == 1 {
                return 3
            }
            if i + 4 <= bytes.count,
               bytes[i] == 0,
               bytes[i + 1] == 0,
               bytes[i + 2] == 0,
               bytes[i + 3] == 1 {
                return 4
            }
            return 0
        }

        var starts: [(Int, Int)] = []
        var i = 0
        while i < bytes.count {
            let len = startCodeLength(at: i)
            if len > 0 {
                starts.append((i, len))
                i += len
            } else {
                i += 1
            }
        }

        guard !starts.isEmpty else { return [data] }

        var units: [Data] = []
        for idx in 0..<starts.count {
            let nalStart = starts[idx].0 + starts[idx].1
            let nalEnd = (idx + 1 < starts.count) ? starts[idx + 1].0 : bytes.count
            if nalStart < nalEnd {
                units.append(data.subdata(in: nalStart..<nalEnd))
            }
        }
        return units
    }
}
