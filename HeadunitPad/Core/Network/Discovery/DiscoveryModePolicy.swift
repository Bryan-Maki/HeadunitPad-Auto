//
//  DiscoveryModePolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit DiscoveryModePolicy.kt
//  Controls whether discovery sweeps probe port 5289 (Wireless Helper) and port 5277 (AAP server).
//

import Foundation

public enum DiscoveryModePolicy {
    /// Whether the port-5289 probe is worth making (mode 2 = Wireless Helper).
    public static func probesWirelessHelper(mode: Int) -> Bool {
        return mode == 2
    }

    /// Whether the selected configuration uses NetworkDiscovery.
    /// mode: 0 = Manual, 1 = Auto (Headunit Server), 2 = Helper, 3 = Native AA.
    /// strategy: 0 = Common WiFi, 1 = WiFi Direct, 2 = Nearby, 3 = Hotspot Host, 4 = Hotspot Passive.
    public static func usesNetworkDiscovery(mode: Int, strategy: Int) -> Bool {
        switch mode {
        case 3: // Native AA runs its own WPP server and does not scan outward
            return false
        case 2: // Helper mode
            return strategy == 0 || strategy == 3 || strategy == 4
        default:
            return true
        }
    }
}
