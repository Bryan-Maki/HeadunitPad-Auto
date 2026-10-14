//
//  AudioSinkCodec.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AudioSinkCodec.kt
//

import Foundation

/// Encoded framing is part of the negotiated format, including when both formats use AAC-LC.
public enum AudioSinkCodec: Equatable, Sendable {
    case pcm
    case aacLc
    case aacLcAdts

    public var isAac: BooleanLiteralType {
        switch self {
        case .pcm:
            return false
        case .aacLc, .aacLcAdts:
            return true
        }
    }
}
