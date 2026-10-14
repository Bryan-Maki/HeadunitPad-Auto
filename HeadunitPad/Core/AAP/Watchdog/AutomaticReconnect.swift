//
//  AutomaticReconnect.swift
//  HeadunitPad
//
//  1:1 Port of open-headunit AutomaticReconnect.kt
//

import Foundation

/// One service-owned retry timer. Scheduling and cancellation are managed safely.
public final class AutomaticReconnect: @unchecked Sendable {
    private let lock = NSLock()
    private var currentTask: Task<Void, Never>?
    private var ownsCheck: (@Sendable () -> Bool)?

    private let currentState: @Sendable () -> AnyObject?
    private let isStopping: @Sendable () -> Bool

    public init(
        currentState: @escaping @Sendable () -> AnyObject?,
        isStopping: @escaping @Sendable () -> Bool
    ) {
        self.currentState = currentState
        self.isStopping = isStopping
    }

    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        currentTask?.cancel()
        currentTask = nil
        ownsCheck = nil
    }

    public func onStateChanged() {
        lock.lock()
        let stopping = isStopping()
        let owns = ownsCheck?() ?? false
        lock.unlock()

        if stopping || !owns {
            cancel()
        }
    }

    public func schedule(
        endedSession: AnyObject,
        delayMs: Int64,
        ownsCheck: (@Sendable () -> Bool)? = nil,
        reconnect: @escaping @Sendable () -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard currentState() === endedSession, !isStopping() else { return }
        currentTask?.cancel()

        let check = ownsCheck ?? { [weak self, weak endedSession] in
            guard let self = self, let ended = endedSession else { return false }
            return self.currentState() === ended
        }
        self.ownsCheck = check

        currentTask = Task { [weak self] in
            let nanos = UInt64(max(0, delayMs)) * 1_000_000
            try? await Task.sleep(nanoseconds: nanos)
            guard !Task.isCancelled else { return }

            guard let self = self else { return }
            self.lock.lock()
            let shouldRun = !self.isStopping() && (self.ownsCheck?() == true)
            self.lock.unlock()

            if shouldRun {
                reconnect()
            }
        }
    }
}
