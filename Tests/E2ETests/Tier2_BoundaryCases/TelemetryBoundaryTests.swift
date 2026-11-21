// TelemetryBoundaryTests.swift — Tier 2 Boundary Cases: Polyline Boundaries & Telemetry Corner Cases

import Foundation
import CoreLocation

public final class TelemetryBoundaryTests: E2ETestSuite {
    public let name = "Telemetry Polyline & Boundary Suite"
    public let tier = TestTier.tier2
    
    public var tests: [TestCaseEntry] {
        return [
            TestCaseEntry(name: "testT2_ZeroAndSingleCoordinatePolylineSafety", tier: tier, block: testT2_ZeroAndSingleCoordinatePolylineSafety),
            TestCaseEntry(name: "testT2_MinimalTwoVertexRouteTelemetryCountdown", tier: tier, block: testT2_MinimalTwoVertexRouteTelemetryCountdown),
            TestCaseEntry(name: "testT2_ExactSwitchbackBoundaryClampingAtEndIndexPlusTwo", tier: tier, block: testT2_ExactSwitchbackBoundaryClampingAtEndIndexPlusTwo),
            TestCaseEntry(name: "testT2_EquidistantPointBetweenTwoSegmentsResolvesDeterministically", tier: tier, block: testT2_EquidistantPointBetweenTwoSegmentsResolvesDeterministically),
            TestCaseEntry(name: "testT2_UserPositionFarBeyondDestinationDoesNotReopenStepDistance", tier: tier, block: testT2_UserPositionFarBeyondDestinationDoesNotReopenStepDistance)
        ]
    }
    
    /// 0-coordinate and 1-coordinate degenerate polylines should not crash or divide by zero
    func testT2_ZeroAndSingleCoordinatePolylineSafety() async throws {
        let (stepDist0, routeDist0, dur0) = OpaqueTelemetryEngine.calculateTelemetry(
            userCoord: TestCoordinates.fairbanksDowntown,
            coordIndex: 0,
            coords: [],
            steps: [],
            currentStepIndex: 0,
            totalDistanceMiles: 0,
            totalDurationSeconds: 0
        )
        assertEqual(stepDist0, 0.0)
        assertEqual(routeDist0, 0.0)
        assertEqual(dur0, 0.0)
        
        let singleCoord = [TestCoordinates.fairbanksDowntown]
        let (stepDist1, routeDist1, dur1) = OpaqueTelemetryEngine.calculateTelemetry(
            userCoord: TestCoordinates.fairbanksDowntown,
            coordIndex: 0,
            coords: singleCoord,
            steps: [],
            currentStepIndex: 0,
            totalDistanceMiles: 0,
            totalDurationSeconds: 0
        )
        assertEqual(stepDist1, 0.0)
        assertEqual(routeDist1, 0.0)
        assertEqual(dur1, 0.0)
    }
    
    /// Minimal 2-vertex route countdown
    func testT2_MinimalTwoVertexRouteTelemetryCountdown() async throws {
        let p1 = CLLocationCoordinate2D(latitude: 64.8400, longitude: -147.7200)
        let p2 = CLLocationCoordinate2D(latitude: 64.8410, longitude: -147.7200)
        let step = OpaqueNavigationStep(instruction: "Drive straight", distanceMiles: 0.07, durationSeconds: 10, maneuverType: 1, streetName: "Cushman", startIndex: 0, endIndex: 1)
        
        let (stepDistAtStart, _, _) = OpaqueTelemetryEngine.calculateTelemetry(
            userCoord: p1,
            coordIndex: 0,
            coords: [p1, p2],
            steps: [step],
            currentStepIndex: 0,
            totalDistanceMiles: 0.07,
            totalDurationSeconds: 10
        )
        assertTrue(stepDistAtStart > 0.05, "Step distance at start should be ~0.07 miles")
        
        let (stepDistAtEnd, _, _) = OpaqueTelemetryEngine.calculateTelemetry(
            userCoord: p2,
            coordIndex: 1,
            coords: [p1, p2],
            steps: [step],
            currentStepIndex: 0,
            totalDistanceMiles: 0.07,
            totalDurationSeconds: 10
        )
        assertEqual(stepDistAtEnd, 0.0, "Step distance at end must be 0.0")
    }
    
    /// Switchback boundary: Exact limit at endIndex + 2
    func testT2_ExactSwitchbackBoundaryClampingAtEndIndexPlusTwo() async throws {
        let (coords, steps) = TestGeometries.makeSwitchbackRoute()
        let step0End = steps[0].endIndex // 10
        let maxAllowedIndex = step0End + 2 // 12
        
        var currentStep = 0
        var currentCoord = 8
        var hasAnnounced = false
        var spoken: [(text: String, stepId: Int?)] = []
        
        // Feed user coord at index 12 (within boundary)
        _ = OpaqueTelemetryEngine.updateStepForLiveLocation(
            userCoord: coords[12],
            coords: coords,
            steps: steps,
            currentStepIndex: &currentStep,
            currentCoordIndex: &currentCoord,
            selectedCoordinate: coords.last,
            hasAnnouncedAdvanceTurn: &hasAnnounced,
            spokenInstructions: &spoken
        )
        assertTrue(currentCoord <= maxAllowedIndex, "Coord index must not exceed stepEnd + 2")
    }
    
    /// Equidistant point between two adjacent segments resolves without NaN or crash
    func testT2_EquidistantPointBetweenTwoSegmentsResolvesDeterministically() async throws {
        let p1 = CLLocationCoordinate2D(latitude: 64.8400, longitude: -147.7200)
        let p2 = CLLocationCoordinate2D(latitude: 64.8410, longitude: -147.7200)
        let p3 = CLLocationCoordinate2D(latitude: 64.8420, longitude: -147.7200)
        
        let userMid = CLLocationCoordinate2D(latitude: 64.8410, longitude: -147.7210) // 100m west of p2
        let d1 = OpaqueTelemetryEngine.distanceToSegmentMeters(p: userMid, a: p1, b: p2)
        let d2 = OpaqueTelemetryEngine.distanceToSegmentMeters(p: userMid, a: p2, b: p3)
        
        assertFalse(d1.isNaN, "Distance 1 must not be NaN")
        assertFalse(d2.isNaN, "Distance 2 must not be NaN")
        assertInDelta(d1, d2, delta: 0.1, "Equidistant point must have equal distances to adjacent segments")
    }
    
    /// User location far beyond route destination (> 500m past polyline end) strictly zeroes remaining step distance
    func testT2_UserPositionFarBeyondDestinationDoesNotReopenStepDistance() async throws {
        let (coords, steps) = TestGeometries.makeSwitchbackRoute()
        let lastCoord = coords.last!
        // User moves 500 meters further past route end
        let userPastEnd = CLLocationCoordinate2D(latitude: lastCoord.latitude - 0.005, longitude: lastCoord.longitude)
        
        let (stepDist, routeDist, remainingDur) = OpaqueTelemetryEngine.calculateTelemetry(
            userCoord: userPastEnd,
            coordIndex: coords.count - 1,
            coords: coords,
            steps: steps,
            currentStepIndex: steps.count - 1,
            totalDistanceMiles: 0.75,
            totalDurationSeconds: 95.0
        )
        
        assertEqual(stepDist, 0.0, "Remaining step distance past destination must remain strictly 0.0")
        assertEqual(routeDist, 0.0, "Remaining route distance past destination must evaluate to 0.0")
        assertEqual(remainingDur, 0.0, "Remaining duration past destination must evaluate to 0.0")
    }
}
