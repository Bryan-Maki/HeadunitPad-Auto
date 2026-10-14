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
}
