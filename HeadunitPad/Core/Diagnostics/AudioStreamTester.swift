//
//  AudioStreamTester.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AudioStreamTester.kt
//  Generates synthetic test tones and validates multi-channel audio output and ducking.
//

import Foundation

public final class AudioStreamTester {
    public static let shared = AudioStreamTester()

    public init() {}

    /// Pure mathematical synthesis of 16-bit LE PCM sine wave with smooth linear ramp envelope.
    public static func generateSineWavePCM(
        sampleRate: Int,
        channelCount: Int,
        frequencyHz: Double,
        durationSeconds: Double,
        rampSeconds: Double = 0.02
    ) -> Data {
        guard sampleRate > 0, channelCount > 0, durationSeconds > 0 else { return Data() }

        let totalFrames = Int(Double(sampleRate) * durationSeconds)
        let rampFrames = max(1, Int(Double(sampleRate) * rampSeconds))
        let amplitude: Double = 32767.0 * 0.70 // ~70% volume to prevent clipping

        var data = Data(capacity: totalFrames * channelCount * 2)

        for i in 0..<totalFrames {
            // Apply 20ms fade-in and fade-out envelope to avoid audible clicks
            let envelope: Double
            if i < rampFrames {
                envelope = Double(i) / Double(rampFrames)
            } else if i >= totalFrames - rampFrames {
                envelope = Double(totalFrames - 1 - i) / Double(rampFrames)
            } else {
                envelope = 1.0
            }

            let phase = 2.0 * .pi * frequencyHz * Double(i) / Double(sampleRate)
            let sampleVal = Int16(clamping: Int((sin(phase) * amplitude * envelope).rounded()))

            for _ in 0..<channelCount {
                var leSample = sampleVal.littleEndian
                withUnsafeBytes(of: &leSample) { bytes in
                    data.append(contentsOf: bytes)
                }
            }
        }

        return data
    }

    /// Plays a 48000Hz stereo 440Hz sine wave (1.0s) on Media channel.
    public func playMediaTestTone() {
        AudioDiagnostics.shared.record("AudioStreamTester: Playing 440Hz Media test tone (48kHz stereo, 1.0s)")
        let data = Self.generateSineWavePCM(
            sampleRate: 48000,
            channelCount: 2,
            frequencyHz: 440.0,
            durationSeconds: 1.0
        )
        PCMAudioPlayer.shared.playPCM(data, on: Channel.ID_AUD)
    }

    /// Plays a 16000Hz mono 587.33Hz (D5) sine wave (1.0s) on Guidance channel.
    public func playGuidanceTestTone() {
        AudioDiagnostics.shared.record("AudioStreamTester: Playing 587Hz Guidance test tone (16kHz mono, 1.0s)")
        let data = Self.generateSineWavePCM(
            sampleRate: 16000,
            channelCount: 1,
            frequencyHz: 587.33,
            durationSeconds: 1.0
        )
        PCMAudioPlayer.shared.playPCM(data, on: Channel.ID_GUD)
    }

    /// Plays a 16000Hz mono 880Hz (A5) sine wave (0.8s) on System channel.
    public func playSystemTestTone() {
        AudioDiagnostics.shared.record("AudioStreamTester: Playing 880Hz System test tone (16kHz mono, 0.8s)")
        let data = Self.generateSineWavePCM(
            sampleRate: 16000,
            channelCount: 1,
            frequencyHz: 880.0,
            durationSeconds: 0.8
        )
        PCMAudioPlayer.shared.playPCM(data, on: Channel.ID_SYS)
    }

    /// Plays 2.5s Media tone, overlaid after 0.6s by 1.0s Guidance tone triggering ducking envelope.
    public func playDuckingTestSequence() {
        AudioDiagnostics.shared.record("AudioStreamTester: Starting ducking test sequence (Media + Guidance overlay)")
        let mediaData = Self.generateSineWavePCM(
            sampleRate: 48000,
            channelCount: 2,
            frequencyHz: 440.0,
            durationSeconds: 2.5
        )
        PCMAudioPlayer.shared.playPCM(mediaData, on: Channel.ID_AUD)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            AudioDiagnostics.shared.record("AudioStreamTester: Overlaying Guidance speech tone (triggering ducking)")
            let guidanceData = Self.generateSineWavePCM(
                sampleRate: 16000,
                channelCount: 1,
                frequencyHz: 880.0,
                durationSeconds: 1.0
            )
            PCMAudioPlayer.shared.noteSpeechActivity()
            PCMAudioPlayer.shared.playPCM(guidanceData, on: Channel.ID_GUD)
        }
    }
}
