//
//  CodecInputSizePolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit CodecInputSizePolicy.kt.
//  Derives optimal input buffer size for a video stream based on resolution and minimum compression ratio.
//

import Foundation

public enum CodecInputSizePolicy {
    private static let macroblock = 16
    private static let yuv420Numerator = 3
    private static let yuv420Denominator = 2
    private static let minCompressionRatio = 2

    public static let minInputSizeBytes = 256 * 1024 // 256 KB floor

    /// Derives the buffer capacity for a given video dimension using ExoPlayer's formula:
    /// (macroblocks_wide * macroblocks_high * 16 * 16 * 3/2) / 2
    public static func deriveInputSize(width: Int, height: Int) -> Int {
        let mbWidth = (max(width, 1) + macroblock - 1) / macroblock
        let mbHeight = (max(height, 1) + macroblock - 1) / macroblock
        let rawPixels = mbWidth * mbHeight * macroblock * macroblock
        let yuvBytes = (rawPixels * yuv420Numerator) / yuv420Denominator
        let maxLegalFrame = yuvBytes / minCompressionRatio
        return max(maxLegalFrame, minInputSizeBytes)
    }

    /// Returns recommended input size capped against codec requirements.
    public static func maxInputSize(width: Int, height: Int, isHevc: Bool) -> Int {
        let derived = deriveInputSize(width: width, height: height)
        let cap = isHevc ? (8 * 1024 * 1024) : (4 * 1024 * 1024)
        return min(derived, cap)
    }
}
