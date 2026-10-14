//
//  LinkGapMonitor.swift
//  HeadunitPad
//
//  1:1 port of open-headunit LinkGapMonitor.kt
//  Measures link and media silence intervals without blocking the receive path.
//

import Foundation

public final class LinkGapMonitor {
    public static let gapThresholdMs: Int64 = 1000
    public static let windowMs: Int64 = 30_000
    public static let subjectLink = "link"
    public static let subjectVideo = "video"
    public static let subjectAudio = "audio"

    public struct Report: Equatable {
        public let subject: String
        public let gapCount: Int
        public var gaps: Int { return gapCount }
        public let deadMs: Int64
        public let longestMs: Int64
        public let windowMs: Int64
        public let intervalMs: Double?

        public var deadPercent: Int {
            return windowMs > 0 ? Int((deadMs * 100) / windowMs) : 0
        }
    }

    public static let minGapsMedia: Int = 2
    public static let maxDeadPercentMedia: Int = 85

    public let subject: String
    private let minGapsToReport: Int
    private let maxDeadPercentToReport: Int

    private var started: Bool = false
    private var lastMessageMs: Int64 = 0
    private var windowStartMs: Int64 = 0
    private var gapCount: Int = 0
    private var deadMs: Int64 = 0
    private var longestMs: Int64 = 0
    private var gapStarts: [Int64] = []

    public init(
        subject: String = LinkGapMonitor.subjectLink,
        minGaps: Int = 1,
        maxDeadPercent: Int = 100
    ) {
        self.subject = subject
        self.minGapsToReport = minGaps
        self.maxDeadPercentToReport = maxDeadPercent
    }

    public convenience init(
        subject: String = LinkGapMonitor.subjectLink,
        minGapsToReport: Int,
        maxDeadPercentToReport: Int = 100
    ) {
        self.init(subject: subject, minGaps: minGapsToReport, maxDeadPercent: maxDeadPercentToReport)
    }

    public func onMessage(nowMs: Int64) -> Report? {
        if !started {
            started = true
            lastMessageMs = nowMs
            windowStartMs = nowMs
            return nil
        }

        let gapMs = nowMs - lastMessageMs
        let gapStartMs = lastMessageMs
        lastMessageMs = nowMs

        if gapMs >= Self.gapThresholdMs {
            gapCount += 1
            deadMs += gapMs
            if gapMs > longestMs { longestMs = gapMs }
            if gapStarts.count < 64 {
                gapStarts.append(gapStartMs)
            }
        }

        let elapsedMs = nowMs - windowStartMs
        let shouldReport = (gapCount >= minGapsToReport) || (elapsedMs >= Self.windowMs)
        if !shouldReport {
            return nil
        }

        let report: Report?
        let deadPercent = elapsedMs > 0 ? Int((deadMs * 100) / elapsedMs) : 0
        if gapCount >= minGapsToReport && (elapsedMs < Self.windowMs || deadPercent <= maxDeadPercentToReport) {
            var interval: Double? = nil
            if gapStarts.count >= 2 {
                let first = gapStarts.first!
                let last = gapStarts.last!
                interval = Double(last - first) / Double(gapStarts.count - 1)
            }
            report = Report(
                subject: subject,
                gapCount: gapCount,
                deadMs: deadMs,
                longestMs: longestMs,
                windowMs: elapsedMs,
                intervalMs: interval
            )
        } else {
            report = nil
        }

        windowStartMs = nowMs
        gapCount = 0
        deadMs = 0
        longestMs = 0
        gapStarts.removeAll(keepingCapacity: true)

        return report
    }

    public func reset() {
        started = false
        lastMessageMs = 0
        windowStartMs = 0
        gapCount = 0
        deadMs = 0
        longestMs = 0
        gapStarts.removeAll()
    }
}
