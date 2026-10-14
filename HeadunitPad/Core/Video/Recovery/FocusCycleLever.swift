//
//  FocusCycleLever.swift
//  HeadunitPad
//
//  1:1 port of open-headunit FocusCycleLever.kt
//  Exclusive claim on the video-focus release/regain cycle.
//  Prevents overlapping cycles from orphaning the video sink in a permanent black screen.
//

import Foundation

public final class FocusCycleLever {
    private let lock = NSLock()
    private var held: Bool = false

    public init() {}

    public func tryClaim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if held { return false }
        held = true
        return true
    }

    public func release() {
        lock.lock()
        defer { lock.unlock() }
        held = false
    }

    public var isHeld: Bool {
        lock.lock()
        defer { lock.unlock() }
        return held
    }
}
