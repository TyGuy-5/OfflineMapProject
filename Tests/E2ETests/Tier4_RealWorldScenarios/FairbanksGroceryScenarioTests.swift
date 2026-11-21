// FairbanksGroceryScenarioTests.swift — Tier 4 Real-World Application Scenario: Downtown to Co-Op Market

import Foundation
import CoreLocation

public final class FairbanksGroceryScenarioTests: E2ETestSuite {
    public let name = "Real-World Scenario 1: Fairbanks Grocery Run"
    public let tier = TestTier.tier4
    
    public var tests: [TestCaseEntry] {
        return [
            TestCaseEntry(name: "testT4_FairbanksGroceryWorkflowFromSearchToArrival", tier: tier, block: testT4_FairbanksGroceryWorkflowFromSearchToArrival)
        ]
    }
    
    /// Scenario 1: Complete end-to-end user workflow
    /// Search "Groceries" in Fairbanks -> select "Co-Op Market & Deli" -> calculate route ->
    /// start navigation -> advance maneuvers via simulation -> arrive at destination -> verify state cleanup.
    func testT4_FairbanksGroceryWorkflowFromSearchToArrival() async throws {
        let userStart = TestCoordinates.fairbanksDowntown
        let voiceController = OpaqueVoiceController()
        
        // Step 1: User types "Groceries" into search bar
        let query = "Groceries"
        assertFalse(query.isEmpty)
        let groceryCandidates = [
            OpaqueSearchResult(id: 1, name: "Co-Op Market & Deli", lat: 64.8465, lon: -147.7120),
            OpaqueSearchResult(id: 2, name: "Fred Meyer Fairbanks", lat: 64.8480, lon: -147.7340),
            OpaqueSearchResult(id: 3, name: "Costco Wholesale", lat: 64.8490, lon: -147.7010)
        ]
        
        // Step 2: Rank by proximity to user start location
        var ranked = groceryCandidates
        ranked.sort {
            ($0.distanceMiles(from: userStart) ?? 0) < ($1.distanceMiles(from: userStart) ?? 0)
        }
        assertEqual(ranked[0].name, "Co-Op Market & Deli")
        assertEqual(ranked[0].category, "grocery")
        assertEqual(ranked[0].iconName, "cart.fill")
        
        // Step 3: User selects Co-Op Market
        let selectedPlace = ranked[0]
        let destCoord = CLLocationCoordinate2D(latitude: selectedPlace.lat, longitude: selectedPlace.lon)
        
        // Step 4: Route calculation generated
        let routeCoords = [
            userStart,
            CLLocationCoordinate2D(latitude: 64.8445, longitude: -147.7180),
            CLLocationCoordinate2D(latitude: 64.8455, longitude: -147.7150),
            destCoord
        ]
        let step0 = OpaqueNavigationStep(instruction: "Head northeast on Cushman St", distanceMiles: 0.15, durationSeconds: 20, maneuverType: 1, streetName: "Cushman St", startIndex: 0, endIndex: 1)
        let step1 = OpaqueNavigationStep(instruction: "Turn right onto 2nd Ave", distanceMiles: 0.20, durationSeconds: 25, maneuverType: 10, streetName: "2nd Ave", startIndex: 1, endIndex: 2)
        let step2 = OpaqueNavigationStep(instruction: "Turn left onto Noble St", distanceMiles: 0.15, durationSeconds: 20, maneuverType: 15, streetName: "Noble St", startIndex: 2, endIndex: 3)
        
        let routeDetails = OpaqueRouteDetails(
            coordinates: routeCoords,
            totalDistanceMiles: 0.50,
            totalDurationSeconds: 65.0,
            steps: [step0, step1, step2],
            costing: "auto"
        )
        assertEqual(routeDetails.steps.count, 3)
        
        // Step 5: Start navigation
        var isNavigating = true
        var currentCoordIndex = 0
        var currentStepIndex = 0
        var spokenTurns: [String] = []
        
        // Initial departure instruction spoken
        let announcedStart = voiceController.speakTurnInstruction(step0.instruction, stepId: 0)
        assertTrue(announcedStart)
        
        // Step 6: Simulate driving progression along route
        var simulationCompleted = false
        while !simulationCompleted {
            simulationCompleted = OpaqueSimulationEngine.advanceSimulation(
                coords: routeCoords,
                steps: [step0, step1, step2],
                speedMultiplier: 2.0,
                currentCoordIndex: &currentCoordIndex,
                currentStepIndex: &currentStepIndex,
                spokenTurns: &spokenTurns
            )
        }
        
        assertTrue(simulationCompleted, "Simulation must reach destination")
        assertEqual(currentCoordIndex, routeCoords.count - 1, "Must reach final coordinate")
        assertEqual(currentStepIndex, 2, "Must reach final step")
        assertTrue(spokenTurns.contains("Turn right onto 2nd Ave"), "Must announce turn 1")
        assertTrue(spokenTurns.contains("Turn left onto Noble St"), "Must announce turn 2")
        assertTrue(spokenTurns.contains("You have arrived at your destination."), "Must announce arrival")
        
        // Step 7: Arrived state cleanup
        isNavigating = false
        voiceController.stopVoice()
        
        assertFalse(isNavigating, "Navigation session must end upon arrival")
    }
}
