//
//  PictureCredibilityPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit PictureCredibilityPolicy.kt
//  Determines whether output frames constitute a credible picture or merely gray/garbage output.
//

import Foundation

public enum PictureCredibilityPolicy {

    public static let pendingKeyframeGraceMs: Int64 = 2000

    public static func hasCrediblePicture(
        renderedSinceCodecStart: Bool,
        keyframeAccountingAvailable: Bool,
        keyframeDecodedSinceCodecStart: Bool,
        msSincePendingKeyframeFed: Int64
    ) -> Bool {
        if !renderedSinceCodecStart { return false }
        if !keyframeAccountingAvailable { return true }
        if keyframeDecodedSinceCodecStart { return true }
        return msSincePendingKeyframeFed < pendingKeyframeGraceMs
    }
}
