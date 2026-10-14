//
//  ConnectionIssues.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ConnectionIssues.kt
//  Actionable diagnostics for wireless connection failures on iPadOS.
//

import Foundation

public enum ConnectionIssue: String, CaseIterable, Identifiable {
    case wifiRadioOff = "WIFI_RADIO_OFF"
    case hotspotNotRunning = "HOTSPOT_NOT_RUNNING"
    case videoLinkTooSlow = "VIDEO_LINK_TOO_SLOW"
    case phoneHoldsStaleEndpoint = "PHONE_HOLDS_STALE_ENDPOINT"
    case peerUnresponsive = "PEER_UNRESPONSIVE"
    case portBindingFailed = "PORT_BINDING_FAILED"
    case noLanClientsFound = "NO_LAN_CLIENTS_FOUND"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .wifiRadioOff:
            return "Wi-Fi Is Turned Off"
        case .hotspotNotRunning:
            return "Hotspot / Wi-Fi Not Connected"
        case .videoLinkTooSlow:
            return "Wireless Bandwidth Too Low"
        case .phoneHoldsStaleEndpoint:
            return "Phone Has Stale Connection"
        case .peerUnresponsive:
            return "Phone Stopped Responding"
        case .portBindingFailed:
            return "Wireless Port In Use"
        case .noLanClientsFound:
            return "No Android Devices Found"
        }
    }

    public var description: String {
        switch self {
        case .wifiRadioOff:
            return "The iPad Wi-Fi interface is inactive. Turn on Wi-Fi in iOS Settings to connect to your phone."
        case .hotspotNotRunning:
            return "Please connect this iPad to your phone's Personal Hotspot or join the same in-car Wi-Fi network."
        case .videoLinkTooSlow:
            return "Video frames are dropping or starved. Try switching to 5GHz Wi-Fi, lowering resolution to 720p, or enabling HEVC."
        case .phoneHoldsStaleEndpoint:
            return "The phone's Android Auto service still has a dangling previous session. Toggle Airplane Mode or restart wireless projection."
        case .peerUnresponsive:
            return "The phone stopped responding to link keep-alives. The connection will automatically retry."
        case .portBindingFailed:
            return "Could not bind to local port 5277 or 5288. Another background instance may be running."
        case .noLanClientsFound:
            return "Subnet scan completed without locating an active Android Auto client on the local network."
        }
    }

    public var remedy: String {
        switch self {
        case .wifiRadioOff:
            return "Open Settings -> Wi-Fi and turn Wi-Fi on."
        case .hotspotNotRunning:
            return "Open Control Center and connect to your phone's Wi-Fi hotspot."
        case .videoLinkTooSlow:
            return "In Settings, set Resolution to 720p and Video Codec to HEVC (H.265)."
        case .phoneHoldsStaleEndpoint:
            return "On your phone, close Android Auto or toggle Wi-Fi off and on."
        case .peerUnresponsive:
            return "Check if phone battery saver or screen lock put the Wi-Fi link to sleep."
        case .portBindingFailed:
            return "Restart the application to release bound networking sockets."
        case .noLanClientsFound:
            return "Ensure phone is connected to the same Wi-Fi and 'Wireless Android Auto' is enabled in Android Auto developer settings."
        }
    }
}

public struct StandingIssue: Equatable {
    public let issue: ConnectionIssue
    public let raisedAtMs: Int64

    public init(issue: ConnectionIssue, raisedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.issue = issue
        self.raisedAtMs = raisedAtMs
    }
}
