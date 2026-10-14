//
//  ReturnRearmPolicy.swift
//  HeadunitPad
//
//  1:1 Port of open-headunit ReturnRearmPolicy.kt
//

import Foundation

/// Whether a return to the screen must re-arm keyframe recovery itself.
public enum ReturnRearmPolicy {
    public static func shouldRearm(
        stoppedOnStop: Bool,
        surfaceSet: Bool,
        lastSurfaceSetMs: Int64,
        resumedAtMs: Int64
    ) -> Bool {
        return stoppedOnStop && surfaceSet && lastSurfaceSetMs < resumedAtMs
    }
}
