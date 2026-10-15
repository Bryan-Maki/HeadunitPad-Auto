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
    public static let shared = PCMAudioPlayer()
    private static let audioQueueKey = DispatchSpecificKey<Void>()

    private final class StreamContext {
        let sampleRate: Int
        let channels: Int
        let format: AVAudioFormat
        let player: AVAudioPlayerNode
        var queuedFrames: Int = 0
        var prebufferQueue: [AVAudioPCMBuffer] = []
        var isPrebuffering: Bool = true
        var needsFadeIn: Bool = true

        init(sampleRate: Int, channels: Int, format: AVAudioFormat, player: AVAudioPlayerNode) {
            self.sampleRate = sampleRate
            self.channels = channels
            self.format = format
            self.player = player
        }
    }

    private let engine = AVAudioEngine()
    private var streams: [UInt8: StreamContext] = [:]
    private var sessionConfigured = false
    private let audioQueue = DispatchQueue(label: "com.headunitpad.audio.player", qos: .userInitiated)
    private var isMicrophoneActive = false
    private var microphoneStateObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var engineConfigObserver: NSObjectProtocol?
    private var isRebuilding = false

    public let mixer = AudioMixer(duckMediaForSpeech: true)
    private var aacDecoders: [UInt8: AacAudioDecoder] = [:]
    private let duckingEnvelope = MixerDuckingEnvelope(sampleRate: 48000, duckedGain: 0.3)
    private var speechActiveTimer: DispatchSourceTimer?
    private var isSpeechActive = false

    public init() {
        audioQueue.setSpecific(key: Self.audioQueueKey, value: ())

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
                self.rebuildEngineAndStreams(reason: "micStateChanged")
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
                let reasonStr = reason.map { "\($0.rawValue)" } ?? "unknown"
                self.logCurrentAudioRoute(prefix: "PCMAudioPlayer: route changed (\(reasonStr))")
                self.rebuildEngineAndStreams(reason: "routeChange-\(reasonStr)")
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
                    self.rebuildEngineAndStreams(reason: "interruptionEnded")
                }
            }
        }

        engineConfigObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.audioQueue.async {
                guard let self = self, !self.isRebuilding else { return }
                self.rebuildEngineAndStreams(reason: "engineConfigChange")
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
        let block = { [self] in
            self.streams.values.forEach {
                $0.player.stop()
                $0.prebufferQueue.removeAll()
                $0.queuedFrames = 0
                $0.isPrebuffering = true
                $0.needsFadeIn = true
            }
            self.streams.removeAll()
            if self.engine.isRunning {
                self.engine.stop()
            }
            self.engine.reset()
            self.sessionConfigured = false
            self.mixer.reset()
            self.aacDecoders.values.forEach { $0.reset() }
            self.duckingEnvelope.reset()
        }

        if DispatchQueue.getSpecific(key: Self.audioQueueKey) != nil {
            block()
        } else {
            audioQueue.sync(execute: block)
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
    func enqueuePCMData(_ data: Data, sampleRate: Int, channels: Int, on channel: UInt8 = Channel.ID_AUD) -> AVAudioPCMBuffer? {
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
                    let floatVal = Float32(sample) / 32768.0
                    floatChannelData[ch][frame] = max(-1.0, min(1.0, floatVal))
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

        if stream.isPrebuffering {
            stream.prebufferQueue.append(buffer)
            let prebufferedFrames = stream.prebufferQueue.reduce(0) { $0 + Int($1.frameLength) }
            let targetThresholdFrames = (stream.sampleRate * 3) / 50 // ~60ms
            if prebufferedFrames >= targetThresholdFrames || stream.prebufferQueue.count >= 4 {
                stream.isPrebuffering = false
                if !engine.isRunning {
                    try? engine.start()
                }
                stream.player.play()
                for buf in stream.prebufferQueue {
                    scheduleStreamBuffer(buf, stream: stream, channel: channel)
                }
                stream.prebufferQueue.removeAll()
            }
        } else {
            if !engine.isRunning {
                try? engine.start()
            }
            stream.player.play()
            scheduleStreamBuffer(buffer, stream: stream, channel: channel)
        }
    }

    private func scheduleStreamBuffer(_ buffer: AVAudioPCMBuffer, stream: StreamContext, channel: UInt8) {
        if stream.needsFadeIn, let floatChannelData = buffer.floatChannelData {
            let rampFrames = min(32, Int(buffer.frameLength))
            for frame in 0..<rampFrames {
                let gain = Float32(frame) / Float32(rampFrames)
                for ch in 0..<stream.channels {
                    floatChannelData[ch][frame] *= gain
                }
            }
            stream.needsFadeIn = false
        }

        let frameCount = Int(buffer.frameLength)
        stream.queuedFrames += frameCount
        weak var weakStream = stream
        stream.player.scheduleBuffer(buffer) { [weak self] in
            self?.audioQueue.async {
                guard let self = self,
                      let s = self.streams[channel],
                      s === weakStream else {
                    return
                }
                s.queuedFrames = max(0, s.queuedFrames - frameCount)
                if s.queuedFrames == 0 {
                    s.isPrebuffering = true
                    s.needsFadeIn = true
                }
            }
        }
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
        do {
            if !isMicrophoneActive {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setPreferredSampleRate(48000)
                try session.setPreferredIOBufferDuration(0.02)
                try session.setActive(true)
            } else {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers])
                try session.setPreferredSampleRate(16000)
                try session.setPreferredIOBufferDuration(0.02)
                try session.setActive(true)
            }
            sessionConfigured = true
            logCurrentAudioRoute(prefix: "PCMAudioPlayer: audio session configured (micActive=\(isMicrophoneActive))")
        } catch {
            print("PCMAudioPlayer: ensureSessionConfigured failed: \(error)")
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

    func rebuildEngineAndStreams(reason: String) {
        let block = { [self] in
            guard !self.isRebuilding else { return }
            self.isRebuilding = true
            defer { self.isRebuilding = false }

            // 1. 停止并清理所有现有 StreamContext 与旧 PlayerNode
            for stream in self.streams.values {
                stream.player.stop()
                if stream.player.engine != nil {
                    self.engine.detach(stream.player)
                }
                stream.prebufferQueue.removeAll()
                stream.queuedFrames = 0
                stream.isPrebuffering = true
                stream.needsFadeIn = true
            }
            self.streams.removeAll()

            // 2. 停止并重置 AVAudioEngine 内部拓扑
            if self.engine.isRunning {
                self.engine.stop()
            }
            self.engine.reset()

            // 3. 强制重新激活当前新路由下的 AVAudioSession
            self.sessionConfigured = false
            self.ensureSessionConfigured()

            // 4. 预备并启动引擎（后续到达的下一个 PCM 包会在 ensureStream 中自动创建全新 PlayerNode 并用新路由格式 connect 到 mainMixerNode）
            self.engine.prepare()
            do {
                try self.engine.start()
            } catch {
                print("PCMAudioPlayer: engine.start() deferred until next packet (\(reason)): \(error)")
            }
        }

        if DispatchQueue.getSpecific(key: Self.audioQueueKey) != nil {
            block()
        } else {
            audioQueue.sync(execute: block)
        }
    }

    public func stop() {
        reset()
    }

    var streamCount: Int {
        if DispatchQueue.getSpecific(key: Self.audioQueueKey) != nil {
            return streams.count
        } else {
            var count = 0
            audioQueue.sync { count = self.streams.count }
            return count
        }
    }

    func isPrebuffering(channel: UInt8) -> Bool? {
        if DispatchQueue.getSpecific(key: Self.audioQueueKey) != nil {
            return streams[channel]?.isPrebuffering
        } else {
            var val: Bool?
            audioQueue.sync { val = self.streams[channel]?.isPrebuffering }
            return val
        }
    }

    private func ensureStream(for channel: UInt8, sampleRate: Int, channels: Int) -> StreamContext? {
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

        let stream = StreamContext(
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
