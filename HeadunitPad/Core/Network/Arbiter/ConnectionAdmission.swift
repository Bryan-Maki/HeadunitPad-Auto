//
//  ConnectionAdmission.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ConnectionAdmission.kt
//  Controls connection admission and ensures stale attempts do not block new sessions.
//

import Foundation

public enum ConnectionAdmission {
    public static func admits(inFlight: Bool, userInitiated: Bool) -> Bool {
        if !inFlight { return true }
        return userInitiated
    }
}
