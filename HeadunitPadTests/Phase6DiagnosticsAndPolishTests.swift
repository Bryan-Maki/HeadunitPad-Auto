//
//  Phase6DiagnosticsAndPolishTests.swift
//  HeadunitPadTests
//
//  Comprehensive test suite for Phase 6 Diagnostics, HUD, Logging, Backup, and Polish:
//  - PerformanceOverlayPolicy & HUD formatting
//  - PerformanceOverlayView non-interactive touch passthrough
//  - AudioStreamTester synthetic 16-bit LE PCM generator & fade envelope
//  - AudioDiagnostics 64-event ring buffer
//  - ConnectionIssues & ConnectionIssueBannerPolicy filtering & dismissal
//  - AppLog in-memory ring buffer & file rotation
//  - LogExporter report generation, clipboard 250KB limit & temp file export
//  - SettingsBackupManager JSON export, import & defaults reset
//  - AnnouncedDensityPolicy portrait/landscape symmetry & huigMaxDpi
//  - AapTransport handshake timing parameters & currentRxMbps
//

import XCTest
import UIKit
@testable import HeadunitPad

final class Phase6DiagnosticsAndPolishTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AppLog.shared.clear()
        AudioDiagnostics.shared.clear()
        ConnectionIssueStore.shared.clearAll()
    }

    override func tearDown() {
        AppLog.shared.clear()
        AudioDiagnostics.shared.clear()
        ConnectionIssueStore.shared.clearAll()
        super.tearDown()
    }

    // MARK: - 1. PerformanceOverlayPolicy & PerformanceOverlayView

    func testPerformanceOverlayPolicyFormatting() {
        let snapshot = PerformanceSnapshot(
            fps: 60,
            rxMbps: 14.82,
            decodeMedianMs: 3.5,
            decodeP95Ms: 6.2,
            audioBufferMs: 32,
            keyframeRepairs: 2,
            droppedFrames: 1,
            resolutionText: "1920x1080"
        )

        let hudText = PerformanceOverlayPolicy.formatHudText(snapshot)
        XCTAssertTrue(hudText.contains("RES 1920x1080"), "Should include resolution")
        XCTAssertTrue(hudText.contains("60 FPS"), "Should include FPS")
        XCTAssertTrue(hudText.contains("14.8 Mbps"), "Should format rxMbps with 1 decimal place")
        XCTAssertTrue(hudText.contains("DEC 3.5ms (p95 6.2ms)"), "Should format decode latencies")
        XCTAssertTrue(hudText.contains("AUD 32ms"), "Should include audio buffer depth")
        XCTAssertTrue(hudText.contains("PLI 2"), "Should include keyframe repairs")
        XCTAssertTrue(hudText.contains("DROP 1"), "Should include dropped frames")
    }

    func testPerformanceOverlayViewTouchPassthrough() {
        let overlay = PerformanceOverlayView()
        XCTAssertFalse(overlay.isUserInteractionEnabled, "Performance overlay HUD must have isUserInteractionEnabled=false for touch passthrough")
        XCTAssertEqual(overlay.subviews.count, 1)
        guard let label = overlay.subviews.first as? UILabel else {
            XCTFail("HUD should contain a label")
            return
        }
        XCTAssertFalse(label.isUserInteractionEnabled, "HUD label must also be non-interactive")
    }

    // MARK: - 2. AudioStreamTester & AudioDiagnostics

    func testAudioStreamTesterGenerateSineWavePCMByteCount() {
        // 48000 Hz, stereo (2 channels), 16-bit LE (2 bytes per sample) -> 4 bytes per frame
        // 0.1s -> 4800 frames * 4 bytes = 19,200 bytes
        let pcm = AudioStreamTester.generateSineWavePCM(
            sampleRate: 48000,
            channelCount: 2,
            frequencyHz: 440.0,
            durationSeconds: 0.1
        )
        XCTAssertEqual(pcm.count, 19200)

        // Invalid parameters return empty data
        let empty1 = AudioStreamTester.generateSineWavePCM(sampleRate: 0, channelCount: 2, frequencyHz: 440, durationSeconds: 1.0)
        XCTAssertTrue(empty1.isEmpty)
        let empty2 = AudioStreamTester.generateSineWavePCM(sampleRate: 48000, channelCount: 0, frequencyHz: 440, durationSeconds: 1.0)
        XCTAssertTrue(empty2.isEmpty)
        let empty3 = AudioStreamTester.generateSineWavePCM(sampleRate: 48000, channelCount: 2, frequencyHz: 440, durationSeconds: 0.0)
        XCTAssertTrue(empty3.isEmpty)
    }

    func testAudioStreamTesterSamplesEnvelopeAndNonZero() {
        let pcm = AudioStreamTester.generateSineWavePCM(
            sampleRate: 16000,
            channelCount: 1,
            frequencyHz: 1000.0,
            durationSeconds: 0.05,
            rampSeconds: 0.01
        )
        XCTAssertEqual(pcm.count, Int(16000 * 0.05) * 2)

        // Read samples as Int16 array
        let samples: [Int16] = pcm.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Int16.self))
        }

        XCTAssertFalse(samples.isEmpty)
        // First sample at t=0 should be 0 or near 0
        XCTAssertEqual(samples[0], 0)

        // Verify non-zero samples exist in the middle
        let middleIndex = samples.count / 2
        let middleMax = samples[(middleIndex - 10)...(middleIndex + 10)].map { abs(Int($0)) }.max() ?? 0
        XCTAssertGreaterThan(middleMax, 5000, "Synthesized tone must produce significant amplitude in the middle")
    }

    func testAudioDiagnosticsRingBufferLimit() {
        let diag = AudioDiagnostics.shared
        diag.clear()
        XCTAssertEqual(diag.snapshot().count, 0)

        for i in 1...70 {
            diag.record("Event #\(i)")
        }

        let snap = diag.snapshot()
        XCTAssertEqual(snap.count, 64, "AudioDiagnostics should cap at 64 entries in its ring buffer")
        XCTAssertTrue(snap.first?.contains("Event #7") ?? false, "Earliest events (1-6) should have rotated out")
        XCTAssertTrue(snap.last?.contains("Event #70") ?? false, "Latest event should be preserved")
    }

    // MARK: - 3. ConnectionIssues & ConnectionIssueBannerPolicy

    func testConnectionIssueProperties() {
        for issue in ConnectionIssue.allCases {
            XCTAssertFalse(issue.title.isEmpty, "Every issue must have a non-empty title")
            XCTAssertFalse(issue.resolutionAdvice.isEmpty, "Every issue must provide actionable advice")
        }
    }

    func testConnectionIssueStorePersistenceAndClear() {
        let store = ConnectionIssueStore.shared
        store.clearAll()
        XCTAssertEqual(store.currentIssues().count, 0)

        store.raise(issue: .connectionRefused5277, epochMs: 1000)
        XCTAssertEqual(store.currentIssues().count, 1)
        XCTAssertEqual(store.currentIssues().first?.issue, .connectionRefused5277)

        // Raising same issue updates timestamp without duplicating
        store.raise(issue: .connectionRefused5277, epochMs: 2000)
        XCTAssertEqual(store.currentIssues().count, 1)
        XCTAssertEqual(store.currentIssues().first?.raisedAtEpochMs, 2000)

        // Raise another issue
        store.raise(issue: .tlsHandshakeFailed, epochMs: 3000)
        XCTAssertEqual(store.currentIssues().count, 2)

        store.clear(issue: .connectionRefused5277)
        XCTAssertEqual(store.currentIssues().count, 1)
        XCTAssertEqual(store.currentIssues().first?.issue, .tlsHandshakeFailed)

        store.clearAll()
        XCTAssertEqual(store.currentIssues().count, 0)
    }

    func testConnectionIssueBannerPolicy() {
        let issue1 = StandingIssue(issue: .headunitServerNotAnswering, raisedAtEpochMs: 1000)
        let issue2 = StandingIssue(issue: .connectionRefused5277, raisedAtEpochMs: 2000)

        // 1. When connected, banner is always nil
        let bannerConnected = ConnectionIssueBannerPolicy.bannerFor(
            standing: [issue1, issue2],
            sessionConnected: true,
            dismissedAtEpochMs: nil
        )
        XCTAssertNil(bannerConnected, "Banner must be suppressed when projection session is connected")

        // 2. When disconnected without dismissal, returns newest issue
        let bannerDisconnected = ConnectionIssueBannerPolicy.bannerFor(
            standing: [issue1, issue2],
            sessionConnected: false,
            dismissedAtEpochMs: nil
        )
        XCTAssertEqual(bannerDisconnected?.issue, .connectionRefused5277)

        // 3. When dismissed at epoch 2000, issue2 is filtered out
        let bannerDismissed = ConnectionIssueBannerPolicy.bannerFor(
            standing: [issue1, issue2],
            sessionConnected: false,
            dismissedAtEpochMs: 2000
        )
        XCTAssertNil(bannerDismissed, "Issues <= dismissed epoch must be suppressed")

        // 4. When a new issue arises at epoch 2500, banner shows the new issue
        let issue3 = StandingIssue(issue: .wifiRadioOff, raisedAtEpochMs: 2500)
        let bannerNew = ConnectionIssueBannerPolicy.bannerFor(
            standing: [issue1, issue2, issue3],
            sessionConnected: false,
            dismissedAtEpochMs: 2000
        )
        XCTAssertEqual(bannerNew?.issue, .wifiRadioOff)
    }

    // MARK: - 4. AppLog & LogExporter

    func testAppLogInMemBufferAndClear() {
        AppLog.shared.clear()
        XCTAssertEqual(AppLog.shared.recentLogs().count, 0)

        AppLog.d("Debug message", tag: "Test")
        AppLog.i("Info message", tag: "Test")
        AppLog.w("Warning message", tag: "Test")
        AppLog.e("Error message", tag: "Test")

        let logs = AppLog.shared.recentLogs()
        XCTAssertEqual(logs.count, 4)
        XCTAssertTrue(logs[0].contains("[DEBUG] [Test] Debug message"))
        XCTAssertTrue(logs[1].contains("[INFO] [Test] Info message"))
        XCTAssertTrue(logs[2].contains("[WARN] [Test] Warning message"))
        XCTAssertTrue(logs[3].contains("[ERROR] [Test] Error message"))

        AppLog.shared.clear()
        XCTAssertEqual(AppLog.shared.recentLogs().count, 0)
    }

    func testLogExporterBannerAndReport() {
        let banner = LogExporter.sessionBanner()
        XCTAssertTrue(banner.contains("=== HEADUNITPAD-AUTO DIAGNOSTICS REPORT ==="))
        XCTAssertTrue(banner.contains("Connection State:"))
        XCTAssertTrue(banner.contains("Video Codec:"))

        let fullReport = LogExporter.generateFullReport()
        XCTAssertTrue(fullReport.contains("AUDIO DIAGNOSTICS"))
        XCTAssertTrue(fullReport.contains("APPLICATION LOGS"))
    }

    func testLogExporterClipboardLimitAndFileExport() {
        // Write a test log file
        let url = LogExporter.exportToTemporaryFile()
        XCTAssertNotNil(url)
        if let url = url {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            try? FileManager.default.removeItem(at: url)
        }

        // Test clipboard max bytes truncation
        let clipboard = LogExporter.exportToClipboardText(maxBytes: 500)
        XCTAssertLessThanOrEqual(clipboard.utf8.count, 500)
    }

    // MARK: - 5. SettingsBackupManager

    func testSettingsBackupManagerExportAndImport() throws {
        // Export current settings
        let json = SettingsBackupManager.exportToJson()
        XCTAssertTrue(json.contains("\"format\" : \"headunitpad-auto-settings\""))
        XCTAssertTrue(json.contains("\"version\" : 1"))

        // Modify a setting
        ProjectionSettings.dpi = 222
        ProjectionSettings.autoReconnect = false

        // Re-import
        let count = try SettingsBackupManager.importFromJson(json)
        XCTAssertEqual(count, 17)

        // Invalid JSON errors
        XCTAssertThrowsError(try SettingsBackupManager.importFromJson("not json")) { error in
            guard case SettingsBackupError.corruptedData = error else {
                XCTFail("Expected corruptedData error")
                return
            }
        }

        // Invalid format error
        let validContainerJson = SettingsBackupManager.exportToJson()
        let wrongFormat = validContainerJson.replacingOccurrences(of: "\"format\" : \"headunitpad-auto-settings\"", with: "\"format\" : \"wrong-format\"")
        XCTAssertThrowsError(try SettingsBackupManager.importFromJson(wrongFormat)) { error in
            guard case SettingsBackupError.invalidFormat = error else {
                XCTFail("Expected invalidFormat error, got: \(error)")
                return
            }
        }

        // Unsupported version error
        let wrongVersion = validContainerJson.replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 99")
        XCTAssertThrowsError(try SettingsBackupManager.importFromJson(wrongVersion)) { error in
            guard case SettingsBackupError.unsupportedVersion(let v) = error, v == 99 else {
                XCTFail("Expected unsupportedVersion(99) error, got: \(error)")
                return
            }
        }

        // Reset to defaults
        SettingsBackupManager.resetToDefaults()
        XCTAssertEqual(ProjectionSettings.dpi, ProjectionSettings.defaultDpi)
        XCTAssertTrue(ProjectionSettings.autoReconnect)
        XCTAssertEqual(ProjectionSettings.fitMode, .fillMargin)
        XCTAssertEqual(ProjectionSettings.gpsSource, .phone)
    }

    // MARK: - 6. AnnouncedDensityPolicy Portrait / Landscape Symmetry

    func testAnnouncedDensityPolicyHuigMaxDpiSymmetry() {
        let landscapeMax = AnnouncedDensityPolicy.huigMaxDpi(w: 1920, h: 1080)
        let portraitMax = AnnouncedDensityPolicy.huigMaxDpi(w: 1080, h: 1920)
        XCTAssertEqual(landscapeMax, portraitMax, "huigMaxDpi must yield identical results regardless of landscape vs portrait orientation")
        XCTAssertGreaterThan(landscapeMax, 160)
    }

    func testAnnouncedDensityPolicyTierSelectionShortSide() {
        // For a 1920x1080 panel, shortSide is 1080 -> 1080p tier
        let dpiLandscape = AnnouncedDensityPolicy.recommendedDpi(activeW: 1920, activeH: 1080, panelW: 2360, panelH: 1640)
        let dpiPortrait = AnnouncedDensityPolicy.recommendedDpi(activeW: 1080, activeH: 1920, panelW: 1640, panelH: 2360)
        XCTAssertEqual(dpiLandscape, dpiPortrait, "Recommended DPI must match between landscape and portrait for the same panel aspect")
    }

    // MARK: - 7. AapTransport Handshake Timing & Inbound Rate

    private final class MockByteConnection: ByteStreamConnection {
        weak var delegate: ByteStreamConnectionDelegate?
        var isConnected: Bool = true
        var sentPackets: [Data] = []
        func send(_ data: Data, completion: ((Error?) -> Void)?) {
            sentPackets.append(data)
            completion?(nil)
        }
        func disconnect() { isConnected = false }
    }

    func testAapTransportTimingDefaults() {
        let mockStream = MockByteConnection()
        let transport = AapTransport(connection: mockStream)

        XCTAssertEqual(transport.initialVersionRequestDelay, 0.5, accuracy: 0.001, "initialVersionRequestDelay must be 0.5s for stable handshake")
        XCTAssertEqual(transport.versionRetryInterval, 2.0, accuracy: 0.001, "versionRetryInterval must be 2.0s")
        XCTAssertEqual(transport.currentRxMbps, 0.0, "Initial Rx throughput must be 0.0 Mbps")
    }
}
