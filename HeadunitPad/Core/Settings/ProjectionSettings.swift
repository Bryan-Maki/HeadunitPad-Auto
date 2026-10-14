//
//  ProjectionSettings.swift
//  HeadunitPad
//
//  Complete projection settings with Resolution, FPS, DPI,
//  FitMode (Fit / FillMargin / Stretch), Driver Position, and Margins.
//

import Foundation
import UIKit
import Network

public enum ProjectionFpsLimit: Int, CaseIterable {
    case fps60 = 1
    case fps30 = 2

    public var title: String {
        switch self {
        case .fps60: return "60 FPS"
        case .fps30: return "30 FPS"
        }
    }
}

public enum ProjectionGpsSource: Int, CaseIterable {
    case phone = 0
    case ipad = 1

    public var title: String {
        switch self {
        case .phone: return "Phone GPS"
        case .ipad: return "iPad GPS"
        }
    }
}

public enum ProjectionOrientation: Int, CaseIterable {
    case landscape = 0
    case portrait = 1

    public var title: String {
        switch self {
        case .landscape: return "Landscape"
        case .portrait: return "Portrait"
        }
    }
}

public enum ProjectionConnectionMode: Int, CaseIterable {
    case auto = 0
    case wirelessHelper = 1
    case directHeadunit = 2

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .wirelessHelper: return "Wireless Helper"
        case .directHeadunit: return "Direct Headunit Server"
        }
    }
}

public enum ProjectionSettings {
    private static let defaults = UserDefaults.standard

    private static let resolutionKey = "projection-resolution-preset"
    private static let fpsLimitKey = "projection-fps-limit"
    private static let dpiKey = "projection-dpi"
    private static let fitModeKey = "projection-fit-mode"
    private static let rightHandDriveKey = "projection-right-hand-drive"
    private static let horizontalMarginKey = "projection-horizontal-margin"
    private static let verticalMarginKey = "projection-vertical-margin"
    private static let gpsSourceKey = "projection-gps-source"
    private static let orientationKey = "projection-orientation"
    private static let connectionModeKey = "projection-connection-mode"
    private static let autoReconnectKey = "projection-auto-reconnect"

    public static let defaultDpi = 160
    public static let minDpi = 100
    public static let maxDpi = 320

    private static var cachedCellularSupport: Bool?

    public static var resolution: ResolutionPreset {
        get {
            let val = defaults.integer(forKey: resolutionKey)
            return ResolutionPreset(rawValue: val) ?? .r1280x720
        }
        set {
            defaults.set(newValue.rawValue, forKey: resolutionKey)
            HeadUnitScreenConfig.shared.recalculate(requestedResolution: newValue)
        }
    }

    public static var fpsLimit: ProjectionFpsLimit {
        get {
            let val = defaults.integer(forKey: fpsLimitKey)
            return ProjectionFpsLimit(rawValue: val) ?? .fps60
        }
        set {
            defaults.set(newValue.rawValue, forKey: fpsLimitKey)
        }
    }

    public static var dpi: Int {
        get {
            let val = defaults.integer(forKey: dpiKey)
            if val == 0 { return defaultDpi }
            return min(max(val, minDpi), maxDpi)
        }
        set {
            let clamped = min(max(newValue, minDpi), maxDpi)
            defaults.set(clamped, forKey: dpiKey)
        }
    }

    public static var fitMode: VideoFitMode {
        get {
            if defaults.object(forKey: fitModeKey) == nil {
                return .fillMargin // Default to full screen on iPad 4:3!
            }
            let val = defaults.integer(forKey: fitModeKey)
            return VideoFitMode(rawValue: val) ?? .fillMargin
        }
        set {
            defaults.set(newValue.rawValue, forKey: fitModeKey)
            HeadUnitScreenConfig.shared.videoFitMode = newValue
            HeadUnitScreenConfig.shared.recalculate(requestedResolution: resolution)
        }
    }

    public static var rightHandDrive: Bool {
        get {
            return defaults.bool(forKey: rightHandDriveKey)
        }
        set {
            defaults.set(newValue, forKey: rightHandDriveKey)
        }
    }

    public static var horizontalMargin: Int {
        get {
            return defaults.integer(forKey: horizontalMarginKey)
        }
        set {
            defaults.set(newValue, forKey: horizontalMarginKey)
            HeadUnitScreenConfig.shared.recalculate(requestedResolution: resolution)
        }
    }

    public static var verticalMargin: Int {
        get {
            return defaults.integer(forKey: verticalMarginKey)
        }
        set {
            defaults.set(newValue, forKey: verticalMarginKey)
            HeadUnitScreenConfig.shared.recalculate(requestedResolution: resolution)
        }
    }

    public static var gpsSource: ProjectionGpsSource {
        get {
            let value = defaults.integer(forKey: gpsSourceKey)
            let source = ProjectionGpsSource(rawValue: value) ?? .phone
            if source == .ipad && !supportsCellularIpad() {
                return .phone
            }
            return source
        }
        set {
            let source = (newValue == .ipad && !supportsCellularIpad()) ? ProjectionGpsSource.phone : newValue
            defaults.set(source.rawValue, forKey: gpsSourceKey)
        }
    }

    public static var orientation: ProjectionOrientation {
        get {
            let value = defaults.integer(forKey: orientationKey)
            return ProjectionOrientation(rawValue: value) ?? .landscape
        }
        set {
            defaults.set(newValue.rawValue, forKey: orientationKey)
        }
    }

    public static var connectionMode: ProjectionConnectionMode {
        get {
            let value = defaults.integer(forKey: connectionModeKey)
            return ProjectionConnectionMode(rawValue: value) ?? .auto
        }
        set {
            defaults.set(newValue.rawValue, forKey: connectionModeKey)
        }
    }

    public static var autoReconnect: Bool {
        get {
            if defaults.object(forKey: autoReconnectKey) == nil {
                return true
            }
            return defaults.bool(forKey: autoReconnectKey)
        }
        set {
            defaults.set(newValue, forKey: autoReconnectKey)
        }
    }

    public static func supportsCellularIpad() -> Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
        if let cached = cachedCellularSupport {
            return cached
        }

#if targetEnvironment(simulator)
        cachedCellularSupport = false
        return false
#else
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.headunitpad.cellular-detect")
        let semaphore = DispatchSemaphore(value: 0)
        var hasCellularInterface = false

        monitor.pathUpdateHandler = { path in
            hasCellularInterface = path.availableInterfaces.contains { $0.type == .cellular }
            semaphore.signal()
        }

        monitor.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 0.35)
        monitor.cancel()

        cachedCellularSupport = hasCellularInterface
        return hasCellularInterface
#endif
    }
}
