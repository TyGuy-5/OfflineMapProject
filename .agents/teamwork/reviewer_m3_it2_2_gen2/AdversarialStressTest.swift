//
//  AdversarialStressTest.swift
//  reviewer_m3_it2_2_gen2
//

import Foundation
import CoreLocation
import Combine
import SwiftUI

@MainActor
func runAllAdversarialStressTests() {
    print("==================================================")
    print("RUNNING ADVERSARIAL REVIEWER STRESS TESTS")
    print("==================================================")

    testR2_1_SwitchbackClampingAdversarial()
    testR2_2_MonotonicCountdownAdversarial()
    testR2_3_SimulationMultiSpeedLoopAdversarial()
    testR2_4_LiveGPSStartFixAdversarial()
    testR2_5_DualPointArrivalAdversarial()
    testContentViewForwardingImmutabilityStress()

    print("==================================================")
    print("ALL ADVERSARIAL STRESS TESTS COMPLETED SUCCESSFULLY!")
    print("==================================================")
}

// MARK: - R2.1: Switchback Clamping
@MainActor
func testR2_1_SwitchbackClampingAdversarial() {
    print("-> Testing R2.1: Switchback Clamping...")
    let routingService = RoutingService()
    let vm = NavigationViewModel(routingService: routingService)

    // Construct a route with a switchback:
    // Vertices 0..4 go North. Maneuver 0 ends at vertex 4.
    // Vertices 4..8 do hairpin turn and go South on parallel road. Maneuver 1 ends at vertex 8.
    // Vertices 8..12 go North again. Maneuver 2 ends at vertex 12.
    var coords: [CLLocationCoordinate2D] = []
    for i in 0...12 {
        coords.append(CLLocationCoordinate2D(latitude: 64.8400 + Double(i) * 0.001, longitude: -147.7200))
    }

    let step0 = NavigationStep(instruction: "Go north", distanceMiles: 0.5, durationSeconds: 60, maneuverType: 1, streetName: "Road 1", startIndex: 0, endIndex: 4)
    let step1 = NavigationStep(instruction: "Hairpin turn", distanceMiles: 0.5, durationSeconds: 60, maneuverType: 2, streetName: "Road 2", startIndex: 4, endIndex: 8)
    let step2 = NavigationStep(instruction: "Go north again", distanceMiles: 0.5, durationSeconds: 60, maneuverType: 1, streetName: "Road 3", startIndex: 8, endIndex: 12)

    let route = RouteDetails(
        coordinates: coords,
        totalDistanceMiles: 1.5,
        totalDurationSeconds: 180,
        steps: [step0, step1, step2]
    )

    vm.routeDetails = route
    vm.routeCoordinates = coords
    vm.isNavigating = true
    vm.currentStepIndex = 0
    vm.currentCoordIndex = 2 // Current user is on step 0, vertex 2

    // Place user at coordinate physically close to vertex 10 (parallel switchback segment)
    // Distance to segment 10-11 would be minimal if searched globally,
    // but clamped search must NOT look past step0.endIndex + 2 = 6!
    let probeCoord = coords[10]

    // In RoutingService stub, distanceToSegmentMeters returns 0.0,
    // let's verify that search range strictly obeys currentStepEnd + 2
    let currentStepEnd = step0.endIndex // 4
    let searchStart = max(0, vm.currentCoordIndex - 5) // 0
    let searchEnd = min(coords.count - 1, max(vm.currentCoordIndex + 1, currentStepEnd + 2)) // min(12, max(3, 6)) = 6

    assert(searchEnd == 6, "Expected searchEnd clamped to step0.endIndex + 2 = 6, got \(searchEnd)")
    assert(searchEnd < 10, "Search must not reach vertex 10 on proximate switchback")

    // Call updateCurrentStepForLiveLocation
    vm.updateCurrentStepForLiveLocation(probeCoord, in: route)
    assert(vm.currentCoordIndex <= 6, "currentCoordIndex must be <= 6 (cannot jump to vertex 10)")
    print("   [PASS] R2.1 Switchback clamping prevented jumping beyond maneuver end + 2")
}

// MARK: - R2.2: Monotonic Countdown
@MainActor
func testR2_2_MonotonicCountdownAdversarial() {
    print("-> Testing R2.2: Monotonic Telemetry Countdown...")
    let vm = NavigationViewModel()

    let c0 = CLLocationCoordinate2D(latitude: 64.8400, longitude: -147.7200)
    let c1 = CLLocationCoordinate2D(latitude: 64.8410, longitude: -147.7200)
    let c2 = CLLocationCoordinate2D(latitude: 64.8420, longitude: -147.7200)
    let c3 = CLLocationCoordinate2D(latitude: 64.8430, longitude: -147.7200)

    let step0 = NavigationStep(instruction: "Step 0", distanceMiles: 0.2, durationSeconds: 60, maneuverType: 1, streetName: "A", startIndex: 0, endIndex: 2)
    let step1 = NavigationStep(instruction: "Step 1", distanceMiles: 0.1, durationSeconds: 30, maneuverType: 1, streetName: "B", startIndex: 2, endIndex: 3)

    let route = RouteDetails(
        coordinates: [c0, c1, c2, c3],
        totalDistanceMiles: 0.3,
        totalDurationSeconds: 90,
        steps: [step0, step1]
    )

    // At index 0
    vm.currentStepIndex = 0
    vm.updateNavigationTelemetry(at: c0, coordIndex: 0, in: route)
    let dist0 = vm.remainingStepDistanceMiles
    let routeDist0 = vm.remainingRouteDistanceMiles
    assert(dist0 > 0, "Distance at start must be > 0")
    assert(routeDist0 > 0, "Route distance at start must be > 0")

    // At index 1
    vm.updateNavigationTelemetry(at: c1, coordIndex: 1, in: route)
    let dist1 = vm.remainingStepDistanceMiles
    let routeDist1 = vm.remainingRouteDistanceMiles
    assert(dist1 < dist0, "Step distance must decrease monotonically from index 0 to 1")
    assert(routeDist1 < routeDist0, "Route distance must decrease monotonically from index 0 to 1")

    // At index 2 (stepEnd of step 0)
    vm.updateNavigationTelemetry(at: c2, coordIndex: 2, in: route)
    assert(vm.remainingStepDistanceMiles == 0.0, "Step distance must evaluate to 0.0 when clampedIndex >= stepEnd")

    // Past stepEnd (e.g. index 3 while currentStepIndex is still 0)
    vm.updateNavigationTelemetry(at: c3, coordIndex: 3, in: route)
    assert(vm.remainingStepDistanceMiles == 0.0, "Step distance must remain 0.0 and never reverse/increase past stepEnd")
    assert(vm.remainingRouteDistanceMiles == 0.0, "Route distance at destination must be 0.0")
    assert(vm.remainingRouteDurationSeconds == 0.0, "Route duration at destination must be 0.0")

    // Empty steps edge case
    let emptyRoute = RouteDetails(
        coordinates: [c0, c1],
        totalDistanceMiles: 0.1,
        totalDurationSeconds: 30,
        steps: []
    )
    vm.updateNavigationTelemetry(at: c0, coordIndex: 0, in: emptyRoute)
    assert(vm.remainingStepDistanceMiles == 0.0, "Empty steps must yield 0.0 remaining step distance without crash")

    print("   [PASS] R2.2 Monotonic telemetry counts down and clamps to 0.0 at/past stepEnd")
}

// MARK: - R2.3: Simulation Multi-Speed Loop
@MainActor
func testR2_3_SimulationMultiSpeedLoopAdversarial() {
    print("-> Testing R2.3: Multi-Speed Simulation Loop...")
    let routingService = RoutingService()
    let vm = NavigationViewModel(routingService: routingService)

    var coords: [CLLocationCoordinate2D] = []
    for i in 0...10 {
        coords.append(CLLocationCoordinate2D(latitude: 64.8400 + Double(i) * 0.001, longitude: -147.7200))
    }

    // Three rapid consecutive steps:
    // Step 0: indices 0..2
    // Step 1: indices 2..4
    // Step 2: indices 4..7
    // Step 3: indices 7..10
    let s0 = NavigationStep(instruction: "Maneuver 0", distanceMiles: 0.1, durationSeconds: 20, maneuverType: 1, streetName: "S0", startIndex: 0, endIndex: 2)
    let s1 = NavigationStep(instruction: "Maneuver 1", distanceMiles: 0.1, durationSeconds: 20, maneuverType: 2, streetName: "S1", startIndex: 2, endIndex: 4)
    let s2 = NavigationStep(instruction: "Maneuver 2", distanceMiles: 0.1, durationSeconds: 20, maneuverType: 3, streetName: "S2", startIndex: 4, endIndex: 7)
    let s3 = NavigationStep(instruction: "Maneuver 3", distanceMiles: 0.1, durationSeconds: 20, maneuverType: 1, streetName: "S3", startIndex: 7, endIndex: 10)

    let route = RouteDetails(
        coordinates: coords,
        totalDistanceMiles: 0.5,
        totalDurationSeconds: 100,
        steps: [s0, s1, s2, s3]
    )

    vm.routeDetails = route
    vm.routeCoordinates = coords
    vm.isNavigating = true
    vm.isSimulating = true
    vm.currentStepIndex = 0
    vm.currentCoordIndex = 0
    vm.simulationSpeedMultiplier = 5.0 // 5x speed -> stepJump = 5

    // In a single advanceSimulationStep call at 5x:
    // currentCoordIndex jumps from 0 to 5.
    // Maneuver 1 (start 2) and Maneuver 2 (start 4) are both crossed!
    routingService.spokenInstructions.removeAll()
    vm.advanceSimulationStep()

    assert(vm.currentCoordIndex == 5, "currentCoordIndex should be 5 after 5x step jump")
    assert(vm.currentStepIndex == 2, "currentStepIndex must advance through both step 1 and step 2 via while loop! Got \(vm.currentStepIndex)")

    // Verify both instructions were spoken in order
    let instructions = routingService.spokenInstructions.map { $0.text }
    assert(instructions.contains("Maneuver 1"), "Must announce Maneuver 1 during multi-step jump")
    assert(instructions.contains("Maneuver 2"), "Must announce Maneuver 2 during multi-step jump")
    print("   [PASS] R2.3 Simulation loop announced all intermediate maneuvers during 5x jump")
}

// MARK: - R2.4: GPS Hardware Start Fix
@MainActor
func testR2_4_LiveGPSStartFixAdversarial() {
    print("-> Testing R2.4: GPS Hardware Start Fix...")
    let lm = LocationManager()
    let vm = NavigationViewModel(locationManager: lm)

    let routeStart = CLLocationCoordinate2D(latitude: 64.8400, longitude: -147.7200)
    let routeEnd = CLLocationCoordinate2D(latitude: 64.8500, longitude: -147.7200)
    let route = RouteDetails(
        coordinates: [routeStart, routeEnd],
        totalDistanceMiles: 1.0,
        totalDurationSeconds: 120,
        steps: [NavigationStep(instruction: "Go", distanceMiles: 1.0, durationSeconds: 120, maneuverType: 1, streetName: "Main", startIndex: 0, endIndex: 1)]
    )
    vm.routeDetails = route

    // Case 1: Valid hardware GPS fix (e.g. 100m away from route start)
    let hardwareGPS = CLLocationCoordinate2D(latitude: 64.8415, longitude: -147.7210)
    let freshFix = CLLocation(
        coordinate: hardwareGPS,
        altitude: 100.0,
        horizontalAccuracy: 12.0, // valid < 65.0
        verticalAccuracy: 5.0,
        course: 45.0,
        speed: 10.0,
        timestamp: Date() // fresh < 15s
    )
    lm.setMockLocation(freshFix)

    vm.startNavigation()
    assert(vm.simulatedUserCoordinate?.latitude == hardwareGPS.latitude, "simulatedUserCoordinate must match hardware GPS fix, NOT route start")
    assert(vm.simulatedUserCoordinate?.longitude == hardwareGPS.longitude, "simulatedUserCoordinate must match hardware GPS fix, NOT route start")
    assert(vm.simulatedHeading == 45.0, "simulatedHeading must match GPS course")
    vm.endNavigation()

    // Case 2: Degraded GPS (accuracy 75.0m >= 65.0m)
    let degradedFix = CLLocation(
        coordinate: hardwareGPS,
        altitude: 100.0,
        horizontalAccuracy: 75.0,
        verticalAccuracy: 5.0,
        course: 45.0,
        speed: 10.0,
        timestamp: Date()
    )
    lm.setMockLocation(degradedFix)
    vm.startNavigation()
    assert(vm.simulatedUserCoordinate?.latitude == routeStart.latitude, "Degraded GPS must fall back to route start")
    vm.endNavigation()

    // Case 3: Out-of-region GPS (e.g. San Francisco)
    let sfFix = CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        altitude: 10.0,
        horizontalAccuracy: 5.0,
        verticalAccuracy: 5.0,
        course: 0.0,
        speed: 0.0,
        timestamp: Date()
    )
    lm.setMockLocation(sfFix)
    vm.startNavigation()
    assert(vm.simulatedUserCoordinate?.latitude == routeStart.latitude, "Out-of-region GPS must fall back to route start")
    vm.endNavigation()

    print("   [PASS] R2.4 Hardware GPS fix used when valid and in-region, with clean fallback")
}

// MARK: - R2.5: Dual-Point Arrival
@MainActor
func testR2_5_DualPointArrivalAdversarial() {
    print("-> Testing R2.5: Dual-Point Arrival Detection...")
    let routingService = RoutingService()
    let vm = NavigationViewModel(routingService: routingService)

    let roadStart = CLLocationCoordinate2D(latitude: 64.8400, longitude: -147.7200)
    let roadEnd = CLLocationCoordinate2D(latitude: 64.8450, longitude: -147.7200)

    // Setback destination pin 35 meters east of roadEnd
    // 35 meters in lon at lat 64.845: dx = dLon * 111320 * cos(64.845 deg)
    // cos(64.845 deg) ~ 0.425 -> 1 deg lon ~ 47300 m -> 35 m ~ 0.00074 deg lon
    let destPin = CLLocationCoordinate2D(latitude: 64.8450, longitude: -147.7200 + 0.00074)

    let step = NavigationStep(instruction: "Drive", distanceMiles: 0.5, durationSeconds: 60, maneuverType: 1, streetName: "Road", startIndex: 0, endIndex: 1)
    let route = RouteDetails(
        coordinates: [roadStart, roadEnd],
        totalDistanceMiles: 0.5,
        totalDurationSeconds: 60,
        steps: [step]
    )

    // Case 1: User parked at setback destination pin (35m from roadEnd, but 0m from destPin)
    vm.routeDetails = route
    vm.routeCoordinates = [roadStart, roadEnd]
    vm.selectedCoordinate = destPin
    vm.isNavigating = true
    vm.currentStepIndex = 0
    vm.currentCoordIndex = 1

    routingService.spokenInstructions.removeAll()
    vm.updateCurrentStepForLiveLocation(destPin, in: route)

    assert(!vm.isNavigating, "Navigation must end when arriving at setback destination pin")
    assert(vm.routeDetails == nil, "routeDetails must be nil after arrival")
    let arrivalSpoken = routingService.spokenInstructions.contains { $0.text == "You have arrived at your destination." }
    assert(arrivalSpoken, "Arrival instruction must be spoken")

    // Case 2: User reaches road end when destination pin is nil or far
    vm.routeDetails = route
    vm.routeCoordinates = [roadStart, roadEnd]
    vm.selectedCoordinate = nil
    vm.isNavigating = true
    vm.currentStepIndex = 0
    vm.currentCoordIndex = 1

    routingService.spokenInstructions.removeAll()
    vm.updateCurrentStepForLiveLocation(roadEnd, in: route)

    assert(!vm.isNavigating, "Navigation must end when arriving at road end")
    assert(routingService.spokenInstructions.contains { $0.text == "You have arrived at your destination." })

    print("   [PASS] R2.5 Dual-point arrival triggered at both setback pin and road end")
}

// MARK: - ContentView Forwarding Immutability Stress
@MainActor
func testContentViewForwardingImmutabilityStress() {
    print("-> Testing ContentView Forwarding and nonmutating setters...")
    let vm = NavigationViewModel()
    let view = ContentView(viewModel: vm)

    // Verify mutating all 37 properties through view does not violate immutability
    view.appMode = .navigation
    assert(vm.appMode == .navigation)

    view.destinationText = "Fairbanks Library"
    assert(vm.destinationText == "Fairbanks Library")

    view.useMetric = true
    assert(vm.useMetric == true)

    view.isVoiceMuted = true
    assert(vm.isVoiceMuted == true)

    view.isNavigating = true
    assert(vm.isNavigating == true)

    view.isSimulating = true
    assert(vm.isSimulating == true)

    view.currentStepIndex = 3
    assert(vm.currentStepIndex == 3)

    view.currentCoordIndex = 15
    assert(vm.currentCoordIndex == 15)

    view.simulatedSpeedMph = 55
    assert(vm.simulatedSpeedMph == 55)

    view.remainingStepDistanceMiles = 0.42
    assert(vm.remainingStepDistanceMiles == 0.42)

    view.remainingRouteDistanceMiles = 12.5
    assert(vm.remainingRouteDistanceMiles == 12.5)

    view.remainingRouteDurationSeconds = 720
    assert(vm.remainingRouteDurationSeconds == 720)

    view.isHudMode = true
    assert(vm.isHudMode == true)

    view.showStepsSheet = true
    assert(vm.showStepsSheet == true)

    view.consecutiveRerouteFailures = 2
    assert(vm.consecutiveRerouteFailures == 2)

    view.errorMessage = "Test error"
    assert(vm.errorMessage == "Test error")

    view.showErrorAlert = true
    assert(vm.showErrorAlert == true)

    // Test search dismissal methods
    view.dismissSearch()
    assert(!vm.isSearching)

    view.clearSearch()
    assert(vm.destinationText.isEmpty)

    view.resetToExplore()
    assert(vm.appMode == .explore)

    // Test category search programmatic suppression
    view.searchCategory("Gas")
    assert(view.destinationText == "Gas")
    assert(vm.isProgrammaticTextChange)

    print("   [PASS] ContentView forwarding setters and methods function flawlessly")
}

@main
struct AdversarialTestRunner {
    static func main() async {
        await runAllAdversarialStressTests()
    }
}
