//
//  DeviceMemoryProfile.swift
//  HeadunitPad
//
//  1:1 port of open-headunit DeviceMemoryProfile.kt.
//  Determines device memory tier for allocating video queue buffers.
//

import Foundation

public enum DeviceMemoryProfile: String, CaseIterable, Codable {
    case constrained
    case normal
    case ample

    public static let constrainedTotalRamMb: Int64 = 1536
    public static let ampleTotalRamMb: Int64 = 3584

    public static func classify(totalRamMb: Int64) -> DeviceMemoryProfile {
        if totalRamMb <= 0 {
            return .normal
        }
        if totalRamMb <= constrainedTotalRamMb {
            return .constrained
        }
        if totalRamMb >= ampleTotalRamMb {
            return .ample
        }
        return .normal
    }

    public static var current: DeviceMemoryProfile {
        let physicalBytes = ProcessInfo.processInfo.physicalMemory
        let physicalMb = Int64(physicalBytes / (1024 * 1024))
        return classify(totalRamMb: physicalMb)
    }
}
