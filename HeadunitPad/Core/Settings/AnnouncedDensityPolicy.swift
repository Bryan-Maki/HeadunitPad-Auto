//
//  AnnouncedDensityPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit AnnouncedDensityPolicy.kt
//

import Foundation

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
            return Decision(announced: fallbackDpi, requested: 0, reason: .automatic)
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
