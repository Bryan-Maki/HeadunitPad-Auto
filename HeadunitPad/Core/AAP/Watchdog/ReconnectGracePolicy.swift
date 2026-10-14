//
//  ReconnectGracePolicy.swift
//  HeadunitPad
//
//  1:1 Port of open-headunit ReconnectGracePolicy.kt
//

import Foundation

/// How long the projection activity holds its reconnecting overlay before giving up and finishing.
public enum ReconnectGracePolicy {

    public static let baseUsbMs: Int64 = 8_000
    public static let baseWirelessMs: Int64 = 20_000
    public static let progressGraceMs: Int64 = 14_000
    public static let ceilingMs: Int64 = 45_000

    public enum Ended: Sendable, Equatable {
        case baseExpired
        case progressWentStale
        case ceilingReached
    }

    public static func baseFor(isUsb: Bool = false) -> Int64 {
        return isUsb ? baseUsbMs : baseWirelessMs
    }

    public static func keepWaiting(isUsb: Bool = false, sinceDisconnectMs: Int64, sinceProgressMs: Int64?) -> Bool {
        return endedBecause(isUsb: isUsb, sinceDisconnectMs: sinceDisconnectMs, sinceProgressMs: sinceProgressMs) == nil
    }

    public static func endedBecause(isUsb: Bool = false, sinceDisconnectMs: Int64, sinceProgressMs: Int64?) -> Ended? {
        if sinceDisconnectMs >= ceilingMs {
            return .ceilingReached
        } else if sinceProgressMs == nil {
            return sinceDisconnectMs >= baseFor(isUsb: isUsb) ? .baseExpired : nil
        } else if let progress = sinceProgressMs, progress >= progressGraceMs && sinceDisconnectMs >= baseFor(isUsb: isUsb) {
            return .progressWentStale
        } else {
            return nil
        }
    }
}
