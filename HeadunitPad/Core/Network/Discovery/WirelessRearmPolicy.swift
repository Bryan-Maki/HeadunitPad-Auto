//
//  WirelessRearmPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit WirelessRearmPolicy.kt
//  Whether a settings change necessitates re-arming the wireless launcher.
//

import Foundation

public enum WirelessRearmPolicy {
    public struct Config: Equatable {
        public let wifiConnectionMode: WifiLauncherMode
        public let wirelessSelected: Bool
        public let listeningPort: Int
        public let targetIp: String?

        public init(
            wifiConnectionMode: WifiLauncherMode,
            wirelessSelected: Bool,
            listeningPort: Int,
            targetIp: String? = nil
        ) {
            self.wifiConnectionMode = wifiConnectionMode
            self.wirelessSelected = wirelessSelected
            self.listeningPort = listeningPort
            self.targetIp = targetIp
        }
    }

    public static func requiresRearm(before: Config, after: Config) -> Bool {
        return before != after
    }
}
