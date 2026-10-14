//
//  PerformanceOverlayPolicy.swift
//  HeadunitPad
//
//  1:1 port of open-headunit PerformanceOverlayPolicy.kt
//  Controls overlay fields, bitmasks, and real-time performance string formatting.
//

import Foundation

public enum PerformanceOverlayField: Int, CaseIterable {
    case fps = 1
    case cpu = 2
    case temp = 4
    case frame = 8
    case bitrate = 16

    public var title: String {
        switch self {
        case .fps: return "FPS"
        case .cpu: return "CPU Usage"
        case .temp: return "Thermal State"
        case .frame: return "Frame Latency"
        case .bitrate: return "Bitrate"
        }
    }
}

public enum PerformanceOverlayPolicy {

    public static let defaultBits: Int = 0b11111

    public static func toBits(_ fields: Set<PerformanceOverlayField>) -> Int {
        return fields.reduce(0) { $0 | $1.rawValue }
    }

    public static func fromBits(_ bits: Int) -> Set<PerformanceOverlayField> {
        return Set(PerformanceOverlayField.allCases.filter { (bits & $0.rawValue) != 0 })
    }

    public static func format(
        fields: Set<PerformanceOverlayField>,
        fps: Int?,
        appCpu: Double?,
        totalCpu: Double?,
        thermalState: String?,
        frameLatencyMs: Double?,
        bitrateKbps: Double?
    ) -> String {
        var lines: [String] = []

        for field in PerformanceOverlayField.allCases where fields.contains(field) {
            switch field {
            case .fps:
                let val = fps.map { "\($0)" } ?? "--"
                lines.append("FPS: \(val)")

            case .cpu:
                let appStr = appCpu.map { String(format: "%.1f%%", $0) } ?? "--"
                let sysStr = totalCpu.map { String(format: "%.1f%%", $0) } ?? "--"
                lines.append("CPU: app \(appStr) / sys \(sysStr)")

            case .temp:
                let state = thermalState ?? "Nominal"
                lines.append("Thermal: \(state)")

            case .frame:
                let val = frameLatencyMs.map { String(format: "%.1f ms", $0) } ?? "--"
                lines.append("Latency: \(val)")

            case .bitrate:
                if let kbps = bitrateKbps {
                    if kbps >= 1000.0 {
                        lines.append(String(format: "Bitrate: %.2f Mbps", kbps / 1000.0))
                    } else {
                        lines.append(String(format: "Bitrate: %.0f kbps", kbps))
                    }
                } else {
                    lines.append("Bitrate: --")
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}
