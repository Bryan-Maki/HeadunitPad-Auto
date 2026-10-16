//
//  ConnectionIssueBannerPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ConnectionIssueBannerPolicy.kt
//  Determines which standing issue should be displayed in the UI banner.
//

import Foundation

public enum ConnectionIssueBannerPolicy {
    /// Selects the most relevant standing issue to display, or nil if connected or dismissed.
    public static func bannerFor(
        standing: [StandingIssue],
        sessionConnected: Bool,
        dismissedAtEpochMs: Int64? = nil
    ) -> StandingIssue? {
        if sessionConnected {
            return nil
        }

        let filtered: [StandingIssue]
        if let dismissed = dismissedAtEpochMs {
            filtered = standing.filter { $0.raisedAtEpochMs > dismissed }
        } else {
            filtered = standing
        }

        return filtered.max(by: { $0.raisedAtEpochMs < $1.raisedAtEpochMs })
    }
}
