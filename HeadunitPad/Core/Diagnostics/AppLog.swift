//
//  AppLog.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AppLog.kt
//  Thread-safe bounded ring buffer logger for diagnostic captures and export.
//

import Foundation

public enum AppLogLevel: Int, Comparable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warn = 3
    case error = 4

    public static func < (lhs: AppLogLevel, rhs: AppLogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    public var tag: String {
        switch self {
        case .verbose: return "V"
        case .debug: return "D"
        case .info: return "I"
        case .warn: return "W"
        case .error: return "E"
        }
    }
}

public struct LogEntry: Equatable {
    public let timestamp: Date
    public let level: AppLogLevel
    public let tag: String
    public let message: String

    public init(timestamp: Date = Date(), level: AppLogLevel, tag: String, message: String) {
        self.timestamp = timestamp
        self.level = level
        self.tag = tag
        self.message = message
    }

    public var formattedLine: String {
        let formatter = ISO8601DateFormatter()
        return "\(formatter.string(from: timestamp)) [\(level.tag)][\(tag)] \(message)"
    }
}

public final class AppLog {
    public static let shared = AppLog()

    public static let maxCapacity: Int = 2000

    private var buffer: [LogEntry] = []
    private let lock = NSLock()
    public var minimumLogLevel: AppLogLevel = .debug

    public init() {}

    public func log(level: AppLogLevel, tag: String, message: String) {
        guard level >= minimumLogLevel else { return }

        let entry = LogEntry(level: level, tag: tag, message: message)
        lock.lock()
        if buffer.count >= AppLog.maxCapacity {
            buffer.removeFirst(buffer.count - AppLog.maxCapacity + 1)
        }
        buffer.append(entry)
        lock.unlock()

        #if DEBUG
        print(entry.formattedLine)
        #endif
    }

    public func v(_ tag: String, _ message: String) {
        log(level: .verbose, tag: tag, message: message)
    }

    public func d(_ tag: String, _ message: String) {
        log(level: .debug, tag: tag, message: message)
    }

    public func i(_ tag: String, _ message: String) {
        log(level: .info, tag: tag, message: message)
    }

    public func w(_ tag: String, _ message: String) {
        log(level: .warn, tag: tag, message: message)
    }

    public func e(_ tag: String, _ message: String) {
        log(level: .error, tag: tag, message: message)
    }

    public func getEntries() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll()
    }

    public func exportToString() -> String {
        let entries = getEntries()
        return entries.map { $0.formattedLine }.joined(separator: "\n")
    }
}
