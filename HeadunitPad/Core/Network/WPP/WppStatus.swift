//
//  WppStatus.swift
//  HeadunitPad
//
//  1:1 port of open-headunit WppStatus.kt
//  Human-readable status code names for Android Auto WPP messages.
//

import Foundation

public enum WppStatus {
    private static let names: [Int: String] = [
        1: "UNSOLICITED_MESSAGE",
        0: "SUCCESS",
        -1: "NO_COMPATIBLE_VERSION",
        -2: "WIFI_INACCESSIBLE_CHANNEL",
        -3: "WIFI_INCORRECT_CREDENTIALS",
        -4: "PROJECTION_ALREADY_STARTED",
        -5: "WIFI_DISABLED",
        -6: "WIFI_NOT_YET_STARTED",
        -7: "INVALID_HOST",
        -8: "NO_SUPPORTED_WIFI_CHANNELS",
        -9: "INSTRUCT_USER_TO_CHECK_THE_PHONE",
        -10: "PHONE_WIFI_DISABLED",
        -11: "WIFI_NETWORK_UNAVAILABLE"
    ]

    public static func describe(_ status: Int?) -> String {
        guard let status = status else { return "-" }
        let name = names[status] ?? "unknown"
        return "\(name)(\(status))"
    }
}
