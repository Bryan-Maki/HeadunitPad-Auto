//
//  ProjectionGeometryPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ProjectionGeometryPolicy.kt
//

import Foundation

public enum ProjectionGeometryPolicy {
    public struct Fit: Equatable {
        public let scaleFactor: Float
        public let isSmallScreen: Bool
        public let isPortraitScaled: Bool?

        public init(scaleFactor: Float, isSmallScreen: Bool, isPortraitScaled: Bool?) {
            self.scaleFactor = scaleFactor
            self.isSmallScreen = isSmallScreen
            self.isPortraitScaled = isPortraitScaled
        }
    }

    public static func divideOrOne(_ numerator: Float, _ denominator: Float) -> Float {
        return denominator == 0.0 ? 1.0 : (numerator / denominator)
    }

    public static func isSmallScreen(panelW: Int, panelH: Int) -> Bool {
        if panelH > panelW {
            return panelW <= 1080 && panelH <= 1920
        } else {
            return panelW <= 1920 && panelH <= 1080
        }
    }

    public static func fit(panelW: Int, panelH: Int, videoW: Int, videoH: Int) -> Fit {
        let small = isSmallScreen(panelW: panelW, panelH: panelH)
        if small || videoW <= 0 || videoH <= 0 {
            return Fit(scaleFactor: 1.0, isSmallScreen: small, isPortraitScaled: nil)
        }
        let sW = Float(panelW)
        let sH = Float(panelH)
        let aspect = Float(videoW) / Float(videoH)
        if (sW / sH) < aspect {
            return Fit(scaleFactor: sH / Float(videoH), isSmallScreen: small, isPortraitScaled: true)
        } else {
            return Fit(scaleFactor: sW / Float(videoW), isSmallScreen: small, isPortraitScaled: false)
        }
    }

    public static func adjustedWidth(videoW: Int, scaleFactor: Float) -> Int {
        return Int((Float(videoW) * scaleFactor).rounded())
    }

    public static func adjustedHeight(videoH: Int, scaleFactor: Float) -> Int {
        return Int((Float(videoH) * scaleFactor).rounded())
    }

    public static func widthMargin(videoW: Int, panelW: Int, scaleFactor: Float) -> Int {
        if scaleFactor == 0.0 { return 0 }
        let diff = Float(adjustedWidth(videoW: videoW, scaleFactor: scaleFactor) - panelW)
        return max(0, Int((diff / scaleFactor).rounded()))
    }

    public static func heightMargin(videoH: Int, panelH: Int, scaleFactor: Float) -> Int {
        if scaleFactor == 0.0 { return 0 }
        let diff = Float(adjustedHeight(videoH: videoH, scaleFactor: scaleFactor) - panelH)
        return max(0, Int((diff / scaleFactor).rounded()))
    }

    /// The largest uniform scale that fits the canvas entirely inside the panel: letterbox
    public static func containScaleFactor(panelW: Int, panelH: Int, videoW: Int, videoH: Int) -> Float {
        return min(
            divideOrOne(Float(panelW), Float(videoW)),
            divideOrOne(Float(panelH), Float(videoH))
        )
    }

    /// The smallest uniform scale that still covers the panel, cropping overshoot
    public static func coverScaleFactor(panelW: Int, panelH: Int, videoW: Int, videoH: Int) -> Float {
        return max(
            1.0,
            max(
                divideOrOne(Float(panelW), Float(videoW)),
                divideOrOne(Float(panelH), Float(videoH))
            )
        )
    }

    public static func coverWidth(panelW: Int, panelH: Int, videoW: Int, videoH: Int) -> Int {
        return Int((Float(videoW) * coverScaleFactor(panelW: panelW, panelH: panelH, videoW: videoW, videoH: videoH)).rounded())
    }

    public static func coverHeight(panelW: Int, panelH: Int, videoW: Int, videoH: Int) -> Int {
        return Int((Float(videoH) * coverScaleFactor(panelW: panelW, panelH: panelH, videoW: videoW, videoH: videoH)).rounded())
    }

    public static func uiWidth(videoW: Int, marginW: Int) -> Int {
        return videoW - marginW
    }

    public static func uiHeight(videoH: Int, marginH: Int) -> Int {
        return videoH - marginH
    }

    private static func fitFactor(mode: VideoFitMode, panelW: Int, panelH: Int, uiW: Int, uiH: Int) -> Float {
        switch mode {
        case .cover:
            return coverScaleFactor(panelW: panelW, panelH: panelH, videoW: uiW, videoH: uiH)
        default:
            return containScaleFactor(panelW: panelW, panelH: panelH, videoW: uiW, videoH: uiH)
        }
    }

    public static func scaleX(
        mode: VideoFitMode,
        forcedScale: Bool,
        panelW: Int,
        panelH: Int,
        videoW: Int,
        videoH: Int,
        marginW: Int,
        marginH: Int
    ) -> Float {
        if forcedScale { return 1.0 }
        let uiW = uiWidth(videoW: videoW, marginW: marginW)
        if mode == .fill || mode == .fillMargin {
            return divideOrOne(Float(videoW), Float(uiW))
        }
        if mode == .stretch {
            return divideOrOne(Float(panelW), Float(videoW))
        }
        let uiH = uiHeight(videoH: videoH, marginH: marginH)
        return fitFactor(mode: mode, panelW: panelW, panelH: panelH, uiW: uiW, uiH: uiH) * divideOrOne(Float(videoW), Float(panelW))
    }

    public static func scaleY(
        mode: VideoFitMode,
        forcedScale: Bool,
        panelW: Int,
        panelH: Int,
        videoW: Int,
        videoH: Int,
        marginW: Int,
        marginH: Int
    ) -> Float {
        if forcedScale { return 1.0 }
        let uiH = uiHeight(videoH: videoH, marginH: marginH)
        if mode == .fill || mode == .fillMargin {
            return divideOrOne(Float(videoH), Float(uiH))
        }
        if mode == .stretch {
            return divideOrOne(Float(panelH), Float(videoH))
        }
        let uiW = uiWidth(videoW: videoW, marginW: marginW)
        return fitFactor(mode: mode, panelW: panelW, panelH: panelH, uiW: uiW, uiH: uiH) * divideOrOne(Float(videoH), Float(panelH))
    }

    public static let squarePixelsE4: Int = 10000
    public static let minPixelAspectE4: Int = 5000
    public static let maxPixelAspectE4: Int = 20000

    public static func pixelAspectRatioE4(
        mode: VideoFitMode,
        panelW: Int,
        panelH: Int,
        videoW: Int,
        videoH: Int,
        marginW: Int,
        marginH: Int
    ) -> Int {
        if mode != .fill && mode != .fillMargin { return squarePixelsE4 }
        let canvasW = uiWidth(videoW: videoW, marginW: marginW)
        let canvasH = uiHeight(videoH: videoH, marginH: marginH)
        if panelW <= 0 || panelH <= 0 || canvasW <= 0 || canvasH <= 0 { return squarePixelsE4 }

        let derived = Int(((Float(panelW) * Float(canvasH)) / (Float(panelH) * Float(canvasW)) * 10000.0).rounded())
        if derived < minPixelAspectE4 || derived > maxPixelAspectE4 { return squarePixelsE4 }
        let deviation = abs(Float(derived - squarePixelsE4)) / Float(squarePixelsE4)
        return deviation > 0.03 ? derived : squarePixelsE4
    }
}
