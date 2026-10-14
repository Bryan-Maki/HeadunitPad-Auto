//
//  ViewControllersSmokeTests.swift
//  HeadunitPadTests
//
//  Smoke tests verifying that all primary ViewControllers, Windows,
//  and custom Views instantiate, layout, and complete their lifecycle without crashing.
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

        // Wireless QR pairing setup dialog
        let qrVC = ProjectionSetupQrViewController()
        qrVC.loadViewIfNeeded()
        qrVC.viewWillAppear(false)
        qrVC.viewDidAppear(false)
        qrVC.view.layoutIfNeeded()
        XCTAssertNotNil(qrVC.view)

        // DPI Preview visualizer
        let previewView = DpiPreviewView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        previewView.dpi = 160
        previewView.panelWidthPx = 2048
        previewView.panelHeightPx = 1536
        previewView.layoutIfNeeded()
        previewView.draw(CGRect(x: 0, y: 0, width: 400, height: 300))
        XCTAssertEqual(previewView.virtualWidthDp, 2048)
    }
}
