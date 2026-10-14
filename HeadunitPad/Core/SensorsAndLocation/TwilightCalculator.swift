//
//  TwilightCalculator.swift
//  HeadunitPad
//
//  1:1 port of open-headunit TwilightCalculator.java
//  Calculates astronomical sunrise and sunset based on timestamp, latitude, and longitude.
//

import Foundation

public final class TwilightCalculator {
    public static let day = 0
    public static let night = 1

    private static let degreesToRadians: Double = .pi / 180.0
    private static let j0: Double = 0.0009
    private static let altitudeCorrectionEarlyNight: Double = 0.017453293 // +1.0 deg in rads (~4 min before sunset)
    private static let c1: Double = 0.0334196
    private static let c2: Double = 0.000349066
    private static let c3: Double = 0.000005236
    private static let obliquity: Double = 0.40927971
    private static let utc2000: Double = 946728000000.0 // Jan 1, 2000 12:00 UTC in ms
    private static let dayInMillis: Double = 86400000.0

    public var sunset: Int64 = -1
    public var sunrise: Int64 = -1
    public var state: Int = TwilightCalculator.day

    public init() {}

    /// Calculates sunrise/sunset based on time (ms since unix epoch) and geographic coordinates.
    public func calculateTwilight(timeMs: Int64, latitude: Double, longitude: Double) {
        let daysSince2000 = (Double(timeMs) - TwilightCalculator.utc2000) / TwilightCalculator.dayInMillis

        // Mean anomaly
        let meanAnomaly = 6.240059968 + daysSince2000 * 0.01720197

        // True anomaly
        let trueAnomaly = meanAnomaly +
            TwilightCalculator.c1 * sin(meanAnomaly) +
            TwilightCalculator.c2 * sin(2.0 * meanAnomaly) +
            TwilightCalculator.c3 * sin(3.0 * meanAnomaly)

        // Ecliptic longitude
        let solarLng = trueAnomaly + 1.796593063 + .pi

        // Solar transit in days since 2000
        let arcLongitude = -longitude / 360.0
        let n = round(daysSince2000 - TwilightCalculator.j0 - arcLongitude)
        let solarTransitJ2000 = n + TwilightCalculator.j0 + arcLongitude +
            0.0053 * sin(meanAnomaly) +
            -0.0069 * sin(2.0 * solarLng)

        // Declination of sun
        let solarDec = asin(sin(solarLng) * sin(TwilightCalculator.obliquity))
        let latRad = latitude * TwilightCalculator.degreesToRadians

        let denom = cos(latRad) * cos(solarDec)
        if abs(denom) < 1e-9 {
            state = TwilightCalculator.night
            sunset = -1
            sunrise = -1
            return
        }

        let cosHourAngle = (sin(TwilightCalculator.altitudeCorrectionEarlyNight) - sin(latRad) * sin(solarDec)) / denom

        if cosHourAngle >= 1.0 {
            state = TwilightCalculator.night
            sunset = -1
            sunrise = -1
            return
        } else if cosHourAngle <= -1.0 {
            state = TwilightCalculator.day
            sunset = -1
            sunrise = -1
            return
        }

        let hourAngle = acos(cosHourAngle) / (2.0 * .pi)
        sunset = Int64(round((solarTransitJ2000 + hourAngle) * TwilightCalculator.dayInMillis + TwilightCalculator.utc2000))
        sunrise = Int64(round((solarTransitJ2000 - hourAngle) * TwilightCalculator.dayInMillis + TwilightCalculator.utc2000))

        if sunrise < timeMs && sunset > timeMs {
            state = TwilightCalculator.day
        } else {
            state = TwilightCalculator.night
        }
    }

    public var isNight: Bool {
        return state == TwilightCalculator.night
    }
}
