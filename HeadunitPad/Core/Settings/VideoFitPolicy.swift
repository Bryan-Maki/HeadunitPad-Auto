//
//  VideoFitPolicy.swift
//  HeadunitPad
//
//  Video fit mode policy for projection rendering.
//

import Foundation

public enum VideoFitMode: Int, CaseIterable {
    /// Keep 16:9 ratio with letterbox/pillarbox
    case contain = 0
    /// Fill using PAR pixel ratio compensation
    case fill = 1
    /// Uniform zoom to cover panel, cropping excess
    case cover = 2
    /// Protocol-level margin announcement and cropping to fill iPad 4:3 screens with 0 black bars
    case fillMargin = 3
    /// Non-uniform stretch to touch all edges
    case stretch = 4

    public var title: String {
        switch self {
        case .contain:
            return "Fit (Letterbox)"
        case .fill:
            return "Fill (PAR)"
        case .cover:
            return "Cover (Crop)"
        case .fillMargin:
            return "Fill Margin (iPad Fullscreen)"
        case .stretch:
            return "Stretch"
        }
    }
}

public enum VideoFitPolicy {
    public static func resolve(storedFitMode: Int?) -> VideoFitMode {
        guard let raw = storedFitMode, let mode = VideoFitMode(rawValue: raw) else {
            return .fillMargin
        }
        return mode
    }
}
