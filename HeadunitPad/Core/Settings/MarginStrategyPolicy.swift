//
//  MarginStrategyPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit MarginStrategyPolicy.kt
//

import Foundation

public enum MarginStrategyPolicy {
    public enum Strategy: Equatable {
        case par
        case margin
    }

    public static func select(
        mode: VideoFitMode,
        panelW: Int,
        panelH: Int,
        videoW: Int,
        videoH: Int
    ) -> Strategy {
        if mode != .fill { return .margin }
        if panelW <= 0 || panelH <= 0 || videoW <= 0 || videoH <= 0 { return .margin }
        let derived = Int(((Float(panelW) * Float(videoH)) / (Float(panelH) * Float(videoW)) * 10000.0).rounded())
        if derived <= ProjectionGeometryPolicy.squarePixelsE4 { return .margin }
        if derived > ProjectionGeometryPolicy.maxPixelAspectE4 { return .margin }
        return .par
    }
}
