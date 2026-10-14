//
//  ProtoWire.swift
//  HeadunitPad
//
//  Pure Swift zero-dependency Protobuf wire format encoder & decoder.
//

import Foundation

public enum ProtoWireType {
    public static let varint = 0
    public static let fixed64 = 1
    public static let lengthDelimited = 2
    public static let startGroup = 3
    public static let endGroup = 4
    public static let fixed32 = 5
}

public enum ProtoError: Error, CustomStringConvertible {
    case unexpectedEndOfData
    case invalidVarint
    case invalidUtf8String
    case unknownWireType(Int)
    case messageTruncated

    public var description: String {
        switch self {
        case .unexpectedEndOfData:
            return "Protobuf reading error: unexpected end of data"
        case .invalidVarint:
            return "Protobuf reading error: malformed varint"
        case .invalidUtf8String:
            return "Protobuf reading error: invalid UTF-8 string"
        case .unknownWireType(let wireType):
            return "Protobuf reading error: unknown wire type \(wireType)"
        case .messageTruncated:
            return "Protobuf reading error: message was truncated"
        }
    }
}

public protocol ProtoEncodable {
    func encode(to writer: inout ProtoWriter)
}

public protocol ProtoDecodable {
    init(from reader: inout ProtoReader) throws
}

public typealias ProtoCodable = ProtoEncodable & ProtoDecodable

public extension ProtoEncodable {
    func serializedData() -> Data {
        var writer = ProtoWriter()
        encode(to: &writer)
        return writer.data
    }
}

// MARK: - ProtoWriter

public struct ProtoWriter {
    public private(set) var data: Data

    public init(capacity: Int = 128) {
        self.data = Data(capacity: capacity)
    }

    public mutating func writeTag(fieldNumber: Int, wireType: Int) {
        let tag = UInt64((fieldNumber << 3) | (wireType & 0x07))
        writeVarint(tag)
    }

    public mutating func writeVarint(_ value: UInt64) {
        var v = value
        while v >= 0x80 {
            data.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        data.append(UInt8(v & 0x7F))
    }

    public mutating func writeInt32(fieldNumber: Int, value: Int32) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtoWireType.varint)
        // Int32 in protobuf varint is encoded as 64-bit sign-extended
        writeVarint(UInt64(bitPattern: Int64(value)))
    }

    public mutating func writeInt64(fieldNumber: Int, value: Int64) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtoWireType.varint)
        writeVarint(UInt64(bitPattern: value))
    }

    public mutating func writeUInt32(fieldNumber: Int, value: UInt32) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtoWireType.varint)
        writeVarint(UInt64(value))
    }

    public mutating func writeUInt64(fieldNumber: Int, value: UInt64) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtoWireType.varint)
        writeVarint(value)
    }

    public mutating func writeSInt32(fieldNumber: Int, value: Int32) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtoWireType.varint)
        let zigzag = UInt32(bitPattern: (value << 1) ^ (value >> 31))
        writeVarint(UInt64(zigzag))
    }

    public mutating func writeSInt64(fieldNumber: Int, value: Int64) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtoWireType.varint)
        let zigzag = UInt64(bitPattern: (value << 1) ^ (value >> 63))
        writeVarint(zigzag)
    }

    public mutating func writeBool(fieldNumber: Int, value: Bool) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtoWireType.varint)
        writeVarint(value ? 1 : 0)
    }

    public mutating func writeEnum(fieldNumber: Int, value: Int32) {
        writeInt32(fieldNumber: fieldNumber, value: value)
    }

    public mutating func writeFixed32(fieldNumber: Int, value: UInt32) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtoWireType.fixed32)
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    public mutating func writeFixed64(fieldNumber: Int, value: UInt64) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtoWireType.fixed64)
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    public mutating func writeFloat(fieldNumber: Int, value: Float) {
        writeFixed32(fieldNumber: fieldNumber, value: value.bitPattern)
    }

    public mutating func writeDouble(fieldNumber: Int, value: Double) {
        writeFixed64(fieldNumber: fieldNumber, value: value.bitPattern)
    }

    public mutating func writeBytes(fieldNumber: Int, value: Data) {
        writeTag(fieldNumber: fieldNumber, wireType: ProtoWireType.lengthDelimited)
        writeVarint(UInt64(value.count))
        data.append(value)
    }

    public mutating func writeString(fieldNumber: Int, value: String) {
        let utf8 = Data(value.utf8)
        writeBytes(fieldNumber: fieldNumber, value: utf8)
    }

    public mutating func writeMessage<M: ProtoEncodable>(fieldNumber: Int, message: M) {
        var subWriter = ProtoWriter()
        message.encode(to: &subWriter)
        writeBytes(fieldNumber: fieldNumber, value: subWriter.data)
    }

    public mutating func writePackedInt32(fieldNumber: Int, values: [Int32]) {
        guard !values.isEmpty else { return }
        var subWriter = ProtoWriter()
        for v in values {
            subWriter.writeVarint(UInt64(bitPattern: Int64(v)))
        }
        writeBytes(fieldNumber: fieldNumber, value: subWriter.data)
    }

    public mutating func writePackedUInt32(fieldNumber: Int, values: [UInt32]) {
        guard !values.isEmpty else { return }
        var subWriter = ProtoWriter()
        for v in values {
            subWriter.writeVarint(UInt64(v))
        }
        writeBytes(fieldNumber: fieldNumber, value: subWriter.data)
    }
}

// MARK: - ProtoReader

public struct ProtoReader {
    public let data: Data
    public private(set) var offset: Int

    public init(data: Data) {
        self.data = data
        self.offset = 0
    }

    public var isAtEnd: Bool {
        return offset >= data.count
    }

    public var bytesRemaining: Int {
        return max(0, data.count - offset)
    }

    public mutating func readTag() throws -> (fieldNumber: Int, wireType: Int)? {
        if isAtEnd { return nil }
        let rawTag = try readVarint()
        let fieldNumber = Int(rawTag >> 3)
        let wireType = Int(rawTag & 0x07)
        return (fieldNumber, wireType)
    }

    public mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard offset < data.count else {
                throw ProtoError.unexpectedEndOfData
            }
            let byte = data[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if (byte & 0x80) == 0 {
                return result
            }
            shift += 7
            if shift > 64 {
                throw ProtoError.invalidVarint
            }
        }
    }

    public mutating func readInt32() throws -> Int32 {
        let v = try readVarint()
        return Int32(truncatingIfNeeded: Int64(bitPattern: v))
    }

    public mutating func readInt64() throws -> Int64 {
        let v = try readVarint()
        return Int64(bitPattern: v)
    }

    public mutating func readUInt32() throws -> UInt32 {
        let v = try readVarint()
        return UInt32(truncatingIfNeeded: v)
    }

    public mutating func readUInt64() throws -> UInt64 {
        return try readVarint()
    }

    public mutating func readSInt32() throws -> Int32 {
        let n = UInt32(truncatingIfNeeded: try readVarint())
        return Int32(bitPattern: (n >> 1) ^ (0 &- (n & 1)))
    }

    public mutating func readSInt64() throws -> Int64 {
        let n = try readVarint()
        return Int64(bitPattern: (n >> 1) ^ (0 &- (n & 1)))
    }

    public mutating func readBool() throws -> Bool {
        return (try readVarint()) != 0
    }

    public mutating func readFixed32() throws -> UInt32 {
        guard offset + 4 <= data.count else { throw ProtoError.unexpectedEndOfData }
        let val = data.subdata(in: offset..<offset+4).withUnsafeBytes { $0.load(as: UInt32.self) }
        offset += 4
        return UInt32(littleEndian: val)
    }

    public mutating func readFixed64() throws -> UInt64 {
        guard offset + 8 <= data.count else { throw ProtoError.unexpectedEndOfData }
        let val = data.subdata(in: offset..<offset+8).withUnsafeBytes { $0.load(as: UInt64.self) }
        offset += 8
        return UInt64(littleEndian: val)
    }

    public mutating func readFloat() throws -> Float {
        let bits = try readFixed32()
        return Float(bitPattern: bits)
    }

    public mutating func readDouble() throws -> Double {
        let bits = try readFixed64()
        return Double(bitPattern: bits)
    }

    public mutating func readBytes() throws -> Data {
        let length = Int(try readVarint())
        guard length >= 0, offset + length <= data.count else {
            throw ProtoError.unexpectedEndOfData
        }
        let slice = data.subdata(in: offset..<(offset + length))
        offset += length
        return slice
    }

    public mutating func readString() throws -> String {
        let bytes = try readBytes()
        guard let s = String(data: bytes, encoding: .utf8) else {
            throw ProtoError.invalidUtf8String
        }
        return s
    }

    public mutating func readMessage<M: ProtoDecodable>(_ type: M.Type) throws -> M {
        let subData = try readBytes()
        var subReader = ProtoReader(data: subData)
        return try M(from: &subReader)
    }

    public mutating func readPackedInt32() throws -> [Int32] {
        let subData = try readBytes()
        var subReader = ProtoReader(data: subData)
        var results: [Int32] = []
        while !subReader.isAtEnd {
            results.append(try subReader.readInt32())
        }
        return results
    }

    public mutating func readPackedUInt32() throws -> [UInt32] {
        let subData = try readBytes()
        var subReader = ProtoReader(data: subData)
        var results: [UInt32] = []
        while !subReader.isAtEnd {
            results.append(try subReader.readUInt32())
        }
        return results
    }

    public mutating func skipField(wireType: Int) throws {
        switch wireType {
        case ProtoWireType.varint:
            _ = try readVarint()
        case ProtoWireType.fixed64:
            guard offset + 8 <= data.count else { throw ProtoError.unexpectedEndOfData }
            offset += 8
        case ProtoWireType.lengthDelimited:
            let length = Int(try readVarint())
            guard length >= 0, offset + length <= data.count else { throw ProtoError.unexpectedEndOfData }
            offset += length
        case ProtoWireType.fixed32:
            guard offset + 4 <= data.count else { throw ProtoError.unexpectedEndOfData }
            offset += 4
        default:
            throw ProtoError.unknownWireType(wireType)
        }
    }
}
