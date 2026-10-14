//
//  VideoFallbackPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit VideoFallbackPolicy.kt.
//  Offers fallback video configuration if primary high resolution is refused by the phone.
//

import Foundation

public enum VideoFallbackPolicy {
    public static let fallbackIndex = 1

    public struct Margins: Equatable {
        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    /// Provides fallback resolution for primary resolution
    public static func fallbackFor(primary: VideoCodecResolutionType) -> VideoCodecResolutionType? {
        switch primary {
        case .resolution1920X1080, .resolution2560X1440, .resolution3840X2160:
            return .resolution1280X720
        case .resolution1080X1920, .resolution1440X2560, .resolution2160X3840:
            return .resolution720X1280
        default:
            return nil
        }
    }

    /// Scales margins proportionally to the fallback resolution
    public static func scaledMargins(primaryW: Int, primaryH: Int, marginW: Int, marginH: Int, fallback: VideoCodecResolutionType) -> Margins {
        let fallbackSize = sizeOf(fallback)
        if primaryW <= 0 || primaryH <= 0 {
            return Margins(width: 0, height: 0)
        }
        let scaledW = Int((Double(marginW) * Double(fallbackSize.width) / Double(primaryW)).rounded())
        let scaledH = Int((Double(marginH) * Double(fallbackSize.height) / Double(primaryH)).rounded())
        return Margins(width: scaledW, height: scaledH)
    }

    public static func sizeOf(_ type: VideoCodecResolutionType) -> (width: Int, height: Int) {
        switch type {
        case .resolution800X480: return (800, 480)
        case .resolution1280X720: return (1280, 720)
        case .resolution1920X1080: return (1920, 1080)
        case .resolution2560X1440: return (2560, 1440)
        case .resolution3840X2160: return (3840, 2160)
        case .resolution720X1280: return (720, 1280)
        case .resolution1080X1920: return (1080, 1920)
        case .resolution1440X2560: return (1440, 2560)
        case .resolution2160X3840: return (2160, 3840)
        }
    }

    public static func configurationIndices(fallbackOffered: Bool) -> [Int] {
        return fallbackOffered ? [0, fallbackIndex] : [0]
    }

    public static func adopts(configurationIndex: Int, offered: Bool) -> Bool {
        return offered && configurationIndex == fallbackIndex
    }
}
