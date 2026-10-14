//
//  AutoConnectHoldPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AutoConnectHoldPolicy.kt
//  Controls whether auto-connect attempts should be delayed or held off.
//

import Foundation

public enum AutoConnectHoldPolicy {
    public static func holdsOff(sessionLive: Bool, manualDisconnect: Bool) -> Bool {
        return sessionLive || manualDisconnect
    }
}
