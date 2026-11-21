// SetbackParkingScenarioTests.swift — Tier 4 Real-World Application Scenario: Setback Parking Lot Arrival

import Foundation
import CoreLocation

public final class SetbackParkingScenarioTests: E2ETestSuite {
    public let name = "Real-World Scenario 2: Setback Parking Lot Arrival"
    public let tier = TestTier.tier4
    
    public var tests: [TestCaseEntry] {
        return [
            TestCaseEntry(name: "testT4_SetbackParkingLotArrivalDualPointDetection", tier: tier, block: testT4_SetbackParkingLotArrivalDualPointDetection)
        ]
    }
    
    /// Scenario 2: Arrival at a destination whose parking lot is set back 35m from the nearest road.
    /// In previous implementations that only checked `coords.last`, the user entering the parking lot never
    /// triggered arrival because they were > 25m from `coords.last`. With dual-point arrival, arrival triggers cleanly!
    func testT4_SetbackParkingLotArrivalDualPointDetection() async throws {
        let (coords, steps, roadEnd, destPin, userArrival) = TestGeometries.makeSetbackDestinationScenario()
        
        // 1. User drives along Cushman St to the end of the road
        var currentStep = 0
        var currentCoord = 1
        var hasAnnounced = false
        var spoken: [(text: String, stepId: Int?)] = []
        
        let atRoadMid = OpaqueTelemetryEngine.updateStepForLiveLocation(
            userCoord: coords[1],
            coords: coords,
            steps: steps,
            currentStepIndex: &currentStep,
            currentCoordIndex: &currentCoord,
            selectedCoordinate: destPin,
            hasAnnouncedAdvanceTurn: &hasAnnounced,
            spokenInstructions: &spoken
        )
        assertFalse(atRoadMid, "Not yet arrived at mid-road")
        
        // 2. User turns off Cushman St into the commercial setback parking lot (userArrival is near destPin, but 30m away from roadEnd)
        let distToRoadEnd = OpaqueTelemetryEngine.segmentDistanceMeters(p1: userArrival, p2: roadEnd)
        let distToDestPin = OpaqueTelemetryEngine.segmentDistanceMeters(p1: userArrival, p2: destPin)
        assertTrue(distToRoadEnd >= 25.0, "User is >= 25m from road endpoint (\(distToRoadEnd)m)")
        assertTrue(distToDestPin < 15.0, "User is within 15m of destination pin (\(distToDestPin)m)")
        
        // 3. Telemetry updates with live location at userArrival
        let atParkingLot = OpaqueTelemetryEngine.updateStepForLiveLocation(
            userCoord: userArrival,
            coords: coords,
            steps: steps,
            currentStepIndex: &currentStep,
            currentCoordIndex: &currentCoord,
            selectedCoordinate: destPin,
            hasAnnouncedAdvanceTurn: &hasAnnounced,
            spokenInstructions: &spoken
        )
        
        assertTrue(atParkingLot, "Dual-point arrival MUST trigger arrival when approaching setback destination pin!")
        assertTrue(spoken.contains(where: { $0.text.contains("arrived at your destination") }), "Arrival announcement must be spoken")
    }
}
