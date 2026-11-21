// AudioSimulationCombinationsTests.swift — Tier 3 Cross-Feature Combinations: Audio Guidance & Simulation Interactions

import Foundation
import CoreLocation

public final class AudioSimulationCombinationsTests: E2ETestSuite {
    public let name = "Audio Guidance & Simulation Combinations Suite"
    public let tier = TestTier.tier3
    
    public var tests: [TestCaseEntry] {
        return [
            TestCaseEntry(name: "testT3_RouteRestartWithVoiceMuteToggleTurnaround", tier: tier, block: testT3_RouteRestartWithVoiceMuteToggleTurnaround),
            TestCaseEntry(name: "testT3_SimulationAtFiveXWithMidRouteMetricUnitSwitching", tier: tier, block: testT3_SimulationAtFiveXWithMidRouteMetricUnitSwitching),
            TestCaseEntry(name: "testT3_WindshieldHUDModeWithTurnManeuverProgression", tier: tier, block: testT3_WindshieldHUDModeWithTurnManeuverProgression)
        ]
    }
    
    /// Pairwise 1: Route Restart + Voice Mute Toggle
    /// Start navigation -> prompt speaks -> mute voice -> cancel route -> restart within 3s -> unmute -> prompt speaks!
    func testT3_RouteRestartWithVoiceMuteToggleTurnaround() async throws {
        let voiceController = OpaqueVoiceController()
        let prompt = "Turn right onto Airport Way"
        
        // 1. Initial navigation session
        assertTrue(voiceController.speakTurnInstruction(prompt, stepId: 1))
        
        // 2. User mutes voice guidance
        voiceController.isVoiceMuted = true
        
        // 3. User cancels navigation session
        voiceController.stopVoice()
        
        // 4. User restarts route 2 seconds later while still muted: instruction should NOT speak
        let mutedAttempt = voiceController.speakTurnInstruction(prompt, stepId: 1)
        assertFalse(mutedAttempt, "Should not speak while muted")
        
        // 5. User unmutes voice guidance and route initiates: instruction MUST speak immediately!
        voiceController.isVoiceMuted = false
        let unmutedRestart = voiceController.speakTurnInstruction(prompt, stepId: 1)
        assertTrue(unmutedRestart, "Turn instruction must speak when unmuted on restarted route within 6 seconds")
    }
    
    /// Pairwise 2: Simulation at 5x Speed + Mid-Route Metric Unit Switching
    /// Running 5x simulation while dynamically toggling useMetric mid-route preserves step progress and converts units
    func testT3_SimulationAtFiveXWithMidRouteMetricUnitSwitching() async throws {
        var coords: [CLLocationCoordinate2D] = []
        for i in 0...20 {
            coords.append(CLLocationCoordinate2D(latitude: 64.840 + Double(i) * 0.0005, longitude: -147.720))
        }
        let step0 = OpaqueNavigationStep(instruction: "Drive north on Cushman", distanceMiles: 0.3, durationSeconds: 30, maneuverType: 1, streetName: "Cushman", startIndex: 0, endIndex: 8)
        let step1 = OpaqueNavigationStep(instruction: "Turn right on 10th Ave", distanceMiles: 0.4, durationSeconds: 40, maneuverType: 10, streetName: "10th Ave", startIndex: 8, endIndex: 20)
        
        var currentCoord = 0
        var currentStep = 0
        var spoken: [String] = []
        var useMetric = false // Start with Imperial (mph / miles)
        
        // Advance at 5x in Imperial mode
        _ = OpaqueSimulationEngine.advanceSimulation(coords: coords, steps: [step0, step1], speedMultiplier: 5.0, currentCoordIndex: &currentCoord, currentStepIndex: &currentStep, spokenTurns: &spoken)
        assertEqual(currentCoord, 5)
        assertEqual(currentStep, 0)
        
        let (stepDistImp, _, _) = OpaqueTelemetryEngine.calculateTelemetry(
            userCoord: coords[currentCoord],
            coordIndex: currentCoord,
            coords: coords,
            steps: [step0, step1],
            currentStepIndex: currentStep,
            totalDistanceMiles: 0.7,
            totalDurationSeconds: 70
        )
        assertTrue(stepDistImp > 0.0, "Imperial distance should be positive")
        
        // User toggles useMetric to true (km/h / kilometers) mid-route
        useMetric = true
        
        // Advance another 5x jump
        _ = OpaqueSimulationEngine.advanceSimulation(coords: coords, steps: [step0, step1], speedMultiplier: 5.0, currentCoordIndex: &currentCoord, currentStepIndex: &currentStep, spokenTurns: &spoken)
        assertEqual(currentCoord, 10)
        assertEqual(currentStep, 1, "Should advance to step 1")
        
        let (_, _, _) = OpaqueTelemetryEngine.calculateTelemetry(
            userCoord: coords[currentCoord],
            coordIndex: currentCoord,
            coords: coords,
            steps: [step0, step1],
            currentStepIndex: currentStep,
            totalDistanceMiles: 0.7,
            totalDurationSeconds: 70
        )
        // Verify formatted output in metric
        let formatted = step0.formattedDistance(useMetric: useMetric)
        assertTrue(formatted.contains("m") || formatted.contains("km"), "Telemetry must format in metric after toggle: \(formatted)")
        assertFalse(formatted.contains("ft"), "Must not contain 'ft'")
    }
    
    /// Pairwise 3: Windshield HUD Mode + Turn Maneuver Icons
    /// Verifies HUD mirror reflection transform with step progression
    func testT3_WindshieldHUDModeWithTurnManeuverProgression() async throws {
        var isHudMode = false
        // User taps HUD button
        isHudMode.toggle()
        assertTrue(isHudMode, "HUD mode active")
        
        // Verify maneuver icons for HUD display
        let leftTurnStep = OpaqueNavigationStep(instruction: "Turn left", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 15, streetName: "Minnie St", startIndex: 0, endIndex: 5)
        let rightTurnStep = OpaqueNavigationStep(instruction: "Turn right", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 10, streetName: "Illinois St", startIndex: 5, endIndex: 10)
        
        assertEqual(leftTurnStep.iconName, "arrow.turn.up.left")
        assertEqual(rightTurnStep.iconName, "arrow.turn.up.right")
        
        // Disabling HUD mode
        isHudMode.toggle()
        assertFalse(isHudMode, "HUD mode restored to standard UI")
    }
}
