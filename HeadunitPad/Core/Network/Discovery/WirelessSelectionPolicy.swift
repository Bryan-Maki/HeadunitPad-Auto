//
//  WirelessSelectionPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit WirelessSelectionPolicy.kt
//  Whether the wireless stack may arm itself when the user never chose a wireless connection.
//

import Foundation

public enum WirelessSelectionPolicy {
    public static func refusesBringUp(wirelessSelected: Bool, userRequested: Bool) -> Bool {
        return !wirelessSelected && !userRequested
    }
}
