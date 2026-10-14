//
//  AacOutputFormat.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AacOutputFormat.kt
//

import Foundation

/// Per-decoder validation; an old codec callback cannot approve a replacement's PCM output.
public final class AacOutputFormat {
    private let rate: Int
    private let channels: Int
    private let allowConversion: Bool
    private var rejected = false

    public private(set) var format: PcmInputFormat?

    public var acceptsOutput: Bool {
        return format != nil
    }

    public init(rate: Int, channels: Int, allowConversion: Bool = false) {
        self.rate = rate
        self.channels = channels
        self.allowConversion = allowConversion
    }

    @discardableResult
    public func update(outputRate: Int, outputChannels: Int, pcmEncoding: Int? = nil) -> Bool {
        let candidate = PcmInputFormat(
            sampleRate: outputRate,
            channels: outputChannels,
            encoding: pcmEncoding ?? PcmInputFormat.pcm16
        )
        if !candidate.supported || (!allowConversion && candidate != PcmInputFormat(sampleRate: rate, channels: channels)) {
            rejected = true
        }
        format = rejected ? nil : candidate
        return acceptsOutput
    }
}
