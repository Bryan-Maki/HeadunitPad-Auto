//
//  LinkLossTeardownPolicy.swift
//  HeadunitPad
//
//  1:1 Port of open-headunit LinkLossTeardownPolicy.kt
//

import Foundation

/// A warning that the link carrying an active session is about to go away.
public enum LinkLossTrigger: Sendable, Equatable {
    /// The device is shutting down or rebooting.
    case deviceShutdown

    /// Wi-Fi station mode is being switched off.
    case wifiStationDisabling

    /// The car is being switched off: ACC power lost.
    case accPowerLost
}

/// Decides whether to close the current session now, while the link still works,
/// rather than letting it die abruptly and wedging the phone's head unit server.
public enum LinkLossTeardownPolicy {

    public static func shouldTearDown(
        trigger: LinkLossTrigger,
        sessionIsWireless: Bool = true,
        hostsOwnAccessPoint: Bool = false,
        peerIsHeadUnitServer: Bool = false,
        accSignalIsExplicit: Bool = false
    ) -> Bool {
        switch trigger {
        case .deviceShutdown:
            return true

        case .wifiStationDisabling:
            // If the head unit is operating as a Wi-Fi client (not hosting its own hotspot),
            // disabling Wi-Fi immediately breaks the link.
            return sessionIsWireless && !hostsOwnAccessPoint

        case .accPowerLost:
            return accSignalIsExplicit || peerIsHeadUnitServer
        }
    }
}
