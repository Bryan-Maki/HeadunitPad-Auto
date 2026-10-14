//
//  MicPcmDecimator.swift
//  HeadunitPad
//
//  1:1 port of open-headunit MicPcmDecimator.kt
//

import Foundation

/// Whole-group averaging from a multiple of 16 kHz down to 16 kHz, on mono 16-bit little-endian PCM.
/// An N-sample mean is a low-pass filter that avoids folding high frequencies into the speech recognition band.
/// Stateful on purpose: carries remainder samples across read boundaries.
public final class MicPcmDecimator {
    public let factor: Int
    private var pendingSum = 0
    private var pendingCount = 0

    public init(factor: Int = 3) {
        guard factor >= 1 else {
            fatalError("factor must be at least 1, was \(factor)")
        }
        self.factor = factor
    }

    /// Upper bound on the bytes decimate can produce from inputBytes.
    public func outputCapacity(inputBytes: Int) -> Int {
        return (inputBytes / 2 + pendingCount) / factor * 2 + 2
    }

    public func decimate(samples: [Int16]) -> [Int16] {
        var output: [Int16] = []
        for s in samples {
            pendingSum += Int(s)
            pendingCount += 1
            if pendingCount == factor {
                let averaged = Int16(clamping: pendingSum / factor)
                output.append(averaged)
                pendingSum = 0
                pendingCount = 0
            }
        }
        return output
    }

    /// Reads srcLen bytes from src and writes converted samples to dst, returning bytes written.
    public func decimate(src: Data, srcLen: Int, dst: inout Data) -> Int {
        let capacity = outputCapacity(inputBytes: srcLen)
        if dst.count < capacity {
            dst = Data(count: capacity)
        }

        var out = 0
        var i = 0

        src.withUnsafeBytes { raw in
            let srcPtr = raw.baseAddress!

            dst.withUnsafeMutableBytes { dstRaw in
                let dstPtr = dstRaw.baseAddress!

                while i + 1 < srcLen {
                    let b0 = Int(srcPtr.advanced(by: i).assumingMemoryBound(to: UInt8.self).pointee)
                    let b1 = Int(srcPtr.advanced(by: i + 1).assumingMemoryBound(to: UInt8.self).pointee)
                    let rawSample = Int16(bitPattern: UInt16((b1 << 8) | b0))
                    let sample = Int(rawSample)

                    pendingSum += sample
                    pendingCount += 1

                    if pendingCount == factor {
                        let averaged = Int16(clamping: pendingSum / factor)
                        let uVal = UInt16(bitPattern: averaged)
                        dstPtr.advanced(by: out).assumingMemoryBound(to: UInt8.self).pointee = UInt8(uVal & 0xFF)
                        dstPtr.advanced(by: out + 1).assumingMemoryBound(to: UInt8.self).pointee = UInt8((uVal >> 8) & 0xFF)
                        out += 2
                        pendingSum = 0
                        pendingCount = 0
                    }

                    i += 2
                }
            }
        }

        return out
    }

    /// Drop the partial group. Called when capture stops.
    public func reset() {
        pendingSum = 0
        pendingCount = 0
    }
}
