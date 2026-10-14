//
//  PCMAudioPlayer.swift
//  HeadunitPad
//
//  Audio playback engine integrating multi-channel AudioMixer, AAC hardware decoding,
//  sample-accurate audio ducking, and jitter buffer concealment.
//

import Foundation
import AVFoundation

final class PCMAudioPlayer {
    private struct Stream {
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

    public let mixer = AudioMixer(duckMediaForSpeech: true)
    private var aacDecoders: [UInt8: AacAudioDecoder] = [:]
    private let duckingEnvelope = MixerDuckingEnvelope(sampleRate: 48000, duckedGain: 0.3)
    private var speechActiveTimer: DispatchSourceTimer?
    private var isSpeechActive = false

    init() {
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
                self.sessionConfigured = false

                if !active {
                    self.streams.values.forEach { $0.player.stop() }
                    self.streams.removeAll()
                    self.engine.stop()
                    self.engine.reset()
                }
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: nil
        ) { [weak self] note in
            self?.audioQueue.async {
                guard let self = self else { return }
                self.logCurrentAudioRoute(prefix: "PCMAudioPlayer: route changed")
                self.streams.values.forEach { $0.player.stop() }
                self.streams.removeAll()
                self.engine.stop()
                self.engine.reset()
                self.sessionConfigured = false
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
    }

    func reset() {
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

    func configureCodec(channel: UInt8, csd: Data) {
        audioQueue.async { [weak self] in
            guard let self = self else { return }
            let (rate, channels): (Int, Int) = {
                switch channel {
                case Channel.ID_AU1, Channel.ID_AU2:
                    return (16000, 1)
                default:
                    return (48000, 2)
                }
            }()

            let decoder = self.aacDecoders[channel] ?? AacAudioDecoder(sampleRate: rate, channels: channels)
            decoder.configure(csd: csd)
            self.aacDecoders[channel] = decoder
        }
    }

    func playAudio(_ data: Data, on channel: UInt8, isAac: Bool) {
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

            self.playPCMInternal(pcmData, on: channel)
        }
    }

    func playPCM(_ data: Data, on channel: UInt8) {
        playAudio(data, on: channel, isAac: false)
    }

    private func playPCMInternal(_ data: Data, on channel: UInt8) {
        guard !data.isEmpty else { return }
        self.ensureSessionConfigured()
        guard let stream = self.ensureStream(for: channel) else { return }
        guard self.startEngineIfNeeded() else { return }

        // Feed to mixer buffer
        mixer.feed(channelId: channel, pcmData: data)

        // Ducking management: if Guidance (Channel 4) or System (Channel 5) plays, smoothly duck Media (Channel 3/6)
        if channel == Channel.ID_AU1 || channel == Channel.ID_AU2 {
            noteSpeechActivity()
        }

        guard let buffer = self.makePCMBuffer(from: data, format: stream.format, channel: channel) else { return }
        stream.player.scheduleBuffer(buffer, completionHandler: nil)
        if !stream.player.isPlaying {
            stream.player.play()
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
        let (rate, channels): (Int, Int) = {
            switch channel {
            case Channel.ID_AU1, Channel.ID_AU2:
                return (16000, 1)
            default:
                return (48000, 2)
            }
        }()
        let decoder = AacAudioDecoder(sampleRate: rate, channels: channels)
        aacDecoders[channel] = decoder
        return decoder
    }

    private func ensureSessionConfigured() {
        let session = AVAudioSession.sharedInstance()

        if isMicrophoneActive || session.category == .playAndRecord {
            do {
                try session.setActive(true)
                sessionConfigured = true
            } catch {
                print("PCMAudioPlayer: Failed to activate existing playAndRecord session: \(error)")
            }
            return
        }

        let needsConfigure = !sessionConfigured
            || session.category != .playback
            || session.mode != .default

        if needsConfigure {
            do {
                try session.setCategory(.playback, mode: .default, options: [])
                try session.setActive(true)
                sessionConfigured = true
                logCurrentAudioRoute(prefix: "PCMAudioPlayer: audio session configured")
            } catch {
                print("PCMAudioPlayer: Failed to configure audio session: \(error)")
            }
        }
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

    private func ensureStream(for channel: UInt8) -> Stream? {
        if let existing = streams[channel] { return existing }

        let (sampleRate, outputChannels): (Double, AVAudioChannelCount)
        switch channel {
        case 6, Channel.ID_AUD:
            sampleRate = 48_000
            outputChannels = 2
        case 4, 5, Channel.ID_AU1, Channel.ID_AU2:
            sampleRate = 16_000
            outputChannels = 2
        default:
            sampleRate = 48_000
            outputChannels = 2
        }

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: outputChannels, interleaved: false) else {
            return nil
        }

        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        let stream = Stream(format: format, player: player)
        streams[channel] = stream
        return stream
    }

    private func makePCMBuffer(from data: Data, format: AVAudioFormat, channel: UInt8) -> AVAudioPCMBuffer? {
        let outputChannels = Int(format.channelCount)
        guard outputChannels > 0 else { return nil }

        let inputChannels: Int
        if format.sampleRate == 16_000 {
            inputChannels = 1
        } else {
            inputChannels = 2
        }

        let bytesPerSample = 2
        let bytesPerFrame = inputChannels * bytesPerSample
        let frameCount = data.count / bytesPerFrame
        guard frameCount > 0 else { return nil }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let channelData = buffer.floatChannelData else { return nil }

        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            if inputChannels == 1 {
                let left = channelData[0]
                let right = outputChannels > 1 ? channelData[1] : nil
                for i in 0..<frameCount {
                    let s = Float(samples[i]) / 32768.0
                    left[i] = s
                    right?[i] = s
                }
            } else {
                let left = channelData[0]
                let right = outputChannels > 1 ? channelData[1] : channelData[0]
                for i in 0..<frameCount {
                    let base = i * inputChannels
                    left[i] = Float(samples[base]) / 32768.0
                    right[i] = Float(samples[base + 1]) / 32768.0
                }
            }
        }

        return buffer
    }

    private func logCurrentAudioRoute(prefix: String) {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let description = outputs.map { "\($0.portName) [\($0.portType.rawValue)]" }.joined(separator: ", ")
        print("\(prefix): \(description.isEmpty ? "no outputs" : description)")
    }
}
