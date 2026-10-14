//
//  Phase6DiagnosticsAndOverlayTests.swift
//  HeadunitPadTests
//
//  Unit tests covering Phase 6:
//  - FloatingButtonOpacityPolicy calculations and touchability
//  - PerformanceOverlayPolicy bitmasks, field filters, and formatting
//  - AudioStreamTester stream frequencies and sine PCM generation
//  - ConnectionIssues & ConnectionIssueBannerPolicy priorities and expiry
//  - AppLog bounded ring buffer and log level filtering
//  - SettingsBackupManager JSON export, import, and version compatibility
//

import XCTest
import Foundation
@testable import HeadunitPad

final class Phase6DiagnosticsAndOverlayTests: XCTestCase {

    // MARK: - 1. Floating Button Opacity Policy

    func testFloatingButtonOpacityTargetAlpha() {
        // Status mode enabled, connected -> connectedOpacityPercent
        let connectedAlpha = FloatingButtonOpacityPolicy.targetAlpha(
            isConnectionStatusMode: true,
            isConnected: true,
            connectedOpacityPercent: 80,
            disconnectedOpacityPercent: 20
        )
        XCTAssertEqual(connectedAlpha, 0.8, accuracy: 0.001)

        // Status mode enabled, disconnected -> disconnectedOpacityPercent
        let disconnectedAlpha = FloatingButtonOpacityPolicy.targetAlpha(
            isConnectionStatusMode: true,
            isConnected: false,
            connectedOpacityPercent: 80,
            disconnectedOpacityPercent: 20
        )
        XCTAssertEqual(disconnectedAlpha, 0.2, accuracy: 0.001)

        // Status mode disabled -> always connectedOpacityPercent
        let alwaysConnectedAlpha = FloatingButtonOpacityPolicy.targetAlpha(
            isConnectionStatusMode: false,
            isConnected: false,
            connectedOpacityPercent: 75,
            disconnectedOpacityPercent: 10
        )
        XCTAssertEqual(alwaysConnectedAlpha, 0.75, accuracy: 0.001)

        // Clamping bounds
        let clampedHigh = FloatingButtonOpacityPolicy.targetAlpha(
            isConnectionStatusMode: false,
            isConnected: true,
            connectedOpacityPercent: 150
        )
        XCTAssertEqual(clampedHigh, 1.0, accuracy: 0.001)

        let clampedLow = FloatingButtonOpacityPolicy.targetAlpha(
            isConnectionStatusMode: false,
            isConnected: true,
            connectedOpacityPercent: 2
        )
        XCTAssertEqual(clampedLow, 0.1, accuracy: 0.001)
    }

    func testFloatingButtonTouchabilityAndIdleAlpha() {
        XCTAssertTrue(FloatingButtonOpacityPolicy.isTouchable(targetAlpha: 0.8))
        XCTAssertTrue(FloatingButtonOpacityPolicy.isTouchable(targetAlpha: 0.1))
        XCTAssertFalse(FloatingButtonOpacityPolicy.isTouchable(targetAlpha: 0.02))

        let idle = FloatingButtonOpacityPolicy.idleAlpha(baseAlpha: 0.8)
        XCTAssertEqual(idle, 0.32, accuracy: 0.001)

        let minIdle = FloatingButtonOpacityPolicy.idleAlpha(baseAlpha: 0.2)
        XCTAssertEqual(minIdle, 0.25, accuracy: 0.001)
    }

    // MARK: - 2. Performance Overlay Policy

    func testPerformanceOverlayBitmasks() {
        let allFields: Set<PerformanceOverlayField> = [.fps, .cpu, .temp, .frame, .bitrate]
        let bits = PerformanceOverlayPolicy.toBits(allFields)
        XCTAssertEqual(bits, 31)

        let decoded = PerformanceOverlayPolicy.fromBits(bits)
        XCTAssertEqual(decoded, allFields)

        let subset: Set<PerformanceOverlayField> = [.fps, .frame]
        let subsetBits = PerformanceOverlayPolicy.toBits(subset)
        XCTAssertEqual(subsetBits, 1 | 8) // 9
        XCTAssertEqual(PerformanceOverlayPolicy.fromBits(subsetBits), subset)
    }

    func testPerformanceOverlayFormatting() {
        let fields: Set<PerformanceOverlayField> = [.fps, .cpu, .frame, .bitrate]
        let text = PerformanceOverlayPolicy.format(
            fields: fields,
            fps: 60,
            appCpu: 12.5,
            totalCpu: 25.0,
            thermalState: "Nominal",
            frameLatencyMs: 16.4,
            bitrateKbps: 8500.0
        )

        XCTAssertTrue(text.contains("FPS: 60"))
        XCTAssertTrue(text.contains("CPU: app 12.5% / sys 25.0%"))
        XCTAssertTrue(text.contains("Latency: 16.4 ms"))
        XCTAssertTrue(text.contains("Bitrate: 8.50 Mbps"))
    }

    // MARK: - 3. Audio Stream Tester

    func testAudioStreamTesterFrequenciesAndStreams() {
        let tester = AudioStreamTester.shared
        XCTAssertEqual(tester.streams.count, 3)
        XCTAssertEqual(tester.frequency(for: .media), 440.0)
        XCTAssertEqual(tester.frequency(for: .guidance), 880.0)
        XCTAssertEqual(tester.frequency(for: .system), 1320.0)
    }

    func testAudioStreamSineToneGeneration() {
        let duration: Double = 0.5
        let sampleRate: Double = 48000.0
        let pcm = AudioStreamTester.generateSineTone(
            frequency: 440.0,
            durationSeconds: duration,
            sampleRate: sampleRate
        )

        // 0.5s * 48000 samples/sec * 2 channels * 2 bytes/sample = 96000 bytes
        let expectedBytes = Int(duration * sampleRate * 4)
        XCTAssertEqual(pcm.count, expectedBytes)
    }

    // MARK: - 4. Connection Issues & Banner Policy

    func testConnectionIssueDescriptionsAndRemedies() {
        for issue in ConnectionIssue.allCases {
            XCTAssertFalse(issue.title.isEmpty)
            XCTAssertFalse(issue.description.isEmpty)
            XCTAssertFalse(issue.remedy.isEmpty)
        }
    }

    func testConnectionIssueBannerPolicyPriorityAndExpiry() {
        let nowMs: Int64 = 1_000_000

        // If connected, never show banner
        let connectedBanner = ConnectionIssueBannerPolicy.decideBanner(
            standingIssues: [StandingIssue(issue: .wifiRadioOff, raisedAtMs: nowMs)],
            isConnected: true,
            nowMs: nowMs
        )
        XCTAssertNil(connectedBanner)

        // Expired issue (> 15000ms ago) should not produce a banner
        let expiredBanner = ConnectionIssueBannerPolicy.decideBanner(
            standingIssues: [StandingIssue(issue: .wifiRadioOff, raisedAtMs: nowMs - 20_000)],
            isConnected: false,
            nowMs: nowMs
        )
        XCTAssertNil(expiredBanner)

        // Priority check: wifiRadioOff should take precedence over videoLinkTooSlow
        let multiIssues = [
            StandingIssue(issue: .videoLinkTooSlow, raisedAtMs: nowMs - 1000),
            StandingIssue(issue: .wifiRadioOff, raisedAtMs: nowMs - 500)
        ]
        let priorityBanner = ConnectionIssueBannerPolicy.decideBanner(
            standingIssues: multiIssues,
            isConnected: false,
            nowMs: nowMs
        )
        XCTAssertNotNil(priorityBanner)
        XCTAssertEqual(priorityBanner?.issue, .wifiRadioOff)
    }

    // MARK: - 5. AppLog Ring Buffer

    func testAppLogRingBufferAndFormatting() {
        let logger = AppLog()
        logger.minimumLogLevel = .debug

        logger.v("TestTag", "Verbose line") // should be filtered out
        logger.d("TestTag", "Debug line")
        logger.i("TestTag", "Info line")
        logger.w("TestTag", "Warn line")
        logger.e("TestTag", "Error line")

        let entries = logger.getEntries()
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(entries[0].level, .debug)
        XCTAssertEqual(entries[0].message, "Debug line")
        XCTAssertEqual(entries[3].level, .error)

        let exported = logger.exportToString()
        XCTAssertTrue(exported.contains("[D][TestTag] Debug line"))
        XCTAssertTrue(exported.contains("[E][TestTag] Error line"))

        logger.clear()
        XCTAssertEqual(logger.getEntries().count, 0)
    }

    // MARK: - 6. Settings Backup Manager

    func testSettingsBackupManagerExportAndImportRoundtrip() {
        // Set test values in UserDefaults
        UserDefaults.standard.set(ResolutionPreset.r1920x1080.rawValue, forKey: "projection-resolution-preset")
        UserDefaults.standard.set(true, forKey: "projection-right-hand-drive")
        UserDefaults.standard.set(220, forKey: "projection-dpi")
        UserDefaults.standard.set("Toyota", forKey: "projection-vehicle-make")

        // Export JSON
        guard let json = SettingsBackupManager.exportJson() else {
            XCTFail("Export JSON should not be nil")
            return
        }
        XCTAssertTrue(json.contains(SettingsBackupManager.format))
        XCTAssertTrue(json.contains("Toyota"))

        // Reset
        UserDefaults.standard.removeObject(forKey: "projection-vehicle-make")
        XCTAssertNil(UserDefaults.standard.string(forKey: "projection-vehicle-make"))

        // Import back
        let result = SettingsBackupManager.importJson(json)
        XCTAssertTrue(result.success)
        XCTAssertGreaterThan(result.importedCount, 0)

        // Verify restored
        XCTAssertEqual(UserDefaults.standard.string(forKey: "projection-vehicle-make"), "Toyota")
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "projection-dpi"), 220)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "projection-right-hand-drive"))
    }

    func testSettingsBackupManagerInvalidFormat() {
        let invalidJson = """
        {
            "format": "unsupported-format",
            "version": 1,
            "exportedAt": "2024-01-01T00:00:00Z",
            "appVersion": "0.1.0",
            "settings": {}
        }
        """
        let result = SettingsBackupManager.importJson(invalidJson)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.errorMessage?.contains("Unsupported") ?? false)
    }
}
