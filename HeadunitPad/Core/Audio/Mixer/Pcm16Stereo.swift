//
//  Pcm16Stereo.swift
//  HeadunitPad
//
//  1:1 port of open-headunit Pcm16Stereo.kt
//

import Foundation

/// Copy a transport-owned PCM16 payload into reusable mixer-owned storage.
public enum Pcm16Stereo {
    public static func decode(source: Data, offset: Int, frames: Int, destination: inout [Int16]) {
        guard offset >= 0, frames >= 0,
              frames <= (source.count - offset) / 4,
              frames * 2 <= destination.count else {
            return
        }
        source.withUnsafeBytes { raw in
            let ptr = raw.baseAddress!.advanced(by: offset).assumingMemoryBound(to: Int16.self)
            for i in 0..<(frames * 2) {
                destination[i] = ptr[i]
            }
        }
    }

    public static func toSamples(data: Data) -> [Int16] {
        let count = data.count / 2
        var samples = [Int16](repeating: 0, count: count)
        _ = data.withUnsafeBytes { raw in
            if let ptr = raw.baseAddress?.assumingMemoryBound(to: Int16.self) {
                for i in 0..<count {
                    samples[i] = ptr[i]
                }
            }
        }
        return samples
    }

    public static func toData(samples: [Int16]) -> Data {
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
