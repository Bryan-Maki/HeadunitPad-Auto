//
//  PcmConverter.swift
//  HeadunitPad
//
//  1:1 port of open-headunit PcmConverter.kt
//

import Foundation

/// Streaming conversion to mixer PCM16 stereo. Retains interpolation phase across packets so
/// packet boundaries cannot duplicate samples or lose fractional frames. At unequal rates the
/// interpolator adds at most one source frame of delay.
public final class PcmConverter {
    public let outputRate: Int
    public private(set) var samples: [Int16] = []

    private var format: PcmInputFormat?
    private var phase = 0
    private var previousLeft = 0
    private var previousRight = 0
    public var inputRate: Int = 48000
    public var inputChannels: Int = 2
    public var outputChannels: Int = 2

    public init(outputRate: Int = 48000) {
        self.outputRate = outputRate
    }

    public convenience init(inputRate: Int, inputChannels: Int, outputRate: Int, outputChannels: Int = 2) {
        self.init(outputRate: outputRate)
        self.inputRate = inputRate
        self.inputChannels = inputChannels
        self.outputChannels = outputChannels
    }

    public func convert(samples inputSamples: [Int16]) -> [Int16] {
        let data = inputSamples.withUnsafeBufferPointer { Data(buffer: $0) }
        let format = PcmInputFormat(sampleRate: inputRate, channels: inputChannels, encoding: PcmInputFormat.pcm16)
        let written = convert(data: data, offset: 0, length: data.count, input: format)
        return Array(self.samples.prefix(written))
    }

    /// A codec discontinuity must not interpolate from the retired codec's last sample.
    public func reset() {
        format = nil
        phase = 0
        hasPrevious = false
    }

    public func convert(data: Data, offset: Int, length: Int, input: PcmInputFormat) -> Int {
        guard input.supported, offset >= 0, length >= 0, offset <= data.count - length else {
            return 0
        }
        guard length % input.bytesPerFrame == 0 else {
            print("PcmConverter: Incomplete PCM frame (length=\(length), bytesPerFrame=\(input.bytesPerFrame))")
            return 0
        }

        if format != input {
            format = input
            phase = 0
            hasPrevious = false
        }

        let frames = length / input.bytesPerFrame
        let outputFrames = Int((Int64(phase) + Int64(frames) * Int64(outputRate)) / Int64(input.sampleRate))
        let count = outputFrames * 2

        if samples.count < count {
            samples = [Int16](repeating: 0, count: max(count, 12288))
        }

        if input.sampleRate == outputRate && input.channels == 2 && input.encoding == PcmInputFormat.pcm16 {
            Pcm16Stereo.decode(source: data, offset: offset, frames: frames, destination: &samples)
            return count
        }

        var written = 0
        let sampleBytes = input.bytesPerFrame / input.channels

        data.withUnsafeBytes { raw in
            let ptr = raw.baseAddress!

            for frame in 0..<frames {
                let frameOffset = offset + frame * input.bytesPerFrame
                let left = sample(from: ptr, index: frameOffset, encoding: input.encoding)
                let right = (input.channels == 1) ? left : sample(from: ptr, index: frameOffset + sampleBytes, encoding: input.encoding)

                if !hasPrevious {
                    previousLeft = left
                    previousRight = right
                    hasPrevious = true
                }

                phase += outputRate
                while phase >= input.sampleRate {
                    phase -= input.sampleRate
                    let l = left + Int(Int64(previousLeft - left) * Int64(phase) / Int64(outputRate))
                    let r = right + Int(Int64(previousRight - right) * Int64(phase) / Int64(outputRate))
                    samples[written] = Int16(clamping: l)
                    samples[written + 1] = Int16(clamping: r)
                    written += 2
                }

                previousLeft = left
                previousRight = right
            }
        }

        return written
    }

    private func sample(from ptr: UnsafeRawPointer, index: Int, encoding: Int) -> Int {
        if encoding == PcmInputFormat.pcm16 {
            let s16 = ptr.advanced(by: index).assumingMemoryBound(to: Int16.self).pointee
            return Int(s16)
        } else {
            let f32 = ptr.advanced(by: index).assumingMemoryBound(to: Float.self).pointee
            if f32.isNaN { return 0 }
            let clamped = max(-1.0, min(1.0, f32))
            return Int(clamping: Int(clamped * 32768.0))
        }
    }
}
