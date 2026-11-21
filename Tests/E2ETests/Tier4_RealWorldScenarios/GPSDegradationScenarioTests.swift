// GPSDegradationScenarioTests.swift — Tier 4 Real-World Application Scenario: Commute & Mountain Canyon GPS Loss

import Foundation
import CoreLocation

public final class GPSDegradationScenarioTests: E2ETestSuite {
    public let name = "Real-World Scenarios 4 & 5: Commute & Canyon GPS Loss"
    public let tier = TestTier.tier4
    
    public var tests: [TestCaseEntry] {
        return [
            TestCaseEntry(name: "testT4_HighSpeedRuralCommuteWithUnitSwitching", tier: tier, block: testT4_HighSpeedRuralCommuteWithUnitSwitching),
            TestCaseEntry(name: "testT4_MountainCanyonDegradationAndSignalRecovery", tier: tier, block: testT4_MountainCanyonDegradationAndSignalRecovery)
        ]
    }
    
    /// Scenario 4: User drives a high-speed rural highway commute (Parks Highway) at 5x simulation speed.
    /// Toggles unit system from imperial (mph) to metric (km/h) mid-commute while voice announcements occur.
    func testT4_HighSpeedRuralCommuteWithUnitSwitching() async throws {
        var coords: [CLLocationCoordinate2D] = []
        for i in 0...30 {
            coords.append(CLLocationCoordinate2D(latitude: 64.840 + Double(i) * 0.001, longitude: -147.720))
        }
        let step0 = OpaqueNavigationStep(instruction: "Take ramp onto Parks Highway", distanceMiles: 0.5, durationSeconds: 30, maneuverType: 8, streetName: "Parks Highway", startIndex: 0, endIndex: 10)
        let step1 = OpaqueNavigationStep(instruction: "Continue south for 10 miles", distanceMiles: 1.0, durationSeconds: 60, maneuverType: 1, streetName: "Parks Highway", startIndex: 10, endIndex: 25)
        let step2 = OpaqueNavigationStep(instruction: "Take exit toward Nenana", distanceMiles: 0.5, durationSeconds: 30, maneuverType: 20, streetName: "Nenana Exit", startIndex: 25, endIndex: 30)
        
        let voiceController = OpaqueVoiceController()
        var currentCoord = 0
        var currentStep = 0
        var spokenTurns: [String] = []
        var useMetric = false
        
        // 1. Start on highway in Imperial mode
        _ = voiceController.speakTurnInstruction(step0.instruction, stepId: 0)
        assertTrue(step0.formattedDistance(useMetric: useMetric).contains("mi"))
        
        // 2. Advance 2 ticks at 5x speed
        for _ in 0..<2 {
            _ = OpaqueSimulationEngine.advanceSimulation(
                coords: coords,
                steps: [step0, step1, step2],
                speedMultiplier: 5.0,
                currentCoordIndex: &currentCoord,
                currentStepIndex: &currentStep,
                spokenTurns: &spokenTurns
            )
        }
        assertEqual(currentCoord, 10)
        assertEqual(currentStep, 1, "Should transition to Step 1 on highway")
        
        // 3. User flips to metric mid-commute
        useMetric = true
        let metricFormatted = step1.formattedDistance(useMetric: useMetric)
        assertTrue(metricFormatted.contains("km"), "Step distance formats in km after switch: \(metricFormatted)")
        
        // 4. Continue at 5x speed to Nenana exit
        while currentCoord < coords.count - 1 {
            _ = OpaqueSimulationEngine.advanceSimulation(
                coords: coords,
                steps: [step0, step1, step2],
                speedMultiplier: 5.0,
                currentCoordIndex: &currentCoord,
                currentStepIndex: &currentStep,
                spokenTurns: &spokenTurns
            )
        }
        assertEqual(currentStep, 2, "Reached final exit maneuver")
        assertTrue(spokenTurns.contains("Take exit toward Nenana"), "Announced Nenana exit")
    }
    
    /// Scenario 5: User navigates through a mountain canyon where GPS signal degrades to 90m for several seconds.
    /// Speedometer zeroes, stationary state flags, and once signal recovers (6m), smooth tracking resumes.
    func testT4_MountainCanyonDegradationAndSignalRecovery() async throws {
        let observer = OpaqueLocationObserver()
        let speedMps = 24.5 // ~55 mph
        
        // 1. Cruising into canyon with solid GPS fix
        observer.processLocationFix(horizontalAccuracy: 6.0, rawSpeedMps: speedMps, ageSeconds: 1.0)
        assertFalse(observer.isGpsSignalLow)
        assertFalse(observer.isStationary)
        assertTrue(observer.smoothedSpeedMph > 50)
        
        // 2. Steep rock walls degrade GPS accuracy to 90m
        for _ in 0..<5 {
            observer.processLocationFix(horizontalAccuracy: 90.0, rawSpeedMps: speedMps, ageSeconds: 1.0)
            assertTrue(observer.isGpsSignalLow, "Low GPS signal warning must be active")
            assertEqual(observer.smoothedSpeedMph, 0, "Speedometer must be 0 mph while in canyon")
            assertTrue(observer.isStationary, "Must report stationary while degraded")
        }
        
        // 3. Vehicle emerges from canyon into open valley (accuracy improves to 5.5m)
        observer.processLocationFix(horizontalAccuracy: 5.5, rawSpeedMps: speedMps, ageSeconds: 1.0)
        assertFalse(observer.isGpsSignalLow, "Low GPS warning must clear")
        assertFalse(observer.isStationary, "Vehicle resumes movement")
        assertTrue(observer.smoothedSpeedMph > 50, "Speedometer restores to ~55 mph")
    }
}
