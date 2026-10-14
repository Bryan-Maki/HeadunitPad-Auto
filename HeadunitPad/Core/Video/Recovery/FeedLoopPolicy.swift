//
//  FeedLoopPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit FeedLoopPolicy.kt
//  Controls whether decoder input feed loop should continue feeding frames.
//

import Foundation

public enum FeedLoopPolicy {
    public static func shouldFeed(running: Bool, isCurrentThread: Bool, hasCodec: Bool, restartPending: Bool) -> Bool {
        return running && isCurrentThread && hasCodec && !restartPending
    }
}
