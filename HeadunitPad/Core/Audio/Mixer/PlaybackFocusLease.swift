//
//  PlaybackFocusLease.swift
//  HeadunitPad
//
//  Ported 1:1 from open-headunit PlaybackFocusLease.kt
//

import Foundation

final class PlaybackFocusLease {
    struct Request: Equatable {
        let version: Int64
        let sinceMs: Int64
    }

    struct Activity: Equatable {
        let ownerId: ObjectIdentifier
        let revision: Int64
    }

    private let lock = NSLock()
    private var owners: [Int: ObjectIdentifier] = [:]
    private var active: [Int: Activity] = [:]
    private var revision: Int64 = 0
    private var pending: Request?
    private var ready = false
    private var closed = false

    func register(channel: Int, owner: AnyObject) -> Int64? {
        lock.lock()
        defer { lock.unlock() }

        if closed { return nil }
        let ownerId = ObjectIdentifier(owner)
        if owners[channel] == ownerId { return nil }
        owners[channel] = ownerId
        return endActivity(channel: channel)
    }

    func retire(channel: Int, owner: AnyObject) -> Int64? {
        lock.lock()
        defer { lock.unlock() }

        let ownerId = ObjectIdentifier(owner)
        if owners[channel] != ownerId { return nil }
        owners.removeValue(forKey: channel)
        return endActivity(channel: channel)
    }

    private func endActivity(channel: Int) -> Int64? {
        if active.removeValue(forKey: channel) == nil { return nil }
        revision += 1
        if !active.isEmpty { return nil }
        pending = nil
        ready = false
        return revision
    }

    func activity(channel: Int, owner: AnyObject, nowMs: Int64) -> Request? {
        lock.lock()
        defer { lock.unlock() }

        let ownerId = ObjectIdentifier(owner)
        if closed || owners[channel] != ownerId { return nil }
        revision += 1
        active[channel] = Activity(ownerId: ownerId, revision: revision)
        if ready || pending != nil { return nil }
        let req = Request(version: revision, sinceMs: nowMs)
        pending = req
        return req
    }

    func accepts(request: Request) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed && pending == request
    }

    func complete(request: Request) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if !(!closed && pending == request) { return false }
        pending = nil
        ready = true
        return true
    }

    func canRender(nowMs: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if closed || active.isEmpty { return false }
        if let request = pending {
            if !ready && (nowMs - request.sinceMs >= 500) {
                pending = nil
                ready = true
            }
        }
        return ready
    }

    func snapshot() -> [Int: Activity] {
        lock.lock()
        defer { lock.unlock() }
        return active
    }

    func release(channel: Int, expected: Activity) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if active[channel] != expected { return false }
        active.removeValue(forKey: channel)
        if !active.isEmpty { return false }
        pending = nil
        ready = false
        return true
    }

    func isOpen() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed
    }

    func clear() -> Int64 {
        lock.lock()
        defer { lock.unlock() }

        active.removeAll()
        pending = nil
        ready = false
        revision += 1
        return revision
    }

    func acceptsRelease(version: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !closed && active.isEmpty && revision == version
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }

        active.removeAll()
        pending = nil
        ready = false
        revision += 1
        owners.removeAll()
        closed = true
    }
}
