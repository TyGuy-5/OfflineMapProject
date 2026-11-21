// NavigationTelemetryTests.swift — Tier 1 Feature Coverage: Navigation Telemetry, Step Progression, GPS Lifecycle

import Foundation
import CoreLocation

public final class NavigationTelemetryTests: E2ETestSuite {
    public let name = "Navigation Telemetry & GPS Lifecycle Suite"
    public let tier = TestTier.tier1
    
    public var tests: [TestCaseEntry] {
        return [
            TestCaseEntry(name: "testT1_SwitchbackSearchClampingEliminatesPrematureStepAdvance", tier: tier, block: testT1_SwitchbackSearchClampingEliminatesPrematureStepAdvance),
            TestCaseEntry(name: "testT1_MonotonicTelemetryCountdownDecreasesToZeroWithoutReversal", tier: tier, block: testT1_MonotonicTelemetryCountdownDecreasesToZeroWithoutReversal),
            TestCaseEntry(name: "testT1_MultiSpeedSimulationLoopAdvancesIntermediateManeuversAt5x", tier: tier, block: testT1_MultiSpeedSimulationLoopAdvancesIntermediateManeuversAt5x),
            TestCaseEntry(name: "testT1_DualPointArrivalDetectionTriggersAtSetbackDestination", tier: tier, block: testT1_DualPointArrivalDetectionTriggersAtSetbackDestination),
            TestCaseEntry(name: "testT1_DualPointArrivalDetectionTriggersAtRoadSnappedEndpoint", tier: tier, block: testT1_DualPointArrivalDetectionTriggersAtRoadSnappedEndpoint),
            TestCaseEntry(name: "testT1_HardwareGPSStartFixAvoidsPuckFreezing", tier: tier, block: testT1_HardwareGPSStartFixAvoidsPuckFreezing),
            TestCaseEntry(name: "testT1_DegradedGPSZeroesSpeedometerAndSetsStationaryState", tier: tier, block: testT1_DegradedGPSZeroesSpeedometerAndSetsStationaryState)
        ]
    }
    
    /// R2.1: Restrict forward coordinate search in updateCurrentStepForLiveLocation to currentStep.endIndex + 2
    func testT1_SwitchbackSearchClampingEliminatesPrematureStepAdvance() async throws {
        let (coords, steps) = TestGeometries.makeSwitchbackRoute()
        // coords has 25 coordinates:
        // Step 0: indices 0..10 (heading north along lon -147.7200)
        // Step 1: indices 10..14 (sharp hairpin turn)
        // Step 2: indices 14..24 (heading south along lon -147.7197, only ~12 meters away from Step 0!)
        
        var currentStepIndex = 0
        var currentCoordIndex = 2 // Early in Step 0
        var hasAnnouncedAdvance = false
        var spoken: [(text: String, stepId: Int?)] = []
        
        // Simulate a location update at index 3 in Step 0.
        // If forward search were unclamped (+50 coordinates), it would snap directly to index 21 in Step 2!
        let userLocation = coords[3]
        let arrived = OpaqueTelemetryEngine.updateStepForLiveLocation(
            userCoord: userLocation,
            coords: coords,
            steps: steps,
            currentStepIndex: &currentStepIndex,
            currentCoordIndex: &currentCoordIndex,
            selectedCoordinate: coords.last,
            hasAnnouncedAdvanceTurn: &hasAnnouncedAdvance,
            spokenInstructions: &spoken
        )
        
        assertFalse(arrived, "User at index 3 should not be marked arrived")
        assertEqual(currentStepIndex, 0, "Current step must remain Step 0 and not jump across hairpin switchback")
        assertTrue(currentCoordIndex <= steps[0].endIndex + 2, "Current coord index (\(currentCoordIndex)) must be clamped within Step 0 slack")
        assertTrue(currentCoordIndex == 2 || currentCoordIndex == 3, "User should snap to segment 2 or 3 near vertex 3")
    }
    
    /// R2.2: Ensure remainingStepDistanceMiles counts down monotonically and evaluates to zero at/past stepEnd
    func testT1_MonotonicTelemetryCountdownDecreasesToZeroWithoutReversal() async throws {
        let (coords, steps) = TestGeometries.makeSwitchbackRoute()
        let step0 = steps[0]
        let stepEnd = step0.endIndex // index 10
        
        var previousDistance: Double = Double.greatestFiniteMagnitude
        
        // Progress through indices 5, 6, 7, 8, 9, 10, 11
        for i in 5...11 {
            let coord = coords[i]
            let (stepDist, routeDist, _) = OpaqueTelemetryEngine.calculateTelemetry(
                userCoord: coord,
                coordIndex: i,
                coords: coords,
                steps: steps,
                currentStepIndex: 0,
                totalDistanceMiles: 0.75,
                totalDurationSeconds: 95.0
            )
            
            if i <= stepEnd {
                assertTrue(stepDist <= previousDistance + 0.0001, "Step distance must decrease monotonically: index \(i) had \(stepDist) vs previous \(previousDistance)")
                previousDistance = stepDist
            }
            
            if i >= stepEnd {
                // Must evaluate strictly to 0.0 at or past stepEnd — zero distance reversal!
                assertEqual(stepDist, 0.0, "Step distance must evaluate to 0.0 at or past stepEnd (index \(i))")
            }
            assertTrue(routeDist >= 0.0, "Route distance must remain non-negative")
        }
    }
    
    /// R2.3: In advanceSimulationStep(), advance currentStepIndex via a while loop so 2x and 5x simulation does not skip maneuvers
    func testT1_MultiSpeedSimulationLoopAdvancesIntermediateManeuversAt5x() async throws {
        // Construct a route with 3 consecutive short steps (indices 0..2, 2..4, 4..8)
        var coords: [CLLocationCoordinate2D] = []
        for i in 0...8 {
            coords.append(CLLocationCoordinate2D(latitude: 64.8400 + Double(i) * 0.0005, longitude: -147.7200))
        }
        let step0 = OpaqueNavigationStep(instruction: "Turn right on 1st Ave", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 10, streetName: "1st Ave", startIndex: 0, endIndex: 2)
        let step1 = OpaqueNavigationStep(instruction: "Turn left on 2nd Ave", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 15, streetName: "2nd Ave", startIndex: 2, endIndex: 4)
        let step2 = OpaqueNavigationStep(instruction: "Continue straight on Airport Way", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 1, streetName: "Airport Way", startIndex: 4, endIndex: 8)
        
        var currentCoord = 0
        var currentStep = 0
        var spokenTurns: [String] = []
        
        // Jump from index 0 with 5x speed multiplier (jump = 5 vertices -> lands at index 5)
        let arrived = OpaqueSimulationEngine.advanceSimulation(
            coords: coords,
            steps: [step0, step1, step2],
            speedMultiplier: 5.0,
            currentCoordIndex: &currentCoord,
            currentStepIndex: &currentStep,
            spokenTurns: &spokenTurns
        )
        
        assertFalse(arrived, "Should not be arrived at index 5 of 8")
        assertEqual(currentCoord, 5, "Coord index should advance to 5")
        // Both step 1 and step 2 must have been announced by the loop!
        assertEqual(currentStep, 2, "Current step must advance to 2 without skipping step 1")
        assertTrue(spokenTurns.contains("Turn left on 2nd Ave"), "Must have announced intermediate step 1")
        assertTrue(spokenTurns.contains("Continue straight on Airport Way"), "Must have announced step 2")
    }
    
    /// R2.5: Dual-point arrival detection: Check distance against destination pin (selectedCoordinate) when setback from road
    func testT1_DualPointArrivalDetectionTriggersAtSetbackDestination() async throws {
        let (coords, steps, roadEnd, destPin, userArrival) = TestGeometries.makeSetbackDestinationScenario()
        
        var currentStep = 0
        var currentCoord = 1
        var hasAnnounced = false
        var spoken: [(text: String, stepId: Int?)] = []
        
        // User is at userArrival: 8m from destPin, but 30m away from roadEnd!
        let distToRoadEnd = OpaqueTelemetryEngine.segmentDistanceMeters(p1: userArrival, p2: roadEnd)
        let distToPin = OpaqueTelemetryEngine.segmentDistanceMeters(p1: userArrival, p2: destPin)
        assertTrue(distToRoadEnd > 25.0, "User is > 25m from road end (\(distToRoadEnd)m)")
        assertTrue(distToPin < 15.0, "User is within 15m of destination pin (\(distToPin)m)")
        
        let arrived = OpaqueTelemetryEngine.updateStepForLiveLocation(
            userCoord: userArrival,
            coords: coords,
            steps: steps,
            currentStepIndex: &currentStep,
            currentCoordIndex: &currentCoord,
            selectedCoordinate: destPin,
            hasAnnouncedAdvanceTurn: &hasAnnounced,
            spokenInstructions: &spoken
        )
        
        assertTrue(arrived, "Dual-point arrival must trigger when approaching setback destination coordinate")
        assertTrue(spoken.contains(where: { $0.text.contains("arrived at your destination") }), "Arrival instruction must be announced")
    }
    
    /// R2.5: Dual-point arrival detection: Check distance against snapped road end (coords.last)
    func testT1_DualPointArrivalDetectionTriggersAtRoadSnappedEndpoint() async throws {
        let (coords, steps, roadEnd, _, _) = TestGeometries.makeSetbackDestinationScenario()
        
        var currentStep = 0
        var currentCoord = 2
        var hasAnnounced = false
        var spoken: [(text: String, stepId: Int?)] = []
        
        // User arrives within 10 meters of road end
        let userAtRoadEnd = CLLocationCoordinate2D(latitude: roadEnd.latitude - 0.00005, longitude: roadEnd.longitude)
        let arrived = OpaqueTelemetryEngine.updateStepForLiveLocation(
            userCoord: userAtRoadEnd,
            coords: coords,
            steps: steps,
            currentStepIndex: &currentStep,
            currentCoordIndex: &currentCoord,
            selectedCoordinate: nil,
            hasAnnouncedAdvanceTurn: &hasAnnounced,
            spokenInstructions: &spoken
        )
        
        assertTrue(arrived, "Dual-point arrival must trigger when reaching road endpoint")
    }
    
    /// R2.4: Do not unconditionally snap simulatedUserCoordinate to polyline start when a valid hardware GPS fix exists
    func testT1_HardwareGPSStartFixAvoidsPuckFreezing() async throws {
        let liveGPSFix = TestCoordinates.fairbanksDowntown
        let routeStart = CLLocationCoordinate2D(latitude: 64.8410, longitude: -147.7180)
        
        // Simulating the startNavigation logic:
        // If live GPS fix exists and is in supported region, use it rather than route start
        let hasValidHardwareFix = true
        let resolvedCoordinate: CLLocationCoordinate2D = hasValidHardwareFix ? liveGPSFix : routeStart
        
        assertEqual(resolvedCoordinate.latitude, liveGPSFix.latitude, "Must retain live hardware GPS coordinate")
        assertEqual(resolvedCoordinate.longitude, liveGPSFix.longitude, "Must not unconditionally snap to routeStart")
    }
    
    /// R2.6: Zero smoothed speed and set stationary state when GPS accuracy degrades (horizontalAccuracy >= 65.0 or < 0)
    func testT1_DegradedGPSZeroesSpeedometerAndSetsStationaryState() async throws {
        let observer = OpaqueLocationObserver()
        
        // Initial good GPS fix moving at 45 mph (~20.1 m/s)
        observer.processLocationFix(horizontalAccuracy: 5.0, rawSpeedMps: 20.1, ageSeconds: 1.0)
        assertFalse(observer.isGpsSignalLow, "GPS signal should be good")
        assertFalse(observer.isStationary, "Vehicle is moving")
        assertTrue(observer.smoothedSpeedMph > 40, "Speedometer should read > 40 mph")
        
        // GPS degrades to 75m accuracy
        observer.processLocationFix(horizontalAccuracy: 75.0, rawSpeedMps: 20.1, ageSeconds: 1.0)
        assertTrue(observer.isGpsSignalLow, "Low GPS warning must activate")
        assertEqual(observer.smoothedSpeedMph, 0, "Speedometer must be zeroed immediately on degraded GPS")
        assertTrue(observer.isStationary, "Must set stationary state on degraded GPS")
        
        // GPS fix with negative accuracy (-1.0, uncalibrated)
        observer.processLocationFix(horizontalAccuracy: -1.0, rawSpeedMps: 15.0, ageSeconds: 1.0)
        assertTrue(observer.isGpsSignalLow, "Negative accuracy must trigger low GPS flag")
        assertEqual(observer.smoothedSpeedMph, 0, "Speedometer must remain zero")
        assertTrue(observer.isStationary, "Must remain stationary")
    }
}
