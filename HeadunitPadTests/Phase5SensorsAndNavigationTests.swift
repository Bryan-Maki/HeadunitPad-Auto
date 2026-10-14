//
//  Phase5SensorsAndNavigationTests.swift
//  HeadunitPadTests
//
//  Unit tests covering Phase 5:
//  - TwilightCalculator astronomical sunrise/sunset calculations
//  - GeofenceLocation containment and JSON serialization
//  - NightModeManager & strategy evaluation
//  - DrivingStatusPolicy unrestricted driving status
//  - KeyDebouncePolicy key filtering, stuck press release, and media debounce
//  - VehicleTypePolicy & VehicleIdentityPolicy customization
//  - AapNavigation turn-by-turn navigation parsing & formatting
//

import XCTest
import Foundation
import CoreLocation
@testable import HeadunitPad

final class Phase5SensorsAndNavigationTests: XCTestCase {

    // MARK: - 1. Twilight Calculator

    func testTwilightCalculatorDayAndNight() {
        let calc = TwilightCalculator()

        // 2024-06-21 12:00:00 UTC (Summer solstice noon on Prime Meridian: London / Greenwich)
        // Timestamp: 1718971200000 ms
        let noonTimeMs: Int64 = 1718971200000
        calc.calculateTwilight(timeMs: noonTimeMs, latitude: 51.5074, longitude: 0.1278)

        XCTAssertEqual(calc.state, TwilightCalculator.day, "At summer solstice noon, London should be in day state")
        XCTAssertGreaterThan(calc.sunset, calc.sunrise, "Sunset should be after sunrise")

        // 2024-06-21 00:00:00 UTC (Midnight on Prime Meridian)
        // Timestamp: 1718928000000 ms
        let midnightTimeMs: Int64 = 1718928000000
        calc.calculateTwilight(timeMs: midnightTimeMs, latitude: 51.5074, longitude: 0.1278)

        XCTAssertEqual(calc.state, TwilightCalculator.night, "At midnight, London should be in night state")
    }

    func testTwilightCalculatorNearEquator() {
        let calc = TwilightCalculator()

        // Singapore (1.3521 N, 103.8198 E)
        // 2024-03-20 04:00:00 UTC (12:00 SGT Equinox noon)
        let sgtNoonMs: Int64 = 1710907200000
        calc.calculateTwilight(timeMs: sgtNoonMs, latitude: 1.3521, longitude: 103.8198)
        XCTAssertEqual(calc.state, TwilightCalculator.day)

        // Singapore 2024-03-20 16:00:00 UTC (00:00 SGT midnight)
        let sgtMidnightMs: Int64 = 1710950400000
        calc.calculateTwilight(timeMs: sgtMidnightMs, latitude: 1.3521, longitude: 103.8198)
        XCTAssertEqual(calc.state, TwilightCalculator.night)
    }

    // MARK: - 2. Geofence Location

    func testGeofenceContainmentAndDistance() {
        // Tokyo Tower (35.6586, 139.7454)
        let tokyoTower = GeofenceLocation(
            id: "geo-1",
            name: "Tokyo Tower",
            latitude: 35.6586,
            longitude: 139.7454,
            radiusMeters: 200,
            forceNight: true
        )

        // Point 50 meters away (inside)
        let insideLat = 35.6588
        let insideLon = 139.7454
        XCTAssertTrue(tokyoTower.contains(lat: insideLat, lon: insideLon))
        XCTAssertLessThan(tokyoTower.distance(toLat: insideLat, lon: insideLon), 200)

        // Point 500 meters away (outside)
        let outsideLat = 35.6630
        let outsideLon = 139.7454
        XCTAssertFalse(tokyoTower.contains(lat: outsideLat, lon: outsideLon))
        XCTAssertGreaterThan(tokyoTower.distance(toLat: outsideLat, lon: outsideLon), 200)
    }

    func testGeofenceSerializationRoundtrip() {
        let items = [
            GeofenceLocation(id: "tunnel-1", name: "Yamashiro Tunnel", latitude: 35.0, longitude: 135.0, radiusMeters: 300, forceNight: true),
            GeofenceLocation(id: "garage-2", name: "Underground Parking", latitude: 35.1, longitude: 135.1, radiusMeters: 100, forceNight: true)
        ]

        let json = GeofenceLocation.listToJson(items)
        XCTAssertFalse(json.isEmpty)

        let decoded = GeofenceLocation.listFromJson(json)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].id, "tunnel-1")
        XCTAssertEqual(decoded[0].name, "Yamashiro Tunnel")
        XCTAssertEqual(decoded[0].radiusMeters, 300)
        XCTAssertEqual(decoded[1].name, "Underground Parking")
    }

    // MARK: - 3. Night Mode Manager & Geofence Manager

    func testNightModeManagerStrategies() {
        let manager = NightModeManager()

        // Force Day
        manager.setMode(.day)
        XCTAssertFalse(manager.isNight)

        // Force Night
        manager.setMode(.night)
        XCTAssertTrue(manager.isNight)

        // Manual Time
        manager.setMode(.manualTime)
        manager.setManualTimes(startHour: 18, startMinute: 0, endHour: 6, endMinute: 0)
        // 20:00 is between 18:00 and 06:00 -> Night
        let isNight2000 = manager.evaluateManualTime(hour: 20, minute: 0)
        XCTAssertTrue(isNight2000)

        // 12:00 is daytime
        let isNight1200 = manager.evaluateManualTime(hour: 12, minute: 0)
        XCTAssertFalse(isNight1200)

        // 04:00 is night
        let isNight0400 = manager.evaluateManualTime(hour: 4, minute: 0)
        XCTAssertTrue(isNight0400)
    }

    // MARK: - 4. Driving Status Policy

    func testDrivingStatusUnrestricted() {
        let status = DrivingStatusPolicy.unrestrictedStatus()
        XCTAssertEqual(status.status, 0, "Android Auto UNRESTRICTED status must be 0")

        let batch = DrivingStatusPolicy.makeSensorBatch()
        XCTAssertFalse(batch.drivingStatusData.isEmpty)
        XCTAssertEqual(batch.drivingStatusData.first?.status, 0)

        let event = DrivingStatusEvent.make()
        XCTAssertEqual(event.channelUInt8, Channel.ID_SEN)
        XCTAssertGreaterThan(event.size, 0)
    }

    // MARK: - 5. Key Debounce Policy

    func testKeyDebouncePolicyNormalPressAndRelease() {
        var state = KeyDebouncePolicy.KeyState()
        let t0: Int64 = 1000

        // Normal Key Down
        let pressResult = KeyDebouncePolicy.decide(
            state: state,
            isPress: true,
            downTime: t0,
            isMediaKey: false,
            now: t0
        )
        XCTAssertTrue(pressResult.forward)
        XCTAssertFalse(pressResult.releaseFirst)
        XCTAssertTrue(pressResult.state.down)
        state = pressResult.state

        // Normal Key Up
        let releaseResult = KeyDebouncePolicy.decide(
            state: state,
            isPress: false,
            downTime: t0,
            isMediaKey: false,
            now: t0 + 100
        )
        XCTAssertTrue(releaseResult.forward)
        XCTAssertFalse(releaseResult.state.down)
    }

    func testKeyDebounceMediaWindowSuppression() {
        var state = KeyDebouncePolicy.KeyState()
        let t0: Int64 = 1000

        // 1st press
        let r1 = KeyDebouncePolicy.decide(state: state, isPress: true, downTime: nil, isMediaKey: true, now: t0)
        XCTAssertTrue(r1.forward)
        state = r1.state

        // Release 50ms later
        let r1Up = KeyDebouncePolicy.decide(state: state, isPress: false, downTime: nil, isMediaKey: true, now: t0 + 50)
        XCTAssertTrue(r1Up.forward)
        state = r1Up.state

        // 2nd press within 600ms media window (e.g. at 200ms) without unique downTime ID
        let r2 = KeyDebouncePolicy.decide(state: state, isPress: true, downTime: nil, isMediaKey: true, now: t0 + 200)
        XCTAssertFalse(r2.forward, "Media press within 600ms without new ID should be dropped as duplicate")
        XCTAssertTrue(r2.state.pressDropped)
        state = r2.state

        // Release of dropped press should also be dropped
        let r2Up = KeyDebouncePolicy.decide(state: state, isPress: false, downTime: nil, isMediaKey: true, now: t0 + 250)
        XCTAssertFalse(r2Up.forward, "Release for dropped press should not be forwarded")
    }

    func testKeyDebounceStuckPressRecovery() {
        var state = KeyDebouncePolicy.KeyState(down: true, downAt: 1000, lastForwardedPressAt: 1000)

        // 2500ms later (> stuckPressMs 2000), a new down comes in
        let result = KeyDebouncePolicy.decide(state: state, isPress: true, downTime: nil, isMediaKey: false, now: 3500)
        XCTAssertTrue(result.forward)
        XCTAssertTrue(result.releaseFirst, "Stuck press must emit synthetic releaseFirst before forwarding new press")
        XCTAssertTrue(result.state.down)
    }

    // MARK: - 6. Vehicle Type & Identity Policies

    func testVehicleTypePolicySanitisationAndMicOverride() {
        XCTAssertEqual(VehicleTypePolicy.sanitised(1), VehicleTypePolicy.car)
        XCTAssertEqual(VehicleTypePolicy.sanitised(2), VehicleTypePolicy.truck)
        XCTAssertEqual(VehicleTypePolicy.sanitised(3), VehicleTypePolicy.motorcycle)
        XCTAssertEqual(VehicleTypePolicy.sanitised(999), VehicleTypePolicy.car)

        // When head unit mic is enabled, user choice is respected
        XCTAssertEqual(VehicleTypePolicy.vehicleType(selected: 2, headUnitMicEnabled: true), VehicleTypePolicy.truck)

        // When head unit mic is disabled, it MUST fall back to motorcycle (phone mic)
        XCTAssertEqual(VehicleTypePolicy.vehicleType(selected: 1, headUnitMicEnabled: false), VehicleTypePolicy.motorcycle)
        XCTAssertEqual(VehicleTypePolicy.vehicleType(selected: 2, headUnitMicEnabled: false), VehicleTypePolicy.motorcycle)
        XCTAssertTrue(VehicleTypePolicy.isOverriddenByMicrophone(selected: 1, headUnitMicEnabled: false))
    }

    func testVehicleIdentityPolicySuffixes() {
        let baseId = "iPad-HeadunitPad"

        // Car: base id unchanged
        XCTAssertEqual(VehicleIdentityPolicy.vehicleId(base: baseId, vehicleType: VehicleTypePolicy.car), baseId)

        // Truck: "-truck" suffix
        XCTAssertEqual(VehicleIdentityPolicy.vehicleId(base: baseId, vehicleType: VehicleTypePolicy.truck), "iPad-HeadunitPad-truck")

        // Motorcycle: "-moto" suffix
        XCTAssertEqual(VehicleIdentityPolicy.vehicleId(base: baseId, vehicleType: VehicleTypePolicy.motorcycle), "iPad-HeadunitPad-moto")
    }

    // MARK: - 7. AapNavigation & NavSnapshot

    func testNavSnapshotFormatting() {
        // Distance
        let shortSnap = NavSnapshot(distanceMeters: 450)
        XCTAssertEqual(shortSnap.formattedDistance, "450 m")

        let longSnap = NavSnapshot(distanceMeters: 2800)
        XCTAssertEqual(longSnap.formattedDistance, "2.8 km")

        let nilSnap = NavSnapshot(distanceMeters: nil)
        XCTAssertEqual(nilSnap.formattedDistance, "")

        // Time
        let secSnap = NavSnapshot(timeToTurnSeconds: 35)
        XCTAssertEqual(secSnap.formattedTime, "35s")

        let minSnap = NavSnapshot(timeToTurnSeconds: 150)
        XCTAssertEqual(minSnap.formattedTime, "2 min")
    }

    func testAapNavigationMessageHandling() {
        let nav = AapNavigation()
        var lastReceivedSnapshot: NavSnapshot?
        nav.onNavigationUpdate = { snap in
            lastReceivedSnapshot = snap
        }

        // Send instrument cluster start
        let startMsg = AapMessage(
            channel: UInt8(Channel.ID_NAV),
            flags: 0,
            type: UInt16(NavigationMsgType.instrumentClusterStart.rawValue),
            payload: Data()
        )
        let handledStart = nav.process(message: startMsg)
        XCTAssertTrue(handledStart)
        XCTAssertEqual(lastReceivedSnapshot?.status, .active)

        // Send instrument cluster stop
        let stopMsg = AapMessage(
            channel: UInt8(Channel.ID_NAV),
            flags: 0,
            type: UInt16(NavigationMsgType.instrumentClusterStop.rawValue),
            payload: Data()
        )
        let handledStop = nav.process(message: stopMsg)
        XCTAssertTrue(handledStop)
        XCTAssertEqual(lastReceivedSnapshot?.status, .inactive)
    }
}
