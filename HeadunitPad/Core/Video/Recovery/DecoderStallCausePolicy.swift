//
//  DecoderStallCausePolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit DecoderStallCausePolicy.kt
//  Separates phone being idle / stream paused from true decoder stalls or keyframe starvation.
//

import Foundation

public enum DecoderStallCausePolicy {

    public static let keyframeStarvationPatienceMs: Int64 = 15_000
    public static let defaultInputIdleThresholdMs: Int64 = 2000

    public enum Cause: Equatable {
        case phoneIdle
        case starvedOfKeyframe
        case stalled
    }

    public static func classify(
        stallGapMs: Int64,
        inputIdleGapMs: Int64,
        inputIdleThresholdMs: Int64 = defaultInputIdleThresholdMs,
        keyframeDecodedSinceStart: Bool,
        sessionHasRendered: Bool
    ) -> Cause {
        if inputIdleGapMs > inputIdleThresholdMs { return .phoneIdle }
        if keyframeDecodedSinceStart { return .stalled }
        if !sessionHasRendered { return .stalled }
        if stallGapMs >= keyframeStarvationPatienceMs { return .stalled }
        return .starvedOfKeyframe
    }
}
