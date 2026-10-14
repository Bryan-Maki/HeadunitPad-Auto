//
//  FragmentedMessageAudit.swift
//  HeadunitPad
//
//  1:1 port of open-headunit FragmentedMessageAudit.kt
//

import Foundation

public final class FragmentedMessageAudit {
    public enum Outcome: Equatable {
        case deltaChanged
        case orphanedFragment
        case truncatedRun
    }

    public struct AuditResult: Equatable, CustomStringConvertible {
        public let channel: Int
        public let outcome: Outcome
        public let declaredTotal: Int
        public let observedTotal: Int64
        public let fragments: Int

        public var delta: Int64 {
            return Int64(declaredTotal) - observedTotal
        }

        public var description: String {
            return "channel=\(channel) fragments=\(fragments) declaredTotal=\(declaredTotal) observed=\(observedTotal) delta=\(delta)"
        }

        public init(channel: Int, outcome: Outcome, declaredTotal: Int, observedTotal: Int64, fragments: Int) {
            self.channel = channel
            self.outcome = outcome
            self.declaredTotal = declaredTotal
            self.observedTotal = observedTotal
            self.fragments = fragments
        }
    }

    public static let defaultChannelCount = 256
    public static let flagBitFirst: UInt8 = 0x01
    public static let flagBitLast: UInt8 = 0x02

    private var open: [Bool]
    private var declared: [Int]
    private var observed: [Int64]
    private var fragments: [Int]

    public init(channelCount: Int = defaultChannelCount) {
        self.open = [Bool](repeating: false, count: channelCount)
        self.declared = [Int](repeating: 0, count: channelCount)
        self.observed = [Int64](repeating: 0, count: channelCount)
        self.fragments = [Int](repeating: 0, count: channelCount)
    }

    public func onMessage(channel: Int, flags: UInt8, plaintextLength: Int, declaredTotal: Int) -> AuditResult? {
        guard channel >= 0 && channel < open.count else { return nil }
        let first = (flags & Self.flagBitFirst) != 0
        let last = (flags & Self.flagBitLast) != 0

        if first {
            let previous = open[channel] ? result(channel: channel, outcome: .truncatedRun) : nil
            open[channel] = !last
            declared[channel] = declaredTotal
            observed[channel] = Int64(plaintextLength)
            fragments[channel] = 1
            return previous
        }

        if !open[channel] {
            return AuditResult(channel: channel, outcome: .orphanedFragment, declaredTotal: 0, observedTotal: Int64(plaintextLength), fragments: 0)
        }

        observed[channel] += Int64(plaintextLength)
        fragments[channel] += 1

        if !last { return nil }
        open[channel] = false

        if observed[channel] != Int64(declared[channel]) {
            return result(channel: channel, outcome: .deltaChanged)
        }
        return nil
    }

    private func result(channel: Int, outcome: Outcome) -> AuditResult {
        return AuditResult(
            channel: channel,
            outcome: outcome,
            declaredTotal: declared[channel],
            observedTotal: observed[channel],
            fragments: fragments[channel]
        )
    }

    public func reset() {
        for i in 0..<open.count {
            open[i] = false
            declared[i] = 0
            observed[i] = 0
            fragments[i] = 0
        }
    }
}
