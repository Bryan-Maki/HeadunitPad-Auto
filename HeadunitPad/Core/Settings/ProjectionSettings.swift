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

// DriverPosition is defined in ControlProto.swift (Int32, proto semantics).
// VideoCodecPreference is defined in CodecTypeSelectionPolicy.swift (String, codec semantics).

public enum AudioCodecPreference: Int, CaseIterable {
    case auto = 0
    case aac = 1
    case pcm = 2

    public var title: String {
        switch self {
        case .auto: return "Auto (AAC-LC / PCM)"
        case .aac: return "AAC-LC"
        case .pcm: return "PCM (Uncompressed)"
        }
    }
}

public typealias ProjectionVideoResolution = ResolutionPreset
public typealias ProjectionResolution = ResolutionPreset

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
    private static let autoResumePlaybackKey = "projection-auto-resume-playback"
    private static let videoCodecPreferenceKey = "projection-video-codec-preference"
    private static let audioCodecPreferenceKey = "projection-audio-codec-preference"
    private static let vehicleMakeKey = "projection-vehicle-make"
    private static let vehicleModelKey = "projection-vehicle-model"
    private static let vehicleYearKey = "projection-vehicle-year"
    private static let vehicleIdKey = "projection-vehicle-id"
    private static let vehicleTypeKey = "projection-vehicle-type"
    private static let headUnitMicEnabledKey = "projection-headunit-mic-enabled"

    public static let defaultDpi = 160
    public static let minDpi = 100
    public static let maxDpi = 320

    private static var cachedCellularSupport: Bool?

    public static var vehicleMake: String {
        get { defaults.string(forKey: vehicleMakeKey) ?? "Apple" }
        set { defaults.set(newValue, forKey: vehicleMakeKey) }
    }

    public static var vehicleModel: String {
        get { defaults.string(forKey: vehicleModelKey) ?? "iPad" }
        set { defaults.set(newValue, forKey: vehicleModelKey) }
    }

    public static var vehicleYear: String {
        get { defaults.string(forKey: vehicleYearKey) ?? "2024" }
        set { defaults.set(newValue, forKey: vehicleYearKey) }
    }

    public static var vehicleId: String {
        get { defaults.string(forKey: vehicleIdKey) ?? "iPad-HeadunitPad" }
        set { defaults.set(newValue, forKey: vehicleIdKey) }
    }

    public static var vehicleType: Int {
        get {
            let val = defaults.integer(forKey: vehicleTypeKey)
            return val == 0 ? VehicleTypePolicy.car : VehicleTypePolicy.sanitised(val)
        }
        set { defaults.set(newValue, forKey: vehicleTypeKey) }
    }

    public static var headUnitMicEnabled: Bool {
        get {
            if defaults.object(forKey: headUnitMicEnabledKey) == nil {
                return true
            }
            return defaults.bool(forKey: headUnitMicEnabledKey)
        }
        set { defaults.set(newValue, forKey: headUnitMicEnabledKey) }
    }

    public static var effectiveVehicleType: Int {
        return VehicleTypePolicy.vehicleType(selected: vehicleType, headUnitMicEnabled: headUnitMicEnabled)
    }

    public static var effectiveVehicleId: String {
        return VehicleIdentityPolicy.vehicleId(base: vehicleId, vehicleType: effectiveVehicleType)
    }

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

    public static var autoResumePlayback: Bool {
        get {
            if defaults.object(forKey: autoResumePlaybackKey) == nil {
                return true
            }
            return defaults.bool(forKey: autoResumePlaybackKey)
        }
        set {
            defaults.set(newValue, forKey: autoResumePlaybackKey)
        }
    }

    public static var videoCodecPreference: VideoCodecPreference {
        get {
            let raw = defaults.string(forKey: videoCodecPreferenceKey) ?? VideoCodecPreference.auto.rawValue
            return VideoCodecPreference(rawValue: raw) ?? .auto
        }
        set {
            defaults.set(newValue.rawValue, forKey: videoCodecPreferenceKey)
        }
    }

    public static var audioCodecPreference: AudioCodecPreference {
        get {
            let val = defaults.integer(forKey: audioCodecPreferenceKey)
            return AudioCodecPreference(rawValue: val) ?? .auto
        }
        set {
            defaults.set(newValue.rawValue, forKey: audioCodecPreferenceKey)
        }
    }

    public static var videoResolution: ResolutionPreset {
        get { resolution }
        set { resolution = newValue }
    }

    public static var videoFitMode: VideoFitMode {
        get { fitMode }
        set { fitMode = newValue }
    }

    public static var driverPosition: DriverPosition {
        get { rightHandDrive ? .right : .left }
        set { rightHandDrive = (newValue == .right) }
    }

    public static var driverPositionTitle: String {
        return rightHandDrive ? "Right-Hand Drive (RHD)" : "Left-Hand Drive (LHD)"
    }

    public static var effectiveFpsLimit: ProjectionFpsLimit {
        if orientation == .portrait {
            return .fps30
        }
        return fpsLimit
    }

    public static var effectiveDpi: Int {
        return dpi
    }

    public static var effectiveVideoCodecResolutionValue: Int {
        return resolution.codecResolutionValue
    }

    public static var effectiveVideoDimensions: (width: Int, height: Int) {
        return resolution.dimensions
    }

    public static func resetDpiToDefault() {
        dpi = defaultDpi
    }

    public static func availableResolutions(for orientation: ProjectionOrientation) -> [ResolutionPreset] {
        return [.r800x480, .r1280x720, .r1920x1080, .r2560x1440, .r3840x2160]
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
