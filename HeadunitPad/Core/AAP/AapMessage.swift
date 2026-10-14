//
//  AapMessage.swift
//  HeadunitPad
//
//  Android Auto Protocol message framing and model.
//  1:1 port of open-headunit AapMessage.kt.
//

import Foundation

public final class AapMessage: Equatable, CustomStringConvertible {
    public let channel: Int
    public let flags: UInt8
    public let type: Int
    public let dataOffset: Int
    public let size: Int
    public let data: Data

    public var typeUInt16: UInt16 {
        return UInt16(type & 0xFFFF)
    }

    public var channelUInt8: UInt8 {
        return UInt8(channel & 0xFF)
    }

    public static let FRAME_HEADER_SIZE = 4
    public static let DEF_BUFFER_LENGTH = 131080

    public init(channel: Int, flags: UInt8, type: Int, dataOffset: Int, size: Int, data: Data) {
        self.channel = channel
        self.flags = flags
        self.type = type
        self.dataOffset = dataOffset
        self.size = size
        self.data = data
    }

    /// Convenience initializer for raw payloads
    public convenience init(channel: UInt8, flags: UInt8, type: UInt16, payload: Data) {
        var buf = Data()
        buf.append(payload)
        self.init(
            channel: Int(channel),
            flags: flags,
            type: Int(type),
            dataOffset: 0,
            size: payload.count,
            data: buf
        )
    }

    /// Outbound constructor from a protobuf message
    public convenience init(channel: Int, type: Int, proto: ProtoEncodable) {
        let protoBytes = proto.serializedData()
        let totalSize = AapMessage.FRAME_HEADER_SIZE + MsgType.SIZE + protoBytes.count
        var buf = Data(count: totalSize)

        let flagsVal = AapMessage.computeFlags(channel: channel, type: type)
        buf[0] = UInt8(channel & 0xFF)
        buf[1] = flagsVal

        let lengthVal = UInt16(protoBytes.count + MsgType.SIZE)
        buf[2] = UInt8((lengthVal >> 8) & 0xFF)
        buf[3] = UInt8(lengthVal & 0xFF)

        buf[4] = UInt8((type >> 8) & 0xFF)
        buf[5] = UInt8(type & 0xFF)

        buf.replaceSubrange(6..<totalSize, with: protoBytes)

        self.init(
            channel: channel,
            flags: flagsVal,
            type: type,
            dataOffset: AapMessage.FRAME_HEADER_SIZE + MsgType.SIZE,
            size: totalSize,
            data: buf
        )
    }

    public convenience init?(data: Data) {
        guard data.count >= 6 else { return nil }

        let chan = Int(data[0])
        let flg = data[1]
        let length = Int(data[2]) << 8 | Int(data[3])
        let msgType = Int(data[4]) << 8 | Int(data[5])

        let payloadStart = 6
        let payloadLength = length - 2
        guard payloadLength >= 0, data.count >= payloadStart + payloadLength else {
            return nil
        }

        let slice = data.subdata(in: payloadStart..<(payloadStart + payloadLength))
        self.init(channel: chan, flags: flg, type: msgType, dataOffset: 0, size: slice.count, data: slice)
    }

    public var payload: Data {
        guard dataOffset >= 0, dataOffset <= size, size <= data.count else {
            return Data()
        }
        return data.subdata(in: dataOffset..<size)
    }

    public var isAudio: Bool {
        return Channel.isAudio(UInt8(channel))
    }

    public var isVideo: Bool {
        return UInt8(channel) == Channel.ID_VID
    }

    public var totalSize: Int {
        return size
    }

    public func toData() -> Data {
        if dataOffset == 6 && data.count >= size {
            return data.prefix(size)
        }

        var buffer = Data()
        buffer.append(UInt8(channel & 0xFF))
        buffer.append(flags)

        let length = UInt16(payload.count + 2)
        buffer.append(UInt8((length >> 8) & 0xFF))
        buffer.append(UInt8(length & 0xFF))

        buffer.append(UInt8((type >> 8) & 0xFF))
        buffer.append(UInt8(type & 0xFF))

        buffer.append(payload)
        return buffer
    }

    public static func computeFlags(channel: Int, type: Int) -> UInt8 {
        var flags: UInt8 = 0x0b // FIRST | LAST | ENCRYPTED
        if channel != Int(Channel.ID_CTR) && MsgType.isControl(type) {
            // Set Control Flag on non-control channels
            flags = 0x0f // FIRST | LAST | CONTROL | ENCRYPTED
        }
        return flags
    }

    public var description: String {
        return "\(Channel.name(for: UInt8(channel))) \(MsgType.name(type, channel: UInt8(channel))) type:\(type) flags:\(flags) size:\(size) dataOffset:\(dataOffset)"
    }

    public static func == (lhs: AapMessage, rhs: AapMessage) -> Bool {
        guard lhs.channel == rhs.channel,
              lhs.flags == rhs.flags,
              lhs.type == rhs.type,
              lhs.dataOffset == rhs.dataOffset,
              lhs.size == rhs.size,
              lhs.data.count >= lhs.size,
              rhs.data.count >= rhs.size else {
            return false
        }
        return lhs.data.prefix(lhs.size) == rhs.data.prefix(rhs.size)
    }
}

public enum AapFlags {
    public static let CONTROL_MESSAGE: UInt8 = 3
    public static let CONTROL_RESPONSE: UInt8 = 2
    public static let NORMAL_MESSAGE: UInt8 = 0
}

public extension AapMessage {
    static var userSelectionByebyeRequest: AapMessage {
        AapMessage(
            channel: Channel.ID_CTR,
            flags: AapFlags.CONTROL_MESSAGE,
            type: UInt16(ControlMsgType.messageByebyeRequest.rawValue),
            payload: Data([0x08, 0x01])
        )
    }
}
