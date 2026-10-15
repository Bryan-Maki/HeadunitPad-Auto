//
//  ViewControllersSmokeTests.swift
//  HeadunitPadTests
//
//  Smoke tests verifying that all primary ViewControllers, Windows,
//  and custom Views instantiate, layout, and scale dynamically without crashing.
//

import XCTest
import UIKit
@testable import HeadunitPad

final class ViewControllersSmokeTests: XCTestCase {

    @MainActor
    func testMainViewControllerLaunchesWithoutCrash() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
        let mainVC = MainViewController()
        window.rootViewController = mainVC
        window.makeKeyAndVisible()

        mainVC.loadViewIfNeeded()
        mainVC.viewWillAppear(false)
        mainVC.viewDidAppear(false)
        mainVC.view.layoutIfNeeded()

        XCTAssertNotNil(mainVC.view)

        // Auxiliary trackpad window
        let trackpadVC = TrackpadViewController()
        trackpadVC.loadViewIfNeeded()
        trackpadVC.viewWillAppear(false)
        trackpadVC.viewDidAppear(false)
        trackpadVC.view.layoutIfNeeded()
        XCTAssertNotNil(trackpadVC.view)

        // Auxiliary video-only window
        let videoOnlyVC = VideoOnlyViewController()
        videoOnlyVC.loadViewIfNeeded()
        videoOnlyVC.viewWillAppear(false)
        videoOnlyVC.viewDidAppear(false)
        videoOnlyVC.view.layoutIfNeeded()
        XCTAssertNotNil(videoOnlyVC.view)
    }

    func testDpiPreviewViewScalesElementsDynamically() {
        let previewView = DpiPreviewView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        previewView.panelWidthPx = 1920
        previewView.panelHeightPx = 1080

        let renderer = UIGraphicsImageRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 300))

        // Test at 120 DPI (spacious, smaller dock & cards)
        previewView.dpi = 120
        _ = renderer.image { _ in
            previewView.draw(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        let railW120 = previewView.lastCalculatedRailWidth
        let cardW120 = previewView.lastCalculatedSecondaryCardWidth
        XCTAssertEqual(previewView.virtualWidthDp, 2560)
        XCTAssertTrue(previewView.isCoolwalkSplitScreen)

        // Test at 240 DPI (dense, larger dock & cards)
        previewView.dpi = 240
        _ = renderer.image { _ in
            previewView.draw(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        let railW240 = previewView.lastCalculatedRailWidth
        let cardW240 = previewView.lastCalculatedSecondaryCardWidth
        XCTAssertEqual(previewView.virtualWidthDp, 1280)
        XCTAssertTrue(previewView.isCoolwalkSplitScreen)

        // Verify elements scaled up when DPI increased
        XCTAssertGreaterThan(railW240, railW120, "Rail width should grow as DPI increases")
        XCTAssertGreaterThan(cardW240, cardW120, "Secondary card width should grow as DPI increases")

        // Test at narrow resolution/high DPI where virtualWidthDp < 800
        previewView.panelWidthPx = 1280
        previewView.panelHeightPx = 720
        previewView.dpi = 320
        _ = renderer.image { _ in
            previewView.draw(CGRect(x: 0, y: 0, width: 400, height: 300))
        }
        XCTAssertEqual(previewView.virtualWidthDp, 640)
        XCTAssertFalse(previewView.isCoolwalkSplitScreen, "Should drop out of Coolwalk split screen when dp < 800")
    }

    func testHotspotGatewayHelperAndModeFiltering() {
        let gw = NetworkAddresses.currentHotspotGatewayIpv4()
        XCTAssertFalse(gw.isEmpty)

        // ProjectionConnectionMode should contain nativeWpp, hotspotServer, and manualIp
        let modes = ProjectionConnectionMode.allCases
        XCTAssertEqual(modes.count, 3)
        XCTAssertTrue(modes.contains(.nativeWpp))
        XCTAssertTrue(modes.contains(.hotspotServer))
        XCTAssertTrue(modes.contains(.manualIp))
        XCTAssertTrue(modes.contains(.auto))
        XCTAssertTrue(modes.contains(.directHeadunit))
    }
}
