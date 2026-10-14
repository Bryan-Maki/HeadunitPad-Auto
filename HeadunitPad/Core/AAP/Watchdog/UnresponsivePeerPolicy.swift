//
//  UnresponsivePeerPolicy.swift
//  HeadunitPad
//
//  1:1 Port of open-headunit UnresponsivePeerPolicy.kt
//

import Foundation

/// How hard to keep retrying a peer that accepts the TCP connection and then says nothing.
public enum UnresponsivePeerPolicy {

    /// Consecutive silent failures against one endpoint before the retry cadence drops.
    public static let silentFailuresBeforeBackoff: Int = 3

    /// And before it drops again, once many attempts have plainly not been answered.
    public static let silentFailuresBeforeLastTier: Int = 10

    /// The ordinary re-scan delay.
    public static let normalRescanMs: Int64 = 10_000

    /// Slow enough to stop manufacturing stranded sockets, fast enough to notice a fix.
    public static let backoffRescanMs: Int64 = 60_000

    /// A last tier rather than giving up completely.
    public static let lastTierRescanMs: Int64 = 300_000

    /// Delay before the next discovery sweep.
    public static func rescanDelayMs(consecutiveSilentFailures: Int) -> Int64 {
        if consecutiveSilentFailures >= silentFailuresBeforeLastTier {
            return lastTierRescanMs
        } else if consecutiveSilentFailures >= silentFailuresBeforeBackoff {
            return backoffRescanMs
        } else {
            return normalRescanMs
        }
    }

    /// True exactly once per episode, at the point the backoff engages.
    public static func shouldExplain(consecutiveSilentFailures: Int) -> Bool {
        return consecutiveSilentFailures == silentFailuresBeforeBackoff
    }

    /// The new streak length after a silent failure.
    public static func countAfterSilentFailure(
        previousCount: Int,
        previousEndpoint: String?,
        endpoint: String?
    ) -> Int {
        if let prev = previousEndpoint, let cur = endpoint, prev == cur {
            return previousCount + 1
        } else {
            return 1
        }
    }
}
