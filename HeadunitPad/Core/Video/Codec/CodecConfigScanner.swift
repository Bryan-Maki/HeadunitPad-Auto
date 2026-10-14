//
//  CodecConfigScanner.swift
//  HeadunitPad
//
//  1:1 port of open-headunit CodecConfigScanner.kt.
//  Answers what an access unit is made of (parameter sets only vs with picture).
//

import Foundation

public enum CodecConfigScanner {

    public enum Content: Equatable {
        /// Parameter sets and nothing that decodes to a picture.
        case parameterSetsOnly

        /// Parameter sets and a coded picture (typical keyframe).
        case parameterSetsWithPicture

        /// An ordinary frame.
        case noParameterSets
    }

    private static let avcParameterSets: Set<Int> = [7, 8, 13, 15]
    private static let avcPictureRange: ClosedRange<Int> = 1...5

    private static let hevcParameterSets: Set<Int> = [32, 33, 34]
    private static let hevcPictureRange: ClosedRange<Int> = 0...31

    public static let maxNalHeadersScanned = 16
    public static let maxBytesScanned = 512

    public static func classify(data: Data, offset: Int, size: Int, isHevc: Bool) -> Content {
        guard size >= 5, offset >= 0, offset + size <= data.count else {
            return .noParameterSets
        }

        let bytes = [UInt8](data)
        return classify(bytes: bytes, offset: offset, size: size, isHevc: isHevc)
    }

    public static func classify(bytes: [UInt8], offset: Int, size: Int, isHevc: Bool) -> Content {
        guard size >= 5, offset >= 0, offset + size <= bytes.count else {
            return .noParameterSets
        }

        let end = min(offset + size, bytes.count)
        let scanEnd = min(end, offset + maxBytesScanned)
        let parameterSets = isHevc ? hevcParameterSets : avcParameterSets
        let pictureRange = isHevc ? hevcPictureRange : avcPictureRange

        var i = offset
        var headersSeen = 0
        var sawParameterSet = false
        var sawPicture = false
        var incomplete = false

        while i + 3 < scanEnd {
            if headersSeen >= maxNalHeadersScanned {
                incomplete = true
                break
            }

            let headerPos = startCodeHeaderPos(bytes: bytes, i: i, end: end)
            if headerPos < 0 {
                i += 1
                continue
            }

            headersSeen += 1
            let b = Int(bytes[headerPos])
            let nalType = isHevc ? ((b & 0x7E) >> 1) : (b & 0x1F)

            if parameterSets.contains(nalType) {
                sawParameterSet = true
            }
            if pictureRange.contains(nalType) {
                sawPicture = true
            }

            if sawParameterSet && sawPicture {
                return .parameterSetsWithPicture
            }

            i = headerPos + 1
        }

        if scanEnd < end {
            incomplete = true
        }

        if sawParameterSet && incomplete {
            return .parameterSetsWithPicture
        }
        if sawParameterSet {
            return .parameterSetsOnly
        }
        return .noParameterSets
    }

    private static func startCodeHeaderPos(bytes: [UInt8], i: Int, end: Int) -> Int {
        if bytes[i] != 0 || bytes[i + 1] != 0 { return -1 }
        let headerPos: Int
        if bytes[i + 2] == 1 {
            headerPos = i + 3
        } else if bytes[i + 2] == 0 && i + 3 < end && bytes[i + 3] == 1 {
            headerPos = i + 4
        } else {
            return -1
        }
        return headerPos < end ? headerPos : -1
    }
}
