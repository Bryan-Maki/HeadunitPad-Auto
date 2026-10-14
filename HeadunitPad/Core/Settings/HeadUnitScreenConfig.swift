//
//  HeadUnitScreenConfig.swift
//  HeadunitPad
//
//  1:1 port of open-headunit HeadUnitScreenConfig.kt
//  Manages iPad display dimensions, negotiated video resolution,
//  margins, DPI density, and video fit calculations.
//

import Foundation
import UIKit

public final class HeadUnitScreenConfig {
    public static let shared = HeadUnitScreenConfig()

    public private(set) var screenWidthPx: Int = 0
    public private(set) var screenHeightPx: Int = 0
    public private(set) var density: Float = 2.0
    public private(set) var scaleFactor: Float = 1.0
    public private(set) var isSmallScreen: Bool = true
    public private(set) var isPortraitScaled: Bool = false
    public private(set) var isInitialized: Bool = false

    public var videoFitMode: VideoFitMode = .fillMargin
    public var negotiatedResolutionType: ControlService.MediaSinkService.VideoConfiguration.VideoCodecResolutionType = ._1280x720
    public var isResolutionLocked: Bool = false

    public var announcedWidthMargin: Int = MarginAnnouncementPolicy.notAnnounced
    public var announcedHeightMargin: Int = MarginAnnouncementPolicy.notAnnounced
    public var announcedCanvasW: Int = 0
    public var announcedCanvasH: Int = 0

    public var onMarginsDiverged: (() -> Bool)?

    private init() {}

    public func initScreen(
        width: Int,
        height: Int,
        scale: Float = 2.0,
        fitMode: VideoFitMode = .fillMargin,
        requestedResolution: ResolutionPreset = .r1280x720
    ) {
        self.videoFitMode = fitMode
        self.density = scale
        self.screenWidthPx = width
        self.screenHeightPx = height
        self.isInitialized = true

        recalculate(requestedResolution: requestedResolution)
    }

    public func recalculate(requestedResolution: ResolutionPreset = .auto) {
        guard screenWidthPx > 0 && screenHeightPx > 0 else { return }

        // 1. Determine negotiated resolution
        if !isResolutionLocked {
            let res = NegotiatedResolutionPolicy.select(
                isLocked: isResolutionLocked,
                selected: requestedResolution,
                panelW: screenWidthPx,
                panelH: screenHeightPx,
                fitMode: videoFitMode,
                hevcSupported: true,
                canHevcHighRes: true
            ) ?? .r1280x720

            self.negotiatedResolutionType = res.protoType
        }

        // 2. Perform scaling and margin calculation
        let (videoW, videoH) = activeSize()
        let fit = ProjectionGeometryPolicy.fit(
            panelW: screenWidthPx,
            panelH: screenHeightPx,
            videoW: videoW,
            videoH: videoH
        )

        self.isSmallScreen = fit.isSmallScreen
        self.scaleFactor = fit.scaleFactor
        if let portraitScaled = fit.isPortraitScaled {
            self.isPortraitScaled = portraitScaled
        }

        // 3. Margin divergence detection
        if MarginAnnouncementPolicy.shouldReannounce(
            announcedWidthMargin: announcedWidthMargin,
            announcedHeightMargin: announcedHeightMargin,
            liveWidthMargin: getWidthMargin(),
            liveHeightMargin: getHeightMargin()
        ) {
            _ = onMarginsDiverged?()
        }
    }

    public func getNegotiatedWidth() -> Int {
        return activeSize().width
    }

    public func getNegotiatedHeight() -> Int {
        return activeSize().height
    }

    public func activeSize() -> (width: Int, height: Int) {
        switch negotiatedResolutionType {
        case ._800x480: return (800, 480)
        case ._1280x720: return (1280, 720)
        case ._1920x1080: return (1920, 1080)
        case ._2560x1440: return (2560, 1440)
        case ._3840x2160: return (3840, 2160)
        case ._720x1280: return (720, 1280)
        case ._1080x1920: return (1080, 1920)
        case ._1440x2560: return (1440, 2560)
        case ._2160x3840: return (2160, 3840)
        }
    }

    public func getWidthMargin() -> Int {
        let (videoW, _) = activeSize()
        // In FillMargin mode on iPad 4:3 display (e.g. 2048x1536 / 1024x768):
        // iPad aspect ratio is 4:3 (1.333), while AA video is 16:9 (1.777).
        // To fill full screen, the left and right margins must be announced to cut off
        // 16:9 width excess so the UI aspect matches iPad display!
        if videoFitMode == .fillMargin {
            let targetVideoWidthFor4to3 = (activeSize().height * screenWidthPx) / screenHeightPx
            let margin = max(0, videoW - targetVideoWidthFor4to3)
            return margin
        }
        if MarginStrategyPolicy.select(mode: videoFitMode, panelW: screenWidthPx, panelH: screenHeightPx, videoW: videoW, videoH: activeSize().height) == .par {
            return 0
        }
        return ProjectionGeometryPolicy.widthMargin(videoW: videoW, panelW: screenWidthPx, scaleFactor: scaleFactor)
    }

    public func getHeightMargin() -> Int {
        let (videoW, videoH) = activeSize()
        if videoFitMode == .fillMargin {
            let targetVideoHeightFor4to3 = (videoW * screenHeightPx) / screenWidthPx
            let margin = max(0, videoH - targetVideoHeightFor4to3)
            return margin
        }
        if MarginStrategyPolicy.select(mode: videoFitMode, panelW: screenWidthPx, panelH: screenHeightPx, videoW: videoW, videoH: videoH) == .par {
            return 0
        }
        return ProjectionGeometryPolicy.heightMargin(videoH: videoH, panelH: screenHeightPx, scaleFactor: scaleFactor)
    }

    public func getLeftMargin() -> Int {
        return getWidthMargin() / 2
    }

    public func getRightMargin() -> Int {
        return getWidthMargin() - getLeftMargin()
    }

    public func getTopMargin() -> Int {
        return getHeightMargin() / 2
    }

    public func getBottomMargin() -> Int {
        return getHeightMargin() - getTopMargin()
    }

    public func getPixelAspectRatioE4() -> Int {
        let (videoW, videoH) = activeSize()
        return ProjectionGeometryPolicy.pixelAspectRatioE4(
            mode: videoFitMode,
            panelW: screenWidthPx,
            panelH: screenHeightPx,
            videoW: videoW,
            videoH: videoH,
            marginW: getWidthMargin(),
            marginH: getHeightMargin()
        )
    }

    public func densityDecision(requestedDpi: Int = 160) -> AnnouncedDensityPolicy.Decision {
        let visibleW = getNegotiatedWidth() - getWidthMargin()
        let visibleH = getNegotiatedHeight() - getHeightMargin()
        return AnnouncedDensityPolicy.decide(stored: requestedDpi, visibleW: visibleW, visibleH: visibleH)
    }

    public func recordAnnouncedMargins(widthMargin: Int, heightMargin: Int) {
        self.announcedWidthMargin = widthMargin
        self.announcedHeightMargin = heightMargin
    }

    public func recordAnnouncedCanvas() {
        self.announcedCanvasW = screenWidthPx
        self.announcedCanvasH = screenHeightPx
    }

    public func clearAnnouncedMargins() {
        self.announcedWidthMargin = MarginAnnouncementPolicy.notAnnounced
        self.announcedHeightMargin = MarginAnnouncementPolicy.notAnnounced
        self.announcedCanvasW = 0
        self.announcedCanvasH = 0
    }

    public var onMarginsDiverged: ((_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) -> Void)?

    public func checkAndNotifyMarginDivergence() {
        let currentWidthMargin = getWidthMargin()
        let currentHeightMargin = getHeightMargin()
        if MarginAnnouncementPolicy.hasDiverged(
            announcedW: announcedWidthMargin,
            announcedH: announcedHeightMargin,
            currentW: currentWidthMargin,
            currentH: currentHeightMargin
        ) {
            let left = getLeftMargin()
            let right = getRightMargin()
            let top = getTopMargin()
            let bottom = getBottomMargin()
            recordAnnouncedMargins(widthMargin: currentWidthMargin, heightMargin: currentHeightMargin)
            onMarginsDiverged?(left, top, right, bottom)
        }
    }

    public func updateDimensions(width: Int, height: Int) -> Bool {
        guard width > 0 && height > 0 else { return false }
        if self.screenWidthPx == width && self.screenHeightPx == height {
            return false
        }
        self.screenWidthPx = width
        self.screenHeightPx = height
        recalculate()
        checkAndNotifyMarginDivergence()
        return true
    }
}
