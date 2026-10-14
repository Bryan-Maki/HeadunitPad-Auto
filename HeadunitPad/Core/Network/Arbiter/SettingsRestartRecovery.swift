//
//  SettingsRestartRecovery.swift
//  HeadunitPad
//
//  1:1 port of open-headunit SettingsRestartRecovery.kt
//  Coordinates seamless reconnection when projection settings are altered during an active session.
//

import Foundation

public enum SettingsRestartRecovery {
    public static func requiresSessionRestart(resolutionChanged: Bool, orientationChanged: Bool) -> Bool {
        return resolutionChanged || orientationChanged
    }
}
