//
//  AudioSinkAnnouncementPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AudioSinkAnnouncementPolicy.kt
//

import Foundation

/// Whether service discovery announces the media and speech audio sinks.
/// System sounds are always announced; media and speech are the ones a setting can disable.
public enum AudioSinkAnnouncementPolicy {
    public static func announcesMediaAndSpeech(sinkEnabled: Bool, isSelfModeSession: Bool = false) -> Bool {
        return sinkEnabled && !isSelfModeSession
    }
}
