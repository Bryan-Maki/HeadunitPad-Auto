//
//  AudioConfigs.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AudioConfigs.kt
//

import Foundation

public enum AudioConfigs {
    private static let audioConfig0 = AudioConfiguration(
        sampleRate: 48000,
        numberOfBits: 16,
        numberOfChannels: 2
    )

    private static let audioConfig1 = AudioConfiguration(
        sampleRate: 16000,
        numberOfBits: 16,
        numberOfChannels: 1
    )

    private static let audioConfig2 = AudioConfiguration(
        sampleRate: 16000,
        numberOfBits: 16,
        numberOfChannels: 1
    )

    public static func get(channel: UInt8) -> AudioConfiguration {
        switch channel {
        case Channel.ID_AUD:
            return audioConfig0
        case Channel.ID_AU1:
            return audioConfig1
        case Channel.ID_AU2:
            return audioConfig2
        default:
            return audioConfig0
        }
    }
}
