//
//  ConnectionStagePolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ConnectionStagePolicy.kt
//  Ensures connection stage updates move forward and never cause status display stutter.
//

import Foundation

public enum ConnectionStagePolicy {
    public static func shouldApply(current: ConnectionStage?, candidate: ConnectionStage) -> Bool {
        guard let current = current else { return true }
        return candidate.rank >= current.rank
    }

    public static func shouldRetreat(current: ConnectionStage?, from: ConnectionStage) -> Bool {
        return current == from
    }
}
