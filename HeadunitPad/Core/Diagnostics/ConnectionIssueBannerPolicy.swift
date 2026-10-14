//
//  ConnectionIssueBannerPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ConnectionIssueBannerPolicy.kt
//  Decides whether and which connection issue banner should be presented on the UI.
//

import Foundation

public struct ConnectionBannerModel: Equatable {
    public let title: String
    public let message: String
    public let actionTitle: String
    public let issue: ConnectionIssue

    public init(issue: ConnectionIssue) {
        self.issue = issue
        self.title = issue.title
        self.message = issue.description
        self.actionTitle = issue.remedy
    }
}

public enum ConnectionIssueBannerPolicy {

    /// How long an issue remains visible before expiring if not refreshed (e.g. 15 seconds).
    public static let issueExpiryWindowMs: Int64 = 15_000

    /// Decides whether a banner should be shown.
    /// Returns a banner model if a relevant issue is active, or nil if none.
    public static func decideBanner(
        standingIssues: [StandingIssue],
        isConnected: Bool,
        nowMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) -> ConnectionBannerModel? {
        // If already connected and running happily, do not show failure banners
        if isConnected {
            return nil
        }

        // Filter expired issues
        let activeIssues = standingIssues.filter {
            (nowMs - $0.raisedAtMs) < issueExpiryWindowMs
        }

        // Prioritize:
        // 1. Wi-Fi radio off
        // 2. Hotspot not running
        // 3. Port binding failed
        // 4. Video link too slow
        // 5. Any other active issue
        let priorityOrder: [ConnectionIssue] = [
            .wifiRadioOff,
            .hotspotNotRunning,
            .portBindingFailed,
            .videoLinkTooSlow,
            .phoneHoldsStaleEndpoint,
            .peerUnresponsive,
            .noLanClientsFound
        ]

        for prio in priorityOrder {
            if activeIssues.contains(where: { $0.issue == prio }) {
                return ConnectionBannerModel(issue: prio)
            }
        }

        return nil
    }
}
