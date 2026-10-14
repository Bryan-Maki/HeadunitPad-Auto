//
//  VideoFragmentAssembler.swift
//  HeadunitPad
//
//  1:1 port of open-headunit VideoFragmentAssembler.kt
//  Reassembles multi-packet video frames received over AAP video channel
//  and detects packet loss anomalies (orphaned, truncated, headless).
//

import Foundation

public final class VideoFragmentAssembler {

    public enum Action: Equatable {
        case decodeWhole(payloadOffset: Int)
        case beginAssembly(payloadOffset: Int)
        case append
        case appendAndDecode
        case discard(consumed: Bool)
    }

    public enum Anomaly: Int, CaseIterable {
        /// A 9 or 11 arrived while a run was still open: the previous frame lost its tail.
        case truncatedPrevious = 0
        /// An 8 or 10 arrived with no run open: this frame lost its head.
        case orphanedFragment = 1
        /// A first fragment whose payload begins with no start code at offset 10 or offset 2.
        case headlessFirstFragment = 2
        /// The frame grew past the reassembly buffer's ceiling.
        case overflow = 3
    }

    public struct Decision: Equatable {
        public let action: Action
        public let anomaly: Anomaly?

        public init(action: Action, anomaly: Anomaly? = nil) {
            self.action = action
            self.anomaly = anomaly
        }
    }

    public private(set) var isAssembling: Bool = false
    public private(set) var isFrameCorrupt: Bool = false

    private var counts = [Int](repeating: 0, count: Anomaly.allCases.count)

    public init() {}

    public func onMessage(flags: Int, payloadStartsAt10: Bool, payloadStartsAt2: Bool) -> Decision {
        var anomaly: Anomaly?

        switch flags {
        case Self.flagSingle, Self.flagFirst:
            if isAssembling {
                anomaly = .truncatedPrevious
            }
            isAssembling = false
            isFrameCorrupt = false

        case Self.flagMiddle, Self.flagLast:
            if !isAssembling {
                anomaly = .orphanedFragment
                isFrameCorrupt = true
            }
            if flags == Self.flagLast {
                isAssembling = false
            }

        default:
            return Decision(action: .discard(consumed: false))
        }

        if let anomaly = anomaly {
            counts[anomaly.rawValue] += 1
        }

        let payloadOffset: Int?
        if payloadStartsAt10 {
            payloadOffset = Self.offsetTimestampIndication
        } else if payloadStartsAt2 {
            payloadOffset = Self.offsetMediaIndication
        } else {
            payloadOffset = nil
        }

        switch flags {
        case Self.flagSingle:
            if let payloadOffset = payloadOffset {
                return Decision(action: .decodeWhole(payloadOffset: payloadOffset), anomaly: anomaly)
            } else {
                return Decision(action: .discard(consumed: false), anomaly: anomaly)
            }

        case Self.flagFirst:
            if let payloadOffset = payloadOffset {
                isAssembling = true
                return Decision(action: .beginAssembly(payloadOffset: payloadOffset), anomaly: anomaly)
            } else {
                isFrameCorrupt = true
                counts[Anomaly.headlessFirstFragment.rawValue] += 1
                return Decision(action: .discard(consumed: false), anomaly: .headlessFirstFragment)
            }

        case Self.flagMiddle:
            if isFrameCorrupt {
                return Decision(action: .discard(consumed: true), anomaly: anomaly)
            } else {
                return Decision(action: .append, anomaly: anomaly)
            }

        default: // flagLast
            if isFrameCorrupt {
                return Decision(action: .discard(consumed: true), anomaly: anomaly)
            } else {
                return Decision(action: .appendAndDecode, anomaly: anomaly)
            }
        }
    }

    @discardableResult
    public func onOverflow() -> Anomaly {
        isFrameCorrupt = true
        counts[Anomaly.overflow.rawValue] += 1
        return .overflow
    }

    public func countOf(_ anomaly: Anomaly) -> Int {
        return counts[anomaly.rawValue]
    }

    public func hasAnomalies() -> Bool {
        return counts.contains { $0 != 0 }
    }

    public func resetCounts() {
        counts = [Int](repeating: 0, count: Anomaly.allCases.count)
    }

    public func reset() {
        isAssembling = false
        isFrameCorrupt = false
        resetCounts()
    }

    public static func isPayload(flags: Int, payloadStartsAt10: Bool, payloadStartsAt2: Bool) -> Bool {
        switch flags {
        case flagMiddle, flagLast:
            return true
        case flagSingle, flagFirst:
            return payloadStartsAt10 || payloadStartsAt2
        default:
            return false
        }
    }

    public static let flagSingle = 11
    public static let flagFirst = 9
    public static let flagMiddle = 8
    public static let flagLast = 10

    public static let offsetTimestampIndication = 10
    public static let offsetMediaIndication = 2
}
