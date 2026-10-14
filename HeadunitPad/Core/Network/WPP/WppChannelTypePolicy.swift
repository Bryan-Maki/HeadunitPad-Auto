//
//  WppChannelTypePolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit WppChannelTypePolicy.kt
//  Wi-Fi band capability and channel list policy for WPP negotiation.
//

import Foundation

public enum WppChannelTypePolicy {
    public static func channelTypeFor(supports5Ghz: Bool) -> WifiChannelType {
        return supports5Ghz ? .channelsDualBand : .channels24GhzOnly
    }

    public static func defaultChannelsFor(supports5Ghz: Bool) -> [Int] {
        if supports5Ghz {
            return [2412, 2437, 2462, 5180, 5200, 5220, 5240, 5745, 5765, 5785, 5805]
        } else {
            return [2412, 2437, 2462]
        }
    }
}
