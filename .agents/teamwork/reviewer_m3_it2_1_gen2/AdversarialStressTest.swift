import Foundation
import CoreLocation
import Combine
import SwiftUI

@main
struct AdversarialRunner {
    @MainActor
    static func main() async {
        print("==================================================")
        print("Starting Reviewer Adversarial Stress Test Suite")
        print("==================================================")

        var testsPassed = 0
        var testsFailed = 0

        func check(_ condition: Bool, _ name: String) {
            if condition {
                print("  ✅ PASS: \(name)")
                testsPassed += 1
            } else {
                print("  ❌ FAIL: \(name)")
                testsFailed += 1
            }
        }

        // ----------------------------------------------------
        // TEST 1: Forwarding Setters Mutability on Immutable `let`
        // ----------------------------------------------------
        print("\n--- Test Suite 1: Forwarding Setters on Immutable 'let' ContentView ---")
        do {
            let view = ContentView() // Immutable value type 'let'

            // Mutating through nonmutating setters on immutable let binding:
            view.appMode = .navigation
            check(view.appMode == .navigation && view.viewModel.appMode == .navigation, "appMode nonmutating set works on let binding")

            let testPlace = SearchResult(id: 999, name: "Denali", lat: 63.0692, lon: -151.0070)
            view.selectedPlace = testPlace
            check(view.selectedPlace?.name == "Denali" && view.viewModel.selectedPlace?.name == "Denali", "selectedPlace nonmutating set works")

            view.selectedTravelMode = "bicycle"
            check(view.selectedTravelMode == "bicycle" && view.viewModel.selectedTravelMode == "bicycle", "selectedTravelMode nonmutating set works")

            view.showStepsSheet = true
            check(view.showStepsSheet == true && view.viewModel.showStepsSheet == true, "showStepsSheet nonmutating set works")

            view.isHudMode = true
            check(view.isHudMode == true && view.viewModel.isHudMode == true, "isHudMode nonmutating set works")

            view.destinationText = "Fairbanks"
            check(view.destinationText == "Fairbanks" && view.viewModel.destinationText == "Fairbanks", "destinationText nonmutating set works")

            view.searchResults = [testPlace]
            check(view.searchResults.count == 1 && view.viewModel.searchResults.count == 1, "searchResults nonmutating set works")

            view.isSearching = true
            check(view.isSearching == true && view.viewModel.isSearching == true, "isSearching nonmutating set works")

            view.isProgrammaticTextChange = true
            check(view.isProgrammaticTextChange == true && view.viewModel.isProgrammaticTextChange == true, "isProgrammaticTextChange nonmutating set works")

            let testCoord = CLLocationCoordinate2D(latitude: 64.84, longitude: -147.72)
            view.selectedCoordinate = testCoord
            check(view.selectedCoordinate?.latitude == 64.84 && view.viewModel.selectedCoordinate?.latitude == 64.84, "selectedCoordinate nonmutating set works")

            view.routeCoordinates = [testCoord]
            check(view.routeCoordinates?.count == 1 && view.viewModel.routeCoordinates?.count == 1, "routeCoordinates nonmutating set works")

            view.simulatedUserCoordinate = testCoord
            check(view.simulatedUserCoordinate?.latitude == 64.84 && view.viewModel.simulatedUserCoordinate?.latitude == 64.84, "simulatedUserCoordinate nonmutating set works")

            view.userLocationCenter = testCoord
            check(view.userLocationCenter?.latitude == 64.84 && view.viewModel.userLocationCenter?.latitude == 64.84, "userLocationCenter nonmutating set works")

            view.simulatedHeading = 180.0
            check(view.simulatedHeading == 180.0 && view.viewModel.simulatedHeading == 180.0, "simulatedHeading nonmutating set works")

            view.zoomStep = 2.0
            check(view.zoomStep == 2.0 && view.viewModel.zoomStep == 2.0, "zoomStep nonmutating set works")

            view.isNavigating = true
            check(view.isNavigating == true && view.viewModel.isNavigating == true, "isNavigating nonmutating set works")

            view.isSimulating = true
            check(view.isSimulating == true && view.viewModel.isSimulating == true, "isSimulating nonmutating set works")

            view.currentStepIndex = 5
            check(view.currentStepIndex == 5 && view.viewModel.currentStepIndex == 5, "currentStepIndex nonmutating set works")

            view.currentCoordIndex = 12
            check(view.currentCoordIndex == 12 && view.viewModel.currentCoordIndex == 12, "currentCoordIndex nonmutating set works")

            view.simulatedSpeedMph = 55
            check(view.simulatedSpeedMph == 55 && view.viewModel.simulatedSpeedMph == 55, "simulatedSpeedMph nonmutating set works")

            view.simulationSpeedMultiplier = 5.0
            check(view.simulationSpeedMultiplier == 5.0 && view.viewModel.simulationSpeedMultiplier == 5.0, "simulationSpeedMultiplier nonmutating set works")

            view.isRecalculating = true
            check(view.isRecalculating == true && view.viewModel.isRecalculating == true, "isRecalculating nonmutating set works")

            view.consecutiveRerouteFailures = 2
            check(view.consecutiveRerouteFailures == 2 && view.viewModel.consecutiveRerouteFailures == 2, "consecutiveRerouteFailures nonmutating set works")

            let now = Date()
            view.lastRerouteTime = now
            check(view.lastRerouteTime == now && view.viewModel.lastRerouteTime == now, "lastRerouteTime nonmutating set works")

            let reqId = UUID()
            view.activeRouteRequestId = reqId
            check(view.activeRouteRequestId == reqId && view.viewModel.activeRouteRequestId == reqId, "activeRouteRequestId nonmutating set works")

            view.remainingStepDistanceMiles = 2.5
            check(view.remainingStepDistanceMiles == 2.5 && view.viewModel.remainingStepDistanceMiles == 2.5, "remainingStepDistanceMiles nonmutating set works")

            view.remainingRouteDistanceMiles = 15.0
            check(view.remainingRouteDistanceMiles == 15.0 && view.viewModel.remainingRouteDistanceMiles == 15.0, "remainingRouteDistanceMiles nonmutating set works")

            view.remainingRouteDurationSeconds = 900.0
            check(view.remainingRouteDurationSeconds == 900.0 && view.viewModel.remainingRouteDurationSeconds == 900.0, "remainingRouteDurationSeconds nonmutating set works")

            view.dynamicArrivalDate = now
            check(view.dynamicArrivalDate == now && view.viewModel.dynamicArrivalDate == now, "dynamicArrivalDate nonmutating set works")

            view.hasAnnouncedAdvanceTurn = true
            check(view.hasAnnouncedAdvanceTurn == true && view.viewModel.hasAnnouncedAdvanceTurn == true, "hasAnnouncedAdvanceTurn nonmutating set works")

            view.errorMessage = "Test Error"
            check(view.errorMessage == "Test Error" && view.viewModel.errorMessage == "Test Error", "errorMessage nonmutating set works")

            view.showErrorAlert = true
            check(view.showErrorAlert == true && view.viewModel.showErrorAlert == true, "showErrorAlert nonmutating set works")

            view.isMapDataMissing = true
            check(view.isMapDataMissing == true && view.viewModel.isMapDataMissing == true, "isMapDataMissing nonmutating set works")
        }

        // ----------------------------------------------------
        // TEST 2: AppStorage Persistence & objectWillChange Notification
        // ----------------------------------------------------
        print("\n--- Test Suite 2: AppStorage Persistence & objectWillChange Notification ---")
        do {
            // Reset UserDefaults keys
            UserDefaults.standard.removeObject(forKey: "useMetric")
            UserDefaults.standard.removeObject(forKey: "isVoiceMuted")

            // 1. Initial default state
            let vm1 = NavigationViewModel()
            check(vm1.useMetric == false, "Initial default useMetric is false")
            check(vm1.isVoiceMuted == false, "Initial default isVoiceMuted is false")

            // 2. Set up observation for objectWillChange
            var vm1ChangeCount = 0
            let cancellable = vm1.objectWillChange.sink { _ in
                vm1ChangeCount += 1
            }

            vm1.useMetric = true
            check(vm1ChangeCount >= 1, "useMetric mutation emits objectWillChange")
            check(UserDefaults.standard.bool(forKey: "useMetric") == true, "useMetric persisted to UserDefaults")

            let changeBeforeMute = vm1ChangeCount
            vm1.isVoiceMuted = true
            check(vm1ChangeCount > changeBeforeMute, "isVoiceMuted mutation emits objectWillChange")
            check(UserDefaults.standard.bool(forKey: "isVoiceMuted") == true, "isVoiceMuted persisted to UserDefaults")
            check(vm1.routingService.isVoiceMuted == true, "routingService.isVoiceMuted synchronized on mutation")

            _ = cancellable

            // 3. Re-instantiate in a new instance (simulating app relaunch)
            let vm2 = NavigationViewModel()
            check(vm2.useMetric == true, "App relaunch: useMetric restored from AppStorage")
            check(vm2.isVoiceMuted == true, "App relaunch: isVoiceMuted restored from AppStorage")
            check(vm2.routingService.isVoiceMuted == true, "App relaunch: routingService isVoiceMuted synchronized on init")

            // 4. Test mutation via ContentView forwarding properties
            let contentView = ContentView(viewModel: vm2)
            contentView.useMetric = false
            check(UserDefaults.standard.bool(forKey: "useMetric") == false, "ContentView.useMetric forwarding updates UserDefaults")
            contentView.isVoiceMuted = false
            check(UserDefaults.standard.bool(forKey: "isVoiceMuted") == false, "ContentView.isVoiceMuted forwarding updates UserDefaults")
        }

        // ----------------------------------------------------
        // TEST 3: Multi-Speed Simulation Loop (Intermediate Maneuvers)
        // ----------------------------------------------------
        print("\n--- Test Suite 3: Multi-Speed Simulation Loop ---")
        do {
            let vm = NavigationViewModel()
            // Create 3 steps with 10 coords each: total 30 coords
            var coords: [CLLocationCoordinate2D] = []
            for i in 0..<30 {
                coords.append(CLLocationCoordinate2D(latitude: 64.8400 + Double(i) * 0.001, longitude: -147.7200))
            }
            let step0 = NavigationStep(instruction: "Step 0", distanceMiles: 0.5, durationSeconds: 60, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 9)
            let step1 = NavigationStep(instruction: "Step 1", distanceMiles: 0.5, durationSeconds: 60, maneuverType: 1, streetName: nil, startIndex: 10, endIndex: 19)
            let step2 = NavigationStep(instruction: "Step 2", distanceMiles: 0.5, durationSeconds: 60, maneuverType: 1, streetName: nil, startIndex: 20, endIndex: 29)
            let details = RouteDetails(coordinates: coords, totalDistanceMiles: 1.5, totalDurationSeconds: 180, steps: [step0, step1, step2])

            vm.routeDetails = details
            vm.routeCoordinates = coords
            vm.isNavigating = true
            vm.isSimulating = true
            vm.currentCoordIndex = 8
            vm.currentStepIndex = 0
            vm.simulationSpeedMultiplier = 5.0 // jumps 5 coordinates at once!

            // Advance simulation: jumping from 8 to 13 should advance from Step 0 to Step 1!
            vm.advanceSimulationStep()
            check(vm.currentCoordIndex == 13, "Coordinate jumped to index 13 at 5x")
            check(vm.currentStepIndex == 1, "Simulation while loop advanced to Step 1")

            // Jump again: from 13 to 18 (still Step 1)
            vm.advanceSimulationStep()
            check(vm.currentCoordIndex == 18, "Coordinate jumped to index 18")
            check(vm.currentStepIndex == 1, "Still Step 1")

            // Jump again: from 18 to 23 (skips over boundary at 20 into Step 2)
            vm.advanceSimulationStep()
            check(vm.currentCoordIndex == 23, "Coordinate jumped to index 23")
            check(vm.currentStepIndex == 2, "Simulation while loop advanced to Step 2 without dropping maneuver")
        }

        // ----------------------------------------------------
        // TEST 4: Telemetry Monotonic Countdown & Dual-Point Arrival
        // ----------------------------------------------------
        print("\n--- Test Suite 4: Telemetry Countdown & Dual-Point Arrival ---")
        do {
            let vm = NavigationViewModel()
            var coords: [CLLocationCoordinate2D] = []
            for i in 0..<10 {
                coords.append(CLLocationCoordinate2D(latitude: 64.8400 + Double(i) * 0.001, longitude: -147.7200))
            }
            let step0 = NavigationStep(instruction: "Step 0", distanceMiles: 0.5, durationSeconds: 60, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 5)
            let step1 = NavigationStep(instruction: "Step 1", distanceMiles: 0.5, durationSeconds: 60, maneuverType: 1, streetName: nil, startIndex: 6, endIndex: 9)
            let details = RouteDetails(coordinates: coords, totalDistanceMiles: 1.0, totalDurationSeconds: 120, steps: [step0, step1])

            vm.routeDetails = details
            vm.routeCoordinates = coords
            vm.isNavigating = true
            vm.currentStepIndex = 0

            // Test telemetry at index 2
            vm.updateNavigationTelemetry(at: coords[2], coordIndex: 2, in: details)
            let distAt2 = vm.remainingStepDistanceMiles
            check(distAt2 > 0.0, "Remaining step distance at index 2 is positive")

            // Test telemetry at index 4
            vm.updateNavigationTelemetry(at: coords[4], coordIndex: 4, in: details)
            let distAt4 = vm.remainingStepDistanceMiles
            check(distAt4 < distAt2, "Step distance counts down monotonically (\(distAt4) < \(distAt2))")

            // Test telemetry at index 5 (stepEnd)
            vm.updateNavigationTelemetry(at: coords[5], coordIndex: 5, in: details)
            check(vm.remainingStepDistanceMiles == 0.0, "Remaining step distance evaluates to 0.0 at stepEnd")

            // Test telemetry beyond stepEnd
            vm.updateNavigationTelemetry(at: coords[6], coordIndex: 6, in: details)
            check(vm.remainingStepDistanceMiles == 0.0, "Remaining step distance remains 0.0 past stepEnd without reversal")

            // Test Dual-Point Arrival: user near pin (setback parking lot)
            let pinDest = CLLocationCoordinate2D(latitude: 64.8490, longitude: -147.7201) // setback 10m from road end
            vm.selectedCoordinate = pinDest
            vm.currentCoordIndex = 8
            vm.currentStepIndex = 1

            let userNearPin = CLLocationCoordinate2D(latitude: 64.8490, longitude: -147.7201)
            vm.updateCurrentStepForLiveLocation(userNearPin, in: details)
            check(vm.isNavigating == false, "Dual-point arrival triggers navigation end when user reaches setback pin")
        }

        print("\n==================================================")
        print("Reviewer Adversarial Stress Test Summary:")
        print("  Passed: \(testsPassed)")
        print("  Failed: \(testsFailed)")
        print("==================================================")
        assert(testsFailed == 0, "Some adversarial stress tests failed!")
    }
}
