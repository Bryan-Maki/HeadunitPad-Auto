//
//  MarginAnnouncementPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit MarginAnnouncementPolicy.kt
//

import Foundation

public enum MarginAnnouncementPolicy {
    public static let notAnnounced: Int = -1

    public static func shouldReannounce(
        announcedWidthMargin: Int,
        announcedHeightMargin: Int,
        liveWidthMargin: Int,
        liveHeightMargin: Int
    ) -> Bool {
        if announcedWidthMargin == notAnnounced || announcedHeightMargin == notAnnounced {
            return false
        }
        return announcedWidthMargin != liveWidthMargin || announcedHeightMargin != liveHeightMargin
    }

    public static func hasDiverged(
        announcedW: Int,
        announcedH: Int,
        currentW: Int,
        currentH: Int
    ) -> Bool {
        return shouldReannounce(
            announcedWidthMargin: announcedW,
            announcedHeightMargin: announcedH,
            liveWidthMargin: currentW,
            liveHeightMargin: currentH
        )
    }
}
