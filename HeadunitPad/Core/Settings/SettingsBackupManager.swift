//
//  SettingsBackupManager.swift
//  HeadunitPad
//
//  1:1 port of open-headunit SettingsBackupManager.kt
//  Exports, imports, and resets ProjectionSettings to/from JSON.
//

import Foundation

public enum SettingsBackupError: LocalizedError {
    case invalidFormat
    case unsupportedVersion(Int)
    case corruptedData(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid settings format: missing or incorrect format identifier"
        case .unsupportedVersion(let v):
            return "Unsupported settings format version: \(v)"
        case .corruptedData(let msg):
            return "Corrupted settings data: \(msg)"
        }
    }
}

public struct SettingsPayload: Codable, Equatable {
    public var resolution: Int
    public var fpsLimit: Int
    public var dpi: Int
    public var fitMode: Int
    public var rightHandDrive: Bool
    public var horizontalMargin: Int
    public var verticalMargin: Int
    public var gpsSource: Int
    public var orientation: Int
    public var connectionMode: Int
    public var autoReconnect: Bool
    public var autoResumePlayback: Bool
    public var videoCodecPreference: String
    public var audioCodecPreference: Int
    public var audioOutputTarget: Int
    public var nightMode: Int
    public var showPerformanceOverlay: Bool

    public init(
        resolution: Int,
        fpsLimit: Int,
        dpi: Int,
        fitMode: Int,
        rightHandDrive: Bool,
        horizontalMargin: Int,
        verticalMargin: Int,
        gpsSource: Int,
        orientation: Int,
        connectionMode: Int,
        autoReconnect: Bool,
        autoResumePlayback: Bool,
        videoCodecPreference: String,
        audioCodecPreference: Int,
        audioOutputTarget: Int,
        nightMode: Int,
        showPerformanceOverlay: Bool
    ) {
        self.resolution = resolution
        self.fpsLimit = fpsLimit
        self.dpi = dpi
        self.fitMode = fitMode
        self.rightHandDrive = rightHandDrive
        self.horizontalMargin = horizontalMargin
        self.verticalMargin = verticalMargin
        self.gpsSource = gpsSource
        self.orientation = orientation
        self.connectionMode = connectionMode
        self.autoReconnect = autoReconnect
        self.autoResumePlayback = autoResumePlayback
        self.videoCodecPreference = videoCodecPreference
        self.audioCodecPreference = audioCodecPreference
        self.audioOutputTarget = audioOutputTarget
        self.nightMode = nightMode
        self.showPerformanceOverlay = showPerformanceOverlay
    }
}

public struct BackupContainer: Codable {
    public let format: String
    public let version: Int
    public let exportedAt: String
    public let settings: SettingsPayload

    public init(format: String = "headunitpad-auto-settings", version: Int = 1, exportedAt: String, settings: SettingsPayload) {
        self.format = format
        self.version = version
        self.exportedAt = exportedAt
        self.settings = settings
    }
}

public enum SettingsBackupManager {
    public static let formatIdentifier = "headunitpad-auto-settings"
    public static let currentVersion = 1

    public static func currentPayload() -> SettingsPayload {
        return SettingsPayload(
            resolution: ProjectionSettings.resolution.rawValue,
            fpsLimit: ProjectionSettings.fpsLimit.rawValue,
            dpi: ProjectionSettings.dpi,
            fitMode: ProjectionSettings.fitMode.rawValue,
            rightHandDrive: ProjectionSettings.rightHandDrive,
            horizontalMargin: ProjectionSettings.horizontalMargin,
            verticalMargin: ProjectionSettings.verticalMargin,
            gpsSource: ProjectionSettings.gpsSource.rawValue,
            orientation: ProjectionSettings.orientation.rawValue,
            connectionMode: ProjectionSettings.connectionMode.rawValue,
            autoReconnect: ProjectionSettings.autoReconnect,
            autoResumePlayback: ProjectionSettings.autoResumePlayback,
            videoCodecPreference: ProjectionSettings.videoCodecPreference.rawValue,
            audioCodecPreference: ProjectionSettings.audioCodecPreference.rawValue,
            audioOutputTarget: ProjectionSettings.audioOutputTarget.rawValue,
            nightMode: ProjectionSettings.nightMode.rawValue,
            showPerformanceOverlay: ProjectionSettings.showPerformanceOverlay
        )
    }

    public static func exportToJson() -> String {
        let payload = currentPayload()
        let container = BackupContainer(
            format: formatIdentifier,
            version: currentVersion,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            settings: payload
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(container),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    @discardableResult
    public static func importFromJson(_ json: String) throws -> Int {
        guard let data = json.data(using: .utf8) else {
            throw SettingsBackupError.corruptedData("Unable to parse UTF-8 data")
        }

        let decoder = JSONDecoder()
        let container: BackupContainer
        do {
            container = try decoder.decode(BackupContainer.self, from: data)
        } catch {
            throw SettingsBackupError.corruptedData(error.localizedDescription)
        }

        guard container.format == formatIdentifier else {
            throw SettingsBackupError.invalidFormat
        }

        guard container.version == currentVersion else {
            throw SettingsBackupError.unsupportedVersion(container.version)
        }

        let s = container.settings
        if let res = ResolutionPreset(rawValue: s.resolution) {
            ProjectionSettings.resolution = res
        }
        if let fps = ProjectionFpsLimit(rawValue: s.fpsLimit) {
            ProjectionSettings.fpsLimit = fps
        }
        ProjectionSettings.dpi = s.dpi
        if let fit = VideoFitMode(rawValue: s.fitMode) {
            ProjectionSettings.fitMode = fit
        }
        ProjectionSettings.rightHandDrive = s.rightHandDrive
        ProjectionSettings.horizontalMargin = s.horizontalMargin
        ProjectionSettings.verticalMargin = s.verticalMargin
        if let gps = ProjectionGpsSource(rawValue: s.gpsSource) {
            ProjectionSettings.gpsSource = gps
        }
        if let ori = ProjectionOrientation(rawValue: s.orientation) {
            ProjectionSettings.orientation = ori
        }
        if let conn = ProjectionConnectionMode(rawValue: s.connectionMode) {
            ProjectionSettings.connectionMode = conn
        }
        ProjectionSettings.autoReconnect = s.autoReconnect
        ProjectionSettings.autoResumePlayback = s.autoResumePlayback
        if let codec = VideoCodecPreference(rawValue: s.videoCodecPreference) {
            ProjectionSettings.videoCodecPreference = codec
        }
        if let aCodec = AudioCodecPreference(rawValue: s.audioCodecPreference) {
            ProjectionSettings.audioCodecPreference = aCodec
        }
        if let aTarget = AudioOutputTarget(rawValue: s.audioOutputTarget) {
            ProjectionSettings.audioOutputTarget = aTarget
        }
        if let nm = NightModeSetting(rawValue: s.nightMode) {
            ProjectionSettings.nightMode = nm
        }
        ProjectionSettings.showPerformanceOverlay = s.showPerformanceOverlay

        HeadUnitScreenConfig.shared.recalculate(requestedResolution: ProjectionSettings.resolution)

        return 17
    }

    public static func resetToDefaults() {
        ProjectionSettings.resolution = .auto
        ProjectionSettings.fpsLimit = .fps60
        ProjectionSettings.dpi = ProjectionSettings.defaultDpi
        ProjectionSettings.fitMode = .fillMargin
        ProjectionSettings.rightHandDrive = false
        ProjectionSettings.horizontalMargin = 0
        ProjectionSettings.verticalMargin = 0
        ProjectionSettings.gpsSource = .phone
        ProjectionSettings.orientation = .system
        ProjectionSettings.connectionMode = .nativeWpp
        ProjectionSettings.autoReconnect = true
        ProjectionSettings.autoResumePlayback = true
        ProjectionSettings.videoCodecPreference = .h264
        ProjectionSettings.audioCodecPreference = .aac
        ProjectionSettings.audioOutputTarget = .ipad
        ProjectionSettings.nightMode = .system
        ProjectionSettings.showPerformanceOverlay = false

        HeadUnitScreenConfig.shared.recalculate(requestedResolution: .auto)
    }
}
