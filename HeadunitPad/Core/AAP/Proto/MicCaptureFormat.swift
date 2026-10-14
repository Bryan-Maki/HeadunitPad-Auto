//
//  MicCaptureFormat.swift
//  HeadunitPad
//
//  1:1 port of open-headunit MicCaptureFormat.kt
//

import Foundation

public enum MicCaptureFormat {
    public static let SAMPLE_RATE_HZ = 16000
    public static let BITS = 16
    public static let CHANNELS = 1
    public static let FRAME_BYTES = 2
    public static let BYTES_PER_SECOND = SAMPLE_RATE_HZ * FRAME_BYTES
    public static let CHUNK_FRAMES = 2048
    public static let CHUNK_BYTES = CHUNK_FRAMES * FRAME_BYTES
    public static let FALLBACK_SAMPLE_RATE_HZ = 48000
}
