//
//  AudioSinkCodecPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AudioSinkCodecPolicy.kt
//

import Foundation

/// An audio sink's codec and framing, read from the type the phone names in its Media
/// Sink Setup rather than from the setting the announcement was built from: the wire is the one
/// source that cannot disagree with what the phone sends. Nil for a type that is not an audio codec.
public enum AudioSinkCodecPolicy {
    public static func codec(for setupType: Int) -> AudioSinkCodec? {
        switch setupType {
        case 1: // MEDIA_CODEC_AUDIO_PCM
            return .pcm
        case 2: // MEDIA_CODEC_AUDIO_AAC_LC
            return .aacLc
        case 3, 4: // MEDIA_CODEC_AUDIO_AAC_LC_ADTS
            return .aacLcAdts
        default:
            return nil
        }
    }

    public static func codec(for codecType: MediaCodecType) -> AudioSinkCodec? {
        switch codecType {
        case .mediaCodecAudioPcm:
            return .pcm
        case .mediaCodecAudioAacLc:
            return .aacLc
        case .mediaCodecAudioAacLcAdts:
            return .aacLcAdts
        default:
            return nil
        }
    }

    public static func codec(forWireValue value: Int) -> AudioSinkCodec {
        switch value {
        case 1:
            return .aacLc
        case 2:
            return .aacLcAdts
        default:
            return .pcm
        }
    }

    public static func wireValue(forCodec codec: AudioSinkCodec) -> Int {
        switch codec {
        case .pcm:
            return 0
        case .aacLc:
            return 1
        case .aacLcAdts:
            return 2
        }
    }
}
