//
//  AacCodecConfig.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AacCodecConfig.kt
//

import Foundation

/// Owned, immutable CSD shared by queued access units so shedding audio cannot lose configuration.
public final class AacCodecConfig: Equatable, Sendable {
    private let bytes: Data

    public init(data: Data) {
        self.bytes = data
    }

    public func copyBytes() -> Data {
        return bytes
    }

    public func sameAs(_ other: AacCodecConfig) -> Bool {
        return bytes == other.bytes
    }

    public static func == (lhs: AacCodecConfig, rhs: AacCodecConfig) -> Bool {
        return lhs.bytes == rhs.bytes
    }

    public static let rates: [Int] = [
        96000, 88200, 64000, 48000, 44100, 32000,
        24000, 22050, 16000, 12000, 11025, 8000, 7350
    ]

    public static func makeDefault(sampleRate: Int, channels: Int) -> AacCodecConfig {
        guard let rateIndex = rates.firstIndex(of: sampleRate), (1...2).contains(channels) else {
            fatalError("Invalid sampleRate (\(sampleRate)) or channels (\(channels))")
        }
        let bits = (2 << 11) | (rateIndex << 7) | (channels << 3)
        let data = Data([UInt8((bits >> 8) & 0xFF), UInt8(bits & 0xFF)])
        return AacCodecConfig(data: data)
    }

    /// Accept the advertised AAC-LC format, without allowing CSD to change the PCM sink.
    public static func parse(data: Data, offset: Int, size: Int, sampleRate: Int, channels: Int) -> AacCodecConfig? {
        guard offset >= 0, (2...64).contains(size), offset <= data.count - size else {
            return nil
        }
        let b0 = Int(data[data.startIndex + offset])
        let b1 = Int(data[data.startIndex + offset + 1])
        let bits = (b0 << 8) | b1
        let rateIndex = (bits >> 7) & 15

        // 1024-frame AAC-LC, no core-coder dependency or GASpecificConfig extension.
        guard (bits >> 11) == 2,
              rateIndex < rates.count,
              rates[rateIndex] == sampleRate,
              ((bits >> 3) & 15) == channels,
              (bits & 7) == 0 else {
            return nil
        }

        let tail = Bits(data: data, offset: offset, size: size, position: 16)
        if !tail.onlyZeroes() {
            // Backward-compatible ASC may begin with LC but enable SBR/PS later.
            guard tail.read(11) == 0x2b7, tail.read(5) == 5, tail.read(1) == 0 else {
                return nil
            }
            if !tail.onlyZeroes() {
                guard tail.read(11) == 0x548, tail.read(1) == 0, tail.onlyZeroes() else {
                    return nil
                }
            }
        }
        let sub = data.subdata(in: (data.startIndex + offset)..<(data.startIndex + offset + size))
        return AacCodecConfig(data: sub)
    }

    /// Bounded to this CSD, not the unused tail of the reusable transport buffer.
    private final class Bits {
        private let data: Data
        private let offset: Int
        private let limit: Int
        private var position: Int

        init(data: Data, offset: Int, size: Int, position: Int) {
            self.data = data
            self.offset = offset
            self.limit = size * 8
            self.position = position
        }

        func read(_ count: Int) -> Int {
            if count > limit - position { return -1 }
            var value = 0
            for _ in 0..<count {
                value = (value << 1) | bit(at: position)
                position += 1
            }
            return value
        }

        func onlyZeroes() -> Bool {
            for index in position..<limit {
                if bit(at: index) != 0 { return false }
            }
            return true
        }

        private func bit(at index: Int) -> Int {
            let byteIndex = data.startIndex + offset + index / 8
            let shift = 7 - (index % 8)
            return (Int(data[byteIndex]) >> shift) & 1
        }
    }
}
