//
//  AacDecoderRecoveryPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AacDecoderRecoveryPolicy.kt
//

import Foundation

/// Whether a failed AAC decoder is rebuilt or parked. A failed codec may never return another
/// input buffer; merely timing out each submission would discard audio for the rest of the session.
/// Rebuilds recover that path, while the count and spacing prevent a persistently failing codec
/// from churning.
public enum AacDecoderRecoveryPolicy {
    /// Rebuilds allowed per track lifetime.
    public static let maxRebuilds = 3

    /// Minimum spacing between rebuilds in milliseconds.
    public static let minSpacingMs: Int64 = 1_000

    public static func allowsRebuild(rebuildsSoFar: Int, sinceLastRebuildMs: Int64) -> Bool {
        return rebuildsSoFar < maxRebuilds && (rebuildsSoFar == 0 || sinceLastRebuildMs >= minSpacingMs)
    }
}
