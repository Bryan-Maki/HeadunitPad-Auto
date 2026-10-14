//
//  ProjectionCanvasPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit ProjectionCanvasPolicy.kt
//

import Foundation

public enum ProjectionCanvasPolicy {
    public enum Source: Equatable {
        case surface
        case window
        case cache
        case display
    }

    public struct Measurement: Equatable {
        public let width: Int
        public let height: Int
        public let hash: Int

        public init(width: Int, height: Int, hash: Int) {
            self.width = width
            self.height = height
            self.hash = hash
        }
    }

    public struct Choice: Equatable {
        public let width: Int
        public let height: Int
        public let source: Source

        public init(width: Int, height: Int, source: Source) {
            self.width = width
            self.height = height
            self.source = source
        }
    }

    public struct Rect: Equatable {
        public let width: Int
        public let height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }
    }

    public static let panelSlack: Float = 1.25

    public static func anchor(canvasW: Int, canvasH: Int, insetW: Int, insetH: Int) -> Rect {
        return Rect(width: canvasW + insetW, height: canvasH + insetH)
    }

    public static func canvas(anchorW: Int, anchorH: Int, insetW: Int, insetH: Int) -> Rect {
        let w = anchorW - insetW
        let h = anchorH - insetH
        if w <= 0 || h <= 0 {
            return Rect(width: anchorW, height: anchorH)
        }
        return Rect(width: w, height: h)
    }

    public static func fitsPanel(canvasW: Int, canvasH: Int, panelW: Int, panelH: Int) -> Bool {
        if panelW <= 0 || panelH <= 0 { return true }
        return Float(canvasW) <= Float(panelW) * panelSlack && Float(canvasH) <= Float(panelH) * panelSlack
    }

    private static func isUsable(_ m: Measurement?, hash: Int) -> Bool {
        guard let m = m else { return false }
        return m.width > 0 && m.height > 0 && m.hash == hash
    }

    public static func choose(
        immersive: Bool,
        realW: Int,
        realH: Int,
        usableW: Int,
        usableH: Int,
        surface: Measurement?,
        window: Measurement?,
        cached: Measurement?,
        hash: Int
    ) -> Choice {
        if isUsable(surface, hash: hash), let surface = surface {
            return Choice(width: surface.width, height: surface.height, source: .surface)
        }
        if isUsable(window, hash: hash), let window = window {
            return Choice(width: window.width, height: window.height, source: .window)
        }
        if isUsable(cached, hash: hash), let cached = cached {
            return Choice(width: cached.width, height: cached.height, source: .cache)
        }
        if immersive {
            return Choice(width: realW, height: realH, source: .display)
        }
        return Choice(width: usableW, height: usableH, source: .display)
    }
}
