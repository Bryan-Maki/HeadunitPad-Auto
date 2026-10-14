//
//  WifiLauncherRestartPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit WifiLauncherRestartPolicy.kt
//  Whether a request to arm the wireless stack should be refused as already answered.
//

import Foundation

public enum WifiLauncherRestartPolicy {
    public static func refusesRestart(
        activeIsStarted: Bool,
        sameConfiguration: Bool,
        force: Bool
    ) -> Bool {
        return !force && activeIsStarted && sameConfiguration
    }
}
