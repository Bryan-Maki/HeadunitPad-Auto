//
//  ConnectionPriorityPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ConnectionPriorityPolicy.kt
//  Arbitrates between user-initiated connect, wireless stack automatic discovery, and QR pairing.
//

import Foundation

public enum ConnectionPriorityPolicy {
    public enum Tier: Int, Comparable {
        case user = 1
        case wirelessHandshake = 2
        case wirelessDiscovery = 3

        public static func < (lhs: Tier, rhs: Tier) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    public enum Owner: Equatable {
        case manual
        case wirelessStack
        case qrPairing
    }

    public enum Verdict: Equatable {
        case proceed
        case preempt
        case refuse
    }

    public static let staleClaimMs: Int64 = 90_000

    public static func decide(
        incoming: Tier,
        incomingOwner: Owner,
        holder: Tier?,
        holderOwner: Owner?,
        holderAgeMs: Int64
    ) -> Verdict {
        guard let holder = holder, let holderOwner = holderOwner else {
            return .proceed
        }
        if holderAgeMs >= staleClaimMs {
            return .proceed
        }
        if holderOwner == incomingOwner {
            return .proceed
        }
        if incoming < holder {
            return .preempt
        }
        if incoming == .user && holder == .user {
            return .preempt
        }
        return .refuse
    }

    public static func standsDownWireless(owner: Owner) -> Bool {
        switch owner {
        case .wirelessStack:
            return false
        case .manual, .qrPairing:
            return true
        }
    }
}
