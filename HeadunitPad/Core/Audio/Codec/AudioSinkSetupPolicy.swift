//
//  AudioSinkSetupPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AudioSinkSetupPolicy.kt
//

import Foundation

/// Whether a Media Sink Setup has to rebuild this channel's sink, or can keep the one already there.
///
/// The phone re-sends setup for every channel mid-session.
/// The channel's rate and channel count are fixed by AudioConfigs, so the codec is the whole of
/// what a setup can change.
public enum AudioSinkSetupPolicy {
    /// `builtCodec` is the codec the live track was actually built with, and `setupCodec` the one this
    /// setup names. A nil `setupCodec` is a setup that named no audio codec, which leaves the sink
    /// alone rather than rebuilding it on no information.
    public static func rebuilds(hasLiveTrack: Bool, builtCodec: AudioSinkCodec?, setupCodec: AudioSinkCodec?) -> Bool {
        if !hasLiveTrack || builtCodec == nil {
            return true
        }
        if setupCodec == nil {
            return false
        }
        return builtCodec != setupCodec
    }
}
