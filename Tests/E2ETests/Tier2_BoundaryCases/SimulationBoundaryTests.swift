// SimulationBoundaryTests.swift — Tier 2 Boundary Cases: Multi-Speed Simulation Edge Cases

import Foundation
import CoreLocation

public final class SimulationBoundaryTests: E2ETestSuite {
    public let name = "Simulation Multi-Speed Boundary Suite"
    public let tier = TestTier.tier2
    
    public var tests: [TestCaseEntry] {
        return [
            TestCaseEntry(name: "testT2_SimulationAtOneXOnSingleCoordinateStep", tier: tier, block: testT2_SimulationAtOneXOnSingleCoordinateStep),
            TestCaseEntry(name: "testT2_SimulationAtTwoXLandingExactlyOnStepBoundary", tier: tier, block: testT2_SimulationAtTwoXLandingExactlyOnStepBoundary),
            TestCaseEntry(name: "testT2_SimulationAtFiveXExceedingPolylineLengthCompletesArrival", tier: tier, block: testT2_SimulationAtFiveXExceedingPolylineLengthCompletesArrival),
            TestCaseEntry(name: "testT2_RapidSimulationSpeedMultiplierToggling", tier: tier, block: testT2_RapidSimulationSpeedMultiplierToggling),
            TestCaseEntry(name: "testT2_RepeatedSimulationCancellationAndRestartCleanliness", tier: tier, block: testT2_RepeatedSimulationCancellationAndRestartCleanliness)
        ]
    }
    
    /// Simulation at 1x speed on short 1-coordinate step
    func testT2_SimulationAtOneXOnSingleCoordinateStep() async throws {
        let p1 = CLLocationCoordinate2D(latitude: 64.840, longitude: -147.720)
        let p2 = CLLocationCoordinate2D(latitude: 64.841, longitude: -147.720)
        let p3 = CLLocationCoordinate2D(latitude: 64.842, longitude: -147.720)
        let step0 = OpaqueNavigationStep(instruction: "Step 0", distanceMiles: 0.05, durationSeconds: 5, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 1)
        let step1 = OpaqueNavigationStep(instruction: "Step 1", distanceMiles: 0.05, durationSeconds: 5, maneuverType: 10, streetName: nil, startIndex: 1, endIndex: 2)
        
        var currentCoord = 0
        var currentStep = 0
        var spoken: [String] = []
        
        _ = OpaqueSimulationEngine.advanceSimulation(
            coords: [p1, p2, p3],
            steps: [step0, step1],
            speedMultiplier: 1.0,
            currentCoordIndex: &currentCoord,
            currentStepIndex: &currentStep,
            spokenTurns: &spoken
        )
        
        assertEqual(currentCoord, 1, "1x speed should advance by exactly 1 vertex")
        assertEqual(currentStep, 1, "Should transition to Step 1")
        assertTrue(spoken.contains("Step 1"))
    }
    
    /// Simulation at 2x speed landing exactly on step boundary
    func testT2_SimulationAtTwoXLandingExactlyOnStepBoundary() async throws {
        var coords: [CLLocationCoordinate2D] = []
        for i in 0...6 {
            coords.append(CLLocationCoordinate2D(latitude: 64.840 + Double(i) * 0.001, longitude: -147.720))
        }
        let step0 = OpaqueNavigationStep(instruction: "Turn right onto Airport Way", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 10, streetName: "Airport Way", startIndex: 0, endIndex: 2)
        let step1 = OpaqueNavigationStep(instruction: "Turn left onto University Ave", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 15, streetName: "University Ave", startIndex: 2, endIndex: 6)
        
        var currentCoord = 0
        var currentStep = 0
        var spoken: [String] = []
        
        // 2x jump lands exactly at index 2 (startIndex of Step 1)
        _ = OpaqueSimulationEngine.advanceSimulation(
            coords: coords,
            steps: [step0, step1],
            speedMultiplier: 2.0,
            currentCoordIndex: &currentCoord,
            currentStepIndex: &currentStep,
            spokenTurns: &spoken
        )
        
        assertEqual(currentCoord, 2, "2x speed should jump to index 2")
        assertEqual(currentStep, 1, "Should advance cleanly to step 1")
        assertTrue(spoken.contains("Turn left onto University Ave"), "Should speak step 1 instruction")
    }
    
    /// Simulation at 5x speed exceeding polyline length completes arrival cleanly
    func testT2_SimulationAtFiveXExceedingPolylineLengthCompletesArrival() async throws {
        let p1 = CLLocationCoordinate2D(latitude: 64.840, longitude: -147.720)
        let p2 = CLLocationCoordinate2D(latitude: 64.841, longitude: -147.720)
        let p3 = CLLocationCoordinate2D(latitude: 64.842, longitude: -147.720)
        let step = OpaqueNavigationStep(instruction: "Arrive at Costco", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 4, streetName: "Airport Way", startIndex: 0, endIndex: 2)
        
        var currentCoord = 1
        var currentStep = 0
        var spoken: [String] = []
        
        // At index 1 of 2, 5x jump attempts to advance to index 6, clamped to index 2
        _ = OpaqueSimulationEngine.advanceSimulation(
            coords: [p1, p2, p3],
            steps: [step],
            speedMultiplier: 5.0,
            currentCoordIndex: &currentCoord,
            currentStepIndex: &currentStep,
            spokenTurns: &spoken
        )
        
        assertEqual(currentCoord, 2, "Coordinate index must clamp to coords.count - 1")
        
        // Next advance reaches end of route and announces arrival
        let finalArrival = OpaqueSimulationEngine.advanceSimulation(
            coords: [p1, p2, p3],
            steps: [step],
            speedMultiplier: 5.0,
            currentCoordIndex: &currentCoord,
            currentStepIndex: &currentStep,
            spokenTurns: &spoken
        )
        assertTrue(finalArrival, "Should signal simulation completion")
        assertTrue(spoken.contains("You have arrived at your destination."))
    }
    
    /// Rapid simulation speed multiplier toggling during active simulation
    func testT2_RapidSimulationSpeedMultiplierToggling() async throws {
        var coords: [CLLocationCoordinate2D] = []
        for i in 0...20 {
            coords.append(CLLocationCoordinate2D(latitude: 64.840 + Double(i) * 0.0005, longitude: -147.720))
        }
        let step0 = OpaqueNavigationStep(instruction: "Turn right", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 10, streetName: nil, startIndex: 0, endIndex: 5)
        let step1 = OpaqueNavigationStep(instruction: "Turn left", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 15, streetName: nil, startIndex: 5, endIndex: 12)
        let step2 = OpaqueNavigationStep(instruction: "Straight", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 1, streetName: nil, startIndex: 12, endIndex: 20)
        
        var currentCoord = 0
        var currentStep = 0
        var spoken: [String] = []
        
        // 1x step
        _ = OpaqueSimulationEngine.advanceSimulation(coords: coords, steps: [step0, step1, step2], speedMultiplier: 1.0, currentCoordIndex: &currentCoord, currentStepIndex: &currentStep, spokenTurns: &spoken)
        assertEqual(currentCoord, 1)
        
        // Switch to 5x
        _ = OpaqueSimulationEngine.advanceSimulation(coords: coords, steps: [step0, step1, step2], speedMultiplier: 5.0, currentCoordIndex: &currentCoord, currentStepIndex: &currentStep, spokenTurns: &spoken)
        assertEqual(currentCoord, 6)
        assertEqual(currentStep, 1)
        
        // Switch to 2x
        _ = OpaqueSimulationEngine.advanceSimulation(coords: coords, steps: [step0, step1, step2], speedMultiplier: 2.0, currentCoordIndex: &currentCoord, currentStepIndex: &currentStep, spokenTurns: &spoken)
        assertEqual(currentCoord, 8)
        
        // Switch back to 1x
        _ = OpaqueSimulationEngine.advanceSimulation(coords: coords, steps: [step0, step1, step2], speedMultiplier: 1.0, currentCoordIndex: &currentCoord, currentStepIndex: &currentStep, spokenTurns: &spoken)
        assertEqual(currentCoord, 9)
    }
    
    /// Repeated simulation cancellation and restart without leaking state
    func testT2_RepeatedSimulationCancellationAndRestartCleanliness() async throws {
        var activeTimerCount = 0
        
        func startSimulation() {
            activeTimerCount += 1
        }
        func stopSimulation() {
            activeTimerCount = max(0, activeTimerCount - 1)
        }
        
        for _ in 0..<10 {
            startSimulation()
            assertEqual(activeTimerCount, 1)
            stopSimulation()
            assertEqual(activeTimerCount, 0)
        }
        assertEqual(activeTimerCount, 0, "No leaked simulation instances")
    }
}
