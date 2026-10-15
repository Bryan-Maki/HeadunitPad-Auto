//
//  Phase3VideoAndRecoveryTests.swift
//  HeadunitPadTests
//
//  Comprehensive test suite for Phase 3:
//  - H.264 & HEVC parameter set inspection and keyframe scanning
//  - VideoFragmentAssembler fragment state machine and packet loss anomalies
//  - KeyframeRepairTracker repair confirmation and fallback
//  - CorruptionConcealmentPolicy visual tearing concealment
//  - KeyframeCycleEscalationPolicy focus cycle escalation and budget limits
//  - WarmRelaunchKeyframePolicy background return recovery
//  - VideoBackpressurePolicy and VideoFeedQueuePolicy capacity derivation
//  - DecodeLatencyMonitor percentile calculations
//  - Decoder restart, stop, stall, and exception policies
//

import XCTest
@testable import HeadunitPad

final class Phase3VideoAndRecoveryTests: XCTestCase {

    // MARK: - 1. NAL Parsing & Keyframe Scanning (AVC & HEVC)

    func testH264KeyframeScanning() {
        // Construct H.264 NAL units: SPS (7), PPS (8), IDR (5)
        var stream = Data([0x00, 0x00, 0x00, 0x01, 0x67, 0x42, 0x00, 0x1E]) // SPS
        stream.append(contentsOf: [0x00, 0x00, 0x00, 0x01, 0x68, 0xCE, 0x3C, 0x80]) // PPS
        stream.append(contentsOf: [0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84, 0x00]) // IDR (5)

        let isKeyframe = VideoKeyframeScanner.containsKeyframe(data: stream, isHevc: false)
        XCTAssertTrue(isKeyframe, "H.264 stream with NAL 5 should be recognized as keyframe")

        // Construct non-keyframe: P-slice (1)
        var pStream = Data([0x00, 0x00, 0x00, 0x01, 0x41, 0x9A])
        let isPKeyframe = VideoKeyframeScanner.containsKeyframe(data: pStream, isHevc: false)
        XCTAssertFalse(isPKeyframe, "H.264 P-slice should not be recognized as keyframe")
    }

    func testHevcKeyframeScanning() {
        // HEVC NAL types: VPS (32 << 1 = 64 = 0x40), SPS (33 << 1 = 66 = 0x42), PPS (34 << 1 = 68 = 0x44), IDR_W_RADL (19 << 1 = 38 = 0x26)
        var stream = Data([0x00, 0x00, 0x00, 0x01, 0x40, 0x01, 0x0C, 0x01]) // VPS
        stream.append(contentsOf: [0x00, 0x00, 0x00, 0x01, 0x42, 0x01, 0x01, 0x01]) // SPS
        stream.append(contentsOf: [0x00, 0x00, 0x00, 0x01, 0x44, 0x01, 0xC0]) // PPS
        stream.append(contentsOf: [0x00, 0x00, 0x00, 0x01, 0x26, 0x01, 0xAF]) // IDR_W_RADL (19)

        let isKeyframe = VideoKeyframeScanner.containsKeyframe(data: stream, isHevc: true)
        XCTAssertTrue(isKeyframe, "HEVC stream with NAL 19 should be recognized as keyframe")

        // Construct CRA_NUT (21 << 1 = 42 = 0x2A)
        let craStream = Data([0x00, 0x00, 0x00, 0x01, 0x2A, 0x01, 0x55])
        XCTAssertTrue(VideoKeyframeScanner.containsKeyframe(data: craStream, isHevc: true), "HEVC CRA_NUT (21) should be recognized as keyframe")

        // Construct HEVC non-keyframe: TRAIL_R (1 << 1 = 2 = 0x02)
        let trailStream = Data([0x00, 0x00, 0x00, 0x01, 0x02, 0x01, 0x11])
        XCTAssertFalse(VideoKeyframeScanner.containsKeyframe(data: trailStream, isHevc: true), "HEVC TRAIL_R (1) should not be recognized as keyframe")
    }

    // MARK: - 2. VideoFragmentAssembler State Machine & Anomalies

    func testFragmentAssemblerHappyPath() {
        let assembler = VideoFragmentAssembler()

        // 1. Single packet (flag 11) with timestamp indication (offset 10)
        let decSingle = assembler.onMessage(flags: 11, payloadStartsAt10: true, payloadStartsAt2: false)
        XCTAssertEqual(decSingle.action, .decodeWhole(payloadOffset: 10))
        XCTAssertNil(decSingle.anomaly)
        XCTAssertFalse(assembler.isAssembling)

        // 2. Fragmented frame: First (9) -> Middle (8) -> Last (10)
        let decFirst = assembler.onMessage(flags: 9, payloadStartsAt10: true, payloadStartsAt2: false)
        XCTAssertEqual(decFirst.action, .beginAssembly(payloadOffset: 10))
        XCTAssertNil(decFirst.anomaly)
        XCTAssertTrue(assembler.isAssembling)

        let decMiddle = assembler.onMessage(flags: 8, payloadStartsAt10: false, payloadStartsAt2: false)
        XCTAssertEqual(decMiddle.action, .append)
        XCTAssertNil(decMiddle.anomaly)
        XCTAssertTrue(assembler.isAssembling)

        let decLast = assembler.onMessage(flags: 10, payloadStartsAt10: false, payloadStartsAt2: false)
        XCTAssertEqual(decLast.action, .appendAndDecode)
        XCTAssertNil(decLast.anomaly)
        XCTAssertFalse(assembler.isAssembling)
        XCTAssertFalse(assembler.hasAnomalies())
    }

    func testFragmentAssemblerAnomalies() {
        let assembler = VideoFragmentAssembler()

        // 1. Truncated previous: send 9, then send another 9 without 10
        _ = assembler.onMessage(flags: 9, payloadStartsAt10: true, payloadStartsAt2: false)
        let decTruncated = assembler.onMessage(flags: 9, payloadStartsAt10: true, payloadStartsAt2: false)
        XCTAssertEqual(decTruncated.anomaly, .truncatedPrevious)
        XCTAssertEqual(assembler.countOf(.truncatedPrevious), 1)

        // 2. Orphaned fragment: middle (8) or last (10) arrives while not assembling
        assembler.reset()
        let decOrphan = assembler.onMessage(flags: 8, payloadStartsAt10: false, payloadStartsAt2: false)
        XCTAssertEqual(decOrphan.anomaly, .orphanedFragment)
        XCTAssertEqual(assembler.countOf(.orphanedFragment), 1)
        XCTAssertTrue(assembler.isFrameCorrupt)

        // 3. Headless first fragment: flag 9 but no start code at 10 or 2
        assembler.reset()
        let decHeadless = assembler.onMessage(flags: 9, payloadStartsAt10: false, payloadStartsAt2: false)
        XCTAssertEqual(decHeadless.anomaly, .headlessFirstFragment)
        XCTAssertEqual(assembler.countOf(.headlessFirstFragment), 1)

        // 4. Overflow
        let anomalyOverflow = assembler.onOverflow()
        XCTAssertEqual(anomalyOverflow, .overflow)
        XCTAssertEqual(assembler.countOf(.overflow), 1)
        XCTAssertTrue(assembler.isFrameCorrupt)

        // 5. Reset clears counts
        assembler.reset()
        XCTAssertFalse(assembler.hasAnomalies())
        XCTAssertFalse(assembler.isAssembling)
        XCTAssertFalse(assembler.isFrameCorrupt)
    }

    // MARK: - 3. KeyframeRepairTracker

    func testKeyframeRepairTrackerFlow() {
        let tracker = KeyframeRepairTracker()
        XCTAssertFalse(tracker.awaitingOutput)
        XCTAssertFalse(tracker.keyframeDecoded)

        // Keyframe fed with pts 1000
        tracker.onKeyframeFed(ptsUs: 1000)
        XCTAssertTrue(tracker.awaitingOutput)

        // Older frame comes out (pts 900) -> not yet repaired
        let r1 = tracker.onFrameRendered(ptsUs: 900)
        XCTAssertFalse(r1)
        XCTAssertTrue(tracker.awaitingOutput)

        // Frame at keyframe PTS (1000) comes out -> repaired!
        let r2 = tracker.onFrameRendered(ptsUs: 1000)
        XCTAssertTrue(r2)
        XCTAssertFalse(tracker.awaitingOutput)
        XCTAssertTrue(tracker.keyframeDecoded)

        // Subsequent frames return false
        XCTAssertFalse(tracker.onFrameRendered(ptsUs: 1033))
    }

    func testKeyframeRepairTrackerTimestampsUnusableFallback() {
        let tracker = KeyframeRepairTracker()
        tracker.onKeyframeFed(ptsUs: 50_000)

        // Decoder returns constant PTS 0 for 30 consecutive frames
        for _ in 0..<29 {
            XCTAssertFalse(tracker.onFrameRendered(ptsUs: 0))
        }
        XCTAssertFalse(tracker.timestampsUnusable)

        // 30th frame -> confirms repair by frame count, flags timestamps as unusable
        let confirmed = tracker.onFrameRendered(ptsUs: 0)
        XCTAssertTrue(confirmed)
        XCTAssertTrue(tracker.timestampsUnusable)
        XCTAssertTrue(tracker.keyframeDecoded)
    }

    // MARK: - 4. CorruptionConcealmentPolicy

    func testCorruptionConcealmentStateTransitions() {
        var state = CorruptionConcealmentPolicy.State.armed
        var windowOpenedMs: Int64 = 0

        // 1. Healthy frame rendered -> SHOW
        let o1 = CorruptionConcealmentPolicy.next(
            nowMs: 1000,
            state: state,
            windowOpenedMs: windowOpenedMs,
            corruptionReported: false,
            keyframeRepaired: false,
            sessionHasRendered: true
        )
        XCTAssertEqual(o1, .show)
        XCTAssertTrue(o1.renders)

        // 2. Corruption reported while ARMED -> OPEN window (do not render)
        let o2 = CorruptionConcealmentPolicy.next(
            nowMs: 1100,
            state: state,
            windowOpenedMs: windowOpenedMs,
            corruptionReported: true,
            keyframeRepaired: false,
            sessionHasRendered: true
        )
        XCTAssertEqual(o2, .open)
        XCTAssertFalse(o2.renders)
        state = .concealing
        windowOpenedMs = 1100

        // 3. During concealment, subsequent frames are CONCEAL
        let o3 = CorruptionConcealmentPolicy.next(
            nowMs: 1200,
            state: state,
            windowOpenedMs: windowOpenedMs,
            corruptionReported: false,
            keyframeRepaired: false,
            sessionHasRendered: true
        )
        XCTAssertEqual(o3, .conceal)
        XCTAssertFalse(o3.renders)

        // 4. Repaired keyframe arrives -> CLOSE_REPAIRED and re-arm
        let o4 = CorruptionConcealmentPolicy.next(
            nowMs: 1300,
            state: state,
            windowOpenedMs: windowOpenedMs,
            corruptionReported: false,
            keyframeRepaired: true,
            sessionHasRendered: true
        )
        XCTAssertEqual(o4, .closeRepaired)
        XCTAssertTrue(o4.renders)
        state = .armed

        // 5. Expiration: window open past 2000ms -> CLOSE_EXPIRED
        state = .concealing
        windowOpenedMs = 2000
        let o5 = CorruptionConcealmentPolicy.next(
            nowMs: 4050, // 2050ms > 2000ms
            state: state,
            windowOpenedMs: windowOpenedMs,
            corruptionReported: false,
            keyframeRepaired: false,
            sessionHasRendered: true
        )
        XCTAssertEqual(o5, .closeExpired)
        XCTAssertTrue(o5.renders)
    }

    // MARK: - 5. KeyframeCycleEscalationPolicy

    func testKeyframeCycleEscalationDecisions() {
        // 1. Newly broken picture (< 2500ms) -> plain NUDGE
        let a1 = KeyframeCycleEscalationPolicy.decide(
            nowMs: 2000,
            unrepairedSinceMs: 1000, // 1000ms unrepaired
            cyclesUsedThisSession: 0,
            lastCycleMs: 0,
            lastWireCorruptionMs: 0
        )
        XCTAssertEqual(a1, .nudge)

        // 2. Unrepaired past 2500ms with quiet wire -> CYCLE_FOCUS
        let a2 = KeyframeCycleEscalationPolicy.decide(
            nowMs: 4000,
            unrepairedSinceMs: 1000, // 3000ms unrepaired
            cyclesUsedThisSession: 0,
            lastCycleMs: 0,
            lastWireCorruptionMs: 0
        )
        XCTAssertEqual(a2, .cycleFocus)

        // 3. Cooldown active (last cycle 10s ago < 30s) -> fallback to NUDGE
        let a3 = KeyframeCycleEscalationPolicy.decide(
            nowMs: 14_000,
            unrepairedSinceMs: 1000,
            cyclesUsedThisSession: 1,
            lastCycleMs: 4000, // 10s ago
            lastWireCorruptionMs: 0
        )
        XCTAssertEqual(a3, .nudge)

        // 4. Wire actively corrupting -> WAIT_FOR_QUIET
        let a4 = KeyframeCycleEscalationPolicy.decide(
            nowMs: 40_000,
            unrepairedSinceMs: 1000,
            cyclesUsedThisSession: 1,
            lastCycleMs: 4000,
            lastWireCorruptionMs: 39_500 // 500ms ago < 3000ms
        )
        XCTAssertEqual(a4, .waitForQuiet)

        // 5. Budget exhausted (>= 3 cycles) -> fallback to NUDGE
        let a5 = KeyframeCycleEscalationPolicy.decide(
            nowMs: 80_000,
            unrepairedSinceMs: 1000,
            cyclesUsedThisSession: 3,
            lastCycleMs: 40_000,
            lastWireCorruptionMs: 0
        )
        XCTAssertEqual(a5, .nudge)
    }

    func testKeyframeCycleRefunds() {
        // After 10 minutes (600,000ms) of quiet wire, 2 windows of 5 min have passed
        let refunds = KeyframeCycleEscalationPolicy.cyclesToRefund(
            nowMs: 700_000,
            cyclesUsedThisSession: 2,
            cyclesSpentThisSession: 2,
            lastBudgetChangeMs: 100_000,
            lastWireCorruptionMs: 100_000,
            pictureUnrepaired: false
        )
        XCTAssertEqual(refunds, 2, "Quiet wire should refund spent cycle budget")
    }

    // MARK: - 6. WarmRelaunchKeyframePolicy

    func testWarmRelaunchKeyframeDecisions() {
        // Surface just set (< 850ms) -> NONE
        let d1 = WarmRelaunchKeyframePolicy.decide(
            sessionHasRendered: true,
            crediblePictureOnSurface: false,
            transportStarted: true,
            msSinceSurfaceSet: 400,
            msSinceLinkActivity: 100,
            linkQuietThresholdMs: 10_000,
            cycleAlreadySpent: false,
            msSinceLastRequest: 5000
        )
        XCTAssertEqual(d1, .none)

        // Surface older than 850ms without picture -> CYCLE_FOCUS
        let d2 = WarmRelaunchKeyframePolicy.decide(
            sessionHasRendered: true,
            crediblePictureOnSurface: false,
            transportStarted: true,
            msSinceSurfaceSet: 900,
            msSinceLinkActivity: 100,
            linkQuietThresholdMs: 10_000,
            cycleAlreadySpent: false,
            msSinceLastRequest: 5000
        )
        XCTAssertEqual(d2, .cycleFocus)

        // Cycle already spent, throttle elapsed -> NUDGE
        let d3 = WarmRelaunchKeyframePolicy.decide(
            sessionHasRendered: true,
            crediblePictureOnSurface: false,
            transportStarted: true,
            msSinceSurfaceSet: 2000,
            msSinceLinkActivity: 100,
            linkQuietThresholdMs: 10_000,
            cycleAlreadySpent: true,
            msSinceLastRequest: 1500
        )
        XCTAssertEqual(d3, .nudge)

        // Credible picture on screen -> NONE
        let d4 = WarmRelaunchKeyframePolicy.decide(
            sessionHasRendered: true,
            crediblePictureOnSurface: true,
            transportStarted: true,
            msSinceSurfaceSet: 2000,
            msSinceLinkActivity: 100,
            linkQuietThresholdMs: 10_000,
            cycleAlreadySpent: false,
            msSinceLastRequest: 5000
        )
        XCTAssertEqual(d4, .none)
    }

    // MARK: - 7. VideoBackpressurePolicy & VideoFeedQueuePolicy

    func testVideoBackpressurePolicy() {
        // Less than 10% input wait -> not backpressure
        XCTAssertFalse(VideoBackpressurePolicy.isBackpressureWindow(windowMs: 5000, inputWaitMs: 300, dropped: 2))

        // More than 10% input wait (1000ms / 5000ms = 20%) with dropped frames -> backpressure window!
        XCTAssertTrue(VideoBackpressurePolicy.isBackpressureWindow(windowMs: 5000, inputWaitMs: 1000, dropped: 2))

        // No dropped frames -> not backpressure
        XCTAssertFalse(VideoBackpressurePolicy.isBackpressureWindow(windowMs: 5000, inputWaitMs: 1000, dropped: 0))

        // Report on second window
        XCTAssertFalse(VideoBackpressurePolicy.shouldReport(backpressureWindows: 1, alreadyReported: false))
        XCTAssertTrue(VideoBackpressurePolicy.shouldReport(backpressureWindows: 2, alreadyReported: false))
        XCTAssertFalse(VideoBackpressurePolicy.shouldReport(backpressureWindows: 2, alreadyReported: true))
    }

    func testVideoFeedQueueCapacity() {
        // At 30 FPS: 30 * 500 / 1000 = 15 frames
        XCTAssertEqual(VideoFeedQueuePolicy.capacityFor(fpsLimit: 30), 15)

        // At 60 FPS: 60 * 500 / 1000 = 30 frames
        XCTAssertEqual(VideoFeedQueuePolicy.capacityFor(fpsLimit: 60), 30)

        // Clamped to [15, 40]
        XCTAssertEqual(VideoFeedQueuePolicy.capacityFor(fpsLimit: 10), 15)
        XCTAssertEqual(VideoFeedQueuePolicy.capacityFor(fpsLimit: 120), 40)
    }

    // MARK: - 8. DecodeLatencyMonitor

    func testDecodeLatencyMonitorCalculations() {
        let monitor = DecodeLatencyMonitor()

        // Feed 10ms, 12ms, 15ms, 18ms, 20ms, 25ms, 30ms, 35ms, 40ms, 50ms (in microseconds)
        let latencies: [Int64] = [10_000, 12_000, 15_000, 18_000, 20_000, 25_000, 30_000, 35_000, 40_000, 50_000]
        for lat in latencies {
            monitor.onFrameDecoded(latencyUs: lat)
        }

        guard let report = monitor.report() else {
            XCTFail("Report should not be nil")
            return
        }

        XCTAssertEqual(report.frames, 10)
        XCTAssertEqual(report.unusable, 0)
        XCTAssertTrue(report.medianUs >= 20_000 && report.medianUs <= 25_000)
        XCTAssertTrue(report.p95Us >= 40_000)
    }

    // MARK: - 9. Miscellaneous Policies (Stop, Restart, Stall, Exception)

    func testDecoderPolicies() {
        // Stop policy
        XCTAssertFalse(DecoderStopPolicy.endsSession(reason: "restart_stall"))
        XCTAssertFalse(DecoderStopPolicy.endsSession(reason: DecoderStopPolicy.reasonSurfaceDestroyed))
        XCTAssertTrue(DecoderStopPolicy.endsSession(reason: "user_disconnect"))

        // Restart policy
        XCTAssertTrue(DecoderRestartPolicy.countsTowardFailure(codecTypePinned: true, renderedSinceLastStart: false, renderedThisSession: false))
        XCTAssertFalse(DecoderRestartPolicy.countsTowardFailure(codecTypePinned: true, renderedSinceLastStart: false, renderedThisSession: true))

        // Exception policy
        XCTAssertEqual(DecoderExceptionPolicy.responseTo(isCodecException: true, isTransient: true, isRecoverable: false), .continueExecution)
        XCTAssertEqual(DecoderExceptionPolicy.responseTo(isCodecException: true, isTransient: false, isRecoverable: true), .countStrike)
        XCTAssertEqual(DecoderExceptionPolicy.responseTo(isCodecException: true, isTransient: false, isRecoverable: false), .restartNow)

        // Stall cause policy
        XCTAssertEqual(DecoderStallCausePolicy.classify(stallGapMs: 1000, inputIdleGapMs: 3000, keyframeDecodedSinceStart: true, sessionHasRendered: true), .phoneIdle)
        XCTAssertEqual(DecoderStallCausePolicy.classify(stallGapMs: 5000, inputIdleGapMs: 100, keyframeDecodedSinceStart: false, sessionHasRendered: true), .starvedOfKeyframe)
        XCTAssertEqual(DecoderStallCausePolicy.classify(stallGapMs: 16_000, inputIdleGapMs: 100, keyframeDecodedSinceStart: false, sessionHasRendered: true), .stalled)
    }

    // MARK: - 10. FrameReleasePacer VSync Timing

    func testVSyncFrameReleasePacerSmoothsBurstArrivals() {
        var pacer = H264VideoRendererView.FrameReleasePacer()
        let frameInterval: Double = 1.0 / 60.0 // ~0.0166667s

        // 3 frames arrive in the same millisecond burst: t = 100.000s, 100.001s, 100.002s
        let pts0 = pacer.nextPts(nowSeconds: 100.000, frameInterval: frameInterval)
        let pts1 = pacer.nextPts(nowSeconds: 100.001, frameInterval: frameInterval)
        let pts2 = pacer.nextPts(nowSeconds: 100.002, frameInterval: frameInterval)

        XCTAssertEqual(pts0, 100.000, accuracy: 0.0001)
        XCTAssertEqual(pts1, 100.000 + frameInterval, accuracy: 0.0001)
        XCTAssertEqual(pts2, 100.000 + (2.0 * frameInterval), accuracy: 0.0001)

        let gap01 = pts1 - pts0
        let gap12 = pts2 - pts1
        XCTAssertEqual(gap01, frameInterval, accuracy: 0.0001)
        XCTAssertEqual(gap12, frameInterval, accuracy: 0.0001)

        // Verify catch-up when backlog exceeds 2.5 frames:
        let pts3 = pacer.nextPts(nowSeconds: 100.200, frameInterval: frameInterval)
        XCTAssertEqual(pts3, 100.200, accuracy: 0.0001, "Should catch up to current time when backlog exceeds 2.5 frames")
    }
}
