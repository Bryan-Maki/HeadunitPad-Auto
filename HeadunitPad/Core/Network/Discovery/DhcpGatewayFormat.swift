//
//  DhcpGatewayFormat.swift
//  HeadunitPad
//
//  1:1 port of open-headunit DhcpGatewayFormat.kt
//  Turns raw 32-bit integer gateway into dotted quad address string.
//

import Foundation

public enum DhcpGatewayFormat {
    /// Formats raw gateway integer to dotted quad IPv4.
    public static func toDottedQuad(rawGateway: UInt32, swapBytes: Bool) -> String? {
        if rawGateway == 0 { return nil }
        let value = swapBytes ? rawGateway.byteSwapped : rawGateway
        let b0 = value & 0xFF
        let b1 = (value >> 8) & 0xFF
        let b2 = (value >> 16) & 0xFF
        let b3 = (value >> 24) & 0xFF
        return "\(b0).\(b1).\(b2).\(b3)"
    }
}
