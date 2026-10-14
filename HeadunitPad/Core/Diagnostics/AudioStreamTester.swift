//
//  AudioStreamTester.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AudioStreamTester.kt
//  Auditions output streams (Media, Guidance, System) with a 1-second pure tone.
//

import Foundation
import AVFoundation

public final class AudioStreamTester {
    public static let shared = AudioStreamTester()

    public static let toneDurationSeconds: Double = 1.0
    public static let defaultSampleRate: Double = 48000.0

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var stopTimer: DispatchSourceTimer?

    public init() {}

    /// The list of available audio streams that can be auditioned.
    public var streams: [MixerStreamType] {
        return MixerStreamType.allCases
    }

    /// Frequency assigned to each stream for distinct auditioning.
    public func frequency(for stream: MixerStreamType) -> Double {
        switch stream {
        case .media:
            return 440.0 // A4 note (warm, musical)
        case .guidance:
            return 880.0 // A5 note (clear speech alert)
        case .system:
            return 1320.0 // E6 note (high chime)
        }
    }

    /// Generates uncompressed 16-bit PCM stereo sine wave data.
    public static func generateSineTone(
        frequency: Double,
        durationSeconds: Double = AudioStreamTester.toneDurationSeconds,
        sampleRate: Double = AudioStreamTester.defaultSampleRate
    ) -> Data {
        let totalSamples = Int(durationSeconds * sampleRate)
        var pcmData = Data(capacity: totalSamples * 4) // 2 channels * 2 bytes = 4 bytes per sample frame

        let angularFrequency = 2.0 * Double.pi * frequency / sampleRate
        let amplitude: Double = 16000.0 // -6 dB to avoid clipping

        for i in 0..<totalSamples {
            // Apply a slight fade-in/out to prevent clicks
            var envelope: Double = 1.0
            let rampSamples = Int(sampleRate * 0.05) // 50ms ramp
            if i < rampSamples {
                envelope = Double(i) / Double(rampSamples)
            } else if i > totalSamples - rampSamples {
                envelope = Double(totalSamples - i) / Double(rampSamples)
            }

            let sampleValue = Int16(sin(Double(i) * angularFrequency) * amplitude * envelope)
            // Stereo: Left and Right
            var leSample = sampleValue.littleEndian
            withUnsafeBytes(of: &leSample) { bytes in
                pcmData.append(contentsOf: bytes)
                pcmData.append(contentsOf: bytes)
            }
        }

        return pcmData
    }

    /// Plays a test tone on the given stream for toneDurationSeconds.
    public func playTone(for stream: MixerStreamType, completion: (() -> Void)? = nil) {
        stopTone()

        let sampleRate = AudioStreamTester.defaultSampleRate
        let freq = frequency(for: stream)
        let totalFrames = AVAudioFrameCount(AudioStreamTester.toneDurationSeconds * sampleRate)

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ),
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            completion?()
            return
        }

        buffer.frameLength = totalFrames
        let angularFreq = Float(2.0 * Double.pi * freq / sampleRate)

        if let leftChannel = buffer.floatChannelData?[0],
           let rightChannel = buffer.floatChannelData?[1] {
            let rampFrames = Int(sampleRate * 0.05)
            for i in 0..<Int(totalFrames) {
                var env: Float = 0.5
                if i < rampFrames {
                    env = Float(i) / Float(rampFrames) * 0.5
                } else if i > Int(totalFrames) - rampFrames {
                    env = Float(Int(totalFrames) - i) / Float(rampFrames) * 0.5
                }
                let sample = sin(Float(i) * angularFreq) * env
                leftChannel[i] = sample
                rightChannel[i] = sample
            }
        }

        let newEngine = AVAudioEngine()
        let newPlayer = AVAudioPlayerNode()

        newEngine.attach(newPlayer)
        newEngine.connect(newPlayer, to: newEngine.mainMixerNode, format: format)

        do {
            try newEngine.start()
            newPlayer.play()
            newPlayer.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
                DispatchQueue.main.async {
                    self?.stopTone()
                    completion?()
                }
            }

            self.engine = newEngine
            self.playerNode = newPlayer
        } catch {
            print("AudioStreamTester: Failed to start audio engine: \(error)")
            completion?()
        }
    }

    /// Stops any currently playing test tone immediately.
    public func stopTone() {
        stopTimer?.cancel()
        stopTimer = nil

        playerNode?.stop()
        engine?.stop()
        playerNode = nil
        engine = nil
    }
}
