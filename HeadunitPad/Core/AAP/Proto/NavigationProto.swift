//
//  NavigationProto.swift
//  HeadunitPad
//
//  Android Auto navigation.proto pure Swift models.
//

import Foundation

public enum NavigationMsgType: Int32, CaseIterable {
    case instrumentClusterStart = 0x8001
    case instrumentClusterStop = 0x8002
    case instrumentClusterNavigationStatus = 0x8003
    case nextTurnDetails = 0x8004
    case nextTurnDistanceAndTime = 0x8005
    case instrumentClusterNavigationState = 0x8006
    case instrumentClusterNavigationCurrentPosition = 0x8007
}

public struct NavigationClusterStatus: ProtoCodable, Equatable {
    public enum NavigationStatusEnum: Int32, CaseIterable {
        case unavailable = 0
        case active = 1
        case inactive = 2
        case rerouting = 3
    }

    public var status: NavigationStatusEnum

    public init(status: NavigationStatusEnum = .active) {
        self.status = status
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeEnum(fieldNumber: 1, value: status.rawValue)
    }

    public init(from reader: inout ProtoReader) throws {
        var s = NavigationStatusEnum.active
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: s = NavigationStatusEnum(rawValue: try reader.readInt32()) ?? .active
            default: try reader.skipField(wireType: w)
            }
        }
        self.status = s
    }
}

public struct NextTurnDetail: ProtoCodable, Equatable {
    public enum Side: Int32, CaseIterable {
        case left = 1
        case right = 2
        case unspecified = 3
    }

    public enum NextEvent: Int32, CaseIterable {
        case unknown = 0x00
        case depart = 0x01
        case nameChange = 0x02
        case slightTurn = 0x03
        case turn = 0x04
        case sharpTurn = 0x05
        case uTurn = 0x06
        case onRamp = 0x07
        case offRamp = 0x08
        case fork = 0x09
        case merge = 0x0a
        case roundaboutEnter = 0x0b
        case roundaboutExit = 0x0c
        case roundaboutEnterAndExit = 0x0d
        case straight = 0x0e
        case ferryBoat = 0x10
        case ferryTrain = 0x11
        case destination = 0x13
    }

    public var road: String
    public var side: Side?
    public var nextTurn: NextEvent?
    public var image: Data?
    public var turnNumber: Int32?
    public var turnAngle: Int32?

    public init(
        road: String = "",
        side: Side? = nil,
        nextTurn: NextEvent? = nil,
        image: Data? = nil,
        turnNumber: Int32? = nil,
        turnAngle: Int32? = nil
    ) {
        self.road = road
        self.side = side
        self.nextTurn = nextTurn
        self.image = image
        self.turnNumber = turnNumber
        self.turnAngle = turnAngle
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeString(fieldNumber: 1, value: road)
        if let s = side { writer.writeEnum(fieldNumber: 2, value: s.rawValue) }
        if let nt = nextTurn { writer.writeEnum(fieldNumber: 3, value: nt.rawValue) }
        if let img = image { writer.writeBytes(fieldNumber: 4, value: img) }
        if let tn = turnNumber { writer.writeInt32(fieldNumber: 5, value: tn) }
        if let ta = turnAngle { writer.writeInt32(fieldNumber: 6, value: ta) }
    }

    public init(from reader: inout ProtoReader) throws {
        var road = ""
        var side: Side?
        var nt: NextEvent?
        var img: Data?
        var tn: Int32?
        var ta: Int32?
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: road = try reader.readString()
            case 2: side = Side(rawValue: try reader.readInt32())
            case 3: nt = NextEvent(rawValue: try reader.readInt32())
            case 4: img = try reader.readBytes()
            case 5: tn = try reader.readInt32()
            case 6: ta = try reader.readInt32()
            default: try reader.skipField(wireType: w)
            }
        }
        self.road = road
        self.side = side
        self.nextTurn = nt
        self.image = img
        self.turnNumber = tn
        self.turnAngle = ta
    }
}

public struct NextTurnDistanceEvent: ProtoCodable, Equatable {
    public enum DistanceUnits: Int32, CaseIterable {
        case unknownDistanceUnit = 0
        case meters = 1
        case kilometers = 2
        case kilometersP1 = 3
        case miles = 4
        case milesP1 = 5
        case feet = 6
        case yards = 7
    }

    public var distanceMeters: Int32?
    public var timeToTurnSeconds: Int32?
    public var displayDistanceE3: Int32?
    public var displayDistanceUnit: DistanceUnits?

    public init(
        distanceMeters: Int32? = nil,
        timeToTurnSeconds: Int32? = nil,
        displayDistanceE3: Int32? = nil,
        displayDistanceUnit: DistanceUnits? = nil
    ) {
        self.distanceMeters = distanceMeters
        self.timeToTurnSeconds = timeToTurnSeconds
        self.displayDistanceE3 = displayDistanceE3
        self.displayDistanceUnit = displayDistanceUnit
    }

    public func encode(to writer: inout ProtoWriter) {
        if let d = distanceMeters { writer.writeInt32(fieldNumber: 1, value: d) }
        if let t = timeToTurnSeconds { writer.writeInt32(fieldNumber: 2, value: t) }
        if let e3 = displayDistanceE3 { writer.writeInt32(fieldNumber: 3, value: e3) }
        if let unit = displayDistanceUnit { writer.writeEnum(fieldNumber: 4, value: unit.rawValue) }
    }

    public init(from reader: inout ProtoReader) throws {
        while let (f, w) = try reader.readTag() {
            switch f {
            case 1: self.distanceMeters = try reader.readInt32()
            case 2: self.timeToTurnSeconds = try reader.readInt32()
            case 3: self.displayDistanceE3 = try reader.readInt32()
            case 4: self.displayDistanceUnit = DistanceUnits(rawValue: try reader.readInt32())
            default: try reader.skipField(wireType: w)
            }
        }
    }
}
