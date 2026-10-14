//
//  AapMessageFraming.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AapMessageFraming.kt
//

import Foundation

public enum AapMessageFraming {
    public static let FLAG_BIT_FIRST: UInt8 = 0x01
    public static let FLAG_BIT_LAST: UInt8 = 0x02
    /// Routes a control message independently of the channel on which it arrived.
    public static let FLAG_BIT_CONTROL: UInt8 = 0x04
    public static let FLAG_BIT_ENCRYPTED: UInt8 = 0x08

    public static func isLast(_ flags: UInt8) -> Bool {
        return (flags & FLAG_BIT_LAST) != 0
    }

    public static func carriesTotalLength(_ flags: UInt8) -> Bool {
        return carriesMessageType(flags) && !isLast(flags)
    }

    /// The type begins here, but a short first fragment may not contain both bytes yet.
    public static func carriesMessageType(_ flags: UInt8) -> Bool {
        return (flags & FLAG_BIT_FIRST) != 0
    }

    /// One permit per complete DATA message; CSD and partial fragments consume none.
    public static func completesMediaData(type: Int, flags: UInt8) -> Bool {
        return type == 0 && isLast(flags)
    }

    public static func carriesTotalLength(flags: Int) -> Bool {
        return carriesTotalLength(UInt8(flags & 0xFF))
    }

    public static func carriesMessageType(flags: Int) -> Bool {
        return carriesMessageType(UInt8(flags & 0xFF))
    }
}
