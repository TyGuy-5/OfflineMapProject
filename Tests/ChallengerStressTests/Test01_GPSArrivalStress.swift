// Test01_GPSArrivalStress.swift
// Empirical Challenger Harness for testAdversarial01_OutOfRegionGPSHandling

import Foundation
import CoreLocation
import SwiftUI

@main
struct Test01Runner {
    static var passCount = 0
    static var failCount = 0

    static func assertCondition(_ cond: Bool, _ name: String, details: String = "") {
        if cond {
            passCount += 1
            print("  ✅ [PASS] \(name)")
        } else {
            failCount += 1
            print("  ❌ [FAIL] \(name): \(details)")
        }
    }

    // Haversine/flat-earth distance formula matching NavigationViewModel.segmentDistanceMeters
    static func calcDistance(p1: CLLocationCoordinate2D, p2: CLLocationCoordinate2D) -> Double {
        let latRad = (p1.latitude + p2.latitude) * 0.5 * Double.pi / 180.0
        let dx = (p2.longitude - p1.longitude) * 111320.0 * cos(latRad)
        let dy = (p2.latitude - p1.latitude) * 110540.0
        return sqrt(dx * dx + dy * dy)
    }

    // Helper to generate coordinate at exact meter offset (dx east, dy north) from base
    static func offsetCoord(base: CLLocationCoordinate2D, eastMeters: Double, northMeters: Double) -> CLLocationCoordinate2D {
        let latRad = base.latitude * Double.pi / 180.0
        let dLat = northMeters / 110540.0
        let dLon = eastMeters / (111320.0 * cos(latRad))
        return CLLocationCoordinate2D(latitude: base.latitude + dLat, longitude: base.longitude + dLon)
    }

    @MainActor
    static func main() async {
        print("=================================================================")
        print("🔬 EMPIRICAL CHALLENGER TEST 01: GPS Arrival & Out-of-Region Fixes")
        print("=================================================================")

        // -------------------------------------------------------------
        // Subtest 1: Empirical reproduction of pre-remediation bug
        // Endpoint = (64.8440, -147.7210), Fix = (64.8438, -147.7212)
        // -------------------------------------------------------------
        print("\n--- Subtest 1: Pre-Remediation Endpoint Collision Bug Reproduction ---")
        let vmPre = NavigationViewModel()
        let oldCoords = [
            CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215),
            CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7210)
        ]
        let oldDist = calcDistance(p1: CLLocationCoordinate2D(latitude: 64.8438, longitude: -147.7212), p2: oldCoords.last!)
        print("  Calculated distance to old endpoint: \(oldDist) meters")
        assertCondition(oldDist < 25.0, "Pre-remediation distance is strictly < 25.0m (\(oldDist)m)")

        vmPre.routeDetails = RouteDetails(coordinates: oldCoords, totalDistanceMiles: 0.1, totalDurationSeconds: 30, steps: [])
        vmPre.routeCoordinates = oldCoords
        vmPre.isNavigating = true
        vmPre.isSimulating = false
        vmPre.simulatedUserCoordinate = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)

        let inRegionFixOld = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 64.8438, longitude: -147.7212),
            altitude: 10,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        vmPre.handleLocationUpdate(inRegionFixOld)
        // With old coordinates, arrival triggered and wiped simulatedUserCoordinate to nil!
        assertCondition(vmPre.isNavigating == false, "Pre-remediation: isNavigating flipped to false (premature arrival)")
        assertCondition(vmPre.simulatedUserCoordinate == nil, "Pre-remediation: simulatedUserCoordinate wiped to nil by endNavigation()")

        // -------------------------------------------------------------
        // Subtest 2: Remediated Endpoint Verification
        // Endpoint = (64.8500, -147.7210), Fix = (64.8438, -147.7212)
        // -------------------------------------------------------------
        print("\n--- Subtest 2: Remediated Section 6 Endpoint Verification ---")
        let vmRem = NavigationViewModel()
        let remediatedCoords = [
            CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215),
            CLLocationCoordinate2D(latitude: 64.8500, longitude: -147.7210)
        ]
        let remDist = calcDistance(p1: CLLocationCoordinate2D(latitude: 64.8438, longitude: -147.7212), p2: remediatedCoords.last!)
        print("  Calculated distance to remediated endpoint: \(remDist) meters")
        assertCondition(remDist > 600.0, "Remediated distance is far from arrival threshold (\(remDist)m > 600m)")

        vmRem.routeDetails = RouteDetails(coordinates: remediatedCoords, totalDistanceMiles: 0.1, totalDurationSeconds: 30, steps: [])
        vmRem.routeCoordinates = remediatedCoords
        vmRem.isNavigating = true
        vmRem.isSimulating = false
        let initialPuck = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        vmRem.simulatedUserCoordinate = initialPuck

        // Deliver out-of-region fix (San Francisco)
        let outOfRegionFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 10,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        vmRem.handleLocationUpdate(outOfRegionFix)
        assertCondition(
            vmRem.simulatedUserCoordinate?.latitude == initialPuck.latitude &&
            vmRem.simulatedUserCoordinate?.longitude == initialPuck.longitude,
            "Out-of-region fix silently dropped; simulatedUserCoordinate remains intact"
        )
        assertCondition(vmRem.isNavigating == true, "Navigation state remains active after out-of-region fix")

        // Deliver valid in-region fix (Fairbanks downtown)
        let inRegionFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 64.8438, longitude: -147.7212),
            altitude: 10,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        vmRem.handleLocationUpdate(inRegionFix)
        assertCondition(
            abs((vmRem.simulatedUserCoordinate?.latitude ?? 0) - 64.8438) < 0.0001 &&
            abs((vmRem.simulatedUserCoordinate?.longitude ?? 0) - (-147.7212)) < 0.0001,
            "Valid in-region fix updates simulatedUserCoordinate accurately"
        )
        assertCondition(vmRem.isNavigating == true, "Navigation continues without triggering destination arrival")
        assertCondition(vmRem.routeDetails != nil, "routeDetails remains valid and active")
        vmRem.endNavigation()

        // -------------------------------------------------------------
        // Subtest 3: Arrival Distance Gradient Probing (Non-Near-End Route)
        // Route has 6 coordinates. User is at vertex 0 (searchStart=0, coords.count=6).
        // coords.count - 3 = 3. currentCoordIndex = 0 < 3. isNearEnd == false.
        // Arrival threshold MUST be strictly 25.0 meters!
        // -------------------------------------------------------------
        print("\n--- Subtest 3: Distance Gradient Probing on Multi-Segment Route (isNearEnd = false) ---")
        let endPoint = CLLocationCoordinate2D(latitude: 64.8500, longitude: -147.7210)
        let longRouteCoords = [
            CLLocationCoordinate2D(latitude: 64.8400, longitude: -147.7250), // 0: Start
            CLLocationCoordinate2D(latitude: 64.8420, longitude: -147.7240), // 1
            CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7230), // 2
            CLLocationCoordinate2D(latitude: 64.8460, longitude: -147.7220), // 3
            CLLocationCoordinate2D(latitude: 64.8480, longitude: -147.7215), // 4
            endPoint                                                         // 5: End
        ]

        let testDists: [(dist: Double, shouldArrive: Bool)] = [
            (100.0, false),
            (50.0, false),
            (35.0, false), // > 25.0m, since isNearEnd=false, 35m must NOT arrive
            (26.0, false), // > 25.0m, must NOT arrive
            (25.1, false), // > 25.0m, must NOT arrive
            (24.9, true),  // < 25.0m, MUST arrive
            (20.0, true),  // < 25.0m, MUST arrive
            (10.0, true),  // < 25.0m, MUST arrive
            (0.0, true)    // 0m, MUST arrive
        ]

        for probe in testDists {
            let vmProbe = NavigationViewModel()
            vmProbe.routeDetails = RouteDetails(coordinates: longRouteCoords, totalDistanceMiles: 1.0, totalDurationSeconds: 120, steps: [])
            vmProbe.routeCoordinates = longRouteCoords
            vmProbe.isNavigating = true
            vmProbe.isSimulating = false
            vmProbe.currentCoordIndex = 0 // Explicitly set to index 0 (isNearEnd = false)

            let probeCoord = offsetCoord(base: endPoint, eastMeters: probe.dist, northMeters: 0)
            let actualDist = calcDistance(p1: probeCoord, p2: endPoint)

            let fix = CLLocation(coordinate: probeCoord, altitude: 0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date())
            vmProbe.handleLocationUpdate(fix)

            if probe.shouldArrive {
                assertCondition(
                    vmProbe.isNavigating == false && vmProbe.routeDetails == nil,
                    "Distance \(probe.dist)m (actual \(String(format: "%.1f", actualDist))m): Correctly triggered arrival"
                )
            } else {
                assertCondition(
                    vmProbe.isNavigating == true && vmProbe.routeDetails != nil && vmProbe.simulatedUserCoordinate != nil,
                    "Distance \(probe.dist)m (actual \(String(format: "%.1f", actualDist))m): Did NOT trigger arrival; puck preserved"
                )
            }
        }

        // -------------------------------------------------------------
        // Subtest 4: Dual-Point Arrival Logic (Destination Pin vs Endpoint)
        // -------------------------------------------------------------
        print("\n--- Subtest 4: Dual-Point Arrival Check (selectedCoordinate vs coords.last) ---")
        let roadEnd = CLLocationCoordinate2D(latitude: 64.8500, longitude: -147.7210)
        let destPin = CLLocationCoordinate2D(latitude: 64.8510, longitude: -147.7210) // 110m north of road end

        // Case A: User arrives at destination pin (e.g. building setback 15m from pin, but 95m from road end)
        let vmDualA = NavigationViewModel()
        vmDualA.routeDetails = RouteDetails(coordinates: longRouteCoords, totalDistanceMiles: 1.0, totalDurationSeconds: 120, steps: [])
        vmDualA.routeCoordinates = longRouteCoords
        vmDualA.selectedCoordinate = destPin
        vmDualA.isNavigating = true
        vmDualA.isSimulating = false
        vmDualA.currentCoordIndex = 0

        let pinCloseCoord = offsetCoord(base: destPin, eastMeters: 15.0, northMeters: 0) // 15m from pin (< 25m)
        let distToRoad = calcDistance(p1: pinCloseCoord, p2: roadEnd)
        let distToPin = calcDistance(p1: pinCloseCoord, p2: destPin)
        print("  Case A: distToRoad = \(String(format: "%.1f", distToRoad))m, distToPin = \(String(format: "%.1f", distToPin))m")

        let fixA = CLLocation(coordinate: pinCloseCoord, altitude: 0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date())
        vmDualA.handleLocationUpdate(fixA)
        assertCondition(
            vmDualA.isNavigating == false && vmDualA.routeDetails == nil,
            "Dual-point arrival: Arrival triggered via destination pin (< 25m) even though road end is far"
        )

        // Case B: User is far from both pin (80m) and road end (80m)
        let vmDualB = NavigationViewModel()
        vmDualB.routeDetails = RouteDetails(coordinates: longRouteCoords, totalDistanceMiles: 1.0, totalDurationSeconds: 120, steps: [])
        vmDualB.routeCoordinates = longRouteCoords
        vmDualB.selectedCoordinate = destPin
        vmDualB.isNavigating = true
        vmDualB.isSimulating = false
        vmDualB.currentCoordIndex = 0

        let farCoord = offsetCoord(base: roadEnd, eastMeters: 80.0, northMeters: 0)
        let fixB = CLLocation(coordinate: farCoord, altitude: 0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date())
        vmDualB.handleLocationUpdate(fixB)
        assertCondition(
            vmDualB.isNavigating == true && vmDualB.simulatedUserCoordinate != nil,
            "Dual-point arrival: User far from both endpoints does not trigger arrival"
        )

        // -------------------------------------------------------------
        // Subtest 5: Alaska Geographic Region Boundary Validation
        // -------------------------------------------------------------
        print("\n--- Subtest 5: Comprehensive Alaska Bounding Box Verification ---")
        let vmRegion = NavigationViewModel()
        let alaskaCities: [(String, CLLocationCoordinate2D)] = [
            ("Fairbanks Downtown", CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)),
            ("Anchorage Downtown", CLLocationCoordinate2D(latitude: 61.2181, longitude: -149.9003)),
            ("Juneau Capital", CLLocationCoordinate2D(latitude: 58.3019, longitude: -134.4197)),
            ("Sitka", CLLocationCoordinate2D(latitude: 57.0531, longitude: -135.3300)),
            ("Ketchikan", CLLocationCoordinate2D(latitude: 55.3422, longitude: -131.6461)),
            ("Utqiagvik (Barrow)", CLLocationCoordinate2D(latitude: 71.2906, longitude: -156.7887)),
            ("Kodiak Island", CLLocationCoordinate2D(latitude: 57.7900, longitude: -152.4072)),
            ("Nome", CLLocationCoordinate2D(latitude: 64.5011, longitude: -165.4064)),
            ("Bethel", CLLocationCoordinate2D(latitude: 60.7922, longitude: -161.7558)),
            ("Deadhorse / Prudhoe Bay", CLLocationCoordinate2D(latitude: 70.2002, longitude: -148.4597))
        ]

        for (city, coord) in alaskaCities {
            assertCondition(
                vmRegion.isWithinSupportedRegion(coord),
                "Region test: \(city) is within supported region"
            )
        }

        let nonAlaskaPoints: [(String, CLLocationCoordinate2D)] = [
            ("Seattle, WA", CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)),
            ("San Francisco, CA", CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)),
            ("Honolulu, HI", CLLocationCoordinate2D(latitude: 21.3069, longitude: -157.8583)),
            ("London, UK", CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)),
            ("Tokyo, JP", CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)),
            ("Just below southern boundary (50.9999°N)", CLLocationCoordinate2D(latitude: 50.9999, longitude: -147.0)),
            ("Just above northern boundary (72.0001°N)", CLLocationCoordinate2D(latitude: 72.0001, longitude: -147.0)),
            ("Just west of boundary (-179.0001°W)", CLLocationCoordinate2D(latitude: 64.0, longitude: -179.0001)),
            ("Just east of boundary (-128.9999°W)", CLLocationCoordinate2D(latitude: 64.0, longitude: -128.9999))
        ]

        for (label, coord) in nonAlaskaPoints {
            assertCondition(
                !vmRegion.isWithinSupportedRegion(coord),
                "Region test: \(label) is correctly rejected"
            )
        }

        // Summary
        print("\n=================================================================")
        print("SUMMARY TEST 01: \(passCount) PASSED, \(failCount) FAILED")
        print("=================================================================")
        if failCount > 0 {
            exit(1)
        }
    }
}
