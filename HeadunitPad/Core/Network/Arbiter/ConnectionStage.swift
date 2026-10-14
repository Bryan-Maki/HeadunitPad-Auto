//
//  ConnectionStage.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ConnectionStage.kt
//  Stages of establishing a wireless connection, ranked monotonically for smooth UI status updates.
//

import Foundation

public enum ConnectionStage: Int, Comparable, CustomStringConvertible {
    case armed = 10
    case preparingNetwork = 20
    case searching = 25
    case creatingNetwork = 30
    case waitingForPhone = 40
    case wakingPhone = 45
    case phoneAnswered = 50
    case sendingCredentials = 55
    case phoneJoining = 60
    case connecting = 70
    case securing = 80
    case startingProjection = 90

    public var rank: Int { return rawValue }

    public static func < (lhs: ConnectionStage, rhs: ConnectionStage) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .armed: return "Ready"
        case .preparingNetwork: return "Preparing Wi-Fi..."
        case .searching: return "Scanning for devices..."
        case .creatingNetwork: return "Setting up network..."
        case .waitingForPhone: return "Waiting for phone..."
        case .wakingPhone: return "Waking phone..."
        case .phoneAnswered: return "Phone detected"
        case .sendingCredentials: return "Negotiating Wi-Fi..."
        case .phoneJoining: return "Phone associating..."
        case .connecting: return "Connecting to Android Auto..."
        case .securing: return "Establishing secure TLS..."
        case .startingProjection: return "Starting projection..."
        }
    }
}
