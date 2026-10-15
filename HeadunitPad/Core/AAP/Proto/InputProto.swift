//
//  InputProto.swift
//  HeadunitPad
//
//  Android Auto input.proto pure Swift models.
//

import Foundation

public enum InputMsgType: Int32, CaseIterable {
    case event = 0x8001
    case bindingRequest = 0x8002
    case bindingResponse = 0x8003
}

public struct ProtoKey: ProtoCodable, Equatable {
    public var keycode: UInt32
    public var down: Bool
    public var metastate: UInt32?
    public var longpress: Bool?

    public init(keycode: UInt32, down: Bool, metastate: UInt32? = nil, longpress: Bool? = nil) {
        self.keycode = keycode
        self.down = down
        self.metastate = metastate
        self.longpress = longpress
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeUInt32(fieldNumber: 1, value: keycode)
        writer.writeBool(fieldNumber: 2, value: down)
        if let meta = metastate { writer.writeUInt32(fieldNumber: 3, value: meta) }
        if let lp = longpress { writer.writeBool(fieldNumber: 4, value: lp) }
    }

    public init(from reader: inout ProtoReader) throws {
        var keycode: UInt32 = 0
        var down = false
        var meta: UInt32?
        var lp: Bool?
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: keycode = try reader.readUInt32()
            case 2: down = try reader.readBool()
            case 3: meta = try reader.readUInt32()
            case 4: lp = try reader.readBool()
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.keycode = keycode
        self.down = down
        self.metastate = meta
        self.longpress = lp
    }
}

public struct ProtoKeyEvent: ProtoCodable, Equatable {
    public var keys: [ProtoKey]

    public init(keys: [ProtoKey] = []) {
        self.keys = keys
    }

    public func encode(to writer: inout ProtoWriter) {
        for key in keys {
            writer.writeMessage(fieldNumber: 1, message: key)
        }
    }

    public init(from reader: inout ProtoReader) throws {
        var keys: [ProtoKey] = []
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: keys.append(try reader.readMessage(ProtoKey.self))
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.keys = keys
    }
}

public struct ProtoTouchEvent: ProtoCodable, Equatable {
    public enum PointerAction: Int32, CaseIterable {
        case touchActionDown = 0
        case touchActionUp = 1
        case touchActionMove = 2
        case touchActionCancel = 3
        case touchActionOutside = 4
        case touchActionPointerDown = 5
        case touchActionPointerUp = 6

        public static let press = PointerAction.touchActionDown
        public static let release = PointerAction.touchActionUp
        public static let drag = PointerAction.touchActionMove
        public static let down = PointerAction.touchActionDown
        public static let up = PointerAction.touchActionUp
        public static let move = PointerAction.touchActionMove
        public static let moved = PointerAction.touchActionMove
        public static let cancel = PointerAction.touchActionCancel
        public static let pointerDown = PointerAction.touchActionPointerDown
        public static let pointerUp = PointerAction.touchActionPointerUp
    }

    public struct Pointer: ProtoCodable, Equatable {
        public var x: UInt32
        public var y: UInt32
        public var pointerId: UInt32

        public init(x: UInt32 = 0, y: UInt32 = 0, pointerId: UInt32 = 0) {
            self.x = x
            self.y = y
            self.pointerId = pointerId
        }

        public func encode(to writer: inout ProtoWriter) {
            writer.writeUInt32(fieldNumber: 1, value: x)
            writer.writeUInt32(fieldNumber: 2, value: y)
            writer.writeUInt32(fieldNumber: 3, value: pointerId)
        }

        public init(from reader: inout ProtoReader) throws {
            var x: UInt32 = 0
            var y: UInt32 = 0
            var pid: UInt32 = 0
            while let (fieldNumber, wireType) = try reader.readTag() {
                switch fieldNumber {
                case 1: x = try reader.readUInt32()
                case 2: y = try reader.readUInt32()
                case 3: pid = try reader.readUInt32()
                default: try reader.skipField(wireType: wireType)
                }
            }
            self.x = x
            self.y = y
            self.pointerId = pid
        }
    }

    public var pointerData: [Pointer]
    public var actionIndex: UInt32?
    public var action: PointerAction

    public init(pointerData: [Pointer] = [], actionIndex: UInt32? = nil, action: PointerAction = .touchActionDown) {
        self.pointerData = pointerData
        self.actionIndex = actionIndex
        self.action = action
    }

    public func encode(to writer: inout ProtoWriter) {
        for ptr in pointerData {
            writer.writeMessage(fieldNumber: 1, message: ptr)
        }
        writer.writeUInt32(fieldNumber: 2, value: actionIndex ?? 0)
        writer.writeEnum(fieldNumber: 3, value: action.rawValue)
    }

    public init(from reader: inout ProtoReader) throws {
        var pointers: [Pointer] = []
        var actionIndex: UInt32?
        var action: PointerAction = .touchActionDown
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: pointers.append(try reader.readMessage(Pointer.self))
            case 2: actionIndex = try reader.readUInt32()
            case 3:
                let raw = try reader.readInt32()
                action = PointerAction(rawValue: raw) ?? .touchActionDown
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.pointerData = pointers
        self.actionIndex = actionIndex
        self.action = action
    }
}

public struct RelativeEventRel: ProtoCodable, Equatable {
    public var keycode: UInt32
    public var delta: Int32

    public init(keycode: UInt32 = 0, delta: Int32 = 0) {
        self.keycode = keycode
        self.delta = delta
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeUInt32(fieldNumber: 1, value: keycode)
        writer.writeInt32(fieldNumber: 2, value: delta)
    }

    public init(from reader: inout ProtoReader) throws {
        var keycode: UInt32 = 0
        var delta: Int32 = 0
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: keycode = try reader.readUInt32()
            case 2: delta = try reader.readInt32()
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.keycode = keycode
        self.delta = delta
    }
}

public struct ProtoRelativeEvent: ProtoCodable, Equatable {
    public var data: [RelativeEventRel]

    public init(data: [RelativeEventRel] = []) {
        self.data = data
    }

    public func encode(to writer: inout ProtoWriter) {
        for rel in data {
            writer.writeMessage(fieldNumber: 1, message: rel)
        }
    }

    public init(from reader: inout ProtoReader) throws {
        var rels: [RelativeEventRel] = []
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: rels.append(try reader.readMessage(RelativeEventRel.self))
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.data = rels
    }
}

public struct AbsoluteEventAbs: ProtoCodable, Equatable {
    public var keycode: UInt32
    public var value: Int32

    public init(keycode: UInt32 = 0, value: Int32 = 0) {
        self.keycode = keycode
        self.value = value
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeUInt32(fieldNumber: 1, value: keycode)
        writer.writeInt32(fieldNumber: 2, value: value)
    }

    public init(from reader: inout ProtoReader) throws {
        var keycode: UInt32 = 0
        var value: Int32 = 0
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: keycode = try reader.readUInt32()
            case 2: value = try reader.readInt32()
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.keycode = keycode
        self.value = value
    }
}

public struct ProtoAbsoluteEvent: ProtoCodable, Equatable {
    public var data: [AbsoluteEventAbs]

    public init(data: [AbsoluteEventAbs] = []) {
        self.data = data
    }

    public func encode(to writer: inout ProtoWriter) {
        for abs in data {
            writer.writeMessage(fieldNumber: 1, message: abs)
        }
    }

    public init(from reader: inout ProtoReader) throws {
        var absList: [AbsoluteEventAbs] = []
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: absList.append(try reader.readMessage(AbsoluteEventAbs.self))
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.data = absList
    }
}

public struct InputReport: ProtoCodable, Equatable {
    public var timestamp: UInt64
    public var dispChannelId: Int32?
    public var touchEvent: ProtoTouchEvent?
    public var keyEvent: ProtoKeyEvent?
    public var absoluteEvent: ProtoAbsoluteEvent?
    public var relativeEvent: ProtoRelativeEvent?
    public var touchpadEvent: ProtoTouchEvent?

    public init(
        timestamp: UInt64 = 0,
        dispChannelId: Int32? = nil,
        touchEvent: ProtoTouchEvent? = nil,
        keyEvent: ProtoKeyEvent? = nil,
        absoluteEvent: ProtoAbsoluteEvent? = nil,
        relativeEvent: ProtoRelativeEvent? = nil,
        touchpadEvent: ProtoTouchEvent? = nil
    ) {
        self.timestamp = timestamp
        self.dispChannelId = dispChannelId
        self.touchEvent = touchEvent
        self.keyEvent = keyEvent
        self.absoluteEvent = absoluteEvent
        self.relativeEvent = relativeEvent
        self.touchpadEvent = touchpadEvent
    }

    public func encode(to writer: inout ProtoWriter) {
        writer.writeUInt64(fieldNumber: 1, value: timestamp)
        if let disp = dispChannelId { writer.writeInt32(fieldNumber: 2, value: disp) }
        if let touch = touchEvent { writer.writeMessage(fieldNumber: 3, message: touch) }
        if let key = keyEvent { writer.writeMessage(fieldNumber: 4, message: key) }
        if let abs = absoluteEvent { writer.writeMessage(fieldNumber: 5, message: abs) }
        if let rel = relativeEvent { writer.writeMessage(fieldNumber: 6, message: rel) }
        if let pad = touchpadEvent { writer.writeMessage(fieldNumber: 7, message: pad) }
    }

    public init(from reader: inout ProtoReader) throws {
        var ts: UInt64 = 0
        var disp: Int32?
        var touch: ProtoTouchEvent?
        var key: ProtoKeyEvent?
        var abs: ProtoAbsoluteEvent?
        var rel: ProtoRelativeEvent?
        var pad: ProtoTouchEvent?
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1: ts = try reader.readUInt64()
            case 2: disp = try reader.readInt32()
            case 3: touch = try reader.readMessage(ProtoTouchEvent.self)
            case 4: key = try reader.readMessage(ProtoKeyEvent.self)
            case 5: abs = try reader.readMessage(ProtoAbsoluteEvent.self)
            case 6: rel = try reader.readMessage(ProtoRelativeEvent.self)
            case 7: pad = try reader.readMessage(ProtoTouchEvent.self)
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.timestamp = ts
        self.dispChannelId = disp
        self.touchEvent = touch
        self.keyEvent = key
        self.absoluteEvent = abs
        self.relativeEvent = rel
        self.touchpadEvent = pad
    }
}

public struct KeyBindingRequest: ProtoCodable, Equatable {
    public var keycodes: [Int32]

    public init(keycodes: [Int32] = []) {
        self.keycodes = keycodes
    }

    public func encode(to writer: inout ProtoWriter) {
        for kc in keycodes {
            writer.writeInt32(fieldNumber: 1, value: kc)
        }
    }

    public init(from reader: inout ProtoReader) throws {
        var kcs: [Int32] = []
        while let (fieldNumber, wireType) = try reader.readTag() {
            switch fieldNumber {
            case 1:
                if wireType == ProtoWireType.lengthDelimited {
                    kcs.append(contentsOf: try reader.readPackedInt32())
                } else {
                    kcs.append(try reader.readInt32())
                }
            default: try reader.skipField(wireType: wireType)
            }
        }
        self.keycodes = kcs
    }
}

public struct BindingResponse: ProtoCodable, Equatable {
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
