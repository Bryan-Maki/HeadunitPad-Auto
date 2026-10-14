//
//  GeofenceLocation.swift
//  HeadunitPad
//
//  1:1 port of open-headunit GeofenceLocation.kt
//  A user-defined circular geofence area (e.g. Tunnel, Garage) that sets night or day appearance.
//

import Foundation
import CoreLocation

public struct GeofenceLocation: Codable, Equatable, Identifiable {
    public static let defaultRadiusMeters: Double = 150.0

    public var id: String
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var radiusMeters: Double
    public var forceNight: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double = GeofenceLocation.defaultRadiusMeters,
        forceNight: Bool = true
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.forceNight = forceNight
    }

    /// Calculate distance in meters to a given coordinate.
    public func distance(toLat lat: Double, lon: Double) -> Double {
        let center = CLLocation(latitude: latitude, longitude: longitude)
        let target = CLLocation(latitude: lat, longitude: lon)
        return center.distance(from: target)
    }

    /// Checks if a given coordinate is within this geofence radius.
    public func contains(lat: Double, lon: Double) -> Bool {
        return distance(toLat: lat, lon: lon) <= radiusMeters
    }

    public static func listFromJson(_ json: String?) -> [GeofenceLocation] {
        guard let json = json, !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = json.data(using: .utf8) else {
            return []
        }
        do {
            return try JSONDecoder().decode([GeofenceLocation].self, from: data)
        } catch {
            return []
        }
    }

    public static func listToJson(_ list: [GeofenceLocation]) -> String {
        do {
            let data = try JSONEncoder().encode(list)
            return String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            return "[]"
        }
    }
}
