//
//  WifiLauncherMode.swift
//  HeadunitPad
//
//  1:1 port of open-headunit WifiLauncherMode.kt
//  Supported wireless launcher connection modes.
//

import Foundation

public enum WifiLauncherMode: Int, CaseIterable, Codable {
    case manual = 0
    case auto = 1
    case native = 3

    public static let `default`: WifiLauncherMode = .native

    public static func byIdOrDefault(_ id: Int) -> WifiLauncherMode {
        return WifiLauncherMode(rawValue: id) ?? .default
    }
}
