//
//  DecoderConfigLadder.swift
//  HeadunitPad
//
//  1:1 port and VideoToolbox mapping of open-headunit DecoderConfigLadder.kt.
//  The order in which to try configuration options and fallback tiers.
//

import Foundation

public enum DecoderConfigLadder {

    public struct Tier: Equatable {
        public let label: String
        public let lowLatency: Bool
        public let realtime: Bool

        public init(label: String, lowLatency: Bool, realtime: Bool) {
            self.label = label
            self.lowLatency = lowLatency
            self.realtime = realtime
        }
    }

    public static let noOptionalKeys = Tier(label: "none", lowLatency: false, realtime: false)
    public static let lowLatencyTier = Tier(label: "low-latency", lowLatency: true, realtime: true)
    public static let realtimeTier = Tier(label: "realtime", lowLatency: false, realtime: true)

    /// The tiers to try in descending order of rich features
    public static func tiers(lowLatencyRequested: Bool) -> [Tier] {
        if !lowLatencyRequested {
            return [noOptionalKeys]
        }
        return [lowLatencyTier, realtimeTier, noOptionalKeys]
    }

    /// Resolution fallback ladder when hardware creation fails
    public static func fallbackResolution(currentWidth: Int, currentHeight: Int) -> (width: Int, height: Int)? {
        if currentWidth >= 3840 || currentHeight >= 2160 {
            return (2560, 1440)
        } else if currentWidth >= 2560 || currentHeight >= 1440 {
            return (1920, 1080)
        } else if currentWidth >= 1920 || currentHeight >= 1080 {
            return (1280, 720)
        } else if currentWidth > 1280 || currentHeight > 720 {
            return (1280, 720)
        }
        return nil
    }
}
