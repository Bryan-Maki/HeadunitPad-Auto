//
//  TouchCoordinateMapper.swift
//  HeadunitPad
//
//  Reverse maps UIKit touch coordinates to Android Auto coordinates,
//  accounting for margin cropping (margin/2), aspect ratio, and video fit modes.
//

import Foundation
import CoreGraphics

public struct TouchCoordinate: Equatable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct TouchCoordinateMapper: Sendable {
    public init() {}

    public func map(
        point: CGPoint,
        containerSize: CGSize,
        videoSize: CGSize,
        mode: VideoFitMode,
        marginW: CGFloat,
        marginH: CGFloat
    ) -> CGPoint {
        let coord = Self.map(
            rawX: Float(point.x),
            rawY: Float(point.y),
            inputSurfaceWidth: Float(containerSize.width),
            inputSurfaceHeight: Float(containerSize.height),
            negotiatedWidth: Int(videoSize.width),
            negotiatedHeight: Int(videoSize.height),
            marginWidth: Float(marginW),
            marginHeight: Float(marginH),
            fitMode: mode
        )
        return CGPoint(x: coord.x, y: coord.y)
    }

    public static func map(
        rawX: Float,
        rawY: Float,
        inputSurfaceWidth: Float,
        inputSurfaceHeight: Float,
        negotiatedWidth: Int,
        negotiatedHeight: Int,
        marginWidth: Float,
        marginHeight: Float,
        fitMode: VideoFitMode,
        hudMirroring: Bool = false
    ) -> TouchCoordinate {
        let surfaceW = max(inputSurfaceWidth, 1.0)
        let surfaceH = max(inputSurfaceHeight, 1.0)
        let px = hudMirroring ? (surfaceW - rawX) : rawX

        let uiW = max(1.0, Float(negotiatedWidth) - marginWidth)
        let uiH = max(1.0, Float(negotiatedHeight) - marginHeight)

        let videoX: Float
        let videoY: Float

        switch fitMode {
        case .stretch:
            videoX = (px / surfaceW) * uiW
            videoY = (rawY / surfaceH) * uiH

        case .fill, .fillMargin:
            let isMismatched = (surfaceW > surfaceH) != (uiW > uiH)
            if isMismatched {
                let videoAspect = uiW / uiH
                let surfaceAspect = surfaceW / surfaceH

                let activeW: Float
                let activeH: Float
                let offsetX: Float
                let offsetY: Float

                if videoAspect > surfaceAspect {
                    activeW = surfaceW
                    activeH = surfaceW / videoAspect
                    offsetX = 0
                    offsetY = (surfaceH - activeH) / 2.0
                } else {
                    activeH = surfaceH
                    activeW = surfaceH * videoAspect
                    offsetX = (surfaceW - activeW) / 2.0
                    offsetY = 0
                }

                if activeW > 0 && activeH > 0 {
                    videoX = ((px - offsetX) / activeW) * uiW
                    videoY = ((rawY - offsetY) / activeH) * uiH
                } else {
                    videoX = (px / surfaceW) * uiW
                    videoY = (rawY / surfaceH) * uiH
                }
            } else {
                videoX = (px / surfaceW) * uiW
                videoY = (rawY / surfaceH) * uiH
            }

        case .contain:
            let uiRatio = uiW / uiH
            let viewRatio = surfaceW / surfaceH

            let displayedUiW: Float
            let displayedUiH: Float

            if viewRatio > uiRatio {
                displayedUiW = surfaceH * uiRatio
                displayedUiH = surfaceH
            } else {
                displayedUiW = surfaceW
                displayedUiH = surfaceW / uiRatio
            }

            let uiLeft = (surfaceW - displayedUiW) / 2.0
            let uiTop = (surfaceH - displayedUiH) / 2.0

            let localX = px - uiLeft
            let localY = rawY - uiTop

            videoX = (localX / displayedUiW) * uiW
            videoY = (localY / displayedUiH) * uiH

        case .cover:
            let uiRatio = uiW / uiH
            let viewRatio = surfaceW / surfaceH

            let displayedUiW: Float
            let displayedUiH: Float

            if viewRatio > uiRatio {
                displayedUiW = surfaceW
                displayedUiH = surfaceW / uiRatio
            } else {
                displayedUiW = surfaceH * uiRatio
                displayedUiH = surfaceH
            }

            let uiLeft = (surfaceW - displayedUiW) / 2.0
            let uiTop = (surfaceH - displayedUiH) / 2.0

            let localX = px - uiLeft
            let localY = rawY - uiTop

            videoX = (localX / displayedUiW) * uiW
            videoY = (localY / displayedUiH) * uiH
        }

        let maxUiX = max(0, negotiatedWidth - Int(marginWidth))
        let maxUiY = max(0, negotiatedHeight - Int(marginHeight))

        let clampedX = min(max(Int(videoX.rounded()), 0), maxUiX)
        let clampedY = min(max(Int(videoY.rounded()), 0), maxUiY)

        return TouchCoordinate(x: clampedX, y: clampedY)
    }
}
