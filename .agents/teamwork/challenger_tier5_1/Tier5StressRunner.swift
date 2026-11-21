// Tier5StressRunner.swift
// Phase 2 (Adversarial Coverage Hardening — Tier 5) Comprehensive White-Box Test Harness
// Tests NavigationViewModel, RoutingService concurrency, and ContentView forwarding

import Foundation
import CoreLocation
import Combine
import SwiftUI

// MARK: - Color Formatter for Console Output
enum ConsoleColor {
    static let red = "\u{001B}[31m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let cyan = "\u{001B}[36m"
    static let bold = "\u{001B}[1m"
    static let reset = "\u{001B}[0m"
}

// MARK: - Runner Harness
@main
struct Tier5StressRunner {
    static var testsRun = 0
    static var testsPassed = 0
    static var testsFailed = 0

    static func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        if !condition() {
            print("  \(ConsoleColor.red)❌ FAIL [line \(line)]: \(message)\(ConsoleColor.reset)")
            testsFailed += 1
            fatalError("Assertion failed: \(message) at line \(line)")
        }
    }

    static func assertFalse(_ condition: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        assertTrue(!condition(), message, file: file, line: line)
    }

    static func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        assertTrue(a == b, "\(message) — Expected [\(b)], got [\(a)]", file: file, line: line)
    }

    static func assertEqualDouble(_ a: Double, _ b: Double, accuracy: Double = 0.0001, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        assertTrue(abs(a - b) <= accuracy, "\(message) — Expected [\(b)] ±\(accuracy), got [\(a)]", file: file, line: line)
    }

    static func assertNil<T>(_ a: T?, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        assertTrue(a == nil, "\(message) — Expected nil, got [\(String(describing: a))]", file: file, line: line)
    }

    static func assertNotNil<T>(_ a: T?, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        assertTrue(a != nil, "\(message) — Expected non-nil", file: file, line: line)
    }

    static func runTest(_ name: String, _ block: () throws -> Void) {
        testsRun += 1
        do {
            try block()
            testsPassed += 1
            print("  \(ConsoleColor.green)✅ PASS: \(name)\(ConsoleColor.reset)")
        } catch {
            testsFailed += 1
            print("  \(ConsoleColor.red)❌ FAIL: \(name) with error: \(error)\(ConsoleColor.reset)")
        }
    }

    static func runAsyncTest(_ name: String, _ block: () async throws -> Void) async {
        testsRun += 1
        do {
            try await block()
            testsPassed += 1
            print("  \(ConsoleColor.green)✅ PASS: \(name)\(ConsoleColor.reset)")
        } catch {
            testsFailed += 1
            print("  \(ConsoleColor.red)❌ FAIL: \(name) with error: \(error)\(ConsoleColor.reset)")
        }
    }

    @MainActor
    static func main() async {
        print("\n========================================================")
        print("🚀 PHASE 2: ADVERSARIAL COVERAGE HARDENING (TIER 5)")
        print("   Targeting: NavigationViewModel, RoutingService, ContentView")
        print("========================================================\n")

        // =================================================================
        // SUITE 1: NavigationViewModel Telemetry & Progression Edge Cases
        // =================================================================
        print("📦 Suite 1: NavigationViewModel Telemetry & Progression Hardening")

        // 1.1 Empty and Single-Coordinate Polylines
        runTest("testT5_01_EmptyAndSingleCoordinatePolylineSafety") {
            let vm = NavigationViewModel()
            let emptyDetails = RouteDetails(coordinates: [], totalDistanceMiles: 0.0, totalDurationSeconds: 0.0, steps: [])
            vm.routeDetails = emptyDetails
            vm.routeCoordinates = []
            vm.isNavigating = true

            // Empty polyline must return immediately without crash or mutation
            vm.updateCurrentStepForLiveLocation(NavigationViewModel.defaultAlaskaCoordinate, in: emptyDetails)
            vm.advanceSimulationStep()
            assertEqual(vm.currentCoordIndex, 0)
            assertEqual(vm.currentStepIndex, 0)

            // Single coordinate polyline
            let singleCoord = [NavigationViewModel.defaultAlaskaCoordinate]
            let singleDetails = RouteDetails(coordinates: singleCoord, totalDistanceMiles: 0.0, totalDurationSeconds: 0.0, steps: [])
            vm.routeDetails = singleDetails
            vm.routeCoordinates = singleCoord

            vm.updateCurrentStepForLiveLocation(NavigationViewModel.defaultAlaskaCoordinate, in: singleDetails)
            assertEqual(vm.remainingStepDistanceMiles, 0.0)
            assertEqual(vm.remainingRouteDistanceMiles, 0.0)

            // advanceSimulationStep with single coordinate triggers immediate arrival
            vm.advanceSimulationStep()
            assertFalse(vm.isNavigating, "Simulation on single-coordinate route must trigger destination arrival")
            assertNil(vm.routeDetails)
        }

        // 1.2 Switchback Clamping: Strict EndIndex + 2 Slack Enforcement
        runTest("testT5_02_SwitchbackSearchClampingAtEndIndexPlusTwo") {
            let vm = NavigationViewModel()
            // Switchback:
            // Step 0: indices 0..3 going north along lon -147.7200
            // Step 1: indices 4..7 going south along lon -147.7198 (approx 15m away)
            var coords: [CLLocationCoordinate2D] = []
            for i in 0...3 {
                coords.append(CLLocationCoordinate2D(latitude: 64.8400 + Double(i) * 0.001, longitude: -147.7200))
            }
            for i in 4...7 {
                coords.append(CLLocationCoordinate2D(latitude: 64.8430 - Double(i - 4) * 0.001, longitude: -147.7198))
            }
            let step0 = NavigationStep(instruction: "Go north", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 1, streetName: "North Way", startIndex: 0, endIndex: 3)
            let step1 = NavigationStep(instruction: "Turn south", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 2, streetName: "South Way", startIndex: 3, endIndex: 7)

            let details = RouteDetails(coordinates: coords, totalDistanceMiles: 0.4, totalDurationSeconds: 40, steps: [step0, step1])
            vm.routeDetails = details
            vm.routeCoordinates = coords
            vm.isNavigating = true
            vm.currentStepIndex = 0
            vm.currentCoordIndex = 1

            // User is near vertex 1, only 15m from vertex 6 on the return leg
            let userPos = CLLocationCoordinate2D(latitude: 64.8410, longitude: -147.7200)
            vm.updateCurrentStepForLiveLocation(userPos, in: details)

            assertEqual(vm.currentStepIndex, 0, "Step must remain 0 on switchback")
            assertTrue(vm.currentCoordIndex <= step0.endIndex + 2, "Coordinate search must clamp within Step 0 endIndex + 2 (<= 5)")
            assertTrue(vm.currentCoordIndex < 6, "Must not jump to return leg vertex 6")
            vm.endNavigation()
        }

        // 1.3 Monotonic Telemetry Distance Countdown and Zero Reversal
        runTest("testT5_03_MonotonicTelemetryCountdownAndZeroReversal") {
            let vm = NavigationViewModel()
            let p0 = CLLocationCoordinate2D(latitude: 64.8400, longitude: -147.7200)
            let p1 = CLLocationCoordinate2D(latitude: 64.8410, longitude: -147.7200)
            let p2 = CLLocationCoordinate2D(latitude: 64.8420, longitude: -147.7200)
            let p3 = CLLocationCoordinate2D(latitude: 64.8430, longitude: -147.7200)
            let p4 = CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7200)
            let coords = [p0, p1, p2, p3, p4]

            let step = NavigationStep(instruction: "Straight", distanceMiles: 0.4, durationSeconds: 40, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 2)
            let details = RouteDetails(coordinates: coords, totalDistanceMiles: 0.4, totalDurationSeconds: 40, steps: [step])
            vm.routeDetails = details
            vm.currentStepIndex = 0

            var prevStepDist = Double.greatestFiniteMagnitude
            var prevRouteDist = Double.greatestFiniteMagnitude

            // Check progression through indices 0 to 4
            for (idx, pt) in coords.enumerated() {
                vm.updateNavigationTelemetry(at: pt, coordIndex: idx, in: details)
                let stepDist = vm.remainingStepDistanceMiles
                let routeDist = vm.remainingRouteDistanceMiles

                if idx <= 2 {
                    assertTrue(stepDist <= prevStepDist + 0.0001, "Step distance must decrease monotonically before stepEnd (idx \(idx))")
                    prevStepDist = stepDist
                } else {
                    assertEqual(stepDist, 0.0, "Step distance must evaluate strictly to 0.0 past stepEnd (idx \(idx))")
                }

                assertTrue(routeDist <= prevRouteDist + 0.0001, "Route distance must decrease monotonically")
                prevRouteDist = routeDist
            }
            assertEqual(vm.remainingRouteDistanceMiles, 0.0, "Route distance at final vertex must be 0.0")
            assertEqual(vm.remainingRouteDurationSeconds, 0.0, "Remaining duration at final vertex must be 0.0")
        }

        // 1.4 Multi-Speed Simulation: 1x, 2x, 5x, 10x, and Multi-Maneuver Traversal
        runTest("testT5_04_MultiSpeedSimulationLoopIntermediateManeuvers") {
            let vm = NavigationViewModel()
            var coords: [CLLocationCoordinate2D] = []
            for i in 0..<30 {
                coords.append(CLLocationCoordinate2D(latitude: 64.84 + Double(i) * 0.001, longitude: -147.72))
            }
            let step0 = NavigationStep(instruction: "Turn 0", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 2)
            let step1 = NavigationStep(instruction: "Turn 1", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 1, streetName: nil, startIndex: 2, endIndex: 4)
            let step2 = NavigationStep(instruction: "Turn 2", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 1, streetName: nil, startIndex: 4, endIndex: 6)
            let step3 = NavigationStep(instruction: "Turn 3", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 1, streetName: nil, startIndex: 6, endIndex: 8)
            let step4 = NavigationStep(instruction: "Turn 4", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 1, streetName: nil, startIndex: 8, endIndex: 10)
            let step5 = NavigationStep(instruction: "Straight", distanceMiles: 1.0, durationSeconds: 100, maneuverType: 1, streetName: nil, startIndex: 10, endIndex: 29)

            let details = RouteDetails(
                coordinates: coords,
                totalDistanceMiles: 1.5,
                totalDurationSeconds: 150,
                steps: [step0, step1, step2, step3, step4, step5]
            )
            vm.routeDetails = details
            vm.routeCoordinates = coords
            vm.isNavigating = true
            vm.isSimulating = true
            vm.currentCoordIndex = 0
            vm.currentStepIndex = 0

            // 1.4a: 10x speed multiplier leap from index 0 -> index 10
            // Spans step0, step1, step2, step3, step4, landing at step5
            vm.simulationSpeedMultiplier = 10.0
            vm.advanceSimulationStep()
            assertEqual(vm.currentCoordIndex, 10, "10x leap must jump 10 coordinate vertices")
            assertEqual(vm.currentStepIndex, 5, "while-loop must traverse all intermediate steps without skipping")

            // 1.4b: Non-positive speed multiplier falls back to stepJump = 1
            vm.simulationSpeedMultiplier = -5.0
            vm.advanceSimulationStep()
            assertEqual(vm.currentCoordIndex, 11, "Negative speed multiplier must clamp to stepJump = 1")

            vm.simulationSpeedMultiplier = 0.0
            vm.advanceSimulationStep()
            assertEqual(vm.currentCoordIndex, 12, "Zero speed multiplier must clamp to stepJump = 1")

            // 1.4c: Leaping past polyline end lands at coords.count - 1, and next tick completes arrival
            vm.simulationSpeedMultiplier = 100.0
            vm.advanceSimulationStep()
            assertEqual(vm.currentCoordIndex, coords.count - 1, "Leaping past end must clamp to coords.count - 1")
            assertTrue(vm.isNavigating, "Puck should display at destination coordinate before final arrival tick")

            // Next tick triggers arrival
            vm.advanceSimulationStep()
            assertFalse(vm.isNavigating, "Next tick must trigger arrival and end navigation")
            assertNil(vm.routeDetails)
        }

        // 1.5 Bearing Angle Calculation on Identical Points (Atan2 Stability)
        runTest("testT5_05_BearingAngleStabilityOnIdenticalCoordinates") {
            let vm = NavigationViewModel()
            let pt = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
            // Two identical coordinates in route
            let coords = [pt, pt, CLLocationCoordinate2D(latitude: 64.8450, longitude: -147.7215)]
            let details = RouteDetails(coordinates: coords, totalDistanceMiles: 0.1, totalDurationSeconds: 10, steps: [])
            vm.routeDetails = details
            vm.routeCoordinates = coords
            vm.isNavigating = true
            vm.isSimulating = true
            vm.currentCoordIndex = 0

            // Advance between two identical points (0 distance)
            vm.advanceSimulationStep()
            assertNotNil(vm.simulatedHeading, "simulatedHeading must not be nil")
            assertFalse(vm.simulatedHeading!.isNaN, "simulatedHeading must not be NaN on identical coordinates")
            assertEqualDouble(vm.simulatedHeading!, 0.0, accuracy: 0.001)
            vm.endNavigation()
        }

        // 1.6 Dual-Point Arrival Detection: Snapped Road End vs Setback Pin
        runTest("testT5_06_DualPointArrivalDetectionThresholds") {
            let vm = NavigationViewModel()
            let roadStart = CLLocationCoordinate2D(latitude: 64.8400, longitude: -147.7200)
            let roadEnd = CLLocationCoordinate2D(latitude: 64.8430, longitude: -147.7200)
            let coords = [roadStart, roadEnd]

            // Destination pin in parking lot 40m away from road endpoint
            let setbackPin = CLLocationCoordinate2D(latitude: 64.8430, longitude: -147.7190)

            let step = NavigationStep(instruction: "Arrive", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 1)
            let details = RouteDetails(coordinates: coords, totalDistanceMiles: 0.2, totalDurationSeconds: 20, steps: [step])

            // Case A: User pulls into parking lot within 15m of setback pin (distToRoadEnd ~40m)
            vm.routeDetails = details
            vm.routeCoordinates = coords
            vm.selectedCoordinate = setbackPin
            vm.isNavigating = true
            vm.currentStepIndex = 0
            vm.currentCoordIndex = 1

            let userNearPin = CLLocationCoordinate2D(latitude: 64.8430, longitude: -147.7192)
            vm.updateCurrentStepForLiveLocation(userNearPin, in: details)
            assertFalse(vm.isNavigating, "Arrival must trigger when within 25m of destination pin")
            assertNil(vm.routeDetails, "Route must be cleared on arrival")

            // Case B: User arrives at road end directly (selectedCoordinate is far or nil)
            vm.routeDetails = details
            vm.routeCoordinates = coords
            vm.selectedCoordinate = nil
            vm.isNavigating = true
            vm.currentStepIndex = 0
            vm.currentCoordIndex = 1

            let userNearRoadEnd = CLLocationCoordinate2D(latitude: 64.8429, longitude: -147.7200)
            vm.updateCurrentStepForLiveLocation(userNearRoadEnd, in: details)
            assertFalse(vm.isNavigating, "Arrival must trigger when within 25m of road end even with nil pin")
            assertNil(vm.routeDetails)
        }

        // 1.7 Off-Route Detection & Exponential Reroute Backoff
        runTest("testT5_07_OffRouteDetectionAndExponentialCooldown") {
            let vm = NavigationViewModel()
            let p0 = CLLocationCoordinate2D(latitude: 64.8400, longitude: -147.7200)
            let p1 = CLLocationCoordinate2D(latitude: 64.8500, longitude: -147.7200)
            let coords = [p0, p1]
            let dest = p1
            let details = RouteDetails(coordinates: coords, totalDistanceMiles: 1.0, totalDurationSeconds: 60, steps: [])

            vm.routeDetails = details
            vm.routeCoordinates = coords
            vm.selectedCoordinate = dest
            vm.isNavigating = true
            vm.consecutiveRerouteFailures = 0
            vm.lastRerouteTime = Date().addingTimeInterval(-10.0) // 10s ago

            // 1.7a: User within 35m of route (on-route) -> No reroute
            let onRouteLocation = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 64.8450, longitude: -147.7201),
                altitude: 10,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 5.0,
                timestamp: Date()
            )
            vm.handleLocationUpdate(onRouteLocation)
            assertFalse(vm.isRecalculating, "User on route must not trigger recalculation")

            // 1.7b: User 80m off-route -> Triggers recalculation
            let offRouteLocation = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 64.8450, longitude: -147.7220),
                altitude: 10,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 5.0,
                timestamp: Date()
            )
            vm.handleLocationUpdate(offRouteLocation)
            assertTrue(vm.isRecalculating, "User 80m off route must trigger recalculation")

            // 1.7c: Immediate subsequent fix while isRecalculating == true -> Ignored
            vm.handleLocationUpdate(offRouteLocation)
            assertTrue(vm.isRecalculating)

            vm.endNavigation()
        }

        // 1.8 Travel Mode Switching & Simulation Speed Dynamics
        runTest("testT5_08_TravelModeSwitchingAndSpeedDynamics") {
            let vm = NavigationViewModel()
            let coords = [CLLocationCoordinate2D(latitude: 64.84, longitude: -147.72), CLLocationCoordinate2D(latitude: 64.85, longitude: -147.72)]
            let details = RouteDetails(coordinates: coords, totalDistanceMiles: 1.0, totalDurationSeconds: 60, steps: [])

            // Test Pedestrian Mode
            vm.routeDetails = details
            vm.routeCoordinates = coords
            vm.selectedTravelMode = "pedestrian"
            assertEqual(vm.selectedTravelMode, "pedestrian")
            vm.startSimulatedDrive()
            assertEqual(vm.simulatedSpeedMph, 3, "Pedestrian mode simulation speed must be 3 mph")
            vm.endNavigation()

            // Test Bicycle Mode
            vm.routeDetails = details
            vm.routeCoordinates = coords
            vm.selectedTravelMode = "bicycle"
            assertEqual(vm.selectedTravelMode, "bicycle")
            vm.startSimulatedDrive()
            assertEqual(vm.simulatedSpeedMph, 12, "Bicycle mode simulation speed must be 12 mph")
            vm.endNavigation()

            // Test Auto Mode
            vm.routeDetails = details
            vm.routeCoordinates = coords
            vm.selectedTravelMode = "auto"
            assertEqual(vm.selectedTravelMode, "auto")
            vm.startSimulatedDrive()
            assertEqual(vm.simulatedSpeedMph, 45, "Auto mode simulation speed must be 45 mph")
            vm.endNavigation()
        }

        // 1.9 HUD Windshield Mode & Unit Formatting Stress
        runTest("testT5_09_HUDWindshieldModeAndUnitFormatting") {
            let vm = NavigationViewModel()
            vm.isHudMode = true
            assertTrue(vm.isHudMode)

            // Imperial formatting
            let impFeet = NavigationViewModel.formatCountdownDistance(0.05, useMetric: false)
            assertTrue(impFeet.contains("ft"), "Distance < 0.1 mi must format in ft (got \(impFeet))")

            let impMiles = NavigationViewModel.formatCountdownDistance(2.5, useMetric: false)
            assertTrue(impMiles.contains("2.5 mi"), "Distance >= 0.1 mi must format in mi (got \(impMiles))")

            // Metric formatting
            let metMeters = NavigationViewModel.formatCountdownDistance(0.2, useMetric: true) // ~321 meters
            assertTrue(metMeters.contains("m"), "Distance < 1000m must format in m (got \(metMeters))")

            let metKm = NavigationViewModel.formatCountdownDistance(1.5, useMetric: true) // ~2.4 km
            assertTrue(metKm.contains("km"), "Distance >= 1000m must format in km (got \(metKm))")

            // Duration formatting
            vm.remainingRouteDurationSeconds = 45 * 60 // 45 min
            assertEqual(vm.formattedRemainingDuration, "45 min")

            vm.remainingRouteDurationSeconds = 135 * 60 // 2 hr 15 min
            assertEqual(vm.formattedRemainingDuration, "2 hr 15 min")

            // endNavigation resets HUD mode
            vm.endNavigation()
            assertFalse(vm.isHudMode, "endNavigation must reset isHudMode to false")
        }

        // 1.10 Search Query Handling, Debounce, and Lifecycle
        await runAsyncTest("testT5_10_SearchQueryHandlingAndDebounce") {
            let vm = NavigationViewModel()

            // 1.10a: Single character query (< 2 chars) suppressed
            vm.handleQueryChange("a")
            assertEqual(vm.searchResults.count, 0)
            assertFalse(vm.isSearching)

            // 1.10b: 2+ character query triggers search task
            vm.handleQueryChange("Coffee")
            assertTrue(vm.isSearching)
            assertNotNil(vm.searchTask)

            // Wait for debounce and search task completion
            try? await Task.sleep(nanoseconds: 250_000_000) // 250ms
            assertFalse(vm.isSearching)
            assertEqual(vm.searchResults.count, 1)

            // 1.10c: Category search programmatic text change flag
            vm.destinationText = ""
            vm.isProgrammaticTextChange = false
            vm.searchCategory("Groceries")
            assertEqual(vm.destinationText, "Groceries")
            assertTrue(vm.isProgrammaticTextChange, "searchCategory must set isProgrammaticTextChange = true")

            // 1.10d: Clean teardown via resetToExplore
            vm.resetToExplore()
            assertEqual(vm.appMode, .explore)
            assertEqual(vm.destinationText, "")
            assertTrue(vm.searchResults.isEmpty)
            assertNil(vm.searchTask)
        }

        // =================================================================
        // SUITE 2: RoutingService Concurrency & Turn Prompt Hardening
        // =================================================================
        print("\n📦 Suite 2: RoutingService Concurrency & Audio Safety Hardening")

        // 2.1 100 Concurrent Threads on speakTurnInstruction
        runTest("testT5_11_HighConcurrency100ThreadsSpeakTurnInstruction") {
            let routingService = RoutingService()
            let threadCount = 100
            let dispatchGroup = DispatchGroup()

            for i in 0..<threadCount {
                dispatchGroup.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    let stepId = (i % 3 == 0) ? nil : i
                    let force = (i % 5 == 0)
                    routingService.speakTurnInstruction("Turn prompt \(i)", stepId: stepId, force: force)
                    dispatchGroup.leave()
                }
            }

            let waitResult = dispatchGroup.wait(timeout: .now() + 5.0)
            assertEqual(waitResult, .success, "100 concurrent threads calling speakTurnInstruction must complete without deadlock")
        }

        // 2.2 Rapid Concurrent Voice Muting and Speech Prompts
        runTest("testT5_12_ConcurrentVoiceMuteMutationAcross60Threads") {
            let routingService = RoutingService()
            let workerCount = 60
            let iterations = 30
            let dispatchGroup = DispatchGroup()

            for worker in 0..<workerCount {
                dispatchGroup.enter()
                DispatchQueue.global(qos: .userInteractive).async {
                    for iter in 0..<iterations {
                        switch worker % 4 {
                        case 0:
                            routingService.isVoiceMuted = true
                        case 1:
                            routingService.isVoiceMuted = false
                        case 2:
                            _ = routingService.isVoiceMuted
                        case 3:
                            routingService.speakTurnInstruction("Prompt \(worker)-\(iter)", stepId: iter, force: (iter % 2 == 0))
                        default:
                            break
                        }
                    }
                    dispatchGroup.leave()
                }
            }

            let waitResult = dispatchGroup.wait(timeout: .now() + 5.0)
            assertEqual(waitResult, .success, "Concurrent voice muting and speech prompt threads must complete without deadlock")
        }

        // 2.3 Step Deduplication Edge Cases (nil stepId, force, muted)
        runTest("testT5_13_StepDeduplicationComprehensiveEdgeCases") {
            let rs = RoutingService()

            // Subtest A: Identical text with nil stepId within 6s is deduplicated
            rs.stopVoice()
            rs.spokenInstructions.removeAll()
            rs.speakTurnInstruction("Proceed along route", stepId: nil, force: false)
            let countA1 = rs.spokenInstructions.count
            rs.speakTurnInstruction("Proceed along route", stepId: nil, force: false)
            let countA2 = rs.spokenInstructions.count
            assertEqual(countA1, countA2, "Identical text with nil stepId within 6s must be deduplicated")

            // Subtest B: Different text with nil stepId is NOT deduplicated
            rs.speakTurnInstruction("In 500 feet, turn left", stepId: nil, force: false)
            let countA3 = rs.spokenInstructions.count
            assertTrue(countA3 > countA2, "Different text with nil stepId must be spoken")

            // Subtest C: Distinct stepId with identical text is NOT deduplicated (e.g. continue straight)
            rs.stopVoice()
            rs.spokenInstructions.removeAll()
            rs.speakTurnInstruction("Continue straight", stepId: 10, force: false)
            let countB1 = rs.spokenInstructions.count
            rs.speakTurnInstruction("Continue straight", stepId: 11, force: false)
            let countB2 = rs.spokenInstructions.count
            assertTrue(countB2 > countB1, "Consecutive distinct steps with identical text must NOT be deduplicated")

            // Subtest D: force = true always speaks
            rs.speakTurnInstruction("Continue straight", stepId: 11, force: true)
            let countB3 = rs.spokenInstructions.count
            assertTrue(countB3 > countB2, "force: true must bypass deduplication")

            // Subtest E: Muted state drops prompt even when force = true
            rs.isVoiceMuted = true
            let countBeforeMuted = rs.spokenInstructions.count
            rs.speakTurnInstruction("Should be dropped", stepId: 12, force: true)
            let countAfterMuted = rs.spokenInstructions.count
            assertEqual(countBeforeMuted, countAfterMuted, "Muted service must drop instructions even when force: true")
            rs.isVoiceMuted = false
        }

        // 2.4 Fast Route Restart Turn Announcement Turnaround (0.01s - 2.0s)
        runTest("testT5_14_FastRouteRestartTurnAnnouncement") {
            let rs = RoutingService()
            let firstTurn = "Turn right onto Chena Pump Road"

            // Start route 1
            rs.stopVoice()
            rs.speakTurnInstruction(firstTurn, stepId: 0, force: false)

            // User cancels navigation and restarts on the EXACT same route after 0.05s
            rs.stopVoice()
            rs.spokenInstructions.removeAll()
            rs.speakTurnInstruction(firstTurn, stepId: 0, force: false)

            assertEqual(rs.spokenInstructions.count, 1, "Immediate restart on same route must announce first turn prompt (stopVoice cleared deduplication state)")
            assertEqual(rs.spokenInstructions.first?.text, firstTurn)
        }

        // 2.5 Route Calculation Fail-Fast Timeout
        runTest("testT5_15_RouteCalculationFailFastTimeout") {
            let rs = RoutingService()
            let outOfRegionA = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194) // SF
            let outOfRegionB = CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195)

            let startTime = CFAbsoluteTimeGetCurrent()
            let details = rs.calculateRoute(from: outOfRegionA, to: outOfRegionB, mode: "auto", useMetric: false)
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime

            assertNil(details, "Out of region route calculation must return nil")
            assertTrue(elapsed < 6.0, "Route calculation must fail fast within timeout and not block indefinitely (took \(elapsed)s)")
        }

        // =================================================================
        // SUITE 3: ContentView Forwarding & State Machine Hardening
        // =================================================================
        print("\n📦 Suite 3: ContentView Forwarding & Immutability Hardening")

        // 3.1 All 37 Forwarding Properties Read/Write on Immutable 'let view'
        runTest("testT5_16_ContentViewAll37ForwardingPropertiesOnImmutableLet") {
            let vm = NavigationViewModel()
            let view = ContentView(viewModel: vm)

            // 1. appMode
            view.appMode = .placeDetail
            assertEqual(view.appMode, .placeDetail)
            assertEqual(view.viewModel.appMode, .placeDetail)

            // 2. selectedPlace
            let place = SearchResult(id: 101, name: "Fred Meyer", lat: 64.84, lon: -147.72, category: "supermarket")
            view.selectedPlace = place
            assertEqual(view.selectedPlace?.id, 101)
            assertEqual(view.viewModel.selectedPlace?.id, 101)

            // 3. routeDetails
            let details = RouteDetails(coordinates: [CLLocationCoordinate2D(latitude: 64.84, longitude: -147.72)], totalDistanceMiles: 1.0, totalDurationSeconds: 60, steps: [])
            view.routeDetails = details
            assertEqual(view.routeDetails?.totalDistanceMiles, 1.0)
            assertEqual(view.viewModel.routeDetails?.totalDistanceMiles, 1.0)

            // 4. selectedTravelMode
            view.selectedTravelMode = "bicycle"
            assertEqual(view.selectedTravelMode, "bicycle")
            assertEqual(view.viewModel.selectedTravelMode, "bicycle")

            // 5. showStepsSheet
            view.showStepsSheet = true
            assertEqual(view.showStepsSheet, true)
            assertEqual(view.viewModel.showStepsSheet, true)

            // 6. isHudMode
            view.isHudMode = true
            assertEqual(view.isHudMode, true)
            assertEqual(view.viewModel.isHudMode, true)
            view.isHudMode = false
            assertEqual(view.isHudMode, false)

            // 7. useMetric
            view.useMetric = true
            assertEqual(view.useMetric, true)
            assertEqual(view.viewModel.useMetric, true)

            // 8. isVoiceMuted
            view.isVoiceMuted = true
            assertEqual(view.isVoiceMuted, true)
            assertEqual(view.viewModel.isVoiceMuted, true)

            // 9. destinationText
            view.destinationText = "Chena Hot Springs"
            assertEqual(view.destinationText, "Chena Hot Springs")
            assertEqual(view.viewModel.destinationText, "Chena Hot Springs")

            // 10. searchResults
            view.searchResults = [place]
            assertEqual(view.searchResults.count, 1)
            assertEqual(view.viewModel.searchResults.count, 1)

            // 11. isSearching
            view.isSearching = true
            assertEqual(view.isSearching, true)
            assertEqual(view.viewModel.isSearching, true)

            // 12. searchTask
            view.searchTask = nil
            assertNil(view.searchTask)

            // 13. isProgrammaticTextChange
            view.isProgrammaticTextChange = true
            assertEqual(view.isProgrammaticTextChange, true)
            assertEqual(view.viewModel.isProgrammaticTextChange, true)

            // 14. selectedCoordinate
            let coord = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
            view.selectedCoordinate = coord
            assertEqualDouble(view.selectedCoordinate!.latitude, coord.latitude)
            assertEqualDouble(view.viewModel.selectedCoordinate!.latitude, coord.latitude)

            // 15. routeCoordinates
            view.routeCoordinates = [coord]
            assertEqual(view.routeCoordinates?.count, 1)
            assertEqual(view.viewModel.routeCoordinates?.count, 1)

            // 16. simulatedUserCoordinate
            view.simulatedUserCoordinate = coord
            assertEqualDouble(view.simulatedUserCoordinate!.latitude, coord.latitude)
            assertEqualDouble(view.viewModel.simulatedUserCoordinate!.latitude, coord.latitude)

            // 17. userLocationCenter
            view.userLocationCenter = coord
            assertEqualDouble(view.userLocationCenter!.latitude, coord.latitude)
            assertEqualDouble(view.viewModel.userLocationCenter!.latitude, coord.latitude)

            // 18. simulatedHeading
            view.simulatedHeading = 270.0
            assertEqualDouble(view.simulatedHeading!, 270.0)
            assertEqualDouble(view.viewModel.simulatedHeading!, 270.0)

            // 19. zoomStep
            view.zoomStep = 14.0
            assertEqualDouble(view.zoomStep!, 14.0)
            assertEqualDouble(view.viewModel.zoomStep!, 14.0)

            // 20. isNavigating
            view.isNavigating = true
            assertEqual(view.isNavigating, true)
            assertEqual(view.viewModel.isNavigating, true)

            // 21. isSimulating
            view.isSimulating = true
            assertEqual(view.isSimulating, true)
            assertEqual(view.viewModel.isSimulating, true)

            // 22. currentStepIndex
            view.currentStepIndex = 3
            assertEqual(view.currentStepIndex, 3)
            assertEqual(view.viewModel.currentStepIndex, 3)

            // 23. currentCoordIndex
            view.currentCoordIndex = 12
            assertEqual(view.currentCoordIndex, 12)
            assertEqual(view.viewModel.currentCoordIndex, 12)

            // 24. simulatedSpeedMph
            view.simulatedSpeedMph = 45
            assertEqual(view.simulatedSpeedMph, 45)
            assertEqual(view.viewModel.simulatedSpeedMph, 45)

            // 25. simulationSpeedMultiplier
            view.simulationSpeedMultiplier = 5.0
            assertEqualDouble(view.simulationSpeedMultiplier, 5.0)
            assertEqualDouble(view.viewModel.simulationSpeedMultiplier, 5.0)

            // 26. isRecalculating
            view.isRecalculating = true
            assertEqual(view.isRecalculating, true)
            assertEqual(view.viewModel.isRecalculating, true)

            // 27. consecutiveRerouteFailures
            view.consecutiveRerouteFailures = 2
            assertEqual(view.consecutiveRerouteFailures, 2)
            assertEqual(view.viewModel.consecutiveRerouteFailures, 2)

            // 28. lastRerouteTime
            let testTime = Date()
            view.lastRerouteTime = testTime
            assertEqual(view.lastRerouteTime, testTime)
            assertEqual(view.viewModel.lastRerouteTime, testTime)

            // 29. activeRouteRequestId
            let testUUID = UUID()
            view.activeRouteRequestId = testUUID
            assertEqual(view.activeRouteRequestId, testUUID)
            assertEqual(view.viewModel.activeRouteRequestId, testUUID)

            // 30. remainingStepDistanceMiles
            view.remainingStepDistanceMiles = 0.75
            assertEqualDouble(view.remainingStepDistanceMiles, 0.75)
            assertEqualDouble(view.viewModel.remainingStepDistanceMiles, 0.75)

            // 31. remainingRouteDistanceMiles
            view.remainingRouteDistanceMiles = 15.2
            assertEqualDouble(view.remainingRouteDistanceMiles, 15.2)
            assertEqualDouble(view.viewModel.remainingRouteDistanceMiles, 15.2)

            // 32. remainingRouteDurationSeconds
            view.remainingRouteDurationSeconds = 900.0
            assertEqualDouble(view.remainingRouteDurationSeconds, 900.0)
            assertEqualDouble(view.viewModel.remainingRouteDurationSeconds, 900.0)

            // 33. dynamicArrivalDate
            view.dynamicArrivalDate = testTime
            assertEqual(view.dynamicArrivalDate, testTime)
            assertEqual(view.viewModel.dynamicArrivalDate, testTime)

            // 34. hasAnnouncedAdvanceTurn
            view.hasAnnouncedAdvanceTurn = true
            assertEqual(view.hasAnnouncedAdvanceTurn, true)
            assertEqual(view.viewModel.hasAnnouncedAdvanceTurn, true)

            // 35. errorMessage
            view.errorMessage = "Test Error"
            assertEqual(view.errorMessage, "Test Error")
            assertEqual(view.viewModel.errorMessage, "Test Error")

            // 36. showErrorAlert
            view.showErrorAlert = true
            assertEqual(view.showErrorAlert, true)
            assertEqual(view.viewModel.showErrorAlert, true)

            // 37. isMapDataMissing
            view.isMapDataMissing = true
            assertEqual(view.isMapDataMissing, true)
            assertEqual(view.viewModel.isMapDataMissing, true)
        }

        // 3.2 ContentView Forwarding Methods Execution
        runTest("testT5_17_ContentViewForwardingMethodsExecution") {
            let vm = NavigationViewModel()
            let view = ContentView(viewModel: vm)

            // 3.2a: searchCategory execution on immutable let
            view.destinationText = ""
            view.isProgrammaticTextChange = false
            view.searchCategory("Groceries")
            assertEqual(view.destinationText, "Groceries")
            assertEqual(view.viewModel.destinationText, "Groceries")

            // 3.2b: formatCountdownDistance forwarding
            let distStr = view.formatCountdownDistance(1.5, useMetric: false)
            assertTrue(distStr.contains("1.5 mi"))

            // 3.2c: isWithinSupportedRegion forwarding
            assertTrue(view.isWithinSupportedRegion(NavigationViewModel.defaultAlaskaCoordinate))
            assertFalse(view.isWithinSupportedRegion(CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)))

            // 3.2d: segmentDistanceMeters forwarding
            let d = view.segmentDistanceMeters(
                p1: CLLocationCoordinate2D(latitude: 64.84, longitude: -147.72),
                p2: CLLocationCoordinate2D(latitude: 64.84, longitude: -147.73)
            )
            assertTrue(d > 0.0)

            // 3.2e: resetToExplore forwarding
            view.appMode = .navigation
            view.resetToExplore()
            assertEqual(view.appMode, .explore)
            assertEqual(view.viewModel.appMode, .explore)

            // 3.2f: handleLocationUpdate with out-of-region coordinate does NOT alter simulatedUserCoordinate
            let outOfRegionLoc = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                altitude: 10,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 5.0,
                timestamp: Date()
            )
            view.simulatedUserCoordinate = nil
            view.handleLocationUpdate(outOfRegionLoc)
            assertNil(view.simulatedUserCoordinate, "Out of region location update must be silently dropped")
        }

        // =================================================================
        // SUITE 4: Advanced Edge Case Matrix & Boundary Hardening
        // =================================================================
        print("\n📦 Suite 4: Advanced Edge Case Matrix & Boundary Hardening")

        // 4.1 Double Switchback Zig-Zag Clamping (S-Curve with 3 Parallel Legs)
        runTest("testT5_18_DoubleSwitchbackZigZagSearchClamping") {
            let vm = NavigationViewModel()
            // 3 legs:
            // Leg 1: (0..3) North along lon -147.7200
            // Leg 2: (4..7) South along lon -147.7198 (~15m east)
            // Leg 3: (8..11) North along lon -147.7196 (~15m further east)
            var coords: [CLLocationCoordinate2D] = []
            for i in 0...3 { coords.append(CLLocationCoordinate2D(latitude: 64.8400 + Double(i) * 0.001, longitude: -147.7200)) }
            for i in 4...7 { coords.append(CLLocationCoordinate2D(latitude: 64.8430 - Double(i - 4) * 0.001, longitude: -147.7198)) }
            for i in 8...11 { coords.append(CLLocationCoordinate2D(latitude: 64.8400 + Double(i - 8) * 0.001, longitude: -147.7196)) }

            let s1 = NavigationStep(instruction: "Leg 1", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 3)
            let s2 = NavigationStep(instruction: "Leg 2", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 1, streetName: nil, startIndex: 3, endIndex: 7)
            let s3 = NavigationStep(instruction: "Leg 3", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 1, streetName: nil, startIndex: 7, endIndex: 11)

            let details = RouteDetails(coordinates: coords, totalDistanceMiles: 0.6, totalDurationSeconds: 60, steps: [s1, s2, s3])
            vm.routeDetails = details
            vm.routeCoordinates = coords
            vm.isNavigating = true
            vm.currentStepIndex = 0
            vm.currentCoordIndex = 1 // Early on Leg 1

            // User is at vertex 1, geographically only ~30m from Leg 3 (vertex 9)
            let userFix = CLLocationCoordinate2D(latitude: 64.8410, longitude: -147.7200)
            vm.updateCurrentStepForLiveLocation(userFix, in: details)

            assertEqual(vm.currentStepIndex, 0, "Must not jump across zigzag legs")
            assertTrue(vm.currentCoordIndex <= s1.endIndex + 2, "Coordinate search must remain strictly clamped to Leg 1 slack (<= 5)")
            vm.endNavigation()
        }

        // 4.2 Effective User Coordinate Fallback Hierarchy
        runTest("testT5_19_EffectiveUserCoordinateFallbacks") {
            let vm = NavigationViewModel()

            // 1. When simulatedUserCoordinate is set -> returns simulated coordinate
            let simCoord = CLLocationCoordinate2D(latitude: 64.8500, longitude: -147.7100)
            vm.simulatedUserCoordinate = simCoord
            assertEqualDouble(vm.effectiveUserCoordinate.latitude, simCoord.latitude)
            assertEqualDouble(vm.effectiveUserCoordinate.longitude, simCoord.longitude)

            // 2. When simulated is nil and hardware location is within Alaska -> returns hardware fix
            vm.simulatedUserCoordinate = nil
            let hwCoord = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
            vm.locationManager.location = CLLocation(
                coordinate: hwCoord,
                altitude: 100,
                horizontalAccuracy: 10,
                verticalAccuracy: 10,
                timestamp: Date()
            )
            assertEqualDouble(vm.effectiveUserCoordinate.latitude, hwCoord.latitude)

            // 3. When hardware location is outside Alaska (e.g. San Francisco) -> falls back to default Alaska coordinate
            vm.locationManager.location = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                altitude: 10,
                horizontalAccuracy: 10,
                verticalAccuracy: 10,
                timestamp: Date()
            )
            assertEqualDouble(vm.effectiveUserCoordinate.latitude, NavigationViewModel.defaultAlaskaCoordinate.latitude)
            assertEqualDouble(vm.effectiveUserCoordinate.longitude, NavigationViewModel.defaultAlaskaCoordinate.longitude)

            // 4. When hardware location is nil -> falls back to default Alaska coordinate
            vm.locationManager.location = nil
            assertEqualDouble(vm.effectiveUserCoordinate.latitude, NavigationViewModel.defaultAlaskaCoordinate.latitude)
        }

        // 4.3 Current Navigation Step Bounds Safety (Empty, Negative, Out of Bounds)
        runTest("testT5_20_CurrentNavigationStepBoundsSafety") {
            let vm = NavigationViewModel()

            // Case A: routeDetails is nil -> returns fallback safe step
            vm.routeDetails = nil
            let defaultStep = vm.currentNavigationStep
            assertEqual(defaultStep.instruction, "Proceed along route")

            // Case B: steps array is empty -> returns fallback safe step
            let emptyDetails = RouteDetails(coordinates: [NavigationViewModel.defaultAlaskaCoordinate], totalDistanceMiles: 0.1, totalDurationSeconds: 10, steps: [])
            vm.routeDetails = emptyDetails
            assertEqual(vm.currentNavigationStep.instruction, "Proceed along route")

            // Case C: currentStepIndex is negative or out of bounds -> clamped safely
            let s1 = NavigationStep(instruction: "First Step", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 1)
            let s2 = NavigationStep(instruction: "Second Step", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 1, streetName: nil, startIndex: 1, endIndex: 2)
            let normalDetails = RouteDetails(coordinates: [NavigationViewModel.defaultAlaskaCoordinate, NavigationViewModel.defaultAlaskaCoordinate], totalDistanceMiles: 0.3, totalDurationSeconds: 30, steps: [s1, s2])
            vm.routeDetails = normalDetails

            vm.currentStepIndex = -10
            assertEqual(vm.currentNavigationStep.instruction, "First Step", "Negative index must clamp to index 0")

            vm.currentStepIndex = 999
            assertEqual(vm.currentNavigationStep.instruction, "Second Step", "Out of bounds index must clamp to last step")
        }

        // 4.4 Hardware GPS Start Fix Retention Matrix
        runTest("testT5_21_HardwareGPSStartFixRetentionMatrix") {
            let vm = NavigationViewModel()
            let routeStart = CLLocationCoordinate2D(latitude: 64.8400, longitude: -147.7200)
            let routeEnd = CLLocationCoordinate2D(latitude: 64.8450, longitude: -147.7200)
            let details = RouteDetails(coordinates: [routeStart, routeEnd], totalDistanceMiles: 0.5, totalDurationSeconds: 50, steps: [])
            vm.routeDetails = details

            // Case 1: Fresh in-region fix (< 15s, accuracy 10m) -> Retained!
            let freshFix = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 64.8415, longitude: -147.7205),
                altitude: 100,
                horizontalAccuracy: 10.0,
                verticalAccuracy: 5.0,
                course: 45.0,
                speed: 15.0,
                timestamp: Date()
            )
            vm.locationManager.location = freshFix
            vm.startNavigation()
            assertEqualDouble(vm.simulatedUserCoordinate!.latitude, freshFix.coordinate.latitude)
            assertEqualDouble(vm.simulatedHeading!, 45.0)
            vm.endNavigation()

            // Case 2: Stale fix (> 15s old, e.g. 60s) -> Snaps to polyline start
            let staleFix = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 64.8415, longitude: -147.7205),
                altitude: 100,
                horizontalAccuracy: 10.0,
                verticalAccuracy: 5.0,
                course: 45.0,
                speed: 15.0,
                timestamp: Date().addingTimeInterval(-60.0)
            )
            vm.locationManager.location = staleFix
            vm.startNavigation()
            assertEqualDouble(vm.simulatedUserCoordinate!.latitude, routeStart.latitude)
            vm.endNavigation()

            // Case 3: Degraded fix (accuracy 70m >= 65m) -> Snaps to polyline start
            let degradedFix = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 64.8415, longitude: -147.7205),
                altitude: 100,
                horizontalAccuracy: 70.0,
                verticalAccuracy: 5.0,
                timestamp: Date()
            )
            vm.locationManager.location = degradedFix
            vm.startNavigation()
            assertEqualDouble(vm.simulatedUserCoordinate!.latitude, routeStart.latitude)
            vm.endNavigation()

            // Case 4: Out-of-region fix (Seattle) -> Snaps to polyline start
            let seattleFix = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321),
                altitude: 100,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 5.0,
                timestamp: Date()
            )
            vm.locationManager.location = seattleFix
            vm.startNavigation()
            assertEqualDouble(vm.simulatedUserCoordinate!.latitude, routeStart.latitude)
            vm.endNavigation()
        }

        // 4.5 Speed & Altitude Conversion Matrix
        runTest("testT5_22_SpeedAndAltitudeUnitConversions") {
            let vm = NavigationViewModel()
            vm.locationManager.smoothedSpeedMph = 45
            vm.locationManager.smoothedSpeedKmh = 72
            vm.locationManager.location = CLLocation(
                coordinate: NavigationViewModel.defaultAlaskaCoordinate,
                altitude: 100.0, // 100 meters = 328 feet
                horizontalAccuracy: 5.0,
                verticalAccuracy: 5.0,
                timestamp: Date()
            )

            // Imperial
            vm.useMetric = false
            vm.isSimulating = false
            assertEqual(vm.displaySpeed, 45)
            assertEqual(vm.speedUnit, "mph")
            assertEqual(vm.altitudeValue, 328)
            assertEqual(vm.altitudeUnit, "ft")

            // Metric
            vm.useMetric = true
            assertEqual(vm.displaySpeed, 72)
            assertEqual(vm.speedUnit, "km/h")
            assertEqual(vm.altitudeValue, 100)
            assertEqual(vm.altitudeUnit, "m")

            // Simulation mode conversion
            vm.isSimulating = true
            vm.simulatedSpeedMph = 60
            vm.useMetric = false
            assertEqual(vm.displaySpeed, 60)
            vm.useMetric = true
            assertEqual(vm.displaySpeed, 96, "60 mph * 1.60934 = 96 km/h")
            vm.isSimulating = false
        }

        // 4.6 Map Long-Press Dropped Pin and Reverse Geocode
        await runAsyncTest("testT5_23_MapLongPressDropPinAndReverseGeocode") {
            let vm = NavigationViewModel()
            let pinCoord = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
            vm.handleMapLongPress(at: pinCoord)

            assertEqual(vm.appMode, .placeDetail)
            assertEqualDouble(vm.selectedCoordinate!.latitude, pinCoord.latitude)
            assertNotNil(vm.selectedPlace)

            // Allow detached task to resolve
            try? await Task.sleep(nanoseconds: 100_000_000)
            assertEqual(vm.appMode, .placeDetail)
            vm.resetToExplore()
        }

        // =================================================================
        // SUMMARY REPORT
        // =================================================================
        print("\n========================================================")
        print("📊 TIER 5 ADVERSARIAL STRESS TEST EXECUTION SUMMARY")
        print("========================================================")
        print("Total Tests Executed: \(testsRun)")
        print("Passed:               \(testsPassed) ✅")
        print("Failed:               \(testsFailed) ❌")
        print("Pass Rate:            \(Int(Double(testsPassed) / Double(testsRun) * 100))%")
        print("========================================================\n")

        if testsFailed == 0 {
            print("🎉 ALL \(testsRun) TIER 5 EMPIRICAL ADVERSARIAL STRESS TESTS PASSED SUCCESSFULLY!")
        } else {
            print("⚠️ \(testsFailed) TEST(S) FAILED!")
        }
    }
}
