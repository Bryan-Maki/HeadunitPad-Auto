//
//  DecoderRestartPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit DecoderRestartPolicy.kt
//  Decides whether a decoder restart counts toward codec-type flip and permanent-failure latch.
//

import Foundation

public enum DecoderRestartPolicy {

    public static func countsTowardFailure(
        codecTypePinned: Bool,
        renderedSinceLastStart: Bool,
        renderedThisSession: Bool
    ) -> Bool {
        return codecTypePinned && !renderedSinceLastStart && !renderedThisSession
    }
}
