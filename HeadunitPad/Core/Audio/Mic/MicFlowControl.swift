//
//  MicFlowControl.swift
//  HeadunitPad
//
//  1:1 port of open-headunit MicFlowControl.kt
//

import Foundation

/// Head-unit-to-phone DATA window negotiated by MicrophoneRequest.maxUnacked.
public final class MicFlowControl<T: AnyObject> {
    public enum Offer: Equatable, Sendable {
        case accepted
        case closed
        case overflow
    }

    public static var maxPendingFrames: Int { 4 }

    private let lock = NSLock()
    private let dispatch: (Int64, T) -> Void

    private var pending: [T] = []
    private var queued: [ObjectIdentifier: Int64] = [:]
    private var sent = 0
    private var generation: Int64 = 0
    private var session = 0
    private var window = 0
    private var inFlight = 0
    private var open = false
    private var ready = false

    public init(dispatch: @escaping (Int64, T) -> Void) {
        self.dispatch = dispatch
    }

    public func begin(sessionId: Int, maxUnacked: Int) -> Int64 {
        lock.lock()
        defer { lock.unlock() }

        guard (1...4096).contains(maxUnacked) else {
            fatalError("maxUnacked must be in 1...4096, was \(maxUnacked)")
        }
        generation += 1
        session = sessionId
        window = maxUnacked
        inFlight = 0
        sent = 0
        queued.removeAll()
        pending.removeAll()
        open = true
        ready = false
        return generation
    }

    public func activate(token: Int64) {
        lock.lock()
        defer { lock.unlock() }
        guard isCurrentLocked(token) else { return }
        ready = true
        pumpLocked()
    }

    public func offer(frame: T) -> Offer {
        lock.lock()
        defer { lock.unlock() }

        if !open { return .closed }
        if pending.count >= MicFlowControl.maxPendingFrames { return .overflow }
        pending.append(frame)
        pumpLocked()
        return .accepted
    }

    public func acknowledge(sessionId: Int, count: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if !open || sessionId != session || count <= 0 || count > sent {
            return false
        }
        inFlight -= count
        sent -= count
        pumpLocked()
        return true
    }

    public func claim(token: Int64, frame: T) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let id = ObjectIdentifier(frame)
        if !isCurrentLocked(token) || queued[id] != token {
            return false
        }
        queued.removeValue(forKey: id)
        sent += 1
        return true
    }

    public func isCurrent(_ token: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCurrentLocked(token)
    }

    private func isCurrentLocked(_ token: Int64) -> Bool {
        return open && token == generation
    }

    @discardableResult
    public func close() -> [T] {
        lock.lock()
        defer { lock.unlock() }

        open = false
        ready = false
        generation += 1
        inFlight = 0
        sent = 0
        let items = pending
        pending.removeAll()
        queued.removeAll()
        return items
    }

    private func pumpLocked() {
        while open && ready && inFlight < window && !pending.isEmpty {
            inFlight += 1
            let frame = pending.removeFirst()
            queued[ObjectIdentifier(frame)] = generation
            dispatch(generation, frame)
        }
    }
}
