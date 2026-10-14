//
//  WirelessProto.swift
//  HeadunitPad
//
//  Android Auto wireless.proto pure Swift models.
//

import Foundation

public enum AccessPointType: Int32, CaseIterable {
    case `static` = 0
    case dynamic = 1
}

public enum WifiChannelType: Int32, CaseIterable {
    case channels5GhzOnly = 0
    case channels24GhzOnly = 1
    case channelsDualBand = 2
    case noChannelsSupported = 3
}

public enum SecurityMode: Int32, CaseIterable {
    case unknownSecurityMode = 0
    case open = 1
    case wep64 = 2
    case wep128 = 3
    case wpaPersonal = 4
    case wpa2Personal = 8
    case wpaWpa2Personal = 12
    case wpaEnterprise = 20
    case wpa2Enterprise = 24
    case wpaWpa2Enterprise = 28
    case wpa3Personal = 32
    case wpa2Wpa3Personal = 40
}

public enum ConnectionRejectionReason: Int32, CaseIterable {
    case unknown = 0
    case mobileDeviceIdNotFound = 1
    case invalidSetupToken = 2
}

public enum StartRequestReason: Int32, CaseIterable {
    case userRequest = 0
    case autoLaunch = 1
    case automaticRestart = 2
}

public struct WifiStartRequest: ProtoCodable, Equatable {
    public var ipAddress: String
    public var port: Int32
    public var startRequestReason: StartRequestReason?

    public init(ipAddress: String = "", port: Int32 = 0, startRequestReason: StartRequestReason? = nil) {
        self.ipAddress = ipAddress
        self.port = port
        self.startRequestReason = startRequestReason
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeString(fieldNumber: 1, value: ipAddress)
        writer.writeInt32(fieldNumber: 2, value: port)
        if let reason = startRequestReason { writer.writeEnum(fieldNumber: 3, value: reason.rawValue) }
    }

    public init(from reader: inout ProtoReader) throws {
        var ip = ""
        var port: Int32 = 0
        var reason: StartRequestReason?
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: ip = try reader.readString()
            case 2: port = try reader.readInt32()
            case 3: reason = StartRequestReason(rawValue: try reader.readInt32())
            default: try reader.skipField(wireType: w)
            }
        }
        self.ipAddress = ip
        self.port = port
        self.startRequestReason = reason
    }
}

public struct WifiInfoRequest: ProtoCodable, Equatable {
    public init() {}
    public func encode(to writer: inout ProtoWriter) {}
    public init(from reader: inout ProtoReader) throws {
        while let (_, w) = try reader.readTag() { try reader.skipField(wireType: w) }
    }
}

public struct WifiInfoResponse: ProtoCodable, Equatable {
    public var ssid: String
    public var key: String
    public var bssid: String?
    public var securityMode: SecurityMode?
    public var accessPointType: AccessPointType?

    public init(
        ssid: String = "",
        key: String = "",
        bssid: String? = nil,
        securityMode: SecurityMode? = nil,
        accessPointType: AccessPointType? = nil
    ) {
        self.ssid = ssid
        self.key = key
        self.bssid = bssid
        self.securityMode = securityMode
        self.accessPointType = accessPointType
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeString(fieldNumber: 1, value: ssid)
        writer.writeString(fieldNumber: 2, value: key)
        if let bssid = bssid { writer.writeString(fieldNumber: 3, value: bssid) }
        if let sec = securityMode { writer.writeEnum(fieldNumber: 4, value: sec.rawValue) }
        if let ap = accessPointType { writer.writeEnum(fieldNumber: 5, value: ap.rawValue) }
    }

    public init(from reader: inout ProtoReader) throws {
        var ssid = ""
        var key = ""
        var bssid: String?
        var sec: SecurityMode?
        var ap: AccessPointType?
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: ssid = try reader.readString()
            case 2: key = try reader.readString()
            case 3: bssid = try reader.readString()
            case 4: sec = SecurityMode(rawValue: try reader.readInt32())
            case 5: ap = AccessPointType(rawValue: try reader.readInt32())
            default: try reader.skipField(wireType: w)
            }
        }
        self.ssid = ssid
        self.key = key
        self.bssid = bssid
        self.securityMode = sec
        self.accessPointType = ap
    }
}

public struct WifiProjectionProtocolInfo: ProtoCodable, Equatable {
    public var ipAddress: String?
    public var port: Int32?

    public init(ipAddress: String? = nil, port: Int32? = nil) {
        self.ipAddress = ipAddress
        self.port = port
    }

    public func encode(to writer: inout ProtoWriter) {
        if let ip = ipAddress { writer.writeString(fieldNumber: 1, value: ip) }
        if let port = port { writer.writeInt32(fieldNumber: 2, value: port) }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: self.ipAddress = try reader.readString()
            case 2: self.port = try reader.readInt32()
            default: try reader.skipField(wireType: w)
            }
        }
    }
}

public struct ProjectionDeepLinkData: ProtoCodable, Equatable {
    public var ssid: String?
    public var bssid: String?
    public var passkey: String?
    public var wppTcpIp: String?
    public var wppTcpPort: Int32?
    public var bluetoothMac: String?
    public var securityMode: SecurityMode?

    public init(
        ssid: String? = nil,
        bssid: String? = nil,
        passkey: String? = nil,
        wppTcpIp: String? = nil,
        wppTcpPort: Int32? = nil,
        bluetoothMac: String? = nil,
        securityMode: SecurityMode? = nil
    ) {
        self.ssid = ssid
        self.bssid = bssid
        self.passkey = passkey
        self.wppTcpIp = wppTcpIp
        self.wppTcpPort = wppTcpPort
        self.bluetoothMac = bluetoothMac
        self.securityMode = securityMode
    }

    public func encode(to writer: inout ProtoWriter) {
        if let ssid = ssid { writer.writeString(fieldNumber: 1, value: ssid) }
        if let bssid = bssid { writer.writeString(fieldNumber: 2, value: bssid) }
        if let passkey = passkey { writer.writeString(fieldNumber: 3, value: passkey) }
        if let ip = wppTcpIp { writer.writeString(fieldNumber: 4, value: ip) }
        if let port = wppTcpPort { writer.writeInt32(fieldNumber: 5, value: port) }
        if let mac = bluetoothMac { writer.writeString(fieldNumber: 6, value: mac) }
        if let sec = securityMode { writer.writeEnum(fieldNumber: 7, value: sec.rawValue) }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: self.ssid = try reader.readString()
            case 2: self.bssid = try reader.readString()
            case 3: self.passkey = try reader.readString()
            case 4: self.wppTcpIp = try reader.readString()
            case 5: self.wppTcpPort = try reader.readInt32()
            case 6: self.bluetoothMac = try reader.readString()
            case 7: self.securityMode = SecurityMode(rawValue: try reader.readInt32())
            default: try reader.skipField(wireType: w)
            }
        }
    }
}
