//
//  ConnectionIssues.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ConnectionIssues.kt
//  Models standing wireless connection issues and remediation advice.
//

import Foundation

public enum ConnectionIssue: String, CaseIterable, Equatable, Codable {
    case wifiRadioOff
    case headunitServerNotAnswering
    case connectionRefused5277
    case tlsHandshakeFailed
    case videoLinkTooSlow

    public var title: String {
        switch self {
        case .wifiRadioOff:
            return "Wi-Fi is Turned Off"
        case .headunitServerNotAnswering:
            return "Headunit Server Not Answering"
        case .connectionRefused5277:
            return "Connection Refused (Port 5277)"
        case .tlsHandshakeFailed:
            return "TLS Handshake Failed"
        case .videoLinkTooSlow:
            return "Wireless Link Too Slow"
        }
    }

    public var resolutionAdvice: String {
        switch self {
        case .wifiRadioOff:
            return "Turn on Wi-Fi in iOS Settings to connect to Android Auto wirelessly."
        case .headunitServerNotAnswering:
            return "Ensure 'Start Headunit Server' is running in Android Auto developer settings on the phone."
        case .connectionRefused5277:
            return "The phone actively refused port 5277. Stop and re-start Headunit Server in Android Auto."
        case .tlsHandshakeFailed:
            return "Cryptographic negotiation failed. Check date/time synchronization or re-pair."
        case .videoLinkTooSlow:
            return "Heavy packet drops on video feed. Move closer to the Wi-Fi hotspot or switch to 5GHz."
        }
    }
}

public struct StandingIssue: Equatable, Codable {
    public let issue: ConnectionIssue
    public let raisedAtEpochMs: Int64

    public init(issue: ConnectionIssue, raisedAtEpochMs: Int64) {
        self.issue = issue
        self.raisedAtEpochMs = raisedAtEpochMs
    }
}

public final class ConnectionIssueStore: @unchecked Sendable {
    public static let shared = ConnectionIssueStore()

    private let lock = NSLock()
    private var issues: [StandingIssue] = []
    private let defaultsKey = "headunitpad-standing-connection-issues"

    public init() {
        loadPersisted()
    }

    public func raise(issue: ConnectionIssue, epochMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        lock.lock()
        defer { lock.unlock() }
        issues.removeAll { $0.issue == issue }
        issues.append(StandingIssue(issue: issue, raisedAtEpochMs: epochMs))
        persist()
    }

    public func clear(issue: ConnectionIssue) {
        lock.lock()
        defer { lock.unlock() }
        issues.removeAll { $0.issue == issue }
        persist()
    }

    public func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        issues.removeAll()
        persist()
    }

    public func currentIssues() -> [StandingIssue] {
        lock.lock()
        defer { lock.unlock() }
        return issues
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(issues) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }
    }

    private func loadPersisted() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([StandingIssue].self, from: data) {
            issues = decoded
        }
    }
}
