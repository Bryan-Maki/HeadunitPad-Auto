//
//  AudioStreamCatalog.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AudioStreamCatalog.kt adapted for iPadOS audio session routing.
//

import Foundation

public enum AudioStreamType: Int, CaseIterable, Sendable {
    case media = 0
    case guidance = 1
    case system = 2

    public var name: String {
        switch self {
        case .media: return "Media (Music)"
        case .guidance: return "Guidance (Speech/Nav)"
        case .system: return "System (Sounds)"
        }
    }
}

public enum AudioStreamCatalog {
    public static func streamType(for channel: UInt8) -> AudioStreamType {
        switch channel {
        case Channel.ID_AUD:
            return .media
        case Channel.ID_AU1:
            return .guidance
        case Channel.ID_AU2:
            return .system
        default:
            return .media
        }
    }
}
