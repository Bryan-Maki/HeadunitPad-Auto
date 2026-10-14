//
//  VideoFeedThrottlePolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit VideoFeedThrottlePolicy.kt
//  Controls backpressure waiting when queue is full before shedding frames,
//  triggering AAP transport natural flow-control instead of visual artifacts.
//

import Foundation

public enum VideoFeedThrottlePolicy {

    public static let offerSliceMs: Int64 = 50
    public static let waitBudgetMs: Int64 = 1000

    public static func shouldKeepWaiting(elapsedMs: Int64, running: Bool) -> Bool {
        return running && (elapsedMs < waitBudgetMs)
    }
}
