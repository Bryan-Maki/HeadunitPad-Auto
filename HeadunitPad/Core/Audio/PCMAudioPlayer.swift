//
//  PCMAudioPlayer.swift
//  HeadunitPad
//
//  Audio playback engine integrating multi-channel AudioMixer, AAC hardware decoding,
//  sample-accurate audio ducking, and jitter buffer concealment.
//

import Foundation
import AVFoundation

public final class PCMAudioPlayer {
    private struct Stream {
        let sampleRate: Int
        let channels: Int
        let format: AVAudioFormat
        let player: AVAudioPlayerNode
    }

    private let engine = AVAudioEngine()
    private var streams: [UInt8: Stream] = [:]
    private var sessionConfigured = false
    private let audioQueue = DispatchQueue(label: "com.headunitpad.audio.player", qos: .userInitiated)
    private var isMicrophoneActive = false
    private var microphoneStateObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var engineConfigObserver: NSObjectProtocol?

    public let mixer = AudioMixer(duckMediaForSpeech: true)
    private var aacDecoders: [UInt8: AacAudioDecoder] = [:]
    private let duckingEnvelope = MixerDuckingEnvelope(sampleRate: 48000, duckedGain: 0.3)
    private var speechActiveTimer: DispatchSourceTimer?
    private var isSpeechActive = false

    public init() {
        // Register mixer channels
        _ = mixer.registerChannel(channelId: Channel.ID_AUD, sampleRate: 48000, channelCount: 2, isMediaSink: true)
        _ = mixer.registerChannel(channelId: Channel.ID_AU1, sampleRate: 16000, channelCount: 1, isMediaSink: false)
        _ = mixer.registerChannel(channelId: Channel.ID_AU2, sampleRate: 16000, channelCount: 1, isMediaSink: false)

        microphoneStateObserver = NotificationCenter.default.addObserver(
            forName: .headunitMicrophoneCaptureStateChanged,
            object: nil,
            queue: nil
        ) { [weak self] note in
            let active = (note.userInfo?["active"] as? Bool) ?? false
            self?.audioQueue.async {
                guard let self = self else { return }
                self.isMicrophoneActive = active
                self.ensureSessionConfigured()
                self.restartEngineAndPlayersIfNeeded()
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let reason = reasonValue.flatMap { AVAudioSession.RouteChangeReason(rawValue: $0) }
            // Ignore categoryChange notifications triggered by our own setCategory call
            if reason == .categoryChange {
                return
            }
            self?.audioQueue.async {
                guard let self = self else { return }
                self.logCurrentAudioRoute(prefix: "PCMAudioPlayer: route changed (\(reason.map { "\($0.rawValue)" } ?? "unknown"))")
                self.restartEngineAndPlayersIfNeeded()
            }
        }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let type = typeValue.flatMap { AVAudioSession.InterruptionType(rawValue: $0) }
            if type == .ended {
                self?.audioQueue.async {
                    guard let self = self else { return }
                    self.sessionConfigured = false
                    self.ensureSessionConfigured()
                    self.restartEngineAndPlayersIfNeeded()
                }
            }
        }

        engineConfigObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.audioQueue.async {
                guard let self = self else { return }
                self.restartEngineAndPlayersIfNeeded()
            }
        }
    }

    deinit {
        speechActiveTimer?.cancel()
        if let microphoneStateObserver {
            NotificationCenter.default.removeObserver(microphoneStateObserver)
        }
        if let routeChangeObserver {
            NotificationCenter.default.removeObserver(routeChangeObserver)
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let engineConfigObserver {
            NotificationCenter.default.removeObserver(engineConfigObserver)
        }
    }

    public func reset() {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            self.streams.values.forEach { $0.player.stop() }
            self.streams.removeAll()
            self.engine.stop()
            self.engine.reset()
            self.sessionConfigured = false
            self.mixer.reset()
            self.aacDecoders.values.forEach { $0.reset() }
            self.duckingEnvelope.reset()
        }
    }

    public func configureCodec(channel: UInt8, csd: Data) {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            let (rate, channels) = self.streamFormatParameters(for: channel)
            let decoder = self.aacDecoders[channel] ?? AacAudioDecoder(sampleRate: rate, channels: channels)
            decoder.configure(csd: csd)
            self.aacDecoders[channel] = decoder
        }
    }

    public func playAudio(_ data: Data, on channel: UInt8, isAac: Bool) {
        guard !data.isEmpty else { return }
        audioQueue.async { [weak self] in
            guard let self = self else { return }

            let pcmData: Data
            if isAac {
                let decoder = self.ensureAacDecoder(for: channel)
                guard let decoded = decoder.decode(aacData: data) else {
                    return
                }
                pcmData = decoded
            } else {
                pcmData = data
            }

            let (sampleRate, channels) = self.streamFormatParameters(for: channel)
            self.enqueuePCMDataInternal(pcmData, sampleRate: sampleRate, channels: channels, on: channel)
        }
    }

    public func playPCM(_ data: Data, on channel: UInt8) {
        playAudio(data, on: channel, isAac: false)
    }

    /// Enqueues 16-bit Little-Endian Signed Integer (Int16) PCM data by converting to
    /// standard non-interleaved Float32 AVAudioPCMBuffer and scheduling on AVAudioPlayerNode.
    @discardableResult
    public func enqueuePCMData(_ data: Data, sampleRate: Int, channels: Int, on channel: UInt8 = Channel.ID_AUD) -> AVAudioPCMBuffer? {
        guard let buffer = Self.convertInt16PCMToFloat32Buffer(data, sampleRate: sampleRate, channels: channels) else {
            return nil
        }
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            self.enqueuePreparedBuffer(buffer, rawPCMData: data, sampleRate: sampleRate, channels: channels, on: channel)
        }
        return buffer
    }

    /// Converts 16-bit Little-Endian Signed Integer (Int16) PCM bytes into a non-interleaved Float32 AVAudioPCMBuffer.
    public static func convertInt16PCMToFloat32Buffer(_ data: Data, sampleRate: Int, channels: Int) -> AVAudioPCMBuffer? {
        guard sampleRate > 0, channels > 0 else { return nil }
        let bytesPerSample = MemoryLayout<Int16>.size
        let bytesPerFrame = channels * bytesPerSample
        let frameCount = data.count / bytesPerFrame
        guard frameCount > 0 else { return nil }

        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channels)
        ) else {
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let floatChannelData = buffer.floatChannelData else {
            return nil
        }

        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            let int16Ptr = baseAddress.assumingMemoryBound(to: Int16.self)
            for frame in 0..<frameCount {
                let frameBase = frame * channels
                for ch in 0..<channels {
                    let sample = Int16(littleEndian: int16Ptr[frameBase + ch])
                    floatChannelData[ch][frame] = Float32(sample) / 32768.0
                }
            }
        }

        return buffer
    }

    private func enqueuePCMDataInternal(_ data: Data, sampleRate: Int, channels: Int, on channel: UInt8) {
        guard let buffer = Self.convertInt16PCMToFloat32Buffer(data, sampleRate: sampleRate, channels: channels) else {
            return
        }
        enqueuePreparedBuffer(buffer, rawPCMData: data, sampleRate: sampleRate, channels: channels, on: channel)
    }

    private func enqueuePreparedBuffer(_ buffer: AVAudioPCMBuffer, rawPCMData: Data, sampleRate: Int, channels: Int, on channel: UInt8) {
        ensureSessionConfigured()
        guard let stream = ensureStream(for: channel, sampleRate: sampleRate, channels: channels) else { return }
        guard startEngineIfNeeded() else { return }

        mixer.feed(channelId: channel, pcmData: rawPCMData)

        if channel == Channel.ID_AU1 || channel == Channel.ID_AU2 {
            noteSpeechActivity()
        }

        if !stream.player.isPlaying {
            stream.player.play()
        }
        stream.player.scheduleBuffer(buffer, completionHandler: nil)
    }

    private func streamFormatParameters(for channel: UInt8) -> (sampleRate: Int, channels: Int) {
        switch channel {
        case Channel.ID_AU1, Channel.ID_AU2:
            return (16000, 1)
        default:
            return (48000, 2)
        }
    }

    private func noteSpeechActivity() {
        isSpeechActive = true
        duckingEnvelope.setSpeechActive(true)
        applyDuckingToMediaStream()

        speechActiveTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: audioQueue)
        timer.schedule(deadline: .now() + 0.8)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.isSpeechActive = false
            self.duckingEnvelope.setSpeechActive(false)
            self.applyDuckingToMediaStream()
        }
        timer.resume()
        speechActiveTimer = timer
    }

    private func applyDuckingToMediaStream() {
        let mediaChannel = Channel.ID_AUD
        if let mediaStream = streams[mediaChannel] {
            let targetVolume: Float = isSpeechActive ? duckingEnvelope.duckedGain : 1.0
            mediaStream.player.volume = targetVolume
        }
    }

    private func ensureAacDecoder(for channel: UInt8) -> AacAudioDecoder {
        if let existing = aacDecoders[channel] { return existing }
        let (rate, channels) = streamFormatParameters(for: channel)
        let decoder = AacAudioDecoder(sampleRate: rate, channels: channels)
        aacDecoders[channel] = decoder
        return decoder
    }

    private func ensureSessionConfigured() {
        guard !sessionConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
        )
        try? session.setPreferredSampleRate(48000)
        try? session.setActive(true)
        sessionConfigured = true
        logCurrentAudioRoute(prefix: "PCMAudioPlayer: audio session configured")
    }

    private func startEngineIfNeeded() -> Bool {
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("PCMAudioPlayer: Failed to start AVAudioEngine: \(error)")
                return false
            }
        }
        return true
    }

    private func restartEngineAndPlayersIfNeeded() {
        ensureSessionConfigured()
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("PCMAudioPlayer: Failed to restart AVAudioEngine after route/config change: \(error)")
                return
            }
        }
        for stream in streams.values {
            if !stream.player.isPlaying {
                stream.player.play()
            }
        }
    }

    private func ensureStream(for channel: UInt8, sampleRate: Int, channels: Int) -> Stream? {
        if let existing = streams[channel],
           existing.sampleRate == sampleRate,
           existing.channels == channels {
            return existing
        }

        guard let floatFormat = AVAudioFormat(
            standardFormatWithSampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channels)
        ) else {
            return nil
        }

        let playerNode = AVAudioPlayerNode()
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: floatFormat)
        if !engine.isRunning {
            try? engine.start()
        }
        playerNode.play()

        let stream = Stream(
            sampleRate: sampleRate,
            channels: channels,
            format: floatFormat,
            player: playerNode
        )
        streams[channel] = stream
        applyDuckingToMediaStream()
        return stream
    }

    private func logCurrentAudioRoute(prefix: String) {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let description = outputs.map { "\($0.portName) [\($0.portType.rawValue)]" }.joined(separator: ", ")
        print("\(prefix): \(description.isEmpty ? "no outputs" : description)")
    }
}
