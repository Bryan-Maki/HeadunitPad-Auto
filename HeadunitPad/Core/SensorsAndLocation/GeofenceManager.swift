//
//  GeofenceManager.swift
//  HeadunitPad
//
//  Manages user-defined geofences (tunnels, underground parking) and detects entries/exits.
//

import Foundation
import CoreLocation

public final class GeofenceManager {
    public static let shared = GeofenceManager()

    private let defaults = UserDefaults.standard
    private let geofencesKey = "headunitpad-geofences"

    public private(set) var geofences: [GeofenceLocation] = []
    public private(set) var currentGeofence: GeofenceLocation?

    public var onGeofenceEntered: ((GeofenceLocation) -> Void)?
    public var onGeofenceExited: ((GeofenceLocation) -> Void)?

    public init() {
        loadGeofences()
    }

    public func loadGeofences() {
        let json = defaults.string(forKey: geofencesKey)
        geofences = GeofenceLocation.listFromJson(json)
    }

    public func saveGeofences() {
        let json = GeofenceLocation.listToJson(geofences)
        defaults.set(json, forKey: geofencesKey)
    }

    public func addGeofence(_ geofence: GeofenceLocation) {
        geofences.append(geofence)
        saveGeofences()
    }

    public func removeGeofence(id: String) {
        geofences.removeAll { $0.id == id }
        saveGeofences()
        if currentGeofence?.id == id {
            currentGeofence = nil
        }
    }

    public func clearAll() {
        geofences.removeAll()
        saveGeofences()
        currentGeofence = nil
    }

    /// Update with current GPS coordinate; returns true if night mode should be forced.
    @discardableResult
    public func updateLocation(latitude: Double, longitude: Double) -> Bool? {
        let matching = geofences.first { $0.contains(lat: latitude, lon: longitude) }

        if let matching = matching {
            if currentGeofence?.id != matching.id {
                currentGeofence = matching
                onGeofenceEntered?(matching)
            }
            return matching.forceNight
        } else {
            if let previous = currentGeofence {
                currentGeofence = nil
                onGeofenceExited?(previous)
            }
            return nil
        }
    }
}
