//
//  PcmInputFormat.swift
//  HeadunitPad
//
//  1:1 port of open-headunit PcmInputFormat.kt
//

import Foundation

/// Immutable format captured with each decoded buffer, including across codec format changes.
public struct PcmInputFormat: Equatable, Sendable {
    public static let pcm16 = 2
    public static let float32 = 4

    public let sampleRate: Int
    public let channels: Int
    public let encoding: Int

    public init(sampleRate: Int, channels: Int, encoding: Int = PcmInputFormat.pcm16) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.encoding = encoding
    }

    public var bytesPerFrame: Int {
        return channels * (encoding == PcmInputFormat.float32 ? 4 : 2)
    }

    public var supported: Bool {
        return (8000...192000).contains(sampleRate) &&
            (1...2).contains(channels) &&
            (encoding == PcmInputFormat.pcm16 || encoding == PcmInputFormat.float32)
    }
}
