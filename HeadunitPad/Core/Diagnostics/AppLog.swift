//
//  AppLog.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AppLog.kt and LogFilesHelper.kt
//  Thread-safe in-memory ring buffer with file rotation for diagnostics.
//

import Foundation

public final class AppLog: @unchecked Sendable {
    public static let shared = AppLog()

    public enum Level: String {
        case verbose = "VERBOSE"
        case debug = "DEBUG"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }

    public static let maxMemoryLines = 4000
    public static let maxLogFiles = 10
    public static let maxFileSizeBytes: Int64 = 2 * 1024 * 1024 // 2MB

    private let lock = NSLock()
    private var memoryBuffer: [String] = []
    private let writeQueue = DispatchQueue(label: "com.headunitpad.applog.file", qos: .utility)
    private var currentFileHandle: FileHandle?
    private var currentFileURL: URL?
    private var currentFileBytesWritten: Int64 = 0

    private let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return df
    }()

    private let fileDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        return df
    }()

    public init() {
        setupLoggingDirectory()
    }

    private func logsDirectory() -> URL {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("HeadunitPadLogs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func setupLoggingDirectory() {
        let dir = logsDirectory()
        cleanOldLogFiles(in: dir)
        openNewLogFile(in: dir)
    }

    private func openNewLogFile(in dir: URL) {
        let filename = "log-\(fileDateFormatter.string(from: Date())).txt"
        let fileURL = dir.appendingPathComponent(filename)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        currentFileURL = fileURL
        currentFileHandle = try? FileHandle(forWritingTo: fileURL)
        currentFileHandle?.seekToEndOfFile()
        currentFileBytesWritten = 0
    }

    private func cleanOldLogFiles(in dir: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles) else { return }
        let sorted = files.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return d1 < d2
        }
        if sorted.count >= Self.maxLogFiles {
            let deleteCount = sorted.count - Self.maxLogFiles + 1
            for i in 0..<deleteCount {
                try? FileManager.default.removeItem(at: sorted[i])
            }
        }
    }

    public func log(level: Level, tag: String = "HeadunitPad", message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level.rawValue)] [\(tag)] \(message)"

        lock.lock()
        memoryBuffer.append(line)
        if memoryBuffer.count > Self.maxMemoryLines {
            memoryBuffer.removeFirst(memoryBuffer.count - Self.maxMemoryLines)
        }
        lock.unlock()

        print(line)

        writeQueue.async { [weak self] in
            guard let self = self else { return }
            guard let data = (line + "\n").data(using: .utf8) else { return }
            self.currentFileHandle?.write(data)
            self.currentFileBytesWritten += Int64(data.count)

            if self.currentFileBytesWritten >= Self.maxFileSizeBytes {
                self.currentFileHandle?.closeFile()
                let dir = self.logsDirectory()
                self.cleanOldLogFiles(in: dir)
                self.openNewLogFile(in: dir)
            }
        }
    }

    public static func v(_ message: String, tag: String = "HeadunitPad") {
        shared.log(level: .verbose, tag: tag, message: message)
    }

    public static func d(_ message: String, tag: String = "HeadunitPad") {
        shared.log(level: .debug, tag: tag, message: message)
    }

    public static func i(_ message: String, tag: String = "HeadunitPad") {
        shared.log(level: .info, tag: tag, message: message)
    }

    public static func w(_ message: String, tag: String = "HeadunitPad") {
        shared.log(level: .warn, tag: tag, message: message)
    }

    public static func e(_ message: String, tag: String = "HeadunitPad") {
        shared.log(level: .error, tag: tag, message: message)
    }

    public func recentLogs(maxLines: Int = 4000) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let count = memoryBuffer.count
        if count <= maxLines {
            return memoryBuffer
        }
        return Array(memoryBuffer[(count - maxLines)...])
    }

    public func allLogText() -> String {
        return recentLogs().joined(separator: "\n")
    }

    public func clear() {
        lock.lock()
        memoryBuffer.removeAll()
        lock.unlock()
    }
}
