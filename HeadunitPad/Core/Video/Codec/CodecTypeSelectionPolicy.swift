//
//  CodecTypeSelectionPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit CodecTypeSelectionPolicy.kt
//

import Foundation

public enum VideoCodecType: String, CaseIterable, Codable {
    case h264 = "H.264"
    case hevc = "H.265 (HEVC)"
}

public enum VideoCodecPreference: String, CaseIterable, Codable {
    case auto = "Auto"
    case h264 = "H.264"
    case hevc = "HEVC (H.265)"

    public var title: String {
        return rawValue
    }

    public var effectiveCodecType: VideoCodecType? {
        switch self {
        case .auto: return nil
        case .h264: return .h264
        case .hevc: return .hevc
        }
    }
}

public enum CodecTypeSelectionPolicy {
    /// Decides which codec to build for the first packet of a session,
    /// given what the stream looks like and what the user asked for.
    public static func select(
        detected: VideoCodecType?,
        requested: VideoCodecType,
        hevcDetectable: BooleanLiteralType,
        hevcUsable: BooleanLiteralType
    ) -> VideoCodecType {
        // Nothing here can play H.265, so the announcement asked for H.264
        if !hevcUsable {
            return .h264
        }

        // The sniff saw both codecs' parameter sets and picked one
        if let detected = detected, hevcDetectable {
            return detected
        }

        // Setting is the better guess
        return requested
    }
}
