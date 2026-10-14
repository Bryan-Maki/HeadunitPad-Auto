//
//  NegotiatedResolutionPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit NegotiatedResolutionPolicy.kt
//

import Foundation

public enum ResolutionPreset: Int, CaseIterable {
    case auto = 0
    case r800x480 = 1
    case r1280x720 = 2
    case r1920x1080 = 3
    case r2560x1440 = 4
    case r3840x2160 = 5

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .r800x480: return "480p (800x480)"
        case .r1280x720: return "720p (1280x720)"
        case .r1920x1080: return "1080p (1920x1080)"
        case .r2560x1440: return "1440p (2560x1440)"
        case .r3840x2160: return "4K (3840x2160)"
        }
    }

    public var width: Int {
        switch self {
        case .auto: return 1280
        case .r800x480: return 800
        case .r1280x720: return 1280
        case .r1920x1080: return 1920
        case .r2560x1440: return 2560
        case .r3840x2160: return 3840
        }
    }

    public var height: Int {
        switch self {
        case .auto: return 720
        case .r800x480: return 480
        case .r1280x720: return 720
        case .r1920x1080: return 1080
        case .r2560x1440: return 1440
        case .r3840x2160: return 2160
        }
    }

    public var protoType: ControlService.MediaSinkService.VideoConfiguration.VideoCodecResolutionType {
        switch self {
        case .auto: return ._1280x720
        case .r800x480: return ._800x480
        case .r1280x720: return ._1280x720
        case .r1920x1080: return ._1920x1080
        case .r2560x1440: return ._2560x1440
        case .r3840x2160: return ._3840x2160
        }
    }

    public func title(for orientation: ProjectionOrientation) -> String {
        return title
    }

    public var codecResolutionValue: Int {
        switch self {
        case .auto, .r1280x720: return 2
        case .r800x480: return 1
        case .r1920x1080: return 3
        case .r2560x1440: return 4
        case .r3840x2160: return 5
        }
    }

    public var dimensions: (width: Int, height: Int) {
        return (width: self.width, height: self.height)
    }
}

public enum NegotiatedResolutionPolicy {
    public static func autoLadder(
        panelW: Int,
        panelH: Int,
        fitMode: VideoFitMode,
        hevcSupported: Bool = true,
        canHevcHighRes: Bool = true
    ) -> ResolutionPreset {
        let longSide = max(panelW, panelH)
        let shortSide = min(panelW, panelH)
        let wide = (fitMode == .fill || fitMode == .fillMargin) ? 0 : longSide

        if longSide <= 800 && shortSide <= 480 {
            return .r800x480
        } else if (shortSide >= 2160 || wide >= 3840) && hevcSupported {
            return .r3840x2160
        } else if (shortSide >= 1440 || wide >= 2560) && canHevcHighRes {
            return .r2560x1440
        } else if shortSide > 720 || wide > 1280 {
            return .r1920x1080
        } else {
            return .r1280x720
        }
    }

    public static func select(
        isLocked: Bool,
        selected: ResolutionPreset?,
        panelW: Int,
        panelH: Int,
        fitMode: VideoFitMode,
        hevcSupported: Bool = true,
        canHevcHighRes: Bool = true
    ) -> ResolutionPreset? {
        if isLocked { return nil }
        if selected == nil || selected == .auto {
            return autoLadder(
                panelW: panelW,
                panelH: panelH,
                fitMode: fitMode,
                hevcSupported: hevcSupported,
                canHevcHighRes: canHevcHighRes
            )
        }
        return selected
    }
}
