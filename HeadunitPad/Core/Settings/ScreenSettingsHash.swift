//
//  ScreenSettingsHash.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ScreenSettingsHash.kt
//

import Foundation

public enum ScreenSettingsHash {
    public static func of(
        resolutionId: Int,
        dpiPixelDensity: Int,
        pixelAspectRatioE4: Int,
        insetLeft: Int,
        insetTop: Int,
        insetRight: Int,
        insetBottom: Int,
        videoFitMode: Int,
        normalisation: ScreenOrientationPolicy.Normalisation
    ) -> Int {
        var hash = 17
        hash = 31 &* hash &+ resolutionId
        hash = 31 &* hash &+ dpiPixelDensity
        hash = 31 &* hash &+ pixelAspectRatioE4
        hash = 31 &* hash &+ insetLeft
        hash = 31 &* hash &+ insetTop
        hash = 31 &* hash &+ insetRight
        hash = 31 &* hash &+ insetBottom
        hash = 31 &* hash &+ videoFitMode
        hash = 31 &* hash &+ normalisation.rawValue
        return hash
    }
}
