//
//  LogExporter.swift
//  HeadunitPad
//
//  1:1 port of open-headunit LogExporter.kt
//  Collects system info, configuration, audio diagnostics, and logs for export.
//

import UIKit

public enum LogExporter {
    public static func sessionBanner() -> String {
        let screen = UIScreen.main
        let bounds = screen.bounds
        let scale = screen.nativeScale
        let w = Int((bounds.width * scale).rounded())
        let h = Int((bounds.height * scale).rounded())

        var lines: [String] = []
        lines.append("=== HEADUNITPAD-AUTO DIAGNOSTICS REPORT ===")
        lines.append("Generated At: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Device: \(UIDevice.current.model) (\(UIDevice.current.systemName) \(UIDevice.current.systemVersion))")
        lines.append("Display: \(w)x\(h) pt=(\(Int(bounds.width))x\(Int(bounds.height))) scale=\(scale)")
        lines.append("Connection State: \(ConnectionManager.shared.state.description)")
        lines.append("Configured Resolution: \(ProjectionSettings.resolution.title)")
        lines.append("Negotiated Resolution: \(HeadUnitScreenConfig.shared.negotiatedWidth)x\(HeadUnitScreenConfig.shared.negotiatedHeight)")
        lines.append("Announced Margins: W=\(HeadUnitScreenConfig.shared.widthMargin) H=\(HeadUnitScreenConfig.shared.heightMargin)")
        lines.append("Configured DPI: \(ProjectionSettings.dpi)")
        lines.append("FPS Limit: \(ProjectionSettings.fpsLimit.title)")
        lines.append("Video Fit Mode: \(ProjectionSettings.fitMode.title)")
        lines.append("Orientation: \(ProjectionSettings.orientation.title)")
        lines.append("Night Mode: \(ProjectionSettings.nightMode.title)")
        lines.append("Performance HUD: \(ProjectionSettings.showPerformanceOverlay ? "On" : "Off")")
        lines.append("Video Codec: \(ProjectionSettings.videoCodecPreference.title)")
        lines.append("Audio Codec: \(ProjectionSettings.audioCodecPreference.title)")
        lines.append("Audio Target: \(ProjectionSettings.audioOutputTarget.title)")
        lines.append("Auto Reconnect: \(ProjectionSettings.autoReconnect)")
        lines.append("===========================================")
        return lines.joined(separator: "\n")
    }

    public static func generateFullReport() -> String {
        var report = sessionBanner()
        report.append("\n\n--- AUDIO DIAGNOSTICS (Latest 64 Events) ---\n")
        let audioEvents = AudioDiagnostics.shared.snapshot()
        if audioEvents.isEmpty {
            report.append("No audio diagnostic events recorded.\n")
        } else {
            report.append(audioEvents.joined(separator: "\n") + "\n")
        }

        report.append("\n--- APPLICATION LOGS ---\n")
        let logs = AppLog.shared.allLogText()
        if logs.isEmpty {
            report.append("No application logs recorded.\n")
        } else {
            report.append(logs + "\n")
        }

        return report
    }

    public static func exportToTemporaryFile() -> URL? {
        let report = generateFullReport()
        guard let data = report.data(using: .utf8) else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
        let filename = "HeadunitPad-Diagnostics-\(Int(Date().timeIntervalSince1970)).txt"
        let fileURL = tempDir.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("LogExporter: Failed to write temp report: \(error)")
            return nil
        }
    }

    public static func exportToClipboardText(maxBytes: Int = 250 * 1024) -> String {
        let full = generateFullReport()
        guard full.utf8.count > maxBytes else { return full }

        let notice = "\n\n... [Log truncated to 250KB for clipboard] ...\n\n"
        let banner = sessionBanner() + notice
        let bannerBytes = banner.utf8.count

        if bannerBytes >= maxBytes {
            let utf8 = full.utf8
            let prefixIndex = utf8.index(utf8.startIndex, offsetBy: maxBytes, limitedBy: utf8.endIndex) ?? utf8.endIndex
            return String(utf8[..<prefixIndex]) ?? ""
        }

        let remainingBytes = max(0, maxBytes - bannerBytes)
        let utf8 = full.utf8
        let startIndex = utf8.index(utf8.endIndex, offsetBy: -remainingBytes, limitedBy: utf8.startIndex) ?? utf8.startIndex
        let trailingLogs = String(utf8[startIndex...]) ?? ""
        return banner + trailingLogs
    }
}
