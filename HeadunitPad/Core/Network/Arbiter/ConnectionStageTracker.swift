//
//  ConnectionStageTracker.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ConnectionStageTracker.kt
//  Maintains current connection stage, notifying listeners monotonically.
//

import Foundation

public final class ConnectionStageTracker {
    public private(set) var currentStage: ConnectionStage?
    public var onStageChanged: ((ConnectionStage) -> Void)?

    public init() {}

    public func beginAttempt() {
        currentStage = nil
    }

    public func advance(to candidate: ConnectionStage) {
        if ConnectionStagePolicy.shouldApply(current: currentStage, candidate: candidate) {
            currentStage = candidate
            DispatchQueue.main.async { [weak self] in
                self?.onStageChanged?(candidate)
            }
        }
    }

    public func retreat(from stage: ConnectionStage, to fallback: ConnectionStage) {
        if ConnectionStagePolicy.shouldRetreat(current: currentStage, from: stage) {
            currentStage = fallback
            DispatchQueue.main.async { [weak self] in
                self?.onStageChanged?(fallback)
            }
        }
    }
}
