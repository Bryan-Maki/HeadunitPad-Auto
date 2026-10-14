//
//  SettingsBackupManager.swift
//  HeadunitPad
//
//  1:1 port of open-headunit SettingsBackupManager.kt
//  JSON import, export, and reset for all projection and keymap configurations.
//

import Foundation
import UIKit

public struct SettingsBackupPayload: Codable {
    public let format: String
    public let version: Int
    public let exportedAt: String
    public let appVersion: String
    public let settings: [String: String]

    public init(
        format: String = SettingsBackupManager.format,
        version: Int = SettingsBackupManager.currentVersion,
        exportedAt: String = ISO8601DateFormatter().string(from: Date()),
        appVersion: String = "0.1.0",
        settings: [String: String]
    ) {
        self.format = format
        self.version = version
        self.exportedAt = exportedAt
        self.appVersion = appVersion
        self.settings = settings
    }
}

public struct SettingsImportResult: Equatable {
    public let importedCount: Int
    public let skippedCount: Int
    public let success: Bool
    public let errorMessage: String?

    public init(importedCount: Int, skippedCount: Int, success: Bool, errorMessage: String? = nil) {
        self.importedCount = importedCount
        self.skippedCount = skippedCount
        self.success = success
        self.errorMessage = errorMessage
    }
}

public final class SettingsBackupManager {

    public static let format = "open-headunit-settings"
    public static let legacyFormat = "headunit-revived-settings"
    public static let currentVersion = 1

    private static let defaults = UserDefaults.standard

    /// List of UserDefaults keys included in settings backup.
    public static let backedUpKeys: [String] = [
        "projection-resolution-preset",
        "projection-fps-limit",
        "projection-dpi",
        "projection-fit-mode",
        "projection-right-hand-drive",
        "projection-horizontal-margin",
        "projection-vertical-margin",
        "projection-gps-source",
        "projection-orientation",
        "projection-connection-mode",
        "projection-auto-reconnect",
        "projection-auto-resume-playback",
        "projection-video-codec-preference",
        "projection-audio-codec-preference",
        "projection-vehicle-make",
        "projection-vehicle-model",
        "projection-vehicle-year",
        "projection-vehicle-id",
        "projection-vehicle-type",
        "projection-headunit-mic-enabled",
        "night-mode-preference",
        "night-mode-manual-start-hour",
        "night-mode-manual-start-minute",
        "night-mode-manual-end-hour",
        "night-mode-manual-end-minute",
        "geofence-locations-json",
        "keymap-custom-mappings"
    ]

    /// Generates a serialized JSON backup string.
    public static func exportJson() -> String? {
        var map: [String: String] = [:]
        for key in backedUpKeys {
            if let obj = defaults.object(forKey: key) {
                map[key] = "\(obj)"
            }
        }

        let payload = SettingsBackupPayload(settings: map)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(payload)
            return String(data: data, encoding: .utf8)
        } catch {
            print("SettingsBackupManager: Failed to serialize settings: \(error)")
            return nil
        }
    }

    /// Imports settings from a JSON backup string.
    public static func importJson(_ jsonString: String) -> SettingsImportResult {
        guard let data = jsonString.data(using: .utf8) else {
            return SettingsImportResult(importedCount: 0, skippedCount: 0, success: false, errorMessage: "Invalid string encoding")
        }

        let payload: SettingsBackupPayload
        do {
            payload = try JSONDecoder().decode(SettingsBackupPayload.self, from: data)
        } catch {
            return SettingsImportResult(importedCount: 0, skippedCount: 0, success: false, errorMessage: "JSON parse failed: \(error.localizedDescription)")
        }

        // Validate format compatibility
        guard payload.format == format || payload.format == legacyFormat else {
            return SettingsImportResult(importedCount: 0, skippedCount: 0, success: false, errorMessage: "Unsupported backup format: \(payload.format)")
        }

        var imported = 0
        var skipped = 0

        for (key, stringVal) in payload.settings {
            if backedUpKeys.contains(key) {
                // Apply according to known types
                if let intVal = Int(stringVal) {
                    defaults.set(intVal, forKey: key)
                } else if stringVal == "true" || stringVal == "false" {
                    defaults.set(stringVal == "true", forKey: key)
                } else {
                    defaults.set(stringVal, forKey: key)
                }
                imported += 1
            } else {
                skipped += 1
            }
        }

        defaults.synchronize()
        return SettingsImportResult(importedCount: imported, skippedCount: skipped, success: true)
    }

    /// Resets all backed-up keys to defaults.
    public static func resetToDefaults() {
        for key in backedUpKeys {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
    }

    /// Exports backup to a temporary file for saving or sharing.
    public static func exportToFile() -> URL? {
        guard let json = exportJson() else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "open-headunit-settings-\(timestamp).json"

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)

        do {
            try json.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("SettingsBackupManager: Failed to write backup file: \(error)")
            return nil
        }
    }
}
