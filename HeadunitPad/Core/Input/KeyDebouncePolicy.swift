//
//  KeyDebouncePolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit KeyDebouncePolicy.kt
//  Decides which key presses/releases are forwarded to Android Auto to eliminate duplicates.
//

import Foundation

public enum KeyDebouncePolicy {
    public static let mediaWindowMs: Int64 = 600
    public static let defaultWindowMs: Int64 = 300
    public static let stuckPressMs: Int64 = 2000

    public struct KeyState: Equatable {
        public var down: Bool = false
        public var downAt: Int64 = 0
        public var lastForwardedPressAt: Int64? = nil
        public var lastForwardedDownTime: Int64? = nil
        public var pressDropped: Bool = false

        public init(
            down: Bool = false,
            downAt: Int64 = 0,
            lastForwardedPressAt: Int64? = nil,
            lastForwardedDownTime: Int64? = nil,
            pressDropped: Bool = false
        ) {
            self.down = down
            self.downAt = downAt
            self.lastForwardedPressAt = lastForwardedPressAt
            self.lastForwardedDownTime = lastForwardedDownTime
            self.pressDropped = pressDropped
        }
    }

    public struct Result: Equatable {
        public let forward: Bool
        public let releaseFirst: Bool
        public let dropReason: String?
        public let state: KeyState

        public init(
            forward: Bool,
            releaseFirst: Bool = false,
            dropReason: String? = nil,
            state: KeyState
        ) {
            self.forward = forward
            self.releaseFirst = releaseFirst
            self.dropReason = dropReason
            self.state = state
        }
    }

    public static func decide(
        state: KeyState,
        isPress: Bool,
        downTime: Int64?,
        isMediaKey: Bool,
        now: Int64
    ) -> Result {
        let id: Int64? = (downTime != nil && downTime! > 0) ? downTime : nil

        if isPress {
            return decidePress(state: state, id: id, isMediaKey: isMediaKey, now: now)
        } else {
            return decideRelease(state: state)
        }
    }

    private static func decidePress(state: KeyState, id: Int64?, isMediaKey: Bool, now: Int64) -> Result {
        let last = state.lastForwardedDownTime
        if let id = id, let last = last, id == last {
            return Result(forward: false, dropReason: "another delivery of the same key event", state: state)
        }

        let identityProvesNewPress = id != nil && last != nil

        if state.down {
            if !identityProvesNewPress && (now - state.downAt) < stuckPressMs {
                return Result(forward: false, dropReason: "the key is already held down", state: state)
            }

            var nextState = state
            nextState.down = true
            nextState.downAt = now
            nextState.lastForwardedPressAt = now
            nextState.lastForwardedDownTime = id
            nextState.pressDropped = false

            return Result(forward: true, releaseFirst: true, state: nextState)
        }

        if let lastPressAt = state.lastForwardedPressAt, !identityProvesNewPress {
            let window = isMediaKey ? mediaWindowMs : defaultWindowMs
            let since = now - lastPressAt
            if since < window {
                var nextState = state
                nextState.pressDropped = true
                return Result(
                    forward: false,
                    dropReason: "duplicate \(since)ms after last press, within \(window)ms",
                    state: nextState
                )
            }
        }

        var nextState = state
        nextState.down = true
        nextState.downAt = now
        nextState.lastForwardedPressAt = now
        nextState.lastForwardedDownTime = id
        nextState.pressDropped = false

        return Result(forward: true, state: nextState)
    }

    private static func decideRelease(state: KeyState) -> Result {
        if state.pressDropped {
            var nextState = state
            nextState.pressDropped = false
            return Result(forward: false, dropReason: "its press was dropped", state: nextState)
        }
        if !state.down {
            return Result(forward: false, dropReason: "no press is outstanding", state: state)
        }
        var nextState = state
        nextState.down = false
        return Result(forward: true, state: nextState)
    }
}
