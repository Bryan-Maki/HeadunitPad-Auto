//
//  NarrowBandProfilePolicy.swift
//  HeadunitPad
//
//  Ported 1:1 from open-headunit NarrowBandProfilePolicy.kt
//

import Foundation

enum NarrowBandProfilePolicy {
    static let fullFrameRate = 60
    static let cappedFrameRate = 30
    static let cappedResolution = ProjectionResolution.p720
    static let max24GhzFrequencyMhz = 4000

    static func runsNarrow(
        supports5Ghz: Bool?,
        sessionFrequencyMhz: Int,
        bandUnreadable: Bool = false
    ) -> Bool {
        return supports5Ghz == false || bandUnreadable || (sessionFrequencyMhz >= 1 && sessionFrequencyMhz <= max24GhzFrequencyMhz)
    }

    static func caps(
        supports5Ghz: Bool?,
        wirelessSession: Bool,
        capEnabled: Bool,
        sessionFrequencyMhz: Int = 0,
        bandUnreadable: Bool = false,
        linkProvedTooSlow: Bool = false
    ) -> Bool {
        return wirelessSession && (linkProvedTooSlow || (capEnabled && runsNarrow(supports5Ghz: supports5Ghz, sessionFrequencyMhz: sessionFrequencyMhz, bandUnreadable: bandUnreadable)))
    }

    static func cappedFrameRate(
        fpsLimit: Int,
        supports5Ghz: Bool?,
        wirelessSession: Bool,
        capEnabled: Bool,
        sessionFrequencyMhz: Int = 0,
        bandUnreadable: Bool = false,
        linkProvedTooSlow: Bool = false
    ) -> Int {
        if caps(supports5Ghz: supports5Ghz, wirelessSession: wirelessSession, capEnabled: capEnabled, sessionFrequencyMhz: sessionFrequencyMhz, bandUnreadable: bandUnreadable, linkProvedTooSlow: linkProvedTooSlow) {
            return min(fpsLimit, cappedFrameRate)
        } else {
            return fpsLimit
        }
    }

    static func useAac(
        userChoice: Bool,
        supports5Ghz: Bool?,
        wirelessSession: Bool,
        capEnabled: Bool,
        sessionFrequencyMhz: Int = 0,
        bandUnreadable: Bool = false,
        linkProvedTooSlow: Bool = false
    ) -> Bool {
        return userChoice || caps(supports5Ghz: supports5Ghz, wirelessSession: wirelessSession, capEnabled: capEnabled, sessionFrequencyMhz: sessionFrequencyMhz, bandUnreadable: bandUnreadable, linkProvedTooSlow: linkProvedTooSlow)
    }

    static func linkCeiling(
        supports5Ghz: Bool?,
        wirelessSession: Bool,
        capEnabled: Bool,
        sessionFrequencyMhz: Int = 0,
        bandUnreadable: Bool = false,
        linkProvedTooSlow: Bool = false
    ) -> ProjectionResolution? {
        if caps(supports5Ghz: supports5Ghz, wirelessSession: wirelessSession, capEnabled: capEnabled, sessionFrequencyMhz: sessionFrequencyMhz, bandUnreadable: bandUnreadable, linkProvedTooSlow: linkProvedTooSlow) {
            return cappedResolution
        } else {
            return nil
        }
    }

    static func advice(
        supports5Ghz: Bool?,
        fpsLimit: Int,
        wirelessSession: Bool,
        capEnabled: Bool = true,
        sessionFrequencyMhz: Int = 0,
        bandUnreadable: Bool = false,
        linkProvedTooSlow: Bool = false
    ) -> String? {
        guard wirelessSession else { return nil }

        if linkProvedTooSlow {
            return "Connections here have repeatedly set up every channel and then ended without a single video frame arriving. Asking for at most 720p at \(cappedFrameRate) fps with AAC audio."
        }

        guard runsNarrow(supports5Ghz: supports5Ghz, sessionFrequencyMhz: sessionFrequencyMhz, bandUnreadable: bandUnreadable) else { return nil }

        let why: String
        if supports5Ghz == false {
            why = "This device has no 5 GHz Wi-Fi band, session runs over 2.4 GHz"
        } else if sessionFrequencyMhz >= 1 && sessionFrequencyMhz <= max24GhzFrequencyMhz {
            why = "This session's network is on 2.4 GHz"
        } else {
            why = "Wi-Fi band could not be determined"
        }

        if !capEnabled {
            if fpsLimit != fullFrameRate { return nil }
            return "\(why). Full 60 fps offered because lower profile on 2.4 GHz is disabled."
        }

        return "\(why). Asking for at most 720p at \(cappedFrameRate) fps and AAC audio to preserve stability."
    }
}
