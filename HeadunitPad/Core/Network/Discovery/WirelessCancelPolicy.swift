//
//  WirelessCancelPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit WirelessCancelPolicy.kt
//  Whether manual cancellation by user holds the wireless stack down.
//

import Foundation

public enum WirelessCancelPolicy {
    public static func refusesBringUp(cancelledByUser: Bool, userRequested: Bool) -> Bool {
        return cancelledByUser && !userRequested
    }
}
