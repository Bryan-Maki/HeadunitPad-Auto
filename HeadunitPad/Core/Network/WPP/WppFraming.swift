//
//  WppFraming.swift
//  HeadunitPad
//
//  1:1 port of open-headunit WppFraming.kt
//  Wire framing for the Android Auto WiFi Projection Protocol (WPP).
//
//  Every frame consists of a 4-byte header followed by the Protobuf payload:
//    0   1   2   3   4 ...
//  +---+---+---+---+--------------+
//  | payload len   | message type | protobuf payload
//  |  uint16 BE    |  uint16 BE   |
//  +---+---+---+---+--------------+
//

import Foundation

public enum WppFramingError: Error, CustomStringConvertible {
    case payloadTooLarge(Int)
    case invalidHeaderSize(Int)
    case invalidType(Int)

    public var description: String {
        switch self {
        case .payloadTooLarge(let sz):
            return "WPP payload size \(sz) exceeds uint16 maximum (65535)"
        case .invalidHeaderSize(let sz):
            return "WPP header requires 4 bytes, got \(sz)"
        case .invalidType(let t):
            return "WPP message type \(t) exceeds uint16 maximum"
        }
    }
}

public enum WppFraming {
    /// Bytes of header in front of every WPP payload (4 bytes).
    public static let headerSize = 4

    /// Largest payload the length field can describe (65535 bytes).
    public static let maxPayloadSize = 0xFFFF

    /// Encodes the 4-byte header for a given payload size and message type.
    public static func encodeHeader(payloadSize: Int, type: Int) throws -> Data {
        guard payloadSize >= 0 && payloadSize <= maxPayloadSize else {
            throw WppFramingError.payloadTooLarge(payloadSize)
        }
        guard type >= 0 && type <= 0xFFFF else {
            throw WppFramingError.invalidType(type)
        }
        var data = Data(count: headerSize)
        data[0] = UInt8((payloadSize >> 8) & 0xFF)
        data[1] = UInt8(payloadSize & 0xFF)
        data[2] = UInt8((type >> 8) & 0xFF)
        data[3] = UInt8(type & 0xFF)
        return data
    }

    /// Encodes a full WPP frame (4-byte header + payload data).
    public static func encodeFrame(payload: Data, type: Int) throws -> Data {
        let header = try encodeHeader(payloadSize: payload.count, type: type)
        return header + payload
    }

    /// Decodes the payload length declared by a 4-byte header.
    public static func decodePayloadSize(header: Data) throws -> Int {
        guard header.count >= headerSize else {
            throw WppFramingError.invalidHeaderSize(header.count)
        }
        let hi = Int(header[0])
        let lo = Int(header[1])
        return (hi << 8) | lo
    }

    /// Decodes the message type declared by a 4-byte header.
    public static func decodeType(header: Data) throws -> Int {
        guard header.count >= headerSize else {
            throw WppFramingError.invalidHeaderSize(header.count)
        }
        let hi = Int(header[2])
        let lo = Int(header[3])
        return (hi << 8) | lo
    }
}
