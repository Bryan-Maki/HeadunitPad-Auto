//
//  ScreenOrientationPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ScreenOrientationPolicy.kt
//

import Foundation

public enum ScreenOrientationPolicy {
    public enum Normalisation: Int, Equatable {
        case landscape
        case portrait
        case asRead
    }

    public static func normalisation(
        isLandscapeRequested: Bool,
        isPortraitRequested: Bool,
        currentDeviceLandscape: Bool
    ) -> Normalisation {
        if isLandscapeRequested {
            return .landscape
        } else if isPortraitRequested {
            return .portrait
        } else {
            return currentDeviceLandscape ? .landscape : .portrait
        }
    }

    public static func normalise(w: Int, h: Int, normalisation: Normalisation) -> ProjectionCanvasPolicy.Rect {
        switch normalisation {
        case .landscape:
            return ProjectionCanvasPolicy.Rect(width: max(w, h), height: min(w, h))
        case .portrait:
            return ProjectionCanvasPolicy.Rect(width: min(w, h), height: max(w, h))
        case .asRead:
            return ProjectionCanvasPolicy.Rect(width: w, height: h)
        }
    }
}
