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
        // Center of user screen (0.5, 0.5) must map to center of active area (1440/2 = 720, 1080/2 = 540)
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

        XCTAssertEqual(centerCoord.x, 720)
        XCTAssertEqual(centerCoord.y, 540)

        // Top-left corner of user screen (0, 0) must map to (0, 0)
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

        XCTAssertEqual(topLeftCoord.x, 0)
        XCTAssertEqual(topLeftCoord.y, 0)

        // Bottom-right corner of user screen (1000, 1000) must map to (1440, 1080)
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

        XCTAssertEqual(bottomRightCoord.x, 1440)
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
        // Active width = 1440. Center = 720.
        // Active height = 1080. Center = 540.
        XCTAssertEqual(center.x, 720)
        XCTAssertEqual(center.y, 540)

        // Top-left tap (0, 0)
        let topLeft = touchView.mapTouchToActiveContent(CGPoint(x: 0, y: 0))
        XCTAssertEqual(topLeft.x, 0)
        XCTAssertEqual(topLeft.y, 0)

        // Bottom-right tap (1180, 820)
        let bottomRight = touchView.mapTouchToActiveContent(CGPoint(x: 1180, y: 820))
        XCTAssertEqual(bottomRight.x, 1440)
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

    // MARK: - 8. Custom DPI Priority & Margins Alignment & WPP Wakeup

    func testCustomDpiOverridesDefaultModelDpiInServiceDiscovery() {
        let config = HeadUnitScreenConfig.shared
        config.initScreen(width: 2360, height: 1640, scale: 2.0, fitMode: .fillMargin, requestedResolution: .r1920x1080)

        // 1. Without custom DPI, iPad Air default recommended DPI in 1080p is 180
        config.customDpi = nil
        ProjectionSettings.isAutoDpi = true
        let defaultDecision = config.densityDecision(requestedDpi: 160)
        XCTAssertEqual(defaultDecision.announced, 180)
        XCTAssertEqual(config.announcedDensity, 180)

        // 2. With ProjectionSettings.dpi = 220 and isAutoDpi = false (independent of customDpi init)
        config.customDpi = nil
        ProjectionSettings.isAutoDpi = false
        ProjectionSettings.dpi = 220
        XCTAssertEqual(config.announcedDensity, 220, "announcedDensity must equal 220 when isAutoDpi is false")
        let customDecision = config.densityDecision(requestedDpi: 160)
        XCTAssertEqual(customDecision.announced, 220)

        // 3. Verify in ServiceDiscoveryResponse videoConfig density
        let message = AapServiceDiscoveryResponseMessage.make(
            screenConfig: config,
            fpsLimit: 60,
            rightHandDrive: false
        )
        var reader = ProtoReader(data: message.payload)
        guard let proto = try? ServiceDiscoveryResponseProto(from: &reader) else {
            XCTFail("Expected ServiceDiscoveryResponseProto")
            return
        }
        let videoService = proto.services.first(where: { $0.id == UInt32(Channel.ID_VID) })
        let videoConfig = videoService?.mediaSinkService?.videoConfigs.first
        XCTAssertEqual(videoConfig?.density, 220, "Video configuration density must equal custom DPI (220)")

        // 4. Test explicit config.customDpi override
        config.customDpi = 240
        XCTAssertEqual(config.announcedDensity, 240)

        // Clean up
        config.customDpi = nil
        ProjectionSettings.resetDpiToDefault()
    }

    func testVideoRendererAndTouchOverlayShareIdenticalMargins() {
        let config = HeadUnitScreenConfig.shared
        // iPad Air 4 (2360x1640, native pt 1180x820)
        config.initScreen(width: 2360, height: 1640, scale: 2.0, fitMode: .fillMargin, requestedResolution: .r1920x1080)

        let renderer = H264VideoRendererView()
        let touchView = TouchInputView()
        touchView.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)
        renderer.frame = CGRect(x: 0, y: 0, width: 1180, height: 820)

        let expectedMarginW = config.getWidthMargin()
        let expectedMarginH = config.getHeightMargin()
        XCTAssertEqual(expectedMarginW, 366, "iPad Air 4 1080p fillMargin width margin must be 366")
        XCTAssertEqual(expectedMarginH, 0)

        config.recordAnnouncedMargins(widthMargin: expectedMarginW, heightMargin: expectedMarginH)

        // Simulate unified syncVideoAndTouchGeometry
        renderer.codecWidth = config.negotiatedWidth
        renderer.codecHeight = config.negotiatedHeight
        renderer.widthMargin = config.announcedWidthMargin
        renderer.heightMargin = config.announcedHeightMargin
        renderer.fitMode = config.videoFitMode

        touchView.surfaceSize = touchView.bounds.size
        touchView.screenConfig = config
        touchView.videoFitMode = config.videoFitMode
        touchView.codecWidth = config.negotiatedWidth
        touchView.codecHeight = config.negotiatedHeight
        touchView.widthMargin = renderer.widthMargin
        touchView.heightMargin = renderer.heightMargin

        XCTAssertEqual(renderer.widthMargin, touchView.widthMargin)
        XCTAssertEqual(renderer.heightMargin, touchView.heightMargin)
        XCTAssertEqual(renderer.codecWidth, touchView.codecWidth)
        XCTAssertEqual(renderer.codecHeight, touchView.codecHeight)

        // 1. Left edge tap (0, 410) on 1180x820 screen -> x = 0 (not 183)
        let mappedLeft = touchView.mapTouchToActiveContent(CGPoint(x: 0, y: 410))
        XCTAssertEqual(mappedLeft.x, 0, "Left screen tap must map to 0 without halfMargin offset")
        XCTAssertEqual(mappedLeft.y, 540)

        // 2. Center tap (590, 410) on 1180x820 screen
        // Active content is (1920 - 366) = 1554 wide.
        // Center of 1554 is 777 (not 960).
        let mappedCenter = touchView.mapTouchToActiveContent(CGPoint(x: 590, y: 410))
        XCTAssertEqual(mappedCenter.x, 777, "Center screen tap must map precisely to active horizontal center 777")
        XCTAssertEqual(mappedCenter.y, 540, "Center screen tap must map precisely to active vertical center 540")

        // 3. Right edge tap (1180, 410) on 1180x820 screen -> x = 1554 (not 1737)
        let mappedRight = touchView.mapTouchToActiveContent(CGPoint(x: 1180, y: 410))
        XCTAssertTrue((1553...1554).contains(mappedRight.x), "Right screen tap must map to active width in [1553, 1554]")
        XCTAssertEqual(mappedRight.y, 540)
    }

    func testWppHandshakeSessionSendsImmediateWifiStartRequestAndAcceptsIncomingAap() {
        let wppSession = WppHandshakeSession()
        let frames = wppSession.start(localIp: "192.168.43.1", aapPort: 5000)

        XCTAssertFalse(frames.isEmpty, "WPP start must produce at least one frame")
        guard let firstFrame = frames.first else { return }

        XCTAssertGreaterThanOrEqual(firstFrame.count, 4, "WPP frame must be at least header size")
        let decodedType = try? WppFraming.decodeType(header: firstFrame.prefix(4))
        XCTAssertEqual(decodedType, WppMessageType.startRequest.rawValue, "WPP frame type must be startRequest (1)")

        let decodedPayloadSize = try? WppFraming.decodePayloadSize(header: firstFrame.prefix(4))
        XCTAssertEqual(firstFrame.count - 4, decodedPayloadSize, "Decoded payload size must match frame body length")

        // Verify TcpHandler has accept(connection:initialData:)
        let tcpHandler = TcpHandler()
        XCTAssertFalse(tcpHandler.isConnected)
    }

    func testVideoMediaAckSentImmediatelyOnFirstFragment() {
        final class MockConnection: ByteStreamConnection {
            weak var delegate: ByteStreamConnectionDelegate?
            var isConnected: Bool = true
            var sentPackets: [Data] = []
            func send(_ data: Data, completion: ((Error?) -> Void)?) {
                sentPackets.append(data)
                completion?(nil)
            }
            func disconnect() { isConnected = false }
        }

        let connection = MockConnection()
        let transport = AapTransport(connection: connection, handshakeProfile: .network)

        // 1. Send Media.Setup on video channel to trigger sendMediaConfig
        let setupMsg = AapMessage(channel: Channel.ID_VID, flags: 0x0b, type: 0x8000, payload: Data())
        transport.handleMessage(setupMsg)

        // Find MediaConfig (0x8003) sent on Channel.ID_VID
        let configPacket = connection.sentPackets.first { packet in
            guard packet.count >= 6 else { return false }
            let chan = packet[0]
            let type = (Int(packet[4]) << 8) | Int(packet[5])
            return chan == Channel.ID_VID && type == 0x8003
        }
        XCTAssertNotNil(configPacket, "Transport must send Media.Config (0x8003) upon setup")
        if let configPacket = configPacket {
            let payload = configPacket.subdata(in: 6..<configPacket.count)
            let maxUnacked = AapTransport.ProtoWire.extractFirstVarint(from: payload, fieldNumber: 2) ?? 0
            XCTAssertGreaterThanOrEqual(maxUnacked, 12, "Video channel maxUnacked must be >= 12 (configured as 16)")
        }

        // 2. Clear sent packets to isolate MediaAck check
        connection.sentPackets.removeAll()

        // 3. Send FIRST fragment of a video frame (flags = 0x09, type = 0x0000)
        var firstFragPayload = Data(repeating: 0x00, count: 8)
        firstFragPayload.append(Data(repeating: 0x12, count: 200))
        let firstFragMsg = AapMessage(channel: Channel.ID_VID, flags: 0x09, type: 0x0000, payload: firstFragPayload)

        transport.handleMessage(firstFragMsg)

        // Verify MediaAck (0x8004) was sent immediately without waiting for 0x0a last fragment
        let ackPacket = connection.sentPackets.first { packet in
            guard packet.count >= 6 else { return false }
            let chan = packet[0]
            let type = (Int(packet[4]) << 8) | Int(packet[5])
            return chan == Channel.ID_VID && type == 0x8004
        }
        XCTAssertNotNil(ackPacket, "MediaAck (0x8004) must be sent immediately upon first fragment (0x09)")
    }

    func testWirelessListenerReusesRunningSocketOnRepeatedStart() {
        let testPort: UInt16 = 5388
        let server = WirelessHelperServer()
        XCTAssertFalse(server.isRunning)

        server.start(port: testPort, enableBonjour: false)

        let exp = expectation(description: "Server isRunning")
        DispatchQueue.global().async {
            for _ in 0..<30 {
                if server.isRunning {
                    exp.fulfill()
                    break
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        wait(for: [exp], timeout: 2.0)

        XCTAssertTrue(server.isRunning)

        // Repeated start on the same port should keep isRunning = true without tearing down
        server.start(port: testPort, enableBonjour: false)
        XCTAssertTrue(server.isRunning, "Repeated start should not tear down running listener")

        server.stop()
        XCTAssertFalse(server.isRunning)
    }

    // MARK: - 10. Night Mode & WPP Overhaul Tests

    func testNightModeSensorStartRequestSendsImmediateNightEventAndLiveUpdate() {
        let prevNight = ProjectionSettings.nightMode
        defer { ProjectionSettings.nightMode = prevNight }

        XCTAssertEqual(NightModeSetting.allCases.count, 4)

        ProjectionSettings.nightMode = .night
        XCTAssertTrue(ProjectionSettings.effectiveIsNightMode())

        ProjectionSettings.nightMode = .day
        XCTAssertFalse(ProjectionSettings.effectiveIsNightMode())

        ProjectionSettings.nightMode = .system
        XCTAssertTrue(ProjectionSettings.effectiveIsNightMode(userInterfaceStyle: .dark))
        XCTAssertFalse(ProjectionSettings.effectiveIsNightMode(userInterfaceStyle: .light))

        ProjectionSettings.nightMode = .auto
        let cal = Calendar.current
        let hour = cal.component(.hour, from: Date())
        let expectedAutoNight = (hour < 7 || hour >= 19)
        XCTAssertEqual(ProjectionSettings.effectiveIsNightMode(), expectedAutoNight)

        final class MockConnection: ByteStreamConnection {
            weak var delegate: ByteStreamConnectionDelegate?
            var isConnected: Bool = true
            var sentPackets: [Data] = []
            func send(_ data: Data, completion: ((Error?) -> Void)?) {
                sentPackets.append(data)
                completion?(nil)
            }
            func disconnect() { isConnected = false }
        }

        let connection = MockConnection()
        let transport = AapTransport(connection: connection, handshakeProfile: .network)

        // 1. Channel open request on sensor channel (Channel.ID_SEN = 1)
        let openMsg = AapMessage(channel: Channel.ID_SEN, flags: 0x03, type: AapMessageType.CHANNEL_OPEN_REQUEST.rawValue, payload: Data([0x08, 0x01]))
        transport.handleMessage(openMsg)

        // 2. Sensor 10 start request (NIGHT)
        let sensor10Req = AapMessage(channel: Channel.ID_SEN, flags: 0x03, type: 0x8001, payload: Data([0x08, 0x0a]))
        transport.handleMessage(sensor10Req)

        let exp = expectation(description: "Wait for processingQueue async night mode event")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        // Verify sentPackets contains Sensor Start Response (0x8002) and NightMode Indication (0x8003)
        let hasStartResponse = connection.sentPackets.contains { packet in
            guard packet.count >= 6 else { return false }
            let chan = packet[0]
            let type = (Int(packet[4]) << 8) | Int(packet[5])
            return chan == Channel.ID_SEN && type == 0x8002
        }
        XCTAssertTrue(hasStartResponse, "Must send Sensor Start Response (0x8002) for sensor 10")

        let hasNightEvent = connection.sentPackets.contains { packet in
            guard packet.count >= 6 else { return false }
            let chan = packet[0]
            let type = (Int(packet[4]) << 8) | Int(packet[5])
            return chan == Channel.ID_SEN && type == 0x8003
        }
        XCTAssertTrue(hasNightEvent, "Must send NightMode SensorEventIndication (0x8003) upon sensor 10 start")
    }

    func testWppTcpServerDefaultPortIs5299AndPointsTo5288() {
        XCTAssertEqual(WppTcpServer.defaultPort, 5299)
        let server = WppTcpServer()
        XCTAssertEqual(server.projectionPort, 5288)
    }

    func testWppHandshakeSessionTcpSessionUpTransitionsToHolding() {
        let session = WppHandshakeSession(credentialsKnown: true)
        let actions1 = session.on(event: .socketReady)
        XCTAssertEqual(session.stage, .awaitVersion)
        XCTAssertEqual(actions1, [.sendVersionRequest])

        // When AAP inbound connection is accepted, tcpSessionUp arrives
        let actions2 = session.on(event: .tcpSessionUp)
        XCTAssertEqual(session.stage, .holding)
        XCTAssertTrue(actions2.contains(.completeSuccess))

        // In holding stage, pings are handled to keep connection alive
        let pingPayload = Data([0xaa, 0xbb, 0xcc])
        let actions3 = session.on(event: .messageReceived(type: WppMessageType.pingRequest.rawValue, status: nil, rawPayload: pingPayload))
        XCTAssertEqual(session.stage, .holding)
        XCTAssertEqual(actions3, [.sendPingResponse(pingPayload)])
    }

    func testResolutionLockedPreventsDimensionResetDuringRotation() {
        let config = HeadUnitScreenConfig.shared
        config.negotiatedWidth = 1920
        config.negotiatedHeight = 1080
        config.isResolutionLocked = true

        // Simulate iPad rotating to portrait: container size changes to 1620x2160
        _ = config.updateDimensions(width: 1620, height: 2160)

        // Codec dimensions must remain locked at 1920x1080
        XCTAssertEqual(config.negotiatedWidth, 1920)
        XCTAssertEqual(config.negotiatedHeight, 1080)
        XCTAssertEqual(config.screenWidthPx, 1620)
        XCTAssertEqual(config.screenHeightPx, 2160)

        // Clearing custom negotiated resolution unlocks resolution
        config.clearCustomNegotiatedResolution()
        XCTAssertFalse(config.isResolutionLocked)
    }

    func testNightModeDeduplicationAndForceFlag() {
        final class MockByteConnection: ByteStreamConnection {
            weak var delegate: ByteStreamConnectionDelegate?
            var isConnected: Bool = true
            var sentPackets: [Data] = []
            func send(_ data: Data, completion: ((Error?) -> Void)?) {
                sentPackets.append(data)
                completion?(nil)
            }
            func disconnect() { isConnected = false }
        }

        let connection = MockByteConnection()
        let transport = AapTransport(connection: connection, handshakeProfile: .network)

        // 1. Channel open request on sensor channel (Channel.ID_SEN = 1)
        let openMsg = AapMessage(channel: Channel.ID_SEN, flags: 0x03, type: AapMessageType.CHANNEL_OPEN_REQUEST.rawValue, payload: Data([0x08, 0x01]))
        transport.handleMessage(openMsg)

        // 2. Sensor 10 start request (NIGHT) -> inserts sensor 10, sets running, sends response (0x8002) and initial event (0x8003)
        let sensor10Req = AapMessage(channel: Channel.ID_SEN, flags: 0x03, type: 0x8001, payload: Data([0x08, 0x0a]))
        transport.handleMessage(sensor10Req)

        let exp1 = expectation(description: "initial night event")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { exp1.fulfill() }
        wait(for: [exp1], timeout: 1.0)

        let initialCount = connection.sentPackets.count
        XCTAssertGreaterThanOrEqual(initialCount, 2, "Sensor start response + initial night mode event must be sent")

        let currentNight = ProjectionSettings.effectiveIsNightMode()
        transport.sendNightModeEvent(isNight: currentNight, force: false)
        let exp2 = expectation(description: "dedup night event")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { exp2.fulfill() }
        wait(for: [exp2], timeout: 1.0)
        XCTAssertEqual(connection.sentPackets.count, initialCount, "Duplicate night mode event must be suppressed")

        transport.sendNightModeEvent(isNight: currentNight, force: true)
        let exp3 = expectation(description: "forced night event")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { exp3.fulfill() }
        wait(for: [exp3], timeout: 1.0)
        XCTAssertEqual(connection.sentPackets.count, initialCount + 1, "Forced night mode event must be transmitted")

        transport.sendNightModeEvent(isNight: !currentNight, force: false)
        let exp4 = expectation(description: "different night event")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { exp4.fulfill() }
        wait(for: [exp4], timeout: 1.0)
        XCTAssertEqual(connection.sentPackets.count, initialCount + 2, "Different night mode value must be transmitted")
    }

    func testDefaultSettingsValuesAndWifiCredentials() {
        XCTAssertEqual(ProjectionOrientation.system.title, "Auto")

        let prevSsid = ProjectionSettings.wifiSsid
        let prevPass = ProjectionSettings.wifiPasskey
        let prevBssid = ProjectionSettings.wifiBssid
        let prevBt = ProjectionSettings.bluetoothMac
        defer {
            ProjectionSettings.wifiSsid = prevSsid
            ProjectionSettings.wifiPasskey = prevPass
            ProjectionSettings.wifiBssid = prevBssid
            ProjectionSettings.bluetoothMac = prevBt
        }

        ProjectionSettings.wifiSsid = "Test-AutoAA"
        ProjectionSettings.wifiPasskey = "secret123"
        ProjectionSettings.wifiBssid = "02:11:22:33:44:55"
        ProjectionSettings.bluetoothMac = "11:22:33:44:55:66"

        XCTAssertEqual(ProjectionSettings.wifiSsid, "Test-AutoAA")
        XCTAssertEqual(ProjectionSettings.wifiPasskey, "secret123")
        XCTAssertEqual(ProjectionSettings.wifiBssid, "02:11:22:33:44:55")
        XCTAssertEqual(ProjectionSettings.bluetoothMac, "11:22:33:44:55:66")
    }
}
