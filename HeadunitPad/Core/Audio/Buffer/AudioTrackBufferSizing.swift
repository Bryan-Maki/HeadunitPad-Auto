//
//  AudioTrackBufferSizing.swift
//  HeadunitPad
//
//  Ported 1:1 from open-headunit AudioTrackBufferSizing.kt
//

import Foundation

enum AudioTrackBufferSizing {
    static func minimumFrames(minimumBytes: Int) -> Int {
        precondition(minimumBytes > 0)
        return max(960, Int((Int64(minimumBytes) + 3) / 4))
    }

    static func allocationBytes(minimumFrames: Int, canResize: Bool) -> Int {
        precondition(minimumFrames >= 1 && minimumFrames <= Int.max / 4)
        let frames: Int
        if canResize {
            let policyMax = OutputBufferPolicy(sampleRate: 48000, burstFrames: 480, minimumFrames: minimumFrames).maximumFrames
            frames = max(19200, policyMax)
        } else {
            frames = minimumFrames
        }
        let bytes = Int64(frames) * 4
        precondition(bytes <= Int64(Int.max), "Audio buffer is too large: \(frames) frames")
        return Int(bytes)
    }
}
