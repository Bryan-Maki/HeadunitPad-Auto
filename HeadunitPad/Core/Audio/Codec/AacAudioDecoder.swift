//
//  AacAudioDecoder.swift
//  HeadunitPad
//
//  AAC-LC Hardware Audio Decoder using iOS AudioToolbox AudioConverter.
//  1:1 port of open-headunit AacAudioDecoder / AudioDecoder logic with watchdog & recovery.
//

import Foundation
import AudioToolbox
import AVFoundation

public final class AacAudioDecoder {
    public let sampleRate: Int
    public let channels: Int

    private var audioConverter: AudioConverterRef?
    private var csdConfig: AacCodecConfig?
    private let recovery = AacDecoderRecovery()
    private let watchdog = AacProgressWatchdog()
    private let outputFormatValidator: AacOutputFormat

    private let lock = NSLock()
    private var isConfigured = false

    public init(sampleRate: Int = 48000, channels: Int = 2) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.outputFormatValidator = AacOutputFormat(rate: sampleRate, channels: channels)
        setupConverter(csd: nil)
    }

    deinit {
        destroyConverter()
    }

    public func configure(csd: Data) {
        lock.lock()
        defer { lock.unlock() }

        if let parsed = AacCodecConfig.parse(
            data: csd,
            offset: 0,
            size: csd.count,
            sampleRate: sampleRate,
            channels: channels
        ) {
            self.csdConfig = parsed
            setupConverter(csd: parsed.copyBytes())
        } else {
            // Apply raw CSD if valid
            setupConverter(csd: csd)
        }
    }

    public func decode(aacData: Data) -> Data? {
        guard !aacData.isEmpty else { return nil }

        lock.lock()
        defer { lock.unlock() }

        guard let converter = audioConverter else {
            // Check if recovery allows rebuild
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            if recovery.next(nowMs: nowMs) == .rebuild {
                setupConverter(csd: csdConfig?.copyBytes())
            }
            return nil
        }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        watchdog.inputWaiting(nowMs: nowMs)

        // Strip ADTS header (7 or 9 bytes) if present
        let rawAac: Data
        if aacData.count > 7, aacData[0] == 0xFF, (aacData[1] & 0xF0) == 0xF0 {
            let protectionAbsent = (aacData[1] & 0x01) != 0
            let headerLen = protectionAbsent ? 7 : 9
            guard aacData.count > headerLen else { return nil }
            rawAac = aacData.subdata(in: headerLen..<aacData.count)
        } else {
            rawAac = aacData
        }

        // AAC-LC decodes into 1024 frames per packet
        let outputFrames: UInt32 = 1024
        let bytesPerFrame = UInt32(channels * 2) // 16-bit PCM
        let outputByteCount = Int(outputFrames * bytesPerFrame)
        var outputBuffer = Data(count: outputByteCount)

        struct InputState {
            var data: Data
            var bytesConsumed: Int
            var packetDesc: AudioStreamPacketDescription
        }

        var state = InputState(
            data: rawAac,
            bytesConsumed: 0,
            packetDesc: AudioStreamPacketDescription(
                mStartOffset: 0,
                mVariableFramesInPacket: 0,
                mDataByteSize: UInt32(rawAac.count)
            )
        )

        let inputCallback: AudioConverterComplexInputDataProc = { (
            converter,
            ioNumberDataPackets,
            ioData,
            outDataPacketDescription,
            inUserData
        ) -> OSStatus in
            guard let inUserData = inUserData else {
                ioNumberDataPackets.pointee = 0
                return -1
            }

            let statePtr = inUserData.assumingMemoryBound(to: InputState.self)
            if statePtr.pointee.bytesConsumed >= statePtr.pointee.data.count {
                ioNumberDataPackets.pointee = 0
                return 0
            }

            let remaining = statePtr.pointee.data.count - statePtr.pointee.bytesConsumed
            ioNumberDataPackets.pointee = 1

            let rawBuffer = statePtr.pointee.data.withUnsafeBytes { raw in
                return UnsafeMutableRawPointer(mutating: raw.baseAddress?.advanced(by: statePtr.pointee.bytesConsumed))
            }

            ioData.pointee.mNumberBuffers = 1
            ioData.pointee.mBuffers.mNumberChannels = UInt32(1)
            ioData.pointee.mBuffers.mDataByteSize = UInt32(remaining)
            ioData.pointee.mBuffers.mData = rawBuffer

            statePtr.pointee.packetDesc = AudioStreamPacketDescription(
                mStartOffset: 0,
                mVariableFramesInPacket: 0,
                mDataByteSize: UInt32(remaining)
            )
            if let outDesc = outDataPacketDescription {
                outDesc.pointee = withUnsafeMutablePointer(to: &statePtr.pointee.packetDesc) { $0 }
            }

            statePtr.pointee.bytesConsumed += remaining
            return noErr
        }

        var ioOutputDataPackets = outputFrames
        let status = outputBuffer.withUnsafeMutableBytes { (rawPtr: UnsafeMutableRawBufferPointer) -> OSStatus in
            var bufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: UInt32(channels),
                    mDataByteSize: UInt32(outputByteCount),
                    mData: rawPtr.baseAddress
                )
            )

            return withUnsafeMutablePointer(to: &state) { statePtr in
                AudioConverterFillComplexBuffer(
                    converter,
                    inputCallback,
                    statePtr,
                    &ioOutputDataPackets,
                    &bufferList,
                    nil
                )
            }
        }

        if status == noErr && ioOutputDataPackets > 0 {
            watchdog.inputAccepted(nowMs: nowMs)
            watchdog.outputCopied()
            let actualByteCount = Int(ioOutputDataPackets * bytesPerFrame)
            if actualByteCount < outputByteCount {
                outputBuffer.count = actualByteCount
            }
            return outputBuffer
        } else {
            // Decoding failed - trigger recovery watchdog
            recovery.request()
            let recoveryAction = recovery.next(nowMs: nowMs)
            if recoveryAction == .rebuild {
                setupConverter(csd: csdConfig?.copyBytes())
            } else if recoveryAction == .stop {
                destroyConverter()
            }
            return nil
        }
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }

        if let converter = audioConverter {
            AudioConverterReset(converter)
        }
        watchdog.reset()
        recovery.reset()
    }

    private func setupConverter(csd: Data?) {
        destroyConverter()

        var inDesc = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 0,
            mReserved: 0
        )

        var outDesc = AudioStreamBasicDescription(
            mSampleRate: Float64(sampleRate),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channels * 2),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(channels * 2),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 16,
            mReserved: 0
        )

        var converter: AudioConverterRef?
        let status = AudioConverterNew(&inDesc, &outDesc, &converter)
        guard status == noErr, let validConverter = converter else {
            print("AacAudioDecoder: Failed to create AudioConverter: \(status)")
            return
        }

        self.audioConverter = validConverter

        if let csdData = csd, !csdData.isEmpty {
            csdData.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    let propStatus = AudioConverterSetProperty(
                        validConverter,
                        kAudioConverterDecompressionMagicCookie,
                        UInt32(csdData.count),
                        base
                    )
                    if propStatus != noErr {
                        print("AacAudioDecoder: Warning, magic cookie set failed: \(propStatus)")
                    }
                }
            }
        }

        outputFormatValidator.update(outputRate: sampleRate, outputChannels: channels, pcmEncoding: PcmInputFormat.pcm16)
        isConfigured = true
    }

    private func destroyConverter() {
        if let converter = audioConverter {
            AudioConverterDispose(converter)
            audioConverter = nil
        }
        isConfigured = false
    }
}
