//
//  VideoKeyframeScanner.swift
//  HeadunitPad
//
//  1:1 port of open-headunit VideoKeyframeScanner.kt
//  Accurately identifies keyframes in AVC (IDR = 5) and HEVC (IRAP = 16...21)
//  without false positives from frame size heuristics.
//

import Foundation

public enum VideoKeyframeScanner {

    private static let avcNalIdr = 5
    private static let hevcIrapRange: ClosedRange<Int> = 16...21
    private static let maxNalHeadersScanned = 8

    /// Answers whether the access unit carries a keyframe decoder can start from.
    public static func containsKeyframe(data: Data, offset: Int = 0, size: Int? = nil, isHevc: Bool) -> Bool {
        let totalSize = size ?? (data.count - offset)
        if totalSize < 4 { return false }
        let end = min(offset + totalSize, data.count)

        var found = false
        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            var idx = offset
            var count = 0
            while idx + 3 < end && count < maxNalHeadersScanned {
                let headerPos = startCodeHeaderPos(ptr: ptr, i: idx, end: end)
                if headerPos < 0 {
                    idx += 1
                    continue
                }
                count += 1
                let b = Int(ptr[headerPos])
                let isKey: Bool
                if isHevc {
                    isKey = hevcIrapRange.contains((b & 0x7E) >> 1)
                } else {
                    isKey = ((b & 0x1F) == avcNalIdr)
                }
                if isKey {
                    found = true
                    return
                }
                idx = headerPos + 1
            }
        }
        return found
    }

    private static func startCodeHeaderPos(ptr: UnsafePointer<UInt8>, i: Int, end: Int) -> Int {
        if ptr[i] != 0 || ptr[i + 1] != 0 { return -1 }
        let headerPos: Int
        if ptr[i + 2] == 1 {
            headerPos = i + 3
        } else if ptr[i + 2] == 0 && i + 3 < end && ptr[i + 3] == 1 {
            headerPos = i + 4
        } else {
            return -1
        }
        return (headerPos < end) ? headerPos : -1
    }
}
