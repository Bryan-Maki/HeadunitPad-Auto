//
//  PerformanceOverlayPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit PerformanceOverlayPolicy.kt
//  Models and formats real-time performance metrics for HUD display.
//

import Foundation

public struct PerformanceSnapshot: Equatable {
    public let fps: Int
    public let rxMbps: Double
    public let decodeMedianMs: Double
    public let decodeP95Ms: Double
    public let audioBufferMs: Int
    public let keyframeRepairs: Int
    public let droppedFrames: Int
    public let resolutionText: String

    public init(
        fps: Int,
        rxMbps: Double,
        decodeMedianMs: Double,
        decodeP95Ms: Double,
        audioBufferMs: Int,
        keyframeRepairs: Int,
        droppedFrames: Int,
        resolutionText: String
    ) {
        self.fps = fps
        self.rxMbps = rxMbps
        self.decodeMedianMs = decodeMedianMs
        self.decodeP95Ms = decodeP95Ms
        self.audioBufferMs = audioBufferMs
        self.keyframeRepairs = keyframeRepairs
        self.droppedFrames = droppedFrames
        self.resolutionText = resolutionText
    }
}

public enum PerformanceOverlayPolicy {
    public static func formatHudText(_ s: PerformanceSnapshot) -> String {
        let line1 = "RES \(s.resolutionText) | \(s.fps) FPS | RX \(String(format: "%.1f", s.rxMbps)) Mbps | DEC \(String(format: "%.1f", s.decodeMedianMs))ms (p95 \(String(format: "%.1f", s.decodeP95Ms))ms)"
        let line2 = "AUD \(s.audioBufferMs)ms | PLI \(s.keyframeRepairs) | DROP \(s.droppedFrames)"
        return "\(line1)\n\(line2)"
    }
}
