//
//  AnnouncedDensityPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AnnouncedDensityPolicy.kt
//

import Foundation
import UIKit

public enum AnnouncedDensityPolicy {
    public static let huigMinWidthDp = 748
    public static let huigMinHeightDp = 450
    public static let widescreenMinWidthDp = 1240
    public static let fallbackDpi = 160

    public enum Reason: Equatable {
        case asStored
        case automatic
        case widthFloor
        case heightFloor
        case portrait
    }

    public struct Decision: Equatable {
        public let announced: Int
        public let requested: Int
        public let reason: Reason

        public init(announced: Int, requested: Int, reason: Reason) {
            self.announced = announced
            self.requested = requested
            self.reason = reason
        }
    }

    /// Recommends comfortable DPI for Android Auto based on iPad physical dimensions and active resolution.
    /// In 1080p: ~160-180 DPI
    /// In 1440p: ~210-240 DPI
    /// In 720p: ~120-140 DPI
    public static func recommendedDpi(
        screenBounds: CGRect = UIScreen.main.bounds,
        activeW: Int,
        activeH: Int,
        panelW: Int? = nil,
        panelH: Int? = nil
    ) -> Int {
        guard activeW > 0, activeH > 0 else { return fallbackDpi }

        let pw = panelW ?? Int((max(screenBounds.width, screenBounds.height) * UIScreen.main.nativeScale).rounded())
        let ph = panelH ?? Int((min(screenBounds.width, screenBounds.height) * UIScreen.main.nativeScale).rounded())
        let family = HeadUnitScreenConfig.detectModelFamily(panelW: pw, panelH: ph)

        let baseDpi: Int
        if activeH >= 1400 {
            // ~1440p / 2K+
            switch family {
            case .ipadMini: baseDpi = 210
            case .ipadStandard102: baseDpi = 220
            case .ipadAirAndStandard109, .ipadPro11: baseDpi = 240
            case .ipadPro129AndAir13, .ipadPro13M4: baseDpi = 240
            case .genericIpad:
                let longPt = max(screenBounds.width, screenBounds.height)
                let shortPt = min(screenBounds.width, screenBounds.height)
                let diagonalPt = sqrt(longPt * longPt + shortPt * shortPt)
                if diagonalPt <= 1360 { baseDpi = 210 }
                else if diagonalPt <= 1550 { baseDpi = 220 }
                else { baseDpi = 240 }
            }
        } else if activeH >= 1000 {
            // ~1080p
            switch family {
            case .ipadMini: baseDpi = 160
            case .ipadStandard102: baseDpi = 170
            case .ipadAirAndStandard109, .ipadPro11: baseDpi = 180
            case .ipadPro129AndAir13, .ipadPro13M4: baseDpi = 200
            case .genericIpad:
                let longPt = max(screenBounds.width, screenBounds.height)
                let shortPt = min(screenBounds.width, screenBounds.height)
                let diagonalPt = sqrt(longPt * longPt + shortPt * shortPt)
                if diagonalPt <= 1360 { baseDpi = 160 }
                else if diagonalPt <= 1550 { baseDpi = 180 }
                else { baseDpi = 200 }
            }
        } else {
            // ~720p / 480p
            switch family {
            case .ipadMini: baseDpi = 120
            case .ipadStandard102: baseDpi = 130
            case .ipadAirAndStandard109, .ipadPro11: baseDpi = 135
            case .ipadPro129AndAir13, .ipadPro13M4: baseDpi = 140
            case .genericIpad:
                let longPt = max(screenBounds.width, screenBounds.height)
                let shortPt = min(screenBounds.width, screenBounds.height)
                let diagonalPt = sqrt(longPt * longPt + shortPt * shortPt)
                if diagonalPt <= 1360 { baseDpi = 120 }
                else if diagonalPt <= 1550 { baseDpi = 130 }
                else { baseDpi = 140 }
            }
        }

        let maxAllowed = huigMaxDpi(w: activeW, h: activeH)
        return min(max(baseDpi, 100), min(maxAllowed, 320))
    }

    public static func huigMaxDpi(w: Int, h: Int) -> Int {
        if w <= 0 || h <= 0 { return fallbackDpi }
        return min(w * 160 / huigMinWidthDp, h * 160 / huigMinHeightDp)
    }

    public static func widescreenMaxDpi(codecWidth: Int) -> Int {
        if codecWidth <= 0 { return 0 }
        return codecWidth * 160 / widescreenMinWidthDp
    }

    public static func widescreenHintDpi(codecWidth: Int, codecHeight: Int) -> Int {
        if codecWidth <= 0 || codecHeight <= 0 || codecHeight > codecWidth {
            return 0
        }
        return widescreenMaxDpi(codecWidth: codecWidth)
    }

    public static func canvasDp(px: Int, dpi: Int) -> Int {
        if dpi <= 0 { return 0 }
        return px * 160 / dpi
    }

    public static func decide(stored: Int, visibleW: Int, visibleH: Int) -> Decision {
        if visibleW <= 0 || visibleH <= 0 {
            return Decision(announced: stored > 0 ? stored : fallbackDpi, requested: stored, reason: stored > 0 ? .asStored : .automatic)
        }
        if visibleH > visibleW {
            let dpi = stored > 0 ? stored : fallbackDpi
            return Decision(announced: dpi, requested: stored, reason: .portrait)
        }
        if stored <= 0 {
            let autoVal = recommendedDpi(activeW: visibleW, activeH: visibleH)
            return Decision(announced: autoVal, requested: 0, reason: .automatic)
        }
        let maxAllowed = huigMaxDpi(w: visibleW, h: visibleH)
        if stored <= maxAllowed {
            return Decision(announced: stored, requested: stored, reason: .asStored)
        }
        let heightBound = (visibleH * 160 / huigMinHeightDp) < (visibleW * 160 / huigMinWidthDp)
        return Decision(announced: maxAllowed, requested: stored, reason: heightBound ? .heightFloor : .widthFloor)
    }

    public static func fallbackDensity(primaryDensity: Int, primaryWidth: Int, fallbackWidth: Int) -> Int {
        if primaryWidth <= 0 { return primaryDensity }
        return Int((Float(primaryDensity) * Float(fallbackWidth) / Float(primaryWidth)).rounded())
    }

    public static func describe(decision: Decision, visibleW: Int, visibleH: Int) -> String {
        let requested = decision.requested > 0 ? "\(decision.requested)" : "automatic"
        let why: String
        switch decision.reason {
        case .asStored: why = "within the HUIG floor"
        case .automatic: why = "codec-based"
        case .widthFloor: why = "clamped to the \(huigMinWidthDp) dp width floor"
        case .heightFloor: why = "clamped to the \(huigMinHeightDp) dp height floor"
        case .portrait: why = "portrait, not clamped"
        }
        return "\(decision.announced) (dp canvas \(canvasDp(px: visibleW, dpi: decision.announced))x\(canvasDp(px: visibleH, dpi: decision.announced)), requested \(requested), \(why))"
    }
}
