//
//  SensorsProto.swift
//  HeadunitPad
//
//  Android Auto sensors.proto pure Swift models.
//

import Foundation

public enum SensorsMsgType: Int32, CaseIterable {
    case sensorStartRequest = 0x8001
    case sensorStartResponse = 0x8002
    case sensorEvent = 0x8003
}

public enum SensorType: Int32, CaseIterable {
    case location = 1
    case compass = 2
    case carSpeed = 3
    case rpm = 4
    case odometer = 5
    case fuelLevel = 6
    case parkingBrake = 7
    case gear = 8
    case diagnostics = 9
    case night = 10
    case environment = 11
    case hvac = 12
    case drivingStatus = 13
    case deadReconing = 14
    case passenger = 15
    case door = 16
    case light = 17
    case tire = 18
    case accel = 19
    case gyro = 20
    case gps = 21
}

public struct SensorBatch: ProtoCodable, Equatable {
    public struct LocationData: ProtoCodable, Equatable {
        public var timestamp: UInt64
        public var latitude: Int32
        public var longitude: Int32
        public var accuracy: UInt32
        public var altitude: Int32?
        public var speed: Int32?
        public var bearing: Int32?

        public init(
            timestamp: UInt64 = 0,
            latitude: Int32 = 0,
            longitude: Int32 = 0,
            accuracy: UInt32 = 0,
            altitude: Int32? = nil,
            speed: Int32? = nil,
            bearing: Int32? = nil
        ) {
            self.timestamp = timestamp
            self.latitude = latitude
            self.longitude = longitude
            self.accuracy = accuracy
            self.altitude = altitude
            self.speed = speed
            self.bearing = bearing
        }

        public func encode(to writer: inout ProtoWriter) {
            writer.writeUInt64(fieldNumber: 1, value: timestamp)
            writer.writeInt32(fieldNumber: 2, value: latitude)
            writer.writeInt32(fieldNumber: 3, value: longitude)
            writer.writeUInt32(fieldNumber: 4, value: accuracy)
            if let alt = altitude { writer.writeInt32(fieldNumber: 5, value: alt) }
            if let spd = speed { writer.writeInt32(fieldNumber: 6, value: spd) }
            if let brg = bearing { writer.writeInt32(fieldNumber: 7, value: brg) }
        }

        public init(from reader: inout ProtoReader) throws {
            var ts: UInt64 = 0
            var lat: Int32 = 0
            var lon: Int32 = 0
            var acc: UInt32 = 0
            var alt: Int32?
            var spd: Int32?
            var brg: Int32?
            while let (fieldNumber, wireType) = try reader.readTag() {
                switch fieldNumber {
                case 1: ts = try reader.readUInt64()
                case 2: lat = try reader.readInt32()
                case 3: lon = try reader.readInt32()
                case 4: acc = try reader.readUInt32()
                case 5: alt = try reader.readInt32()
                case 6: spd = try reader.readInt32()
                case 7: brg = try reader.readInt32()
                default: try reader.skipField(wireType: wireType)
                }
            }
            self.timestamp = ts
            self.latitude = lat
            self.longitude = lon
            self.accuracy = acc
            self.altitude = alt
            self.speed = spd
            self.bearing = brg
        }
    }

    public struct NightData: ProtoCodable, Equatable {
        public var isNightMode: Bool

        public init(isNightMode: Bool = false) {
            self.isNightMode = isNightMode
        }

        public func encode(to writer: inout ProtoWriter) {
            writer.writeBool(fieldNumber: 1, value: isNightMode)
        }

        public init(from reader: inout ProtoReader) throws {
            var isNight = false
            while let (fieldNumber, wireType) = try reader.readTag() {
                switch fieldNumber {
                case 1: isNight = try reader.readBool()
                default: try reader.skipField(wireType: wireType)
                }
            }
            self.isNightMode = isNight
        }
    }

    public struct DrivingStatusData: ProtoCodable, Equatable {
        public enum Status: Int32, CaseIterable {
            case unrestricted = 0
            case noVideo = 1
            case noKeyboardInput = 2
            case noVoiceInput = 4
            case noConfig = 8
            case limitMessageLen = 16
            case fullyRestricted = 31
        }

        public var status: Int32

        public init(status: Int32 = 0) {
            self.status = status
        }

        public func encode(to writer: inout ProtoWriter) {
            writer.writeInt32(fieldNumber: 1, value: status)
        }

        public init(from reader: inout ProtoReader) throws {
            var status: Int32 = 0
            while let (fieldNumber, wireType) = try reader.readTag() {
                switch fieldNumber {
                case 1: status = try reader.readInt32()
                default: try reader.skipField(wireType: wireType)
                }
            }
            self.status = status
        }
    }

    public struct ParkingBrakeData: ProtoCodable, Equatable {
        public var isEngaged: Bool

        public init(isEngaged: Bool = false) {
            self.isEngaged = isEngaged
        }

        public func encode(to writer: inout ProtoWriter) {
            writer.writeBool(fieldNumber: 1, value: isEngaged)
        }

        public init(from reader: inout ProtoReader) throws {
            var engaged = false
            while let (fieldNumber, wireType) = try reader.readTag() {
                switch fieldNumber {
                case 1: engaged = try reader.readBool()
                default: try reader.skipField(wireType: wireType)
                }
            }
            self.isEngaged = engaged
        }
    }

    public var locationData: [LocationData]
    public var nightMode: [NightData]
    public var drivingStatus: [DrivingStatusData]
    public var parkingBrakeData: [ParkingBrakeData]

    public init(
        locationData: [LocationData] = [],
        nightMode: [NightData] = [],
        drivingStatus: [DrivingStatusData] = [],
        parkingBrakeData: [ParkingBrakeData] = []
    ) {
        self.locationData = locationData
        self.nightMode = nightMode
        self.drivingStatus = drivingStatus
        self.parkingBrakeData = parkingBrakeData
    }

    public func encode(to writer: inout ProtoWriter) {
        for loc in locationData { writer.writeMessage(fieldNumber: 1, message: loc) }
        for brake in parkingBrakeData { writer.writeMessage(fieldNumber: 7, message: brake) }
        for night in nightMode { writer.writeMessage(fieldNumber: 10, message: night) }
        for driving in drivingStatus { writer.writeMessage(fieldNumber: 13, message: driving) }
    }

    public init(from reader: inout ProtoReader) throws {
        var locs: [LocationData] = []
        var brakes: [ParkingBrakeData] = []
        var nights: [NightData] = []
        var drivings: [DrivingStatusData] = []
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: locs.append(try reader.readMessage(LocationData.self))
            case 7: brakes.append(try reader.readMessage(ParkingBrakeData.self))
            case 10: nights.append(try reader.readMessage(NightData.self))
            case 13: drivings.append(try reader.readMessage(DrivingStatusData.self))
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.locationData = locs
        self.parkingBrakeData = brakes
        self.nightMode = nights
        self.drivingStatus = drivings
    }
}

public struct SensorRequest: ProtoCodable, Equatable {
    public var type: SensorType
    public var minUpdatePeriod: Int64

    public init(type: SensorType = .night, minUpdatePeriod: Int64 = 0) {
        self.type = type
        self.minUpdatePeriod = minUpdatePeriod
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeEnum(fieldNumber: 1, value: type.rawValue)
        writer.writeInt64(fieldNumber: 2, value: minUpdatePeriod)
    }

    public init(from reader: inout ProtoReader) throws {
        var type: SensorType = .night
        var minPeriod: Int64 = 0
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1:
                let raw = try reader.readInt32()
                type = SensorType(rawValue: raw) ?? .night
            case 2: minPeriod = try reader.readInt64()
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.type = type
        self.minUpdatePeriod = minPeriod
    }
}

public struct SensorResponse: ProtoCodable, Equatable {
    public var status: MessageStatus

    public init(status: MessageStatus = .statusSuccess) {
        self.status = status
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeEnum(fieldNumber: 1, value: status.rawValue)
    }

    public init(from reader: inout ProtoReader) throws {
        var status: MessageStatus = .statusSuccess
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1:
                let raw = try reader.readInt32()
                status = MessageStatus(rawValue: raw) ?? .statusSuccess
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.status = status
    }
}

public typealias SensorEventIndicationProto = SensorBatch
public typealias NightData = SensorBatch.NightData
