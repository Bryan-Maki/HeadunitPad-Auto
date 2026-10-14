//
//  PlaybackFocusPolicy.swift
//  HeadunitPad
//
//  Ported 1:1 from open-headunit PlaybackFocusPolicy.kt
//

import Foundation

enum PlaybackFocusPolicy {
    enum Mode: Int, CaseIterable {
        case auto = 0
        case always = 1
        case never = 2

        static func fromInt(_ value: Int) -> Mode {
            return Mode(rawValue: value) ?? .auto
        }
    }

    static let selfDefeatingLimit = 2
    static let selfDefeatingWindowMs: Int64 = 5_000

    static func shouldAcquire(
        mode: Mode,
        staticAudioFocus: Bool,
        audioSinkEnabled: Bool,
        isAudioChannel: Bool,
        selfDefeatingLatched: Bool
    ) -> Bool {
        if staticAudioFocus || !audioSinkEnabled || !isAudioChannel {
            return false
        }

        switch mode {
        case .never:
            return false
        case .always:
            return true
        case .auto:
            return !selfDefeatingLatched
        }
    }

    static func shouldAcquirePermanent(
        mode: Mode,
        staticAudioFocus: Bool,
        audioSinkEnabled: Bool,
        btMediaLinkActive: Bool
    ) -> Bool {
        if !staticAudioFocus || !audioSinkEnabled {
            return false
        }

        switch mode {
        case .never:
            return false
        case .always:
            return true
        case .auto:
            return !btMediaLinkActive
        }
    }

    static func countsAsSelfDefeating(isMediaChannel: Bool, msSinceAcquire: Int64) -> Bool {
        return isMediaChannel && msSinceAcquire >= 0 && msSinceAcquire < selfDefeatingWindowMs
    }
}
