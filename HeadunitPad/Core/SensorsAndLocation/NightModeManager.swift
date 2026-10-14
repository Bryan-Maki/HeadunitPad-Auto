//
//  NightModeManager.swift
//  HeadunitPad
//
//  1:1 port of open-headunit NightModeManager.kt & NightMode.kt
//  Manages Day/Night appearance switching across multiple strategies:
//  System (iPadOS theme), Force Day, Force Night, Astronomical Twilight, Manual Schedule, Geofence.
//

import Foundation
import UIKit

public enum NightModePreference: Int, CaseIterable, Codable {
    case system = 0        // Follows iPadOS appearance (Dark Mode)
    case day = 1           // Force Day mode
    case night = 2         // Force Night mode
    case auto = 3          // Astronomical sunrise/sunset via TwilightCalculator
    case manualTime = 4    // Scheduled hours/minutes (e.g. 20:00 - 07:00)
    case geofence = 5      // Tunnel / Underground parking area detection

    public var title: String {
        switch self {
        case .system: return "Follow iPadOS Theme"
        case .day: return "Always Day"
        case .night: return "Always Night"
        case .auto: return "Astronomical Sunrise/Sunset"
        case .manualTime: return "Scheduled Time"
        case .geofence: return "Geofence (Tunnels & Garages)"
        }
    }
}

public final class NightModeManager {
    public static let shared = NightModeManager()

    private let twilightCalculator = TwilightCalculator()
    private let geofenceManager = GeofenceManager.shared

    private var lastEmittedNight: Bool?
    private var lastKnownLatitude: Double?
    private var lastKnownLongitude: Double?

    public var onNightModeChanged: ((Bool) -> Void)?

    public var preference: NightModePreference = .system {
        didSet {
            evaluate(immediate: true)
        }
    }

    // Manual schedule minutes from midnight (e.g. 20:00 = 1200, 07:00 = 420)
    public var manualStartMinutes: Int = 20 * 60
    public var manualEndMinutes: Int = 7 * 60

    private var timer: Timer?

    public init() {
        startPeriodicCheck()
    }

    deinit {
        timer?.invalidate()
    }

    public func startPeriodicCheck() {
        timer?.invalidate()
        // Check every 60 seconds for twilight or manual schedule shifts
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.evaluate(immediate: false)
        }
    }

    /// Update current GPS coordinates from LocationCapture or phone report.
    public func updateLocation(latitude: Double, longitude: Double) {
        lastKnownLatitude = latitude
        lastKnownLongitude = longitude

        if preference == .geofence {
            let forced = geofenceManager.updateLocation(latitude: latitude, longitude: longitude)
            if let forced = forced {
                emit(night: forced, immediate: true)
                return
            }
        }

        if preference == .auto {
            evaluate(immediate: false)
        }
    }

    /// Evaluates current state based on active strategy.
    public func evaluate(immediate: Bool = false) {
        let isNight: Bool

        switch preference {
        case .system:
            if #available(iOS 13.0, *) {
                isNight = UITraitCollection.current.userInterfaceStyle == .dark
            } else {
                isNight = false
            }

        case .day:
            isNight = false

        case .night:
            isNight = true

        case .auto:
            let lat = lastKnownLatitude ?? 39.9042 // Default fallback
            let lon = lastKnownLongitude ?? 116.4074
            let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
            twilightCalculator.calculateTwilight(timeMs: nowMs, latitude: lat, longitude: lon)
            isNight = twilightCalculator.isNight

        case .manualTime:
            let calendar = Calendar.current
            let hour = calendar.component(.hour, from: Date())
            let minute = calendar.component(.minute, from: Date())
            let currentMinutes = hour * 60 + minute

            if manualStartMinutes <= manualEndMinutes {
                isNight = currentMinutes >= manualStartMinutes && currentMinutes <= manualEndMinutes
            } else {
                // Rollover across midnight (e.g. 20:00 to 07:00)
                isNight = currentMinutes >= manualStartMinutes || currentMinutes <= manualEndMinutes
            }

        case .geofence:
            if let lat = lastKnownLatitude, let lon = lastKnownLongitude,
               let forced = geofenceManager.updateLocation(latitude: lat, longitude: lon) {
                isNight = forced
            } else {
                // Outside geofence, fallback to astronomical twilight
                let lat = lastKnownLatitude ?? 39.9042
                let lon = lastKnownLongitude ?? 116.4074
                let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
                twilightCalculator.calculateTwilight(timeMs: nowMs, latitude: lat, longitude: lon)
                isNight = twilightCalculator.isNight
            }
        }

        emit(night: isNight, immediate: immediate)
    }

    private func emit(night: Bool, immediate: Bool) {
        if lastEmittedNight != night {
            lastEmittedNight = night
            print("NightModeManager: emitted nightMode = \(night) (strategy: \(preference.title))")
            onNightModeChanged?(night)
        }
    }

    public var currentNightState: Bool {
        return lastEmittedNight ?? false
    }
}
