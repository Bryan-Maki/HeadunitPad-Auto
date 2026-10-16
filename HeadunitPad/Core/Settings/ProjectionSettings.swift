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
    case system = 2

    public var title: String {
        switch self {
        case .landscape: return "Landscape"
        case .portrait: return "Portrait"
        case .system: return "Auto"
        }
    }
}

public enum NightModeSetting: Int, CaseIterable {
    case auto = 0
    case day = 1
    case night = 2
    case system = 3

    public var title: String {
        switch self {
        case .auto: return "Auto (Time 07:00-19:00)"
        case .day: return "Day (Always Light)"
        case .night: return "Night (Always Dark)"
        case .system: return "System (Follow iPad)"
        }
    }
}

public enum ProjectionConnectionMode: Int, CaseIterable {
    case nativeWpp = 0
    case hotspotServer = 1
    case manualIp = 2

    public static let auto = ProjectionConnectionMode.nativeWpp
    public static let directHeadunit = ProjectionConnectionMode.hotspotServer

    public var title: String {
        switch self {
        case .nativeWpp: return "Native Mode (Auto WPP)"
        case .hotspotServer: return "Hotspot Server Mode (Port 5277)"
        case .manualIp: return "Manual IP"
        }
    }
}

// DriverPosition is defined in ControlProto.swift (Int32, proto semantics).
// VideoCodecPreference is defined in CodecTypeSelectionPolicy.swift (String, codec semantics).

public enum AudioCodecPreference: Int, CaseIterable {
    case aac = 1
    case pcm = 2

    public var title: String {
        switch self {
        case .aac: return "AAC-LC"
        case .pcm: return "PCM (Uncompressed)"
        }
    }
}

public enum AudioOutputTarget: Int, CaseIterable {
    case ipad = 0
    case phone = 1

    public var title: String {
        switch self {
        case .ipad: return "iPad (Speaker / iPad BT)"
        case .phone: return "Phone (Original Device)"
        }
    }

    public var isAudioSinkEnabled: Bool {
        return self == .ipad
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
    private static let audioOutputTargetKey = "projection-audio-output-target"
    private static let nightModeKey = "projection-night-mode"
    private static let wifiSsidKey = "projection-wifi-ssid"
    private static let wifiPasskeyKey = "projection-wifi-passkey"
    private static let wifiBssidKey = "projection-wifi-bssid"
    private static let bluetoothMacKey = "projection-bt-mac"

    private static let autoDpiKey = "projection-auto-dpi"

    public static let defaultDpi = 160
    public static let minDpi = 100
    public static let maxDpi = 320

    private static var cachedCellularSupport: Bool?

    public static var resolution: ResolutionPreset {
        get {
            if defaults.object(forKey: resolutionKey) == nil {
                return .auto
            }
            let val = defaults.integer(forKey: resolutionKey)
            return ResolutionPreset(rawValue: val) ?? .auto
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
            guard defaults.object(forKey: orientationKey) != nil else { return .system }
            let value = defaults.integer(forKey: orientationKey)
            return ProjectionOrientation(rawValue: value) ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: orientationKey)
        }
    }

    public static var nightMode: NightModeSetting {
        get {
            guard defaults.object(forKey: nightModeKey) != nil else { return .auto }
            let val = defaults.integer(forKey: nightModeKey)
            return NightModeSetting(rawValue: val) ?? .auto
        }
        set {
            defaults.set(newValue.rawValue, forKey: nightModeKey)
        }
    }

    public static func effectiveIsNightMode(userInterfaceStyle: UIUserInterfaceStyle? = nil) -> Bool {
        switch nightMode {
        case .day:
            return false
        case .night:
            return true
        case .auto:
            let hour = Calendar.current.component(.hour, from: Date())
            return hour >= 19 || hour < 7
        case .system:
            let style: UIUserInterfaceStyle
            if let userInterfaceStyle = userInterfaceStyle {
                style = userInterfaceStyle
            } else if Thread.isMainThread {
                style = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first(where: { $0.isKeyWindow })?.traitCollection.userInterfaceStyle ?? UITraitCollection.current.userInterfaceStyle
            } else {
                style = UITraitCollection.current.userInterfaceStyle
            }
            return style == .dark
        }
    }

    public static var connectionMode: ProjectionConnectionMode {
        get {
            guard defaults.object(forKey: connectionModeKey) != nil else {
                return .hotspotServer
            }
            let value = defaults.integer(forKey: connectionModeKey)
            return ProjectionConnectionMode(rawValue: value) ?? .hotspotServer
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
            guard let raw = defaults.string(forKey: videoCodecPreferenceKey),
                  let pref = VideoCodecPreference(rawValue: raw) else {
                return .h264
            }
            return pref
        }
        set {
            defaults.set(newValue.rawValue, forKey: videoCodecPreferenceKey)
        }
    }

    public static var audioCodecPreference: AudioCodecPreference {
        get {
            guard let raw = defaults.object(forKey: audioCodecPreferenceKey) as? Int,
                  let pref = AudioCodecPreference(rawValue: raw) else {
                return .aac
            }
            return pref
        }
        set {
            defaults.set(newValue.rawValue, forKey: audioCodecPreferenceKey)
        }
    }

    public static var wifiSsid: String {
        get { defaults.string(forKey: wifiSsidKey) ?? "" }
        set { defaults.set(newValue, forKey: wifiSsidKey) }
    }

    public static var wifiPasskey: String {
        get { defaults.string(forKey: wifiPasskeyKey) ?? "" }
        set { defaults.set(newValue, forKey: wifiPasskeyKey) }
    }

    public static var wifiBssid: String {
        get { defaults.string(forKey: wifiBssidKey) ?? "02:00:00:00:00:00" }
        set { defaults.set(newValue, forKey: wifiBssidKey) }
    }

    public static var bluetoothMac: String {
        get { defaults.string(forKey: bluetoothMacKey) ?? "" }
        set {
            let formatted = newValue.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            defaults.set(formatted, forKey: bluetoothMacKey)
        }
    }

    public static func resetToDefaults() {
        orientation = .system
        videoCodecPreference = .h264
        audioCodecPreference = .aac
        audioOutputTarget = .ipad
        nightMode = .auto
        resetDpiToDefault()
    }

    public static var audioOutputTarget: AudioOutputTarget {
        get {
            guard let raw = defaults.object(forKey: audioOutputTargetKey) as? Int,
                  let target = AudioOutputTarget(rawValue: raw) else {
                return .ipad
            }
            return target
        }
        set {
            defaults.set(newValue.rawValue, forKey: audioOutputTargetKey)
        }
    }

    public static var isAudioSinkEnabled: Bool {
        return audioOutputTarget == .ipad
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

    public static var isAutoDpi: Bool {
        get {
            if defaults.object(forKey: autoDpiKey) == nil {
                return true
            }
            return defaults.bool(forKey: autoDpiKey)
        }
        set {
            defaults.set(newValue, forKey: autoDpiKey)
        }
    }

    public static func recommendedDpiForCurrentDevice() -> Int {
        let config = HeadUnitScreenConfig.shared
        let codecW = config.getNegotiatedWidth()
        let codecH = config.getNegotiatedHeight()
        let marginW = config.getWidthMargin()
        let marginH = config.getHeightMargin()
        let activeW = max(1, codecW - marginW)
        let activeH = max(1, codecH - marginH)
        return AnnouncedDensityPolicy.recommendedDpi(activeW: activeW, activeH: activeH)
    }

    public static var effectiveDpi: Int {
        if isAutoDpi {
            return recommendedDpiForCurrentDevice()
        }
        return dpi
    }

    public static var effectiveVideoCodecResolutionValue: Int {
        return resolution.codecResolutionValue
    }

    public static var effectiveVideoDimensions: (width: Int, height: Int) {
        return resolution.dimensions
    }

    public static var effectiveResolution: (width: Int, height: Int) {
        return resolution.dimensions
    }

    public static func resetDpiToDefault() {
        isAutoDpi = true
        dpi = defaultDpi
    }

    public static func availableResolutions(for orientation: ProjectionOrientation) -> [ResolutionPreset] {
        return [.auto, .r1280x720, .r1920x1080, .r2560x1440, .r3840x2160]
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
        let hasCellular = monitor.currentPath.availableInterfaces.contains { $0.type == .cellular }
        if hasCellular {
            cachedCellularSupport = true
            return true
        }

        if Thread.isMainThread {
            let queue = DispatchQueue(label: "com.headunitpad.cellular-detect")
            monitor.pathUpdateHandler = { path in
                cachedCellularSupport = path.availableInterfaces.contains { $0.type == .cellular }
                monitor.cancel()
            }
            monitor.start(queue: queue)
            return false
        }

        let queue = DispatchQueue(label: "com.headunitpad.cellular-detect")
        let semaphore = DispatchSemaphore(value: 0)
        var hasCellularInterface = false

        monitor.pathUpdateHandler = { path in
            hasCellularInterface = path.availableInterfaces.contains { $0.type == .cellular }
            semaphore.signal()
        }

        monitor.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 0.15)
        monitor.cancel()

        cachedCellularSupport = hasCellularInterface
        return hasCellularInterface
#endif
    }
}
