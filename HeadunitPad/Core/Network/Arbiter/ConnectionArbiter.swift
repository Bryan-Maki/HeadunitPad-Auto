//
//  ConnectionArbiter.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ConnectionArbiter.kt
//  Coordinates competing wireless connection attempts and prevents race conditions.
//

import Foundation

public final class ConnectionArbiter {
    public static let shared = ConnectionArbiter()

    public final class Claim: CustomStringConvertible {
        public let tier: ConnectionPriorityPolicy.Tier
        public let owner: ConnectionPriorityPolicy.Owner
        public let what: String
        public let sinceMs: Int64

        public init(tier: ConnectionPriorityPolicy.Tier, owner: ConnectionPriorityPolicy.Owner, what: String, sinceMs: Int64) {
            self.tier = tier
            self.owner = owner
            self.what = what
            self.sinceMs = sinceMs
        }

        public var description: String {
            return "\(what) (\(tier))"
        }
    }

    public protocol Actions: AnyObject {
        func preempt(loser: Claim)
        func standDownWireless(by: Claim) -> Bool
        func giveBack(wireless: Bool)
    }

    public weak var actions: Actions?
    private let lock = NSLock()
    private var holder: Claim?
    private var wirelessOwed: Bool = false
    private var generation: Int64 = 0

    public init() {}

    public func claim(tier: ConnectionPriorityPolicy.Tier, owner: ConnectionPriorityPolicy.Owner, what: String) -> Claim? {
        lock.lock()
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let held = holder
        let holderAge = held.map { now - $0.sinceMs } ?? 0

        let verdict = ConnectionPriorityPolicy.decide(
            incoming: tier,
            incomingOwner: owner,
            holder: held?.tier,
            holderOwner: held?.owner,
            holderAgeMs: holderAge
        )

        if verdict == .refuse {
            print("ConnectionArbiter: \(what) (\(tier)) refused while \(String(describing: held)) in flight")
            lock.unlock()
            return nil
        }

        let loser: Claim? = (verdict == .preempt) ? held : nil
        generation += 1
        let newClaim = Claim(tier: tier, owner: owner, what: what, sinceMs: now)
        holder = newClaim
        lock.unlock()

        if let loser = loser {
            print("ConnectionArbiter: \(newClaim) preempts \(loser)")
            actions?.preempt(loser: loser)
        }

        if ConnectionPriorityPolicy.standsDownWireless(owner: owner) {
            if actions?.standDownWireless(by: newClaim) == true {
                lock.lock()
                wirelessOwed = true
                lock.unlock()
            }
        }

        return newClaim
    }

    public func release(claim: Claim?, sessionFormed: Bool) {
        guard let claim = claim else { return }
        lock.lock()
        guard holder === claim else {
            lock.unlock()
            return
        }
        holder = nil
        let oweWireless = wirelessOwed && !sessionFormed
        wirelessOwed = false
        lock.unlock()

        if oweWireless {
            actions?.giveBack(wireless: true)
        }
    }

    public func reset() {
        lock.lock()
        holder = nil
        wirelessOwed = false
        lock.unlock()
    }
}
