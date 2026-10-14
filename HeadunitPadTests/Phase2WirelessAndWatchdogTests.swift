//
//  Phase2WirelessAndWatchdogTests.swift
//  HeadunitPadTests
//
//  Tests covering Phase 2: WPP Framing & Handshake, Network Discovery & SameEndpoint,
//  Link Gap & Video Starvation & Unresponsive Peer Policies, Automatic Reconnect & Playback Resume,
//  and QR DeepLink & Generation.
//

import XCTest
import UIKit
@testable import HeadunitPad

final class Phase2WirelessAndWatchdogTests: XCTestCase {

    // MARK: - 1. WPP Framing & Messages & Handshake Session

    func testWppFramingRoundtrip() throws {
        let payload = Data([0x01, 0x02, 0x03, 0x04])
        let framed = WppFraming.frame(type: .wifiVersionResponse, payload: payload)

        XCTAssertEqual(framed.count, 4 + payload.count)
        let (type, extractedPayload) = try WppFraming.unframe(data: framed)
        XCTAssertEqual(type, .wifiVersionResponse)
        XCTAssertEqual(extractedPayload, payload)
    }

    func testWppFramingHeaderTooShort() {
        let incomplete = Data([0x00, 0x04])
        XCTAssertThrowsError(try WppFraming.unframe(data: incomplete)) { error in
            XCTAssertEqual(error as? WppFramingError, .headerTooShort)
        }
    }

    func testWppHandshakeSessionVersionNegotiation() throws {
        var sentMessages: [WppMessageType] = []
        let session = WppHandshakeSession(sendCallback: { type, _ in
            sentMessages.append(type)
        })

        XCTAssertEqual(session.currentState, .waitingForVersionRequest)

        // Receive Version Request
        let req = WifiVersionRequest(majorVersion: 1, minorVersion: 1)
        try session.onMessageReceived(type: .wifiVersionRequest, payload: req.encode())

        XCTAssertTrue(sentMessages.contains(.wifiVersionResponse))
        XCTAssertEqual(session.currentState, .waitingForSecurityOrStart)

        // Receive Start Request
        try session.onMessageReceived(type: .wifiStartRequest, payload: Data())
        XCTAssertTrue(sentMessages.contains(.wifiStartResponse))
        XCTAssertEqual(session.currentState, .completed)
    }

    // MARK: - 2. Discovery Subnet Policy & Network Addresses & Same Endpoint

    func testDiscoverySubnetPolicyGeneratesHostIps() {
        let baseIp = "192.168.1.50"
        let candidates = DiscoverySubnetPolicy.generateSubnetCandidates(baseIp: baseIp, maxHosts: 5)
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.contains("192.168.1.1"))
    }

    func testDhcpGatewayFormat() {
        let gw = DhcpGatewayFormat.gatewayAddress(forInterfaceIp: "192.168.43.15")
        XCTAssertEqual(gw, "192.168.43.1")
    }

    func testSameEndpointConnectPolicy() {
        let policy = SameEndpointConnectPolicy()

        XCTAssertTrue(policy.shouldConnect(endpoint: "192.168.1.100:5277"))
        policy.recordConnectionStarted(endpoint: "192.168.1.100:5277")

        // In flight attempt to same endpoint should be rejected
        XCTAssertFalse(policy.shouldConnect(endpoint: "192.168.1.100:5277"))

        // Different endpoint allowed
        XCTAssertTrue(policy.shouldConnect(endpoint: "192.168.1.101:5277"))

        // Completed connection clears lock
        policy.recordConnectionEnded(endpoint: "192.168.1.100:5277")
        XCTAssertTrue(policy.shouldConnect(endpoint: "192.168.1.100:5277"))
    }

    // MARK: - 3. Link Gap Monitor, Unresponsive Peer & Video Starvation Policies

    func testLinkGapMonitorReportsOutages() {
        let monitor = LinkGapMonitor(minGaps: 1, maxDeadPercent: 10)
        _ = monitor.onMessage(nowMs: 1000)

        // 3 second gap exceeds default 1800ms threshold
        let report = monitor.onMessage(nowMs: 4500)
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.gaps, 1)
        XCTAssertEqual(report?.longestMs, 3500)
    }

    func testUnresponsivePeerPolicyBackoff() {
        XCTAssertEqual(UnresponsivePeerPolicy.rescanDelayMs(consecutiveSilentFailures: 0), 10_000)
        XCTAssertEqual(UnresponsivePeerPolicy.rescanDelayMs(consecutiveSilentFailures: 2), 10_000)

        // Tier 1 backoff at 3 failures
        XCTAssertEqual(UnresponsivePeerPolicy.rescanDelayMs(consecutiveSilentFailures: 3), 60_000)
        XCTAssertTrue(UnresponsivePeerPolicy.shouldExplain(consecutiveSilentFailures: 3))
        XCTAssertFalse(UnresponsivePeerPolicy.shouldExplain(consecutiveSilentFailures: 4))

        // Last tier backoff at 10 failures
        XCTAssertEqual(UnresponsivePeerPolicy.rescanDelayMs(consecutiveSilentFailures: 10), 300_000)

        // Streak counting
        let count1 = UnresponsivePeerPolicy.countAfterSilentFailure(previousCount: 2, previousEndpoint: "192.168.1.1", endpoint: "192.168.1.1")
        XCTAssertEqual(count1, 3)

        let count2 = UnresponsivePeerPolicy.countAfterSilentFailure(previousCount: 2, previousEndpoint: "192.168.1.1", endpoint: "192.168.1.2")
        XCTAssertEqual(count2, 1)
    }

    func testVideoStarvationPolicyStreakAndAdvisory() {
        var streak = 0
        streak = VideoStarvationPolicy.nextStreak(current: streak, reachedHandshake: true, renderedAnyFrame: false)
        XCTAssertEqual(streak, 1)
        XCTAssertFalse(VideoStarvationPolicy.shouldAdvise(consecutiveStarvedSessions: streak))

        streak = VideoStarvationPolicy.nextStreak(current: streak, reachedHandshake: true, renderedAnyFrame: false)
        XCTAssertEqual(streak, 2)
        XCTAssertFalse(VideoStarvationPolicy.shouldAdvise(consecutiveStarvedSessions: streak))

        streak = VideoStarvationPolicy.nextStreak(current: streak, reachedHandshake: true, renderedAnyFrame: false)
        XCTAssertEqual(streak, 3)
        XCTAssertTrue(VideoStarvationPolicy.shouldAdvise(consecutiveStarvedSessions: streak))
        XCTAssertTrue(VideoStarvationPolicy.shouldCap(consecutiveStarvedSessions: streak))

        // When a frame renders, streak clears
        streak = VideoStarvationPolicy.nextStreak(current: streak, reachedHandshake: true, renderedAnyFrame: true)
        XCTAssertEqual(streak, 0)
        XCTAssertFalse(VideoStarvationPolicy.shouldCap(consecutiveStarvedSessions: streak))
    }

    // MARK: - 4. Automatic Reconnect, Grace Policy & Auto-Resume Playback

    func testReconnectGracePolicy() {
        // Ceiling
        XCTAssertEqual(
            ReconnectGracePolicy.endedBecause(isUsb: false, sinceDisconnectMs: 46_000, sinceProgressMs: nil),
            .ceilingReached
        )

        // Base expired with no progress
        XCTAssertEqual(
            ReconnectGracePolicy.endedBecause(isUsb: false, sinceDisconnectMs: 21_000, sinceProgressMs: nil),
            .baseExpired
        )

        // Still waiting within base
        XCTAssertNil(
            ReconnectGracePolicy.endedBecause(isUsb: false, sinceDisconnectMs: 5_000, sinceProgressMs: nil)
        )

        // Progress stale
        XCTAssertEqual(
            ReconnectGracePolicy.endedBecause(isUsb: false, sinceDisconnectMs: 25_000, sinceProgressMs: 15_000),
            .progressWentStale
        )
    }

    func testAutoResumePlaybackPolicy() {
        // Disabled in settings
        XCTAssertFalse(AutoResumePlaybackPolicy.shouldResume(enabled: false, wasPlayingBeforeDisconnect: true, elapsedSinceDisconnectMs: 5000))

        // Was not playing before disconnect
        XCTAssertFalse(AutoResumePlaybackPolicy.shouldResume(enabled: true, wasPlayingBeforeDisconnect: false, elapsedSinceDisconnectMs: 5000))

        // Eligible quick reconnect (< 60s)
        XCTAssertTrue(AutoResumePlaybackPolicy.shouldResume(enabled: true, wasPlayingBeforeDisconnect: true, elapsedSinceDisconnectMs: 15000))

        // Reconnect after window (> 60s)
        XCTAssertFalse(AutoResumePlaybackPolicy.shouldResume(enabled: true, wasPlayingBeforeDisconnect: true, elapsedSinceDisconnectMs: 65000))
    }

    func testReconnectPlaybackSnapshot() {
        let snapshot = ReconnectPlaybackSnapshot()
        snapshot.onDisconnected(lastPlaying: true, now: 10_000, deliberate: false)

        let resume = snapshot.consume(now: 15_000)
        XCTAssertTrue(resume.wasPlaying)
        XCTAssertEqual(resume.elapsedMs, 5_000)

        // Consuming clears the intent
        let secondConsume = snapshot.consume(now: 20_000)
        XCTAssertFalse(secondConsume.wasPlaying)
    }

    // MARK: - 5. QR Code DeepLink & Image Generator

    func testProjectionDeepLinkUri() {
        let uri = ProjectionDeepLink.generateUri(
            ssid: "TestHotspot",
            passphrase: "secretPassword",
            ipAddress: "192.168.43.1",
            port: 5277
        )

        XCTAssertTrue(uri.hasPrefix("https://androidauto.com/projection/setup?data="))
        XCTAssertTrue(ProjectionQrPolicy.isValidPairingUri(uri))
    }

    func testQrCodeGeneratorProducesImage() {
        let testString = "https://androidauto.com/projection/setup?data=mock123"
        let image = QrCodeGenerator.generateQRCode(from: testString, targetSize: CGSize(width: 200, height: 200))

        XCTAssertNotNil(image)
        XCTAssertGreaterThan(image?.size.width ?? 0, 0)
        XCTAssertGreaterThan(image?.size.height ?? 0, 0)
    }
}
