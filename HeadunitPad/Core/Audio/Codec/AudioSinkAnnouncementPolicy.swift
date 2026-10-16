//
//  AudioSinkAnnouncementPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AudioSinkAnnouncementPolicy.kt
//

import Foundation

/// Whether service discovery announces the media and speech audio sinks.
/// System sounds are always announced; media and speech are the ones a setting can disable.
public final class AudioSinkAnnouncementPolicy {
    public init() {}

    public static func announcesMediaAndSpeech(sinkEnabled: Bool, isSelfModeSession: Bool = false) -> Bool {
        return sinkEnabled && !isSelfModeSession
    }

    public func supportedCodecs(for preference: AudioCodecPreference, channel: Int) -> [AudioSinkCodec] {
        switch preference {
        case .pcm:
            return [.pcm]
        case .aac:
            return [.aacLc, .aacLcAdts]
        }
    }
}
