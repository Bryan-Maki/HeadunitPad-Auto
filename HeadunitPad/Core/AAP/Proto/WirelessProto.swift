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

public struct WppCarInfo: ProtoCodable, Equatable {
    public var make: String?
    public var model: String?
    public var modelYear: String?
    public var vehicleId: String?
    public var headUnitMake: String?
    public var headUnitModel: String?
    public var headUnitSoftwareBuild: String?
    public var headUnitSoftwareVersion: String?
    public var bodyType: Int32?

    public init(
        make: String? = nil,
        model: String? = nil,
        modelYear: String? = nil,
        vehicleId: String? = nil,
        headUnitMake: String? = nil,
        headUnitModel: String? = nil,
        headUnitSoftwareBuild: String? = nil,
        headUnitSoftwareVersion: String? = nil,
        bodyType: Int32? = nil
    ) {
        self.make = make
        self.model = model
        self.modelYear = modelYear
        self.vehicleId = vehicleId
        self.headUnitMake = headUnitMake
        self.headUnitModel = headUnitModel
        self.headUnitSoftwareBuild = headUnitSoftwareBuild
        self.headUnitSoftwareVersion = headUnitSoftwareVersion
        self.bodyType = bodyType
    }

    public func encode(to writer: inout ProtoWriter) {
        if let make = make { writer.writeString(fieldNumber: 1, value: make) }
        if let model = model { writer.writeString(fieldNumber: 2, value: model) }
        if let year = modelYear { writer.writeString(fieldNumber: 3, value: year) }
        if let vid = vehicleId { writer.writeString(fieldNumber: 4, value: vid) }
        if let hmake = headUnitMake { writer.writeString(fieldNumber: 5, value: hmake) }
        if let hmodel = headUnitModel { writer.writeString(fieldNumber: 6, value: hmodel) }
        if let build = headUnitSoftwareBuild { writer.writeString(fieldNumber: 7, value: build) }
        if let ver = headUnitSoftwareVersion { writer.writeString(fieldNumber: 8, value: ver) }
        if let btype = bodyType { writer.writeInt32(fieldNumber: 9, value: btype) }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: self.make = try reader.readString()
            case 2: self.model = try reader.readString()
            case 3: self.modelYear = try reader.readString()
            case 4: self.vehicleId = try reader.readString()
            case 5: self.headUnitMake = try reader.readString()
            case 6: self.headUnitModel = try reader.readString()
            case 7: self.headUnitSoftwareBuild = try reader.readString()
            case 8: self.headUnitSoftwareVersion = try reader.readString()
            case 9: self.bodyType = try reader.readInt32()
            default: try reader.skipField(wireType: w)
            }
        }
    }
}

public struct WifiVersionRequest: ProtoCodable, Equatable {
    public var major: Int32?
    public var minor: Int32?
    public var supportedWifiChannelType: WifiChannelType?
    public var supportedWifiChannels: [Int32]
    public var carInfo: WppCarInfo?
    public var wppInfo: WifiProjectionProtocolInfo?

    public init(
        major: Int32? = nil,
        minor: Int32? = nil,
        supportedWifiChannelType: WifiChannelType? = nil,
        supportedWifiChannels: [Int32] = [],
        carInfo: WppCarInfo? = nil,
        wppInfo: WifiProjectionProtocolInfo? = nil
    ) {
        self.major = major
        self.minor = minor
        self.supportedWifiChannelType = supportedWifiChannelType
        self.supportedWifiChannels = supportedWifiChannels
        self.carInfo = carInfo
        self.wppInfo = wppInfo
    }

    public func encode(to writer: inout ProtoWriter) {
        if let maj = major { writer.writeInt32(fieldNumber: 1, value: maj) }
        if let min = minor { writer.writeInt32(fieldNumber: 2, value: min) }
        if let chanType = supportedWifiChannelType { writer.writeEnum(fieldNumber: 3, value: chanType.rawValue) }
        if !supportedWifiChannels.isEmpty {
            writer.writePackedInt32(fieldNumber: 4, values: supportedWifiChannels)
        }
        if let car = carInfo { writer.writeMessage(fieldNumber: 5, value: car) }
        if let wpp = wppInfo { writer.writeMessage(fieldNumber: 6, value: wpp) }
    }

    public init(from reader: inout ProtoReader) throws {
        self.supportedWifiChannels = []
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: self.major = try reader.readInt32()
            case 2: self.minor = try reader.readInt32()
            case 3: self.supportedWifiChannelType = WifiChannelType(rawValue: try reader.readInt32())
            case 4:
                if w == .lengthDelimited {
                    self.supportedWifiChannels = try reader.readPackedInt32()
                } else {
                    self.supportedWifiChannels.append(try reader.readInt32())
                }
            case 5: self.carInfo = try reader.readMessage()
            case 6: self.wppInfo = try reader.readMessage()
            default: try reader.skipField(wireType: w)
            }
        }
    }
}

public struct WppWifiDeviceInfo: ProtoCodable, Equatable {
    public var deviceId: String?
    public var connectivityLifetimeId: String?
    public var deviceName: String?
    public var bluetoothAddress: String?

    public init(deviceId: String? = nil, connectivityLifetimeId: String? = nil, deviceName: String? = nil, bluetoothAddress: String? = nil) {
        self.deviceId = deviceId
        self.connectivityLifetimeId = connectivityLifetimeId
        self.deviceName = deviceName
        self.bluetoothAddress = bluetoothAddress
    }

    public func encode(to writer: inout ProtoWriter) {
        if let id = deviceId { writer.writeString(fieldNumber: 1, value: id) }
        if let cid = connectivityLifetimeId { writer.writeString(fieldNumber: 2, value: cid) }
        if let name = deviceName { writer.writeString(fieldNumber: 3, value: name) }
        if let bt = bluetoothAddress { writer.writeString(fieldNumber: 4, value: bt) }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: self.deviceId = try reader.readString()
            case 2: self.connectivityLifetimeId = try reader.readString()
            case 3: self.deviceName = try reader.readString()
            case 4: self.bluetoothAddress = try reader.readString()
            default: try reader.skipField(wireType: w)
            }
        }
    }
}

public struct WifiVersionResponse: ProtoCodable, Equatable {
    public var major: Int32?
    public var minor: Int32?
    public var deviceSerial: String?
    public var status: Int32?
    public var selectedWifiChannelType: Int32?
    public var deviceInfo: WppWifiDeviceInfo?
    public var setupToken: Data?

    public init(
        major: Int32? = nil,
        minor: Int32? = nil,
        deviceSerial: String? = nil,
        status: Int32? = nil,
        selectedWifiChannelType: Int32? = nil,
        deviceInfo: WppWifiDeviceInfo? = nil,
        setupToken: Data? = nil
    ) {
        self.major = major
        self.minor = minor
        self.deviceSerial = deviceSerial
        self.status = status
        self.selectedWifiChannelType = selectedWifiChannelType
        self.deviceInfo = deviceInfo
        self.setupToken = setupToken
    }

    public func encode(to writer: inout ProtoWriter) {
        if let maj = major { writer.writeInt32(fieldNumber: 1, value: maj) }
        if let min = minor { writer.writeInt32(fieldNumber: 2, value: min) }
        if let serial = deviceSerial { writer.writeString(fieldNumber: 3, value: serial) }
        if let st = status { writer.writeInt32(fieldNumber: 4, value: st) }
        if let sel = selectedWifiChannelType { writer.writeInt32(fieldNumber: 5, value: sel) }
        if let dev = deviceInfo { writer.writeMessage(fieldNumber: 6, value: dev) }
        if let tok = setupToken { writer.writeBytes(fieldNumber: 7, value: tok) }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: self.major = try reader.readInt32()
            case 2: self.minor = try reader.readInt32()
            case 3: self.deviceSerial = try reader.readString()
            case 4: self.status = try reader.readInt32()
            case 5: self.selectedWifiChannelType = try reader.readInt32()
            case 6: self.deviceInfo = try reader.readMessage()
            case 7: self.setupToken = try reader.readBytes()
            default: try reader.skipField(wireType: w)
            }
        }
    }
}

public struct WifiConnectStatus: ProtoCodable, Equatable {
    public var status: Int32?
    public var errorMessageHint: String?

    public init(status: Int32? = nil, errorMessageHint: String? = nil) {
        self.status = status
        self.errorMessageHint = errorMessageHint
    }

    public func encode(to writer: inout ProtoWriter) {
        if let st = status { writer.writeInt32(fieldNumber: 1, value: st) }
        if let hint = errorMessageHint { writer.writeString(fieldNumber: 2, value: hint) }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: self.status = try reader.readInt32()
            case 2: self.errorMessageHint = try reader.readString()
            default: try reader.skipField(wireType: w)
            }
        }
    }
}

public struct WifiStartResponse: ProtoCodable, Equatable {
    public var ipAddress: String?
    public var port: Int32?
    public var status: Int32?

    public init(ipAddress: String? = nil, port: Int32? = nil, status: Int32? = nil) {
        self.ipAddress = ipAddress
        self.port = port
        self.status = status
    }

    public func encode(to writer: inout ProtoWriter) {
        if let ip = ipAddress { writer.writeString(fieldNumber: 1, value: ip) }
        if let p = port { writer.writeInt32(fieldNumber: 2, value: p) }
        if let st = status { writer.writeInt32(fieldNumber: 3, value: st) }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: self.ipAddress = try reader.readString()
            case 2: self.port = try reader.readInt32()
            case 3: self.status = try reader.readInt32()
            default: try reader.skipField(wireType: w)
            }
        }
    }
}

public struct WifiPingRequest: ProtoCodable, Equatable {
    public var timestamp: Int64?
    public init(timestamp: Int64? = nil) { self.timestamp = timestamp }
    public func encode(to writer: inout ProtoWriter) {
        if let ts = timestamp { writer.writeInt64(fieldNumber: 1, value: ts) }
    }
    public init(from reader: inout ProtoReader) throws {
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: self.timestamp = try reader.readInt64()
            default: try reader.skipField(wireType: w)
            }
        }
    }
}

public struct WifiPingResponse: ProtoCodable, Equatable {
    public var timestamp: Int64?
    public init(timestamp: Int64? = nil) { self.timestamp = timestamp }
    public func encode(to writer: inout ProtoWriter) {
        if let ts = timestamp { writer.writeInt64(fieldNumber: 1, value: ts) }
    }
    public init(from reader: inout ProtoReader) throws {
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: self.timestamp = try reader.readInt64()
            default: try reader.skipField(wireType: w)
            }
        }
    }
}

public struct WifiConnectionRejection: ProtoCodable, Equatable {
    public var reason: ConnectionRejectionReason?

    public init(reason: ConnectionRejectionReason? = nil) {
        self.reason = reason
    }

    public func encode(to writer: inout ProtoWriter) {
        if let r = reason { writer.writeEnum(fieldNumber: 1, value: r.rawValue) }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: self.reason = ConnectionRejectionReason(rawValue: try reader.readInt32())
            default: try reader.skipField(wireType: w)
            }
        }
    }
}

