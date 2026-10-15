//
//  Phase5SystemIntegrationTests.swift
//  HeadunitPadTests
//
//  System integration tests for Phase 5:
//  - 2020+ iPad Model Family Catalog & recommended DPI
//  - ServiceDiscoveryResponse pipelined decoder depth (8)
//  - TouchCoordinateMapper margin reverse mapping & TouchInputView
//  - ProjectionConnectionModes (Native WPP, Hotspot Server, Manual IP)
//  - Fullscreen projection state and status bar / home indicator hiding
//

import XCTest
import UIKit
import AVFoundation
@testable import HeadunitPad

final class Phase5SystemIntegrationTests: XCTestCase {

    // MARK: - 1. 2020+ iPad Model Catalog & Detection

    func testIPadModelFamilyCatalogDetection() {
        // iPad mini 6 / 7 (8.3")
        let mini = HeadUnitScreenConfig.detectModelFamily(panelW: 2266, panelH: 1488)
        XCTAssertEqual(mini, .ipadMini)
        XCTAssertEqual(mini.displayName, "iPad mini (8.3\")")

        // iPad 8 / 9 (10.2")
        let standard102 = HeadUnitScreenConfig.detectModelFamily(panelW: 2160, panelH: 1620)
        XCTAssertEqual(standard102, .ipadStandard102)

        // iPad 10 / 11 & Air 4 / 5 / M2 (10.9" / 11")
        let air109 = HeadUnitScreenConfig.detectModelFamily(panelW: 2360, panelH: 1640)
        XCTAssertEqual(air109, .ipadAirAndStandard109)

        // iPad Pro 11" (Gen 2-4 & M4)
        let pro11 = HeadUnitScreenConfig.detectModelFamily(panelW: 2388, panelH: 1668)
        XCTAssertEqual(pro11, .ipadPro11)

        // iPad Pro 12.9" & Air 13"
        let pro129 = HeadUnitScreenConfig.detectModelFamily(panelW: 2732, panelH: 2048)
        XCTAssertEqual(pro129, .ipadPro129AndAir13)

        // iPad Pro 13" M4 OLED
        let pro13M4 = HeadUnitScreenConfig.detectModelFamily(panelW: 2752, panelH: 2064)
        XCTAssertEqual(pro13M4, .ipadPro13M4)

        // Generic fallback
        let generic = HeadUnitScreenConfig.detectModelFamily(panelW: 1000, panelH: 800)
        XCTAssertEqual(generic, .genericIpad)
    }

    // MARK: - 2. 2020+ iPad Recommended DPI

    func testIPadModelCatalogRecommendedDpi() {
        // iPad mini in 1080p (active ~1440x1080) -> 160 DPI
        let miniDpi1080 = AnnouncedDensityPolicy.recommendedDpi(activeW: 1440, activeH: 1080, panelW: 2266, panelH: 1488)
        XCTAssertEqual(miniDpi1080, 160)

        // iPad mini in 1440p (active ~1920x1440) -> 210 DPI
        let miniDpi1440 = AnnouncedDensityPolicy.recommendedDpi(activeW: 1920, activeH: 1440, panelW: 2266, panelH: 1488)
        XCTAssertEqual(miniDpi1440, 210)

        // iPad 10.2" in 1080p -> 170 DPI
        let stdDpi1080 = AnnouncedDensityPolicy.recommendedDpi(activeW: 1440, activeH: 1080, panelW: 2160, panelH: 1620)
        XCTAssertEqual(stdDpi1080, 170)

        // iPad 10.2" in 1440p -> 220 DPI
        let stdDpi1440 = AnnouncedDensityPolicy.recommendedDpi(activeW: 1920, activeH: 1440, panelW: 2160, panelH: 1620)
        XCTAssertEqual(stdDpi1440, 220)

        // iPad Air / Pro 11" in 1080p -> 180 DPI
        let airDpi1080 = AnnouncedDensityPolicy.recommendedDpi(activeW: 1440, activeH: 1080, panelW: 2360, panelH: 1640)
        XCTAssertEqual(airDpi1080, 180)

        // iPad Air / Pro 11" in 1440p -> 240 DPI
        let airDpi1440 = AnnouncedDensityPolicy.recommendedDpi(activeW: 1920, activeH: 1440, panelW: 2388, panelH: 1668)
        XCTAssertEqual(airDpi1440, 240)

        // iPad Pro 12.9" / 13" in 1080p -> 200 DPI
        let proDpi1080 = AnnouncedDensityPolicy.recommendedDpi(activeW: 1440, activeH: 1080, panelW: 2732, panelH: 2048)
        XCTAssertEqual(proDpi1080, 200)

        // iPad Pro 12.9" / 13" in 1440p -> 240 DPI
        let proDpi1440 = AnnouncedDensityPolicy.recommendedDpi(activeW: 1920, activeH: 1440, panelW: 2752, panelH: 2064)
        XCTAssertEqual(proDpi1440, 240)
    }

    // MARK: - 3. ServiceDiscoveryResponse Pipelined Depth & Margins

    func testServiceDiscoveryResponseVideoConfiguration() {
        let config = HeadUnitScreenConfig.shared
        config.initScreen(width: 2160, height: 1620, scale: 2.0, fitMode: .fillMargin, requestedResolution: .r1920x1080)

        let message = AapServiceDiscoveryResponseMessage.make(
            screenConfig: config,
            fpsLimit: 60,
            rightHandDrive: false,
            requestedDpi: 170
        )

        XCTAssertEqual(message.channel, Int(Channel.ID_CTR))
        XCTAssertEqual(message.type, Int(ControlMsgType.messageServiceDiscoveryResponse.rawValue))

        var reader = ProtoReader(data: message.payload)
        guard let proto = try? ServiceDiscoveryResponseProto(from: &reader) else {
            XCTFail("Expected ServiceDiscoveryResponseProto")
            return
        }

        // Find video service
        let videoService = proto.services.first(where: { $0.id == UInt32(Channel.ID_VID) })
        XCTAssertNotNil(videoService)
        XCTAssertNotNil(videoService?.mediaSinkService)

        let videoConfig = videoService?.mediaSinkService?.videoConfigs.first
        XCTAssertNotNil(videoConfig)
        XCTAssertEqual(videoConfig?.codecResolution, ._1920x1080)
        XCTAssertEqual(videoConfig?.decoderAdditionalDepth, 8, "decoderAdditionalDepth should be 8 for pipelined rendering")
        XCTAssertEqual(videoConfig?.frameRate, ._60)

        // Find input service and verify touchscreen matches negotiated dimensions
        let inputService = proto.services.first(where: { $0.id == UInt32(Channel.ID_INP) })
        XCTAssertNotNil(inputService)
        XCTAssertEqual(inputService?.inputSourceService?.touchscreen?.width, 1920)
        XCTAssertEqual(inputService?.inputSourceService?.touchscreen?.height, 1080)
    }

    // MARK: - 4. Touch Coordinate Mapping & Reverse Calculation

    func testTouchCoordinateMapperWithMargins() {
        // Test 1920x1080 codec container with widthMargin = 480 (active area 1440x1080)
        // Center of user screen (0.5, 0.5) must map to center of active area (halfMargin + active/2 = 240 + 720 = 960)
        let centerCoord = TouchCoordinateMapper.map(
            rawX: 500,
            rawY: 500,
            inputSurfaceWidth: 1000,
            inputSurfaceHeight: 1000,
            negotiatedWidth: 1920,
            negotiatedHeight: 1080,
            marginWidth: 480,
            marginHeight: 0,
            fitMode: .fillMargin
        )

        XCTAssertEqual(centerCoord.x, 960)
        XCTAssertEqual(centerCoord.y, 540)

        // Top-left corner of user screen (0, 0) must map to (240, 0)
        let topLeftCoord = TouchCoordinateMapper.map(
            rawX: 0,
            rawY: 0,
            inputSurfaceWidth: 1000,
            inputSurfaceHeight: 1000,
            negotiatedWidth: 1920,
            negotiatedHeight: 1080,
            marginWidth: 480,
            marginHeight: 0,
            fitMode: .fillMargin
        )

        XCTAssertEqual(topLeftCoord.x, 240)
        XCTAssertEqual(topLeftCoord.y, 0)

        // Bottom-right corner of user screen (1000, 1000) must map to (240 + 1440 = 1680, 1080)
        let bottomRightCoord = TouchCoordinateMapper.map(
            rawX: 1000,
            rawY: 1000,
            inputSurfaceWidth: 1000,
            inputSurfaceHeight: 1000,
            negotiatedWidth: 1920,
            negotiatedHeight: 1080,
            marginWidth: 480,
            marginHeight: 0,
            fitMode: .fillMargin
        )

        XCTAssertEqual(bottomRightCoord.x, 1680)
        XCTAssertEqual(bottomRightCoord.y, 1080)
    }

    // MARK: - 5. Projection Connection Modes

    func testProjectionConnectionModes() {
        let modes = ProjectionConnectionMode.allCases
        XCTAssertEqual(modes.count, 3)
        XCTAssertEqual(modes[0], .nativeWpp)
        XCTAssertEqual(modes[1], .hotspotServer)
        XCTAssertEqual(modes[2], .manualIp)

        XCTAssertEqual(ProjectionConnectionMode.nativeWpp.title, "Native Mode (Auto WPP)")
        XCTAssertEqual(ProjectionConnectionMode.hotspotServer.title, "Hotspot Server Mode (Port 5277)")
        XCTAssertEqual(ProjectionConnectionMode.manualIp.title, "Manual IP")

        // Backwards compatibility aliases
        XCTAssertEqual(ProjectionConnectionMode.auto, .nativeWpp)
        XCTAssertEqual(ProjectionConnectionMode.directHeadunit, .hotspotServer)
    }

    // MARK: - 6. MainViewController Fullscreen & Touch View Hierarchy

    @MainActor
    func testMainViewControllerFullscreenAndTouchHierarchy() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let mainVC = MainViewController()
        window.rootViewController = mainVC
        window.makeKeyAndVisible()

        mainVC.loadViewIfNeeded()
        mainVC.view.layoutIfNeeded()

        // Verify status bar & home indicator initial state (disconnected -> false)
        XCTAssertFalse(mainVC.prefersStatusBarHidden)
        XCTAssertFalse(mainVC.prefersHomeIndicatorAutoHidden)

        // Verify TouchInputView is userInteractionEnabled
        let touchViews = mainVC.view.subviews.flatMap { $0.subviews }.compactMap { $0 as? TouchInputView }
        XCTAssertFalse(touchViews.isEmpty, "TouchInputView should exist in the view hierarchy")
        for touchView in touchViews {
            XCTAssertTrue(touchView.isUserInteractionEnabled)
            XCTAssertTrue(touchView.isMultipleTouchEnabled)
        }
    }

    // MARK: - 7. Touch Event Zero-Field Encoding, MediaAck Session=0 & PCM Float32 Conversion

    func testTouchEventEncodingAlwaysWritesZeroFields() {
        let msg = AapTouchEventMessage.make(
            timestampNs: 0,
            action: .down,
            actionIndex: 0,
            pointers: [(id: 0, x: 0, y: 0)]
        )

        let bytes = [UInt8](msg.payload)
        // InputReport field 1 (timestamp = 0) -> [0x08, 0x00]
        XCTAssertTrue(bytes.starts(with: [0x08, 0x00]), "InputReport must always write timestamp field 1 even when 0")
        // InputReport field 3 (touch_event) tag is 0x1A
        XCTAssertTrue(bytes.contains(0x1A), "InputReport must encode touch_event at field 3 (wire tag 0x1A)")

        // Pointer message must explicitly encode x=0 (0x08, 0x00), y=0 (0x10, 0x00), pointer_id=0 (0x18, 0x00)
        let expectedPointerBytes: [UInt8] = [0x0A, 0x06, 0x08, 0x00, 0x10, 0x00, 0x18, 0x00]
        XCTAssertNotNil(
            bytes.firstRange(of: expectedPointerBytes),
            "TouchEvent Pointer must explicitly write x=0, y=0, and pointer_id=0 ([0x18, 0x00])"
        )

        // TouchEvent must explicitly encode action_index=0 (0x10, 0x00) and action=ACTION_DOWN (0x18, 0x00)
        let expectedActionTail: [UInt8] = [0x10, 0x00, 0x18, 0x00]
        XCTAssertTrue(
            bytes.suffix(4).elementsEqual(expectedActionTail),
            "TouchEvent must explicitly write action_index=0 ([0x10, 0x00]) and action=0 ([0x18, 0x00])"
        )
    }

    func testMediaAckAlwaysWritesSessionZero() {
        let mediaAck = MediaAck(sessionId: 0, ack: 1)
        let encoded = mediaAck.serializedData()
        let bytes = [UInt8](encoded)

        XCTAssertGreaterThanOrEqual(bytes.count, 4, "MediaAck with sessionId=0 must be at least 4 bytes")
        XCTAssertEqual(Array(bytes.prefix(4)), [0x08, 0x00, 0x10, 0x01], "MediaAck must never omit session=0")

        let defaultAck = MediaAck(sessionId: 0).serializedData()
        XCTAssertEqual([UInt8](defaultAck), [0x08, 0x00, 0x10, 0x01])
    }

    func testPCMAudioPlayerInt16ToFloat32Conversion() {
        let samples: [Int16] = [16384, -16384, 32767, -32768]
        var pcmData = Data(capacity: samples.count * MemoryLayout<Int16>.size)
        for sample in samples {
            var le = sample.littleEndian
            withUnsafeBytes(of: &le) { pcmData.append(contentsOf: $0) }
        }

        let player = PCMAudioPlayer()
        guard let buffer = player.enqueuePCMData(pcmData, sampleRate: 48000, channels: 2) else {
            XCTFail("Expected non-nil Float32 AVAudioPCMBuffer")
            return
        }

        XCTAssertEqual(buffer.format.commonFormat, .pcmFormatFloat32)
        XCTAssertFalse(buffer.format.isInterleaved, "AVAudioPCMBuffer must use standard non-interleaved Float32 format")
        XCTAssertEqual(buffer.format.sampleRate, 48000)
        XCTAssertEqual(buffer.format.channelCount, 2)
        XCTAssertEqual(buffer.frameLength, 2)

        guard let floatChannels = buffer.floatChannelData else {
            XCTFail("Expected non-nil floatChannelData")
            return
        }

        // Frame 0: L = 16384 / 32768 = 0.5, R = -16384 / 32768 = -0.5
        XCTAssertEqual(floatChannels[0][0], 0.5, accuracy: 0.0001)
        XCTAssertEqual(floatChannels[1][0], -0.5, accuracy: 0.0001)

        // Frame 1: L = 32767 / 32768, R = -32768 / 32768 = -1.0
        XCTAssertEqual(floatChannels[0][1], Float(32767.0 / 32768.0), accuracy: 0.0001)
        XCTAssertEqual(floatChannels[1][1], -1.0, accuracy: 0.0001)
    }

    // MARK: - 7. Real-Device Touch Single-Pass Mapping, Audio Fragment Reassembly & Native Exit

    func testSinglePassTouchMappingMatchesActiveVideoRegion() {
        let touchView = TouchInputView(frame: CGRect(x: 0, y: 0, width: 1180, height: 820))
        touchView.surfaceSize = CGSize(width: 1180, height: 820)
        touchView.codecWidth = 1920
        touchView.codecHeight = 1080
        touchView.widthMargin = 480
        touchView.heightMargin = 0
        touchView.videoFitMode = .fillMargin

        // Center tap (590, 410)
        let center = touchView.mapTouchToActiveContent(CGPoint(x: 590, y: 410))
        // widthMargin/2 = 240. Active width = 1440. Center = 240 + 720 = 960.
        // heightMargin/2 = 0. Active height = 1080. Center = 540.
        XCTAssertEqual(center.x, 960)
        XCTAssertEqual(center.y, 540)

        // Top-left tap (0, 0)
        let topLeft = touchView.mapTouchToActiveContent(CGPoint(x: 0, y: 0))
        XCTAssertEqual(topLeft.x, 240)
        XCTAssertEqual(topLeft.y, 0)

        // Bottom-right tap (1180, 820)
        let bottomRight = touchView.mapTouchToActiveContent(CGPoint(x: 1180, y: 820))
        XCTAssertEqual(bottomRight.x, 1680)
        XCTAssertEqual(bottomRight.y, 1080)
    }

    func testFragmentedAudioPacketReassemblyDoesNotStripMidStreamBytes() {
        final class TestAudioDelegate: AapTransportDelegate {
            var deliveredAudio: [Data] = []
            func aapTransport(_ transport: AapTransport, didReceiveVideoData data: Data) {}
            func aapTransport(_ transport: AapTransport, didReceiveAudioData data: Data, on channel: UInt8) {
                deliveredAudio.append(data)
            }
            func aapTransport(_ transport: AapTransport, didReceiveAudioData data: Data, on channel: UInt8, isAac: Bool) {
                deliveredAudio.append(data)
            }
            func aapTransport(_ transport: AapTransport, didReceiveAudioCodecConfig data: Data, on channel: UInt8) {}
            func aapTransport(_ transport: AapTransport, didReceiveMediaMetadata metadata: AapMediaMetadata) {}
            func aapTransport(_ transport: AapTransport, didReceivePlaybackStatus status: AapPlaybackStatus) {}
            func aapTransport(_ transport: AapTransport, didRequestMicrophoneCapture isOpen: Bool) {}
            func aapTransport(_ transport: AapTransport, didRequestLocationUpdates isEnabled: Bool) {}
            func aapTransport(_ transport: AapTransport, didChangeState state: AapTransportState) {}
            func aapTransportDidDisconnect(_ transport: AapTransport) {}
            func aapTransportDidRequestExit(_ transport: AapTransport) {}
        }

        final class DummyConnection: ByteStreamConnection {
            weak var delegate: ByteStreamConnectionDelegate?
            var isConnected: Bool = true
            func send(_ data: Data, completion: ((Error?) -> Void)?) { completion?(nil) }
            func disconnect() { isConnected = false }
        }

        let connection = DummyConnection()
        let transport = AapTransport(connection: connection, handshakeProfile: .network)
        let delegate = TestAudioDelegate()
        transport.delegate = delegate

        let channel = Channel.ID_AUD // 3 (stereo PCM)

        // Fragment 1 (FIRST, flags = 0x09): 8 bytes timestamp + 100 bytes PCM (0xAA)
        var p1 = Data(repeating: 0x00, count: 8) // 8-byte timestamp
        p1.append(Data(repeating: 0xAA, count: 100))
        let msg1 = AapMessage(channel: channel, flags: 0x09, type: 0, payload: p1)

        // Fragment 2 (MIDDLE, flags = 0x08): 100 bytes PCM (0xBB), NO timestamp
        let p2 = Data(repeating: 0xBB, count: 100)
        let msg2 = AapMessage(channel: channel, flags: 0x08, type: 0, payload: p2)

        // Fragment 3 (LAST, flags = 0x0a): 100 bytes PCM (0xCC), NO timestamp
        let p3 = Data(repeating: 0xCC, count: 100)
        let msg3 = AapMessage(channel: channel, flags: 0x0a, type: 0, payload: p3)

        transport.handleMessage(msg1)
        XCTAssertEqual(delegate.deliveredAudio.count, 0, "First fragment should be buffered awaiting complete assembly")

        transport.handleMessage(msg2)
        XCTAssertEqual(delegate.deliveredAudio.count, 0, "Middle fragment should be appended to assembly buffer")

        transport.handleMessage(msg3)
        XCTAssertEqual(delegate.deliveredAudio.count, 1, "Last fragment should trigger delivery of complete audio payload")

        guard let assembled = delegate.deliveredAudio.first else {
            XCTFail("Expected assembled audio data")
            return
        }

        // Expected count: 100 + 100 + 100 = 300 bytes (aligned to 4-byte stereo Int16 frames)
        XCTAssertEqual(assembled.count, 300)
        XCTAssertEqual(assembled.prefix(100), Data(repeating: 0xAA, count: 100))
        XCTAssertEqual(assembled.subdata(in: 100..<200), Data(repeating: 0xBB, count: 100))
        XCTAssertEqual(assembled.suffix(100), Data(repeating: 0xCC, count: 100))
    }

    func testNativeVideoFocusRequestTriggersExitToHomeScreen() {
        final class TestExitDelegate: AapTransportDelegate {
            var exitRequested = false
            func aapTransport(_ transport: AapTransport, didReceiveVideoData data: Data) {}
            func aapTransport(_ transport: AapTransport, didReceiveAudioData data: Data, on channel: UInt8) {}
            func aapTransport(_ transport: AapTransport, didReceiveAudioData data: Data, on channel: UInt8, isAac: Bool) {}
            func aapTransport(_ transport: AapTransport, didReceiveAudioCodecConfig data: Data, on channel: UInt8) {}
            func aapTransport(_ transport: AapTransport, didReceiveMediaMetadata metadata: AapMediaMetadata) {}
            func aapTransport(_ transport: AapTransport, didReceivePlaybackStatus status: AapPlaybackStatus) {}
            func aapTransport(_ transport: AapTransport, didRequestMicrophoneCapture isOpen: Bool) {}
            func aapTransport(_ transport: AapTransport, didRequestLocationUpdates isEnabled: Bool) {}
            func aapTransport(_ transport: AapTransport, didChangeState state: AapTransportState) {}
            func aapTransportDidDisconnect(_ transport: AapTransport) {}
            func aapTransportDidRequestExit(_ transport: AapTransport) {
                exitRequested = true
            }
        }

        final class DummyConnection: ByteStreamConnection {
            weak var delegate: ByteStreamConnectionDelegate?
            var isConnected: Bool = true
            func send(_ data: Data, completion: ((Error?) -> Void)?) { completion?(nil) }
            func disconnect() { isConnected = false }
        }

        let connection = DummyConnection()
        let transport = AapTransport(connection: connection, handshakeProfile: .network)
        let delegate = TestExitDelegate()
        transport.delegate = delegate

        // Send VideoFocusRequest (0x8007) with mode = 2 (VIDEO_FOCUS_NATIVE)
        // field 2 (mode) = 2 (0x10, 0x02)
        var payload = Data()
        payload.append(contentsOf: [0x10, 0x02])
        let msg = AapMessage(channel: Channel.ID_VID, flags: 0, type: 0x8007, payload: payload)

        transport.handleMessage(msg)
        XCTAssertTrue(delegate.exitRequested, "Native video focus request (mode=2) must trigger aapTransportDidRequestExit")
    }
}
