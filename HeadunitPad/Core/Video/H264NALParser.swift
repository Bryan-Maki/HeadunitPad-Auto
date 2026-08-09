import Foundation

nonisolated enum H264NALParser {
    static func nalUnits(from data: Data) -> [Data] {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return [] }

        // Check the self-describing formats first. A zero-valued AAP timestamp
        // immediately followed by avcC's leading 0x01 can otherwise resemble
        // an Annex-B start code across the timestamp/config boundary.
        for offset in candidateOffsets(for: bytes.count) {
            if let units = parseAVCDecoderConfigurationRecord(bytes, offset: offset) {
                return units
            }
        }

        let annexB = parseAnnexB(bytes)
        if !annexB.isEmpty {
            return annexB
        }

        for offset in candidateOffsets(for: bytes.count) {
            for lengthSize in [4, 2] {
                if let units = parseLengthPrefixed(bytes, offset: offset, lengthSize: lengthSize) {
                    return units
                }
            }
        }

        for offset in candidateOffsets(for: bytes.count) where offset < bytes.count {
            let nalType = bytes[offset] & 0x1F
            if (1...12).contains(nalType) {
                return [Data(bytes[offset...])]
            }
        }

        return []
    }

    static func annexBParameterSets(from data: Data) -> Data? {
        let parameterSets = nalUnits(from: data).filter { nal in
            guard let header = nal.first else { return false }
            let type = header & 0x1F
            return type == 7 || type == 8
        }
        guard !parameterSets.isEmpty else { return nil }

        var output = Data()
        for nal in parameterSets {
            output.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
            output.append(nal)
        }
        return output
    }

    private static func candidateOffsets(for count: Int) -> [Int] {
        [0, 2, 8, 10].filter { $0 < count }
    }

    private static func parseAnnexB(_ bytes: [UInt8]) -> [Data] {
        func startCodeLength(at index: Int) -> Int {
            if index + 3 <= bytes.count,
               bytes[index] == 0, bytes[index + 1] == 0, bytes[index + 2] == 1 {
                return 3
            }
            if index + 4 <= bytes.count,
               bytes[index] == 0, bytes[index + 1] == 0,
               bytes[index + 2] == 0, bytes[index + 3] == 1 {
                return 4
            }
            return 0
        }

        var starts: [(index: Int, length: Int)] = []
        var index = 0
        while index < bytes.count {
            let length = startCodeLength(at: index)
            if length > 0 {
                starts.append((index, length))
                index += length
            } else {
                index += 1
            }
        }
        guard !starts.isEmpty else { return [] }

        return starts.indices.compactMap { position in
            let start = starts[position].index + starts[position].length
            let end = position + 1 < starts.count ? starts[position + 1].index : bytes.count
            guard start < end else { return nil }
            return Data(bytes[start..<end])
        }
    }

    private static func parseAVCDecoderConfigurationRecord(
        _ bytes: [UInt8],
        offset: Int
    ) -> [Data]? {
        guard offset + 7 <= bytes.count,
              bytes[offset] == 1,
              bytes[offset + 4] & 0xFC == 0xFC,
              bytes[offset + 5] & 0xE0 == 0xE0 else {
            return nil
        }

        var index = offset + 6
        let spsCount = Int(bytes[offset + 5] & 0x1F)
        guard spsCount > 0 else { return nil }
        var units: [Data] = []

        for _ in 0..<spsCount {
            guard let nal = readLengthPrefixedNAL(bytes, index: &index, lengthSize: 2) else {
                return nil
            }
            units.append(nal)
        }

        guard index < bytes.count else { return nil }
        let ppsCount = Int(bytes[index])
        index += 1
        for _ in 0..<ppsCount {
            guard let nal = readLengthPrefixedNAL(bytes, index: &index, lengthSize: 2) else {
                return nil
            }
            units.append(nal)
        }

        guard units.contains(where: { ($0.first ?? 0) & 0x1F == 7 }) else { return nil }
        return units
    }

    private static func parseLengthPrefixed(
        _ bytes: [UInt8],
        offset: Int,
        lengthSize: Int
    ) -> [Data]? {
        var index = offset
        var units: [Data] = []
        while index < bytes.count {
            guard let nal = readLengthPrefixedNAL(bytes, index: &index, lengthSize: lengthSize),
                  let header = nal.first,
                  (1...12).contains(header & 0x1F) else {
                return nil
            }
            units.append(nal)
        }
        return units.isEmpty ? nil : units
    }

    private static func readLengthPrefixedNAL(
        _ bytes: [UInt8],
        index: inout Int,
        lengthSize: Int
    ) -> Data? {
        guard index + lengthSize <= bytes.count else { return nil }
        var length = 0
        for byte in bytes[index..<(index + lengthSize)] {
            length = (length << 8) | Int(byte)
        }
        index += lengthSize
        guard length > 0, index + length <= bytes.count else { return nil }
        let nal = Data(bytes[index..<(index + length)])
        index += length
        return nal
    }
}
