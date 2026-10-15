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

        // iPad Pro 12.9" / 13" in 1440p -> 260 DPI
        let proDpi1440 = AnnouncedDensityPolicy.recommendedDpi(activeW: 1920, activeH: 1440, panelW: 2752, panelH: 2064)
        XCTAssertEqual(proDpi1440, 260)
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
}
