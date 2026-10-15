//
//  Phase4AudioAndMicTests.swift
//  HeadunitPadTests
//
//  Unit tests covering Phase 4:
//  - AAC-LC Codec parsing & Audio Sink Policies
//  - Ducking Envelope & Soft Clipper
//  - PCM Converter & Multi-channel Audio Mixer
//  - Adaptive Jitter Buffer & Latency Recovery
//  - Microphone Decimator (48kHz -> 16kHz) & Chunk Accumulator & Flow Control
//

import XCTest
import Foundation
@testable import HeadunitPad

final class Phase4AudioAndMicTests: XCTestCase {

    // MARK: - 1. AAC Codec Config & Sink Policies

    func testAacCodecConfigDefaultGenerationAndParsing() {
        // 48kHz (sampling frequency index 3), 2 channels (channel config 2)
        // audioObjectType = 2 (AAC-LC, 5 bits) -> 00010
        // samplingFrequencyIndex = 3 (4 bits) -> 0011
        // channelConfiguration = 2 (4 bits) -> 0010
        // Combined bits: 0001 0001 1001 0000 -> 0x11, 0x90
        let csd48kStereo = AacCodecConfig.defaultConfig(sampleRate: 48000, channels: 2)
        XCTAssertEqual(csd48kStereo.count, 2)
        XCTAssertEqual(csd48kStereo[0], 0x11)
        XCTAssertEqual(csd48kStereo[1], 0x90)

        let parsed48k = AacCodecConfig.parse(csd: csd48kStereo)
        XCTAssertNotNil(parsed48k)
        XCTAssertEqual(parsed48k?.sampleRate, 48000)
        XCTAssertEqual(parsed48k?.channels, 2)
        XCTAssertEqual(parsed48k?.audioObjectType, 2)

        // 16kHz (sampling frequency index 8 = 1000), 1 channel (0001)
        // Combined bits: 0001 0100 0000 1000 -> 0x14, 0x08
        let csd16kMono = AacCodecConfig.defaultConfig(sampleRate: 16000, channels: 1)
        let parsed16k = AacCodecConfig.parse(csd: csd16kMono)
        XCTAssertNotNil(parsed16k)
        XCTAssertEqual(parsed16k?.sampleRate, 16000)
        XCTAssertEqual(parsed16k?.channels, 1)
    }

    func testAacCodecConfigInvalidAsc() {
        let empty = Data()
        XCTAssertNil(AacCodecConfig.parse(csd: empty))

        let singleByte = Data([0x11])
        XCTAssertNil(AacCodecConfig.parse(csd: singleByte))
    }

    func testAudioSinkCodecPolicyMapping() {
        XCTAssertEqual(AudioSinkCodecPolicy.codec(forWireValue: 0), .pcm)
        XCTAssertEqual(AudioSinkCodecPolicy.codec(forWireValue: 1), .aacLc)
        XCTAssertEqual(AudioSinkCodecPolicy.codec(forWireValue: 2), .aacLcAdts)
        XCTAssertEqual(AudioSinkCodecPolicy.codec(forWireValue: 99), .pcm)

        XCTAssertEqual(AudioSinkCodecPolicy.wireValue(forCodec: .pcm), 0)
        XCTAssertEqual(AudioSinkCodecPolicy.wireValue(forCodec: .aacLc), 1)
        XCTAssertEqual(AudioSinkCodecPolicy.wireValue(forCodec: .aacLcAdts), 2)
    }

    func testAudioSinkSetupPolicyRebuildRules() {
        let policy = AudioSinkSetupPolicy()

        // Same parameters -> no rebuild
        XCTAssertFalse(policy.shouldRebuild(currentCodec: .aacLc, newCodec: .aacLc, currentRate: 48000, newRate: 48000, currentChannels: 2, newChannels: 2))

        // Codec changed -> rebuild
        XCTAssertTrue(policy.shouldRebuild(currentCodec: .pcm, newCodec: .aacLc, currentRate: 48000, newRate: 48000, currentChannels: 2, newChannels: 2))

        // Sample rate changed -> rebuild
        XCTAssertTrue(policy.shouldRebuild(currentCodec: .aacLc, newCodec: .aacLc, currentRate: 44100, newRate: 48000, currentChannels: 2, newChannels: 2))

        // Channels changed -> rebuild
        XCTAssertTrue(policy.shouldRebuild(currentCodec: .aacLc, newCodec: .aacLc, currentRate: 48000, newRate: 48000, currentChannels: 1, newChannels: 2))
    }

    func testAudioSinkAnnouncementPolicy() {
        let policy = AudioSinkAnnouncementPolicy()

        // Auto mode should prefer AAC
        let autoCodecs = policy.supportedCodecs(for: .auto, channel: 3)
        XCTAssertTrue(autoCodecs.contains(.aacLc))
        XCTAssertTrue(autoCodecs.contains(.pcm))

        // PCM only mode
        let pcmCodecs = policy.supportedCodecs(for: .pcm, channel: 3)
        XCTAssertEqual(pcmCodecs, [.pcm])

        // AAC mode
        let aacCodecs = policy.supportedCodecs(for: .aac, channel: 3)
        XCTAssertTrue(aacCodecs.contains(.aacLc))
    }

    // MARK: - 2. Ducking Envelope & Soft Clipper

    func testMixerDuckingEnvelopeTransitions() {
        let duck = MixerDuckingEnvelope(sampleRate: 48000, attackMs: 10, releaseMs: 20, duckedGain: 0.3)
        XCTAssertEqual(duck.currentGain, 1.0, accuracy: 0.001)

        // Set speech active -> gain should decay towards 0.3
        duck.setSpeechActive(true)

        // Process 240 frames (5ms) -> gain should be between 1.0 and 0.3
        let buffer1 = [Float](repeating: 1.0, count: 240)
        let ducked1 = duck.process(samples: buffer1, channels: 1)
        XCTAssertEqual(ducked1.count, 240)
        XCTAssertLessThan(ducked1.last!, 1.0)
        XCTAssertGreaterThan(ducked1.last!, 0.3)

        // Process another 480 frames (10ms) -> should be fully clamped to 0.3
        let buffer2 = [Float](repeating: 1.0, count: 480)
        let ducked2 = duck.process(samples: buffer2, channels: 1)
        XCTAssertEqual(ducked2.last!, 0.3, accuracy: 0.01)

        // Set speech inactive -> gain should ramp back towards 1.0
        duck.setSpeechActive(false)
        let buffer3 = [Float](repeating: 1.0, count: 48000) // 1 second
        let ducked3 = duck.process(samples: buffer3, channels: 1)
        XCTAssertEqual(ducked3.last!, 1.0, accuracy: 0.001)
    }

    func testMixerSoftClipperLinearAndCompression() {
        // Below linear threshold (<= 20480), output equals input
        XCTAssertEqual(MixerSoftClipper.clip(sample: 0), 0)
        XCTAssertEqual(MixerSoftClipper.clip(sample: 1000), 1000)
        XCTAssertEqual(MixerSoftClipper.clip(sample: -1000), -1000)
        XCTAssertEqual(MixerSoftClipper.clip(sample: 20480), 20480)
        XCTAssertEqual(MixerSoftClipper.clip(sample: -20480), -20480)

        // Above threshold, should smoothly compress towards max Int16 without wrapping or overflowing
        let clippedHigh = MixerSoftClipper.clip(sample: 40000)
        XCTAssertGreaterThan(clippedHigh, 20480)
        XCTAssertLessThanOrEqual(clippedHigh, 32767)

        let clippedExtreme = MixerSoftClipper.clip(sample: 100000)
        XCTAssertGreaterThan(clippedExtreme, 25000)
        XCTAssertLessThanOrEqual(clippedExtreme, 32767)

        let clippedLow = MixerSoftClipper.clip(sample: -50000)
        XCTAssertLessThan(clippedLow, -20480)
        XCTAssertGreaterThanOrEqual(clippedLow, -32768)
    }

    // MARK: - 3. PCM Converter & Multi-channel Mixer

    func testPcm16StereoToSamples() {
        // 2 samples (Left = 100, Right = -200) -> 4 bytes
        var data = Data()
        var s1: Int16 = 100
        var s2: Int16 = -200
        withUnsafeBytes(of: &s1) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &s2) { data.append(contentsOf: $0) }

        let samples = Pcm16Stereo.toSamples(data: data)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0], 100)
        XCTAssertEqual(samples[1], -200)

        let backToData = Pcm16Stereo.toData(samples: samples)
        XCTAssertEqual(backToData, data)
    }

    func testPcmConverterResampling16kMonoTo48kStereo() {
        let converter = PcmConverter(inputRate: 16000, inputChannels: 1, outputRate: 48000, outputChannels: 2)

        // 16 samples of 16kHz mono -> should produce 16 * 3 = 48 stereo frames = 96 interleaved samples
        let inputSamples: [Int16] = [Int16](repeating: 1000, count: 16)
        let outputSamples = converter.convert(samples: inputSamples)

        XCTAssertEqual(outputSamples.count, 96)
        // In mono to stereo conversion, left and right channels should be equal
        for i in stride(from: 0, to: outputSamples.count, by: 2) {
            XCTAssertEqual(outputSamples[i], outputSamples[i + 1])
            XCTAssertEqual(outputSamples[i], 1000)
        }
    }

    func testAudioMixerChannelRegistrationAndMixing() {
        let mixer = AudioMixer(duckMediaForSpeech: true)
        XCTAssertTrue(mixer.registerChannel(channelId: 3, sampleRate: 48000, channelCount: 2, isMediaSink: true))
        XCTAssertTrue(mixer.registerChannel(channelId: 4, sampleRate: 16000, channelCount: 1, isMediaSink: false))

        // Push media samples (48kHz stereo, 480 frames = 960 samples)
        let mediaSamples = [Int16](repeating: 1000, count: 960)
        let mediaData = Pcm16Stereo.toData(samples: mediaSamples)
        mixer.pushPcm(data: mediaData, on: 3)

        // Read mixed output
        let mixed = mixer.readMixedPcm(frames: 480)
        XCTAssertEqual(mixed.count, 480 * 2 * 2) // 480 frames * 2 channels * 2 bytes = 1920 bytes

        let mixedSamples = Pcm16Stereo.toSamples(data: mixed)
        XCTAssertEqual(mixedSamples.count, 960)
        XCTAssertEqual(mixedSamples.last!, 1000)
    }

    // MARK: - 4. Adaptive Jitter Buffer & Latency Recovery

    func testAudioJitterBufferPolicyMultipliers() {
        let policy = AudioJitterBufferPolicy()
        XCTAssertEqual(policy.targetLatencyMs(multiplier: 8), 200)
        XCTAssertEqual(policy.targetLatencyMs(multiplier: 16), 400)
        XCTAssertEqual(policy.targetLatencyMs(multiplier: 4), 100)
    }

    func testAdaptivePcmBufferWriteAndRead() {
        let buffer = AdaptivePcmBuffer(sampleRate: 48000, channels: 2, targetLatencyMs: 100)

        // Write 4800 frames (100ms) = 9600 samples
        let samples = [Int16](repeating: 500, count: 9600)
        buffer.write(samples: samples)
        XCTAssertEqual(buffer.availableFrames, 4800)

        // Read 2400 frames (50ms)
        let readSamples = buffer.read(frames: 2400)
        XCTAssertEqual(readSamples.count, 4800)
        XCTAssertEqual(buffer.availableFrames, 2400)
        XCTAssertEqual(readSamples[0], 500)
    }

    func testAdaptivePcmBufferUnderrunPlcConcealment() {
        let buffer = AdaptivePcmBuffer(sampleRate: 48000, channels: 2, targetLatencyMs: 50)

        // Write 100 frames = 200 samples of 1000
        let samples = [Int16](repeating: 1000, count: 200)
        buffer.write(samples: samples)

        // Read 100 frames (empties buffer)
        _ = buffer.read(frames: 100)
        XCTAssertEqual(buffer.availableFrames, 0)

        // Read another 50 frames when buffer is empty -> triggers PLC decay
        let plcSamples = buffer.read(frames: 50)
        XCTAssertEqual(plcSamples.count, 100)
        // Samples should have decayed below 1000 but not be entirely silence immediately
        XCTAssertLessThan(plcSamples[0], 1000)
        XCTAssertGreaterThanOrEqual(plcSamples[0], 0)
    }

    func testLatencyRecoveryPolicyCatchUp() {
        let policy = LatencyRecoveryPolicy(highWatermarkMs: 250, targetMs: 100)

        // Backlog 150ms -> within normal limits
        XCTAssertFalse(policy.shouldShedOrCatchUp(currentBacklogMs: 150))

        // Backlog 300ms -> exceeds high watermark
        XCTAssertTrue(policy.shouldShedOrCatchUp(currentBacklogMs: 300))
        XCTAssertEqual(policy.framesToSkip(currentBacklogMs: 300, sampleRate: 48000), Int((300 - 100) * 48000 / 1000))
    }

    // MARK: - 5. Mic Decimator & Chunk Accumulator & Flow Control

    func testMicPcmDecimator48kTo16kDecimation() {
        let decimator = MicPcmDecimator()

        // 48 samples of 48kHz mono -> should decimate by 3 to produce 16 samples of 16kHz mono
        let inputSamples: [Int16] = (0..<48).map { Int16($0 * 100) }
        let outputSamples = decimator.decimate(samples: inputSamples)

        XCTAssertEqual(outputSamples.count, 16)

        // Stateful residue test: pass 10 samples (10 / 3 = 3 samples, 1 residue)
        let chunk1: [Int16] = [Int16](repeating: 1000, count: 10)
        let out1 = decimator.decimate(samples: chunk1)
        XCTAssertEqual(out1.count, 3)

        // Pass next 11 samples (1 residue + 11 = 12 samples / 3 = 4 samples)
        let chunk2: [Int16] = [Int16](repeating: 1000, count: 11)
        let out2 = decimator.decimate(samples: chunk2)
        XCTAssertEqual(out2.count, 4)
    }

    func testMicChunkAccumulatorFixedSizeEmission() {
        // Accumulator with chunkSize = 2048 samples (4096 bytes)
        let accumulator = MicChunkAccumulator(targetChunkSamples: 2048)

        // Add 1000 samples -> not enough for a chunk
        let samples1 = [Int16](repeating: 100, count: 1000)
        let emitted1 = accumulator.append(samples: samples1)
        XCTAssertTrue(emitted1.isEmpty)

        // Add 1500 samples -> total 2500 -> emits 1 chunk of 2048 samples, 452 remain
        let samples2 = [Int16](repeating: 200, count: 1500)
        let emitted2 = accumulator.append(samples: samples2)
        XCTAssertEqual(emitted2.count, 1)
        XCTAssertEqual(emitted2[0].count, 2048)
        XCTAssertEqual(accumulator.pendingSampleCount, 452)
    }

    func testMicFlowControlAndUplinkFrame() {
        let flow = MicFlowControl(initialCredits: 3)
        XCTAssertTrue(flow.consumeCredit())
        XCTAssertTrue(flow.consumeCredit())
        XCTAssertTrue(flow.consumeCredit())
        XCTAssertFalse(flow.consumeCredit()) // No credits left

        flow.grantCredit(2)
        XCTAssertTrue(flow.consumeCredit())
        XCTAssertTrue(flow.consumeCredit())
        XCTAssertFalse(flow.consumeCredit())

        // Frame building test
        let pcmData = Data([0x01, 0x02, 0x03, 0x04])
        let timestampUs: UInt64 = 1_000_000
        let frame = MicUplinkFrame.frame(timestampUs: timestampUs, pcmData: pcmData)

        // Frame header: 2 bytes type (0x00, 0x00) + 8 bytes timestamp + 4 bytes PCM = 14 bytes
        XCTAssertEqual(frame.count, 14)
        XCTAssertEqual(frame[0], 0x00)
        XCTAssertEqual(frame[1], 0x00)

        let parsedTs = frame.subdata(in: 2..<10).withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        XCTAssertEqual(parsedTs, timestampUs)
        XCTAssertEqual(frame.subdata(in: 10..<14), pcmData)
    }

    func testMicrophoneResponseMessageEncoding() {
        let msg = AapMicrophoneResponseMessage(status: 0)
        let payload = msg.encode()
        XCTAssertEqual(payload.count, 2)
        XCTAssertEqual(payload[0], 0x00)
        XCTAssertEqual(payload[1], 0x00)
    }

    // MARK: - 6. Focus, Lifecycle, Buffer Sizing & Profile Policies

    func testPlaybackFocusPolicyDecisions() {
        // Dynamic path:
        XCTAssertFalse(PlaybackFocusPolicy.shouldAcquire(mode: .never, staticAudioFocus: false, audioSinkEnabled: true, isAudioChannel: true, selfDefeatingLatched: false))
        XCTAssertTrue(PlaybackFocusPolicy.shouldAcquire(mode: .always, staticAudioFocus: false, audioSinkEnabled: true, isAudioChannel: true, selfDefeatingLatched: false))
        XCTAssertTrue(PlaybackFocusPolicy.shouldAcquire(mode: .auto, staticAudioFocus: false, audioSinkEnabled: true, isAudioChannel: true, selfDefeatingLatched: false))
        XCTAssertFalse(PlaybackFocusPolicy.shouldAcquire(mode: .auto, staticAudioFocus: false, audioSinkEnabled: true, isAudioChannel: true, selfDefeatingLatched: true))

        // Static mode:
        XCTAssertFalse(PlaybackFocusPolicy.shouldAcquirePermanent(mode: .never, staticAudioFocus: true, audioSinkEnabled: true, btMediaLinkActive: false))
        XCTAssertTrue(PlaybackFocusPolicy.shouldAcquirePermanent(mode: .always, staticAudioFocus: true, audioSinkEnabled: true, btMediaLinkActive: false))
        XCTAssertTrue(PlaybackFocusPolicy.shouldAcquirePermanent(mode: .auto, staticAudioFocus: true, audioSinkEnabled: true, btMediaLinkActive: false))
        XCTAssertFalse(PlaybackFocusPolicy.shouldAcquirePermanent(mode: .auto, staticAudioFocus: true, audioSinkEnabled: true, btMediaLinkActive: true))

        // Self-defeating check
        XCTAssertTrue(PlaybackFocusPolicy.countsAsSelfDefeating(isMediaChannel: true, msSinceAcquire: 2000))
        XCTAssertFalse(PlaybackFocusPolicy.countsAsSelfDefeating(isMediaChannel: false, msSinceAcquire: 2000))
        XCTAssertFalse(PlaybackFocusPolicy.countsAsSelfDefeating(isMediaChannel: true, msSinceAcquire: 6000))
    }

    func testPlaybackFocusLeaseLifecycle() {
        let lease = PlaybackFocusLease()
        class DummyOwner {}
        let owner1 = DummyOwner()

        XCTAssertTrue(lease.isOpen())
        _ = lease.register(channel: 3, owner: owner1)

        let req = lease.activity(channel: 3, owner: owner1, nowMs: 1000)
        XCTAssertNotNil(req)
        XCTAssertTrue(lease.accepts(request: req!))
        XCTAssertTrue(lease.complete(request: req!))
        XCTAssertTrue(lease.canRender(nowMs: 1050))

        _ = lease.retire(channel: 3, owner: owner1)
        XCTAssertFalse(lease.canRender(nowMs: 1100))
    }

    func testMixerOutputLifecycleStateTransitions() {
        let lifecycle = MixerOutputLifecycle(keepOutputActive: false)

        // Initial idle -> wait
        XCTAssertEqual(lifecycle.update(nowMs: 0, idle: true, warming: false, receivedAudio: false, drainMs: 500), .wait)

        // Audio arrives -> start
        XCTAssertEqual(lifecycle.update(nowMs: 100, idle: false, warming: false, receivedAudio: true, drainMs: 500), .start)

        // While playing -> write
        XCTAssertEqual(lifecycle.update(nowMs: 200, idle: false, warming: false, receivedAudio: true, drainMs: 500), .write)

        // Becomes idle -> write during drain window
        XCTAssertEqual(lifecycle.update(nowMs: 300, idle: true, warming: false, receivedAudio: false, drainMs: 500), .write)

        // Exceeds drain window (300 + 500 = 800) -> pause
        XCTAssertEqual(lifecycle.update(nowMs: 850, idle: true, warming: false, receivedAudio: false, drainMs: 500), .pause)
    }

    func testCallStateDetection() {
        XCTAssertTrue(CallState.isCallActive(audioMode: 2, appHoldsCommunicationMode: false))
        XCTAssertTrue(CallState.isCallActive(audioMode: 3, appHoldsCommunicationMode: false))
        XCTAssertFalse(CallState.isCallActive(audioMode: 3, appHoldsCommunicationMode: true))
        XCTAssertFalse(CallState.isCallActive(audioMode: 0, appHoldsCommunicationMode: false))

        XCTAssertTrue(CallState.isCallStarting(audioMode: 1))
        XCTAssertFalse(CallState.isCallStarting(audioMode: 2))
    }

    func testOutputWriteWatchdogRecovery() {
        let watchdog = OutputWriteWatchdog(stableProgressUnits: 2)

        // Blocked for less than 500ms -> wait
        XCTAssertEqual(watchdog.onBlocked(nowMs: 100), .wait)
        XCTAssertEqual(watchdog.onBlocked(nowMs: 300), .wait)

        // Blocked for >= 500ms -> first failure triggers reopen
        XCTAssertEqual(watchdog.onBlocked(nowMs: 650), .reopen)

        // Second failure -> triggers reopen
        XCTAssertEqual(watchdog.onFailure(), .reopen)

        // Third failure -> triggers stop
        XCTAssertEqual(watchdog.onFailure(), .stop)
    }

    func testMicCaptureRatePolicySelection() {
        // Direct 16kHz available
        let directDecision = MicCaptureRatePolicy.decide(preferredFallbackHz: 48000) { rate in
            rate == 16000 ? 1024 : 0
        }
        XCTAssertEqual(directDecision?.captureRateHz, 16000)
        XCTAssertEqual(directDecision?.decimationFactor, 1)
        XCTAssertTrue(directDecision?.isDirect ?? false)

        // 16kHz unavailable, fallback to 48kHz (decimationFactor = 3)
        let fallbackDecision = MicCaptureRatePolicy.decide(preferredFallbackHz: 48000) { rate in
            rate == 48000 ? 3072 : 0
        }
        XCTAssertEqual(fallbackDecision?.captureRateHz, 48000)
        XCTAssertEqual(fallbackDecision?.decimationFactor, 3)
        XCTAssertFalse(fallbackDecision?.isDirect ?? true)
    }

    func testMicrophonePolicyDeclineReasons() {
        XCTAssertEqual(MicrophonePolicy.declineReason(headUnitMicEnabled: true, recorderAvailable: true), .none)
        XCTAssertEqual(MicrophonePolicy.declineReason(headUnitMicEnabled: false, recorderAvailable: true), .userSetting)
        XCTAssertEqual(MicrophonePolicy.declineReason(headUnitMicEnabled: true, recorderAvailable: false), .noMicrophone)

        XCTAssertTrue(MicrophonePolicy.shouldCapture(headUnitMicEnabled: true, recorderAvailable: true))
        XCTAssertFalse(MicrophonePolicy.shouldCapture(headUnitMicEnabled: false, recorderAvailable: true))
    }

    func testNarrowBandProfilePolicyCapsAndAac() {
        // 2.4 GHz link: should cap to 30 fps, 720p, and enforce AAC
        XCTAssertTrue(NarrowBandProfilePolicy.runsNarrow(supports5Ghz: false, sessionFrequencyMhz: 0))
        XCTAssertTrue(NarrowBandProfilePolicy.runsNarrow(supports5Ghz: true, sessionFrequencyMhz: 2412))
        XCTAssertFalse(NarrowBandProfilePolicy.runsNarrow(supports5Ghz: true, sessionFrequencyMhz: 5180))

        XCTAssertTrue(NarrowBandProfilePolicy.caps(supports5Ghz: false, wirelessSession: true, capEnabled: true))
        XCTAssertEqual(NarrowBandProfilePolicy.cappedFrameRate(fpsLimit: 60, supports5Ghz: false, wirelessSession: true, capEnabled: true), 30)
        XCTAssertTrue(NarrowBandProfilePolicy.useAac(userChoice: false, supports5Ghz: false, wirelessSession: true, capEnabled: true))
        XCTAssertEqual(NarrowBandProfilePolicy.linkCeiling(supports5Ghz: false, wirelessSession: true, capEnabled: true), .p720)
    }

    func testAudioOutputTargetPhoneOmitsMediaAndSpeechSinksButKeepsSystemSink() {
        XCTAssertTrue(AudioOutputTarget.ipad.isAudioSinkEnabled)
        XCTAssertFalse(AudioOutputTarget.phone.isAudioSinkEnabled)
        XCTAssertEqual(AudioOutputTarget.ipad.title, "iPad (Speaker / iPad BT)")
        XCTAssertEqual(AudioOutputTarget.phone.title, "Phone (Original Device)")

        XCTAssertTrue(AudioSinkAnnouncementPolicy.announcesMediaAndSpeech(sinkEnabled: true))
        XCTAssertFalse(AudioSinkAnnouncementPolicy.announcesMediaAndSpeech(sinkEnabled: false))

        // When enableAudioSink is false (Phone mode):
        let phoneMsg = AapServiceDiscoveryResponseMessage.make(enableAudioSink: false)
        var readerPhone = ProtoReader(data: phoneMsg.payload)
        guard let phoneProto = try? ServiceDiscoveryResponseProto(from: &readerPhone) else {
            XCTFail("Failed to parse ServiceDiscoveryResponseProto")
            return
        }
        let phoneChannelIds = phoneProto.services.map { $0.id }
        XCTAssertTrue(phoneChannelIds.contains(UInt32(Channel.ID_AU2)), "System audio sink must always be announced")
        XCTAssertFalse(phoneChannelIds.contains(UInt32(Channel.ID_AUD)), "Media sink must NOT be announced when enableAudioSink is false")
        XCTAssertFalse(phoneChannelIds.contains(UInt32(Channel.ID_AU1)), "Speech sink must NOT be announced when enableAudioSink is false")

        // When enableAudioSink is true (iPad mode):
        let ipadMsg = AapServiceDiscoveryResponseMessage.make(enableAudioSink: true)
        var readerIpad = ProtoReader(data: ipadMsg.payload)
        guard let ipadProto = try? ServiceDiscoveryResponseProto(from: &readerIpad) else {
            XCTFail("Failed to parse ServiceDiscoveryResponseProto")
            return
        }
        let ipadChannelIds = ipadProto.services.map { $0.id }
        XCTAssertTrue(ipadChannelIds.contains(UInt32(Channel.ID_AU2)), "System audio sink must be announced")
        XCTAssertTrue(ipadChannelIds.contains(UInt32(Channel.ID_AUD)), "Media sink must be announced when enableAudioSink is true")
        XCTAssertTrue(ipadChannelIds.contains(UInt32(Channel.ID_AU1)), "Speech sink must be announced when enableAudioSink is true")
    }

    func testPCMAudioPlayerRouteRebuildResetsStreamsCleanly() {
        let player = PCMAudioPlayer.shared
        player.reset()
        XCTAssertEqual(player.streamCount, 0)
        XCTAssertTrue(player.isPrebuffering(channel: Channel.ID_AUD))

        player.rebuildEngineAndStreams(reason: "unit-test-route-change")
        XCTAssertEqual(player.streamCount, 0)

        player.stop()
        XCTAssertEqual(player.streamCount, 0)
    }
}
