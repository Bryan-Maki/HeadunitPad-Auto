//
//  AudioMixer.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AudioMixer.kt
//

import Foundation

/// Multi-channel audio mixer managing Media, Guidance, and System audio streams.
/// Performs linear sample-rate conversion to 48kHz stereo, sample-accurate ducking,
/// and soft-limiting to eliminate digital clipping.
public final class AudioMixer {
    public static let outputSampleRate = 48000
    public static let outputChannels = 2
    public static let outputBitDepth = 16
    public static let mixIntervalMs: Int64 = 10
    public static let samplesPerCycle = Int(Int64(outputSampleRate) * mixIntervalMs / 1000) // 480 frames
    public static let shortsPerCycle = samplesPerCycle * outputChannels // 960 shorts

    public final class ChannelState {
        public let channelId: UInt8
        public let rate: Int
        public let channels: Int
        public let isMediaSink: Bool

        public let buffer: AdaptivePcmBuffer
        public let format: PcmInputFormat
        public let converter: PcmConverter

        public var gain: Float = 1.0
        public var activeThisCycle: Bool = false

        public init(
            channelId: UInt8,
            rate: Int,
            channels: Int,
            latencyMultiplier: Int = AudioJitterBufferPolicy.defaultMultiplier,
            isMediaSink: Bool
        ) {
            self.channelId = channelId
            self.rate = rate
            self.channels = channels
            self.isMediaSink = isMediaSink

            self.buffer = AdaptivePcmBuffer(
                sampleRate: rate,
                channels: channels,
                latencyMultiplier: latencyMultiplier,
                isMediaSink: isMediaSink
            )
            self.format = PcmInputFormat(sampleRate: rate, channels: channels)
            self.converter = PcmConverter(outputRate: AudioMixer.outputSampleRate)
        }
    }

    private let lock = NSLock()
    private var channels: [UInt8: ChannelState] = [:]
    public var duckMediaForSpeech: Bool = true

    private let limiter = MixerSoftClipper()
    private let ducking = MixerDuckingEnvelope(sampleRate: outputSampleRate, duckedGain: 0.3)

    private var mixBuffer = [Int](repeating: 0, count: shortsPerCycle)
    private var mediaBuffer = [Int](repeating: 0, count: shortsPerCycle)
    private var channelBuffer = [Int16](repeating: 0, count: shortsPerCycle)
    private var outputBuffer = [Int16](repeating: 0, count: shortsPerCycle)

    public init(duckMediaForSpeech: Bool = true) {
        self.duckMediaForSpeech = duckMediaForSpeech
    }

    public func registerChannel(
        channelId: UInt8,
        sampleRate: Int,
        channelCount: Int,
        latencyMultiplier: Int = AudioJitterBufferPolicy.defaultMultiplier,
        isMediaSink: Bool
    ) -> ChannelState {
        lock.lock()
        defer { lock.unlock() }

        if let existing = channels[channelId], existing.rate == sampleRate, existing.channels == channelCount {
            return existing
        }

        let state = ChannelState(
            channelId: channelId,
            rate: sampleRate,
            channels: channelCount,
            latencyMultiplier: latencyMultiplier,
            isMediaSink: isMediaSink
        )
        channels[channelId] = state
        return state
    }

    public func unregisterChannel(channelId: UInt8) {
        lock.lock()
        defer { lock.unlock() }
        channels.removeValue(forKey: channelId)
    }

    public func feed(channelId: UInt8, pcmData: Data, format: PcmInputFormat? = nil) {
        lock.lock()
        guard let state = channels[channelId] else {
            lock.unlock()
            return
        }
        lock.unlock()

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let inFormat = format ?? state.format
        let convertedShorts = state.converter.convert(
            data: pcmData,
            offset: 0,
            length: pcmData.count,
            input: inFormat
        )
        guard convertedShorts > 0 else { return }

        state.buffer.write(data: state.converter.samples, length: convertedShorts, nowMs: nowMs)
    }

    public func noteArrival(channelId: UInt8, frames: Int, nowMs: Int64) {
        lock.lock()
        let state = channels[channelId]
        lock.unlock()
        state?.buffer.noteArrival(nowMs: nowMs, frames: frames)
    }

    public func finish(channelId: UInt8) {
        lock.lock()
        let state = channels[channelId]
        lock.unlock()
        state?.buffer.finish()
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        for state in channels.values {
            state.buffer.reset()
            state.converter.reset()
        }
        limiter.reset()
        ducking.reset()
    }

    /// Render-clock DSP: mixes all active channels into outputBuffer (48kHz stereo Int16).
    public func renderCycle(nowMs: Int64, outputBurstFrames: Int? = nil) -> [Int16] {
        lock.lock()
        let states = Array(channels.values)
        lock.unlock()

        for i in 0..<AudioMixer.shortsPerCycle {
            mixBuffer[i] = 0
            mediaBuffer[i] = 0
        }

        var activeChannels = 0
        var speechActive = false
        var boosted = false

        for state in states {
            let active = state.buffer.render(
                out: &channelBuffer,
                nowMs: nowMs,
                outputBurstFrames: outputBurstFrames
            )
            state.activeThisCycle = active
            let gain = state.gain

            if active && gain > 0 {
                activeChannels += 1
            }
            if active && !state.isMediaSink && gain > 0 {
                speechActive = true
            }
            if active && gain > 1.0 {
                boosted = true
            }

            let isDuckedMedia = duckMediaForSpeech && state.isMediaSink
            for i in 0..<AudioMixer.shortsPerCycle {
                let sample = Int(channelBuffer[i])
                let scaled = Int(Float(sample) * gain)
                if isDuckedMedia {
                    mediaBuffer[i] += scaled
                } else {
                    mixBuffer[i] += scaled
                }
            }
        }

        ducking.setSpeechActive(duckMediaForSpeech && speechActive)
        limiter.setEnabled(activeChannels > 1 || boosted)

        var mediaGain: Float = 1.0
        for i in 0..<AudioMixer.shortsPerCycle {
            if i % AudioMixer.outputChannels == 0 {
                mediaGain = ducking.nextGain()
                limiter.advance()
            }
            mixBuffer[i] += Int(Float(mediaBuffer[i]) * mediaGain)
            outputBuffer[i] = limiter.process(mixBuffer[i])
        }

        return outputBuffer
    }
}
