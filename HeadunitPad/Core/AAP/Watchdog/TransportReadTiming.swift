//
//  TransportReadTiming.swift
//  HeadunitPad
//
//  1:1 port of open-headunit TransportReadTiming.kt
//  Records stage durations of inbound AAP packet reading, decryption and dispatch.
//

import Foundation

public struct TransportReadTiming: Equatable {
    public let channel: Int
    public let readerGapMs: Int64
    public let headerMs: Int64
    public let bodyMs: Int64
    public let decryptMs: Int64
    public let dispatchMs: Int64

    public init(
        channel: Int,
        readerGapMs: Int64,
        headerMs: Int64,
        bodyMs: Int64,
        decryptMs: Int64,
        dispatchMs: Int64
    ) {
        self.channel = channel
        self.readerGapMs = readerGapMs
        self.headerMs = headerMs
        self.bodyMs = bodyMs
        self.decryptMs = decryptMs
        self.dispatchMs = dispatchMs
    }

    public static func isProcessingSlow(readerGapMs: Int64, afterHeaderMs: Int64) -> Bool {
        return readerGapMs >= 50 || afterHeaderMs >= 50
    }
}
