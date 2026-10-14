//
//  MicCaptureRatePolicy.swift
//  HeadunitPad
//
//  Ported 1:1 from open-headunit MicCaptureRatePolicy.kt
//

import Foundation

enum MicCaptureRatePolicy {
    static let directSampleRateHz = 16000
    static let fallbackSampleRateHz = 48000

    struct Decision: Equatable {
        let captureRateHz: Int
        let minBufferSize: Int

        var decimationFactor: Int {
            return captureRateHz / MicCaptureRatePolicy.directSampleRateHz
        }

        var isDirect: Bool {
            return decimationFactor == 1
        }
    }

    static func decide(preferredFallbackHz: Int, minBufferSize: (Int) -> Int) -> Decision? {
        let direct = minBufferSize(directSampleRateHz)
        if direct > 0 {
            return Decision(captureRateHz: directSampleRateHz, minBufferSize: direct)
        }

        let candidates = [preferredFallbackHz, fallbackSampleRateHz]
        for rate in candidates {
            if rate <= directSampleRateHz { continue }
            if rate % directSampleRateHz != 0 { continue }
            let size = minBufferSize(rate)
            if size > 0 {
                return Decision(captureRateHz: rate, minBufferSize: size)
            }
        }
        return nil
    }
}
