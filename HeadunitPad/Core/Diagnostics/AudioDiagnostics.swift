//
//  AudioDiagnostics.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AudioDiagnostics.kt
//  Thread-safe ring buffer for audio channel events and status tracking.
//

import Foundation

public final class AudioDiagnostics: @unchecked Sendable {
    public static let shared = AudioDiagnostics()

    public static let capacity = 64
    private let lock = NSLock()
    private var buffer = [String]()
    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    public init() {}

    public func record(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let entry = "[\(timestamp)] \(message)"
        lock.lock()
        buffer.append(entry)
        if buffer.count > Self.capacity {
            buffer.removeFirst(buffer.count - Self.capacity)
        }
        lock.unlock()
    }

    public func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    public func clear() {
        lock.lock()
        buffer.removeAll()
        lock.unlock()
    }
}
