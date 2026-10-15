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

    public var customDpi: Int?

    public var announcedWidthMargin: Int = MarginAnnouncementPolicy.notAnnounced
    public var announcedHeightMargin: Int = MarginAnnouncementPolicy.notAnnounced
    public var announcedCanvasW: Int = 0
    public var announcedCanvasH: Int = 0

    public var onMarginsDiverged: (() -> Bool)?

    public init() {
        self.videoFitMode = ProjectionSettings.videoFitMode
        if !ProjectionSettings.isAutoDpi && ProjectionSettings.dpi > 0 {
            self.customDpi = ProjectionSettings.dpi
        }
    }

    public enum IPadModelFamily: String, CaseIterable {
        case ipadMini              // iPad mini 6 / 7 (8.3")
        case ipadStandard102       // iPad 8 / 9 (10.2")
        case ipadAirAndStandard109 // iPad 10 / 11 & Air 4 / 5 / M2 (10.9" / 11")
        case ipadPro11             // iPad Pro 11" (Gen 2-4 & M4)
        case ipadPro129AndAir13    // iPad Pro 12.9" & Air 13"
        case ipadPro13M4           // iPad Pro 13" M4 OLED
        case genericIpad           // Fallback

        public var displayName: String {
            switch self {
            case .ipadMini: return "iPad mini (8.3\")"
            case .ipadStandard102: return "iPad (10.2\")"
            case .ipadAirAndStandard109: return "iPad / iPad Air (10.9\"-11\")"
            case .ipadPro11: return "iPad Pro 11\""
            case .ipadPro129AndAir13: return "iPad Pro 12.9\" / iPad Air 13\""
            case .ipadPro13M4: return "iPad Pro 13\" (M4 OLED)"
            case .genericIpad: return "iPad (Generic)"
            }
        }
    }

    public static func detectModelFamily(panelW: Int, panelH: Int) -> IPadModelFamily {
        let longW = max(panelW, panelH)
        let shortH = min(panelW, panelH)

        if (longW == 2266 && shortH == 1488) || (longW == 1133 && shortH == 744) {
            return .ipadMini
        } else if (longW == 2160 && shortH == 1620) || (longW == 1080 && shortH == 810) {
            return .ipadStandard102
        } else if (longW == 2360 && shortH == 1640) || (longW == 1180 && shortH == 820) {
            return .ipadAirAndStandard109
        } else if (longW == 2388 && shortH == 1668) || (longW == 2420 && shortH == 1668) || (longW == 1194 && shortH == 834) || (longW == 1210 && shortH == 834) {
            return .ipadPro11
        } else if (longW == 2732 && shortH == 2048) || (longW == 1366 && shortH == 1024) {
            return .ipadPro129AndAir13
        } else if (longW == 2752 && shortH == 2064) || (longW == 1376 && shortH == 1032) {
            return .ipadPro13M4
        } else {
            return .genericIpad
        }
    }

    public var currentModelFamily: IPadModelFamily {
        return Self.detectModelFamily(panelW: screenWidthPx, panelH: screenHeightPx)
    }

    public static func currentIpadLandscapeDimensions() -> (width: Int, height: Int) {
        let screen = UIScreen.main
        let bounds = screen.bounds
        let scale = screen.nativeScale
        let landW = Int((max(bounds.width, bounds.height) * scale).rounded())
        let landH = Int((min(bounds.width, bounds.height) * scale).rounded())
        return (landW, landH)
    }

    public func initScreen(
        width: Int,
        height: Int,
        scale: Float = 2.0,
        fitMode: VideoFitMode = .fillMargin,
        requestedResolution: ResolutionPreset = .auto
    ) {
        self.videoFitMode = fitMode
        self.density = scale
        self.screenWidthPx = max(width, height)
        self.screenHeightPx = min(width, height)
        self.isInitialized = true

        recalculate(requestedResolution: requestedResolution)
    }

    public func recalculate(requestedResolution: ResolutionPreset? = nil) {
        guard screenWidthPx > 0 && screenHeightPx > 0 else { return }

        // 1. Determine negotiated resolution
        if !isResolutionLocked {
            let canHevc = (ProjectionSettings.videoCodecPreference != .h264)
            if let req = requestedResolution {
                let res = NegotiatedResolutionPolicy.select(
                    isLocked: isResolutionLocked,
                    selected: req,
                    panelW: screenWidthPx,
                    panelH: screenHeightPx,
                    fitMode: videoFitMode,
                    hevcSupported: true,
                    canHevcHighRes: canHevc
                ) ?? .r1280x720

                self.negotiatedResolutionType = res.protoType
            } else if negotiatedResolutionType == ._1280x720 {
                let res = NegotiatedResolutionPolicy.autoLadder(
                    panelW: screenWidthPx,
                    panelH: screenHeightPx,
                    fitMode: videoFitMode,
                    hevcSupported: true,
                    canHevcHighRes: canHevc
                )
                self.negotiatedResolutionType = res.protoType
            }
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

    private var customNegotiatedWidth: Int?
    private var customNegotiatedHeight: Int?

    public var negotiatedWidth: Int {
        get { customNegotiatedWidth ?? getNegotiatedWidth() }
        set {
            customNegotiatedWidth = newValue
            if let h = customNegotiatedHeight {
                updateNegotiatedResolutionType(w: newValue, h: h)
            }
        }
    }

    public var negotiatedHeight: Int {
        get { customNegotiatedHeight ?? getNegotiatedHeight() }
        set {
            customNegotiatedHeight = newValue
            if let w = customNegotiatedWidth {
                updateNegotiatedResolutionType(w: w, h: newValue)
            }
        }
    }

    public func setNegotiatedResolution(width: Int, height: Int) {
        customNegotiatedWidth = width
        customNegotiatedHeight = height
        updateNegotiatedResolutionType(w: width, h: height)
    }

    private func updateNegotiatedResolutionType(w: Int, h: Int) {
        let allRes: [ControlService.MediaSinkService.VideoConfiguration.VideoCodecResolutionType] = [
            ._800x480, ._1280x720, ._1920x1080, ._2560x1440, ._3840x2160,
            ._720x1280, ._1080x1920, ._1440x2560, ._2160x3840
        ]
        for res in allRes {
            let dims = resolutionDimensions(res)
            if dims.0 == w && dims.1 == h {
                negotiatedResolutionType = res
                break
            }
        }
    }

    private func resolutionDimensions(_ type: ControlService.MediaSinkService.VideoConfiguration.VideoCodecResolutionType) -> (Int, Int) {
        switch type {
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

    public func recalculateMargins() {
        recalculate(requestedResolution: ProjectionSettings.resolution)
    }

    public func getNegotiatedWidth() -> Int {
        return activeSize().width
    }

    public func getNegotiatedHeight() -> Int {
        return activeSize().height
    }

    public func activeSize() -> (width: Int, height: Int) {
        if let w = customNegotiatedWidth, let h = customNegotiatedHeight, w > 0 && h > 0 {
            return (w, h)
        }
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

    public func getMargins() -> (widthMargin: Int, heightMargin: Int) {
        guard screenWidthPx > 0 && screenHeightPx > 0 else { return (0, 0) }
        let (codecW, codecH) = activeSize()
        guard codecW > 0 && codecH > 0 else { return (0, 0) }

        if videoFitMode == .fillMargin {
            let screenAspect = Double(screenWidthPx) / Double(screenHeightPx)
            let codecAspect = Double(codecW) / Double(codecH)
            if screenAspect < codecAspect {
                let activeH = codecH
                let activeW = Int((Double(codecH) * screenAspect).rounded()) & ~1
                let widthMargin = max(0, codecW - activeW)
                return (widthMargin, 0)
            } else {
                let activeW = codecW
                let activeH = Int((Double(codecW) / screenAspect).rounded()) & ~1
                let heightMargin = max(0, codecH - activeH)
                return (0, heightMargin)
            }
        }
        if MarginStrategyPolicy.select(mode: videoFitMode, panelW: screenWidthPx, panelH: screenHeightPx, videoW: codecW, videoH: codecH) == .par {
            return (0, 0)
        }
        return (
            ProjectionGeometryPolicy.widthMargin(videoW: codecW, panelW: screenWidthPx, scaleFactor: scaleFactor),
            ProjectionGeometryPolicy.heightMargin(videoH: codecH, panelH: screenHeightPx, scaleFactor: scaleFactor)
        )
    }

    public func getWidthMargin() -> Int {
        return getMargins().widthMargin
    }

    public func getHeightMargin() -> Int {
        return getMargins().heightMargin
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

    public var codecWidthPx: Int { getNegotiatedWidth() }
    public var codecHeightPx: Int { getNegotiatedHeight() }
    public var widthMargin: Int { getWidthMargin() }
    public var heightMargin: Int { getHeightMargin() }
    public var activeWidthPx: Int { max(1, codecWidthPx - widthMargin) }
    public var activeHeightPx: Int { max(1, codecHeightPx - heightMargin) }

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

    public var announcedDensity: Int {
        if let custom = customDpi, custom > 0 {
            return min(max(custom, 100), 400)
        }
        if !ProjectionSettings.isAutoDpi && ProjectionSettings.dpi > 0 {
            return min(max(ProjectionSettings.dpi, 100), 400)
        }
        let visibleW = max(1, getNegotiatedWidth() - getWidthMargin())
        let visibleH = max(1, getNegotiatedHeight() - getHeightMargin())
        return AnnouncedDensityPolicy.recommendedDpi(activeW: visibleW, activeH: visibleH, panelW: screenWidthPx, panelH: screenHeightPx)
    }

    public func densityDecision(requestedDpi: Int = 160) -> AnnouncedDensityPolicy.Decision {
        if let custom = customDpi, custom > 0 {
            let clamped = min(max(custom, 100), 400)
            return AnnouncedDensityPolicy.Decision(announced: clamped, requested: clamped, reason: .asStored)
        }
        if !ProjectionSettings.isAutoDpi && ProjectionSettings.dpi > 0 {
            let clamped = min(max(ProjectionSettings.dpi, 100), 400)
            return AnnouncedDensityPolicy.Decision(announced: clamped, requested: clamped, reason: .asStored)
        }
        let visibleW = max(1, getNegotiatedWidth() - getWidthMargin())
        let visibleH = max(1, getNegotiatedHeight() - getHeightMargin())
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

    public var onMarginsDivergedDetailed: ((_ left: Int, _ top: Int, _ right: Int, _ bottom: Int) -> Void)?

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
            onMarginsDivergedDetailed?(left, top, right, bottom)
        }
    }

    public func updateDimensions(width: Int, height: Int) -> Bool {
        guard width > 0 && height > 0 else { return false }
        let landW = max(width, height)
        let landH = min(width, height)
        if self.screenWidthPx == landW && self.screenHeightPx == landH {
            return false
        }
        self.screenWidthPx = landW
        self.screenHeightPx = landH
        recalculate(requestedResolution: ProjectionSettings.resolution)
        checkAndNotifyMarginDivergence()
        return true
    }
}
