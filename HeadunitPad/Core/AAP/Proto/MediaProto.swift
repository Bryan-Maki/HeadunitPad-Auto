//
//  MediaProto.swift
//  HeadunitPad
//
//  Android Auto media.proto pure Swift models.
//

import Foundation

public enum MediaMsgType: Int32, CaseIterable {
    case mediaMessageData = 0
    case mediaMessageCodecConfig = 1
    case mediaMessageSetup = 0x8000
    case mediaMessageStart = 0x8001
    case mediaMessageStop = 0x8002
    case mediaMessageConfig = 0x8003
    case mediaMessageAck = 0x8004
    case mediaMessageMicrophoneRequest = 0x8005
    case mediaMessageMicrophoneResponse = 0x8006
    case mediaMessageVideoFocusRequest = 0x8007
    case mediaMessageVideoFocusNotification = 0x8008
    case mediaMessageUpdateUiConfigRequest = 0x8009
    case mediaMessageUpdateUiConfigReply = 0x800A
    case mediaMessageAudioUnderflowNotification = 0x800B
}

public enum MediaCodecType: Int32, CaseIterable {
    case mediaCodecAudioPcm = 1
    case mediaCodecAudioAacLc = 2
    case mediaCodecVideoH264Bp = 3
    case mediaCodecAudioAacLcAdts = 4
    case mediaCodecVideoVp9 = 5
    case mediaCodecVideoAv1 = 6
    case mediaCodecVideoH265 = 7
}

public enum AudioStreamType: Int32, CaseIterable {
    case none = 0
    case speech = 1
    case system = 2
    case media = 3
    case alarm = 4
    case guidance = 5
    case announcement = 6
    case ring = 7
}

public struct AudioConfiguration: ProtoCodable, Equatable {
    public var sampleRate: UInt32
    public var numberOfBits: UInt32
    public var numberOfChannels: UInt32

    public init(sampleRate: UInt32 = 48000, numberOfBits: UInt32 = 16, numberOfChannels: UInt32 = 2) {
        self.sampleRate = sampleRate
        self.numberOfBits = numberOfBits
        self.numberOfChannels = numberOfChannels
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeUInt32(fieldNumber: 1, value: sampleRate)
        writer.writeUInt32(fieldNumber: 2, value: numberOfBits)
        writer.writeUInt32(fieldNumber: 3, value: numberOfChannels)
    }

    public init(from reader: inout ProtoReader) throws {
        var sampleRate: UInt32 = 48000
        var numberOfBits: UInt32 = 16
        var numberOfChannels: UInt32 = 2
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: sampleRate = try reader.readUInt32()
            case 2: numberOfBits = try reader.readUInt32()
            case 3: numberOfChannels = try reader.readUInt32()
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.sampleRate = sampleRate
        self.numberOfBits = numberOfBits
        self.numberOfChannels = numberOfChannels
    }
}

public struct MediaStart: ProtoCodable, Equatable {
    public var sessionId: Int32
    public var configurationIndex: UInt32

    public init(sessionId: Int32 = 0, configurationIndex: UInt32 = 0) {
        self.sessionId = sessionId
        self.configurationIndex = configurationIndex
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeInt32(fieldNumber: 1, value: sessionId)
        writer.writeUInt32(fieldNumber: 2, value: configurationIndex)
    }

    public init(from reader: inout ProtoReader) throws {
        var sessionId: Int32 = 0
        var configIndex: UInt32 = 0
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: sessionId = try reader.readInt32()
            case 2: configIndex = try reader.readUInt32()
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.sessionId = sessionId
        self.configurationIndex = configIndex
    }
}

public struct MediaAck: ProtoCodable, Equatable {
    public var sessionId: Int32
    public var ack: UInt32?
    public var receiveTimestampNs: [UInt64]

    public init(sessionId: Int32 = 0, ack: UInt32? = 1, receiveTimestampNs: [UInt64] = []) {
        self.sessionId = sessionId
        self.ack = ack
        self.receiveTimestampNs = receiveTimestampNs
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeInt32(fieldNumber: 1, value: sessionId)
        writer.writeUInt32(fieldNumber: 2, value: ack ?? 1)
        for ts in receiveTimestampNs {
            writer.writeUInt64(fieldNumber: 3, value: ts)
        }
    }

    public init(from reader: inout ProtoReader) throws {
        var sessionId: Int32 = 0
        var ack: UInt32?
        var timestamps: [UInt64] = []
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: sessionId = try reader.readInt32()
            case 2: ack = try reader.readUInt32()
            case 3:
                if wireType == ProtoWireType.lengthDelimited {
                    let subData = try reader.readBytes()
                    var sub = ProtoReader(data: subData)
                    while !sub.isAtEnd {
                        timestamps.append(try sub.readUInt64())
                    }
                } else {
                    timestamps.append(try reader.readUInt64())
                }
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.sessionId = sessionId
        self.ack = ack
        self.receiveTimestampNs = timestamps
    }
}

public struct AudioUnderflowNotification: ProtoCodable, Equatable {
    public var sessionId: Int32

    public init(sessionId: Int32 = 0) {
        self.sessionId = sessionId
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeInt32(fieldNumber: 1, value: sessionId)
    }

    public init(from reader: inout ProtoReader) throws {
        var sessionId: Int32 = 0
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: sessionId = try reader.readInt32()
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.sessionId = sessionId
    }
}

public struct MicrophoneRequest: ProtoCodable, Equatable {
    public var open: Bool
    public var ancEnabled: Bool?
    public var ecEnabled: Bool?
    public var maxUnacked: Int32?

    public init(open: Bool = false, ancEnabled: Bool? = nil, ecEnabled: Bool? = nil, maxUnacked: Int32? = nil) {
        self.open = open
        self.ancEnabled = ancEnabled
        self.ecEnabled = ecEnabled
        self.maxUnacked = maxUnacked
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeBool(fieldNumber: 1, value: open)
        if let anc = ancEnabled { writer.writeBool(fieldNumber: 2, value: anc) }
        if let ec = ecEnabled { writer.writeBool(fieldNumber: 3, value: ec) }
        if let maxUnacked = maxUnacked { writer.writeInt32(fieldNumber: 4, value: maxUnacked) }
    }

    public init(from reader: inout ProtoReader) throws {
        var open = false
        var anc: Bool?
        var ec: Bool?
        var maxUnacked: Int32?
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: open = try reader.readBool()
            case 2: anc = try reader.readBool()
            case 3: ec = try reader.readBool()
            case 4: maxUnacked = try reader.readInt32()
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.open = open
        self.ancEnabled = anc
        self.ecEnabled = ec
        self.maxUnacked = maxUnacked
    }
}

public struct MicrophoneResponse: ProtoCodable, Equatable {
    public var status: Int32
    public var sessionId: UInt32

    public init(status: Int32 = 0, sessionId: UInt32 = 0) {
        self.status = status
        self.sessionId = sessionId
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeInt32(fieldNumber: 1, value: status)
        writer.writeUInt32(fieldNumber: 2, value: sessionId)
    }

    public init(from reader: inout ProtoReader) throws {
        var status: Int32 = 0
        var session: UInt32 = 0
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: status = try reader.readInt32()
            case 2: session = try reader.readUInt32()
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.status = status
        self.sessionId = session
    }
}

public enum VideoFocusMode: Int32, CaseIterable {
    case videoFocusProjected = 1
    case videoFocusNative = 2
    case videoFocusNativeTransient = 3
    case videoFocusProjectedNoInputFocus = 4
}

public struct VideoFocusRequestNotification: ProtoCodable, Equatable {
    public enum VideoFocusReason: Int32, CaseIterable {
        case unknown = 0
        case phoneScreenOff = 1
        case launchNative = 2
        case videoFocusReasonLastMode = 3
        case videoFocusReasonUserSelection = 4
    }

    public var dispChannelId: Int32?
    public var mode: VideoFocusMode
    public var reason: VideoFocusReason?

    public init(dispChannelId: Int32? = nil, mode: VideoFocusMode = .videoFocusProjected, reason: VideoFocusReason? = nil) {
        self.dispChannelId = dispChannelId
        self.mode = mode
        self.reason = reason
    }

    public func encode(to writer: inout ProtoWriter) {
        if let disp = dispChannelId { writer.writeInt32(fieldNumber: 1, value: disp) }
        writer.writeEnum(fieldNumber: 2, value: mode.rawValue)
        if let reason = reason { writer.writeEnum(fieldNumber: 3, value: reason.rawValue) }
    }

    public init(from reader: inout ProtoReader) throws {
        var disp: Int32?
        var mode: VideoFocusMode = .videoFocusProjected
        var reason: VideoFocusReason?
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: disp = try reader.readInt32()
            case 2:
                let raw = try reader.readInt32()
                mode = VideoFocusMode(rawValue: raw) ?? .videoFocusProjected
            case 3:
                let raw = try reader.readInt32()
                reason = VideoFocusReason(rawValue: raw)
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.dispChannelId = disp
        self.mode = mode
        self.reason = reason
    }
}

public struct VideoFocusNotification: ProtoCodable, Equatable {
    public var mode: VideoFocusMode
    public var unsolicited: Bool

    public init(mode: VideoFocusMode = .videoFocusProjected, unsolicited: Bool = false) {
        self.mode = mode
        self.unsolicited = unsolicited
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeEnum(fieldNumber: 1, value: mode.rawValue)
        writer.writeBool(fieldNumber: 2, value: unsolicited)
    }

    public init(from reader: inout ProtoReader) throws {
        var mode: VideoFocusMode = .videoFocusProjected
        var unsolicited = false
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1:
                let raw = try reader.readInt32()
                mode = VideoFocusMode(rawValue: raw) ?? .videoFocusProjected
            case 2: unsolicited = try reader.readBool()
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.mode = mode
        self.unsolicited = unsolicited
    }
}

public struct MediaSetupRequest: ProtoCodable, Equatable {
    public var type: UInt32

    public init(type: UInt32 = 0) {
        self.type = type
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeUInt32(fieldNumber: 1, value: type)
    }

    public init(from reader: inout ProtoReader) throws {
        var type: UInt32 = 0
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: type = try reader.readUInt32()
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.type = type
    }
}

public struct MediaConfig: ProtoCodable, Equatable {
    public enum ConfigStatus: Int32, CaseIterable {
        case statusWait = 1
        case statusReady = 2
    }

    public var status: ConfigStatus
    public var maxUnacked: UInt32
    public var configurationIndices: [UInt32]

    public init(status: ConfigStatus = .statusReady, maxUnacked: UInt32 = 1, configurationIndices: [UInt32] = []) {
        self.status = status
        self.maxUnacked = maxUnacked
        self.configurationIndices = configurationIndices
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeEnum(fieldNumber: 1, value: status.rawValue)
        writer.writeUInt32(fieldNumber: 2, value: maxUnacked)
        for idx in configurationIndices {
            writer.writeUInt32(fieldNumber: 3, value: idx)
        }
    }

    public init(from reader: inout ProtoReader) throws {
        var status: ConfigStatus = .statusReady
        var maxUnacked: UInt32 = 1
        var indices: [UInt32] = []
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1:
                let raw = try reader.readInt32()
                status = ConfigStatus(rawValue: raw) ?? .statusReady
            case 2: maxUnacked = try reader.readUInt32()
            case 3:
                if wireType == ProtoWireType.lengthDelimited {
                    let subData = try reader.readBytes()
                    var sub = ProtoReader(data: subData)
                    while !sub.isAtEnd {
                        indices.append(try sub.readUInt32())
                    }
                } else {
                    indices.append(try reader.readUInt32())
                }
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.status = status
        self.maxUnacked = maxUnacked
        self.configurationIndices = indices
    }
}

public struct MediaInsets: ProtoCodable, Equatable {
    public var top: Int32?
    public var bottom: Int32?
    public var left: Int32?
    public var right: Int32?

    public init(top: Int32? = nil, bottom: Int32? = nil, left: Int32? = nil, right: Int32? = nil) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }

    public func encode(to writer: inout ProtoWriter) {
        if let top = top { writer.writeInt32(fieldNumber: 1, value: top) }
        if let bottom = bottom { writer.writeInt32(fieldNumber: 2, value: bottom) }
        if let left = left { writer.writeInt32(fieldNumber: 3, value: left) }
        if let right = right { writer.writeInt32(fieldNumber: 4, value: right) }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: self.top = try reader.readInt32()
            case 2: self.bottom = try reader.readInt32()
            case 3: self.left = try reader.readInt32()
            case 4: self.right = try reader.readInt32()
            default: try reader.skipField(wireType: wireType)
            }
        }
    }
}

public struct UiConfig: ProtoCodable, Equatable {
    public var margins: MediaInsets?
    public var contentInsets: MediaInsets?
    public var stableContentInsets: MediaInsets?
    public var uiTheme: Int32?

    public init(margins: MediaInsets? = nil, contentInsets: MediaInsets? = nil, stableContentInsets: MediaInsets? = nil, uiTheme: Int32? = nil) {
        self.margins = margins
        self.contentInsets = contentInsets
        self.stableContentInsets = stableContentInsets
        self.uiTheme = uiTheme
    }

    public func encode(to writer: inout ProtoWriter) {
        if let margins = margins { writer.writeMessage(fieldNumber: 1, message: margins) }
        if let contentInsets = contentInsets { writer.writeMessage(fieldNumber: 2, message: contentInsets) }
        if let stableContentInsets = stableContentInsets { writer.writeMessage(fieldNumber: 3, message: stableContentInsets) }
        if let uiTheme = uiTheme { writer.writeInt32(fieldNumber: 4, value: uiTheme) }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: self.margins = try reader.readMessage(MediaInsets.self)
            case 2: self.contentInsets = try reader.readMessage(MediaInsets.self)
            case 3: self.stableContentInsets = try reader.readMessage(MediaInsets.self)
            case 4: self.uiTheme = try reader.readInt32()
            default: try reader.skipField(wireType: wireType)
            }
        }
    }
}

public struct UpdateUiConfigRequestProto: ProtoCodable, Equatable {
    public var uiConfig: UiConfig

    public init(uiConfig: UiConfig = UiConfig()) {
        self.uiConfig = uiConfig
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeMessage(fieldNumber: 1, message: uiConfig)
    }

    public init(from reader: inout ProtoReader) throws {
        var config = UiConfig()
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: config = try reader.readMessage(UiConfig.self)
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.uiConfig = config
    }
}

public struct UpdateUiConfigReplyProto: ProtoCodable, Equatable {
    public var uiConfig: UiConfig?

    public init(uiConfig: UiConfig? = nil) {
        self.uiConfig = uiConfig
    }

    public func encode(to writer: inout ProtoWriter) {
        if let uiConfig = uiConfig {
            writer.writeMessage(fieldNumber: 1, message: uiConfig)
        }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: self.uiConfig = try reader.readMessage(UiConfig.self)
            default: try reader.skipField(wireType: wireType)
            }
        }
    }
}
