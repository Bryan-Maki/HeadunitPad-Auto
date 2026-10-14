//
//  CorruptionConcealmentPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit CorruptionConcealmentPolicy.kt
//  Hides visual tearing / green smearing after wireless packet loss
//  by concealing corrupt frames until a repaired keyframe renders.
//

import Foundation

public enum CorruptionConcealmentPolicy {

    public static let concealMaxMs: Int64 = 2000
    public static let escalatedRepairObservedMs: Int64 = 2780

    public enum State: Equatable {
        case armed
        case disarmed
        case concealing
    }

    public enum Outcome: Equatable {
        case show
        case rearm
        case open
        case conceal
        case closeRepaired
        case closeExpired

        public var renders: Bool {
            switch self {
            case .show, .rearm, .closeRepaired, .closeExpired:
                return true
            case .open, .conceal:
                return false
            }
        }
    }

    public static func next(
        nowMs: Int64,
        state: State,
        windowOpenedMs: Int64,
        corruptionReported: Bool,
        keyframeRepaired: Bool,
        sessionHasRendered: Bool
    ) -> Outcome {
        if state == .concealing {
            if keyframeRepaired { return .closeRepaired }
            if nowMs - windowOpenedMs >= concealMaxMs { return .closeExpired }
            return .conceal
        }
        if keyframeRepaired { return .rearm }
        if !sessionHasRendered { return .show }
        if corruptionReported && state == .armed { return .open }
        return .show
    }
}
