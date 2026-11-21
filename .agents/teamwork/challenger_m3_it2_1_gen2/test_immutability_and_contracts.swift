import Foundation
import CoreLocation
import SwiftUI

@main
struct Verifier {
    @MainActor
    static func main() async {
        print("=== STARTING IMMUTABILITY & CONTRACT VERIFICATION ===")

        // Test 1: Instantiate ContentView as an immutable 'let' constant
        let view = ContentView()
        print("PASS 1: Instantiated immutable 'let view = ContentView()'")

        // Test 2: Verify nonmutating property assignments on 'let view'
        view.isHudMode = true
        assert(view.isHudMode == true, "view.isHudMode should be true")
        assert(view.viewModel.isHudMode == true, "viewModel.isHudMode should be true")
        print("PASS 2: view.isHudMode = true on immutable 'let view' succeeded")

        view.isHudMode = false
        assert(view.isHudMode == false, "view.isHudMode should be false")
        assert(view.viewModel.isHudMode == false, "viewModel.isHudMode should be false")
        print("PASS 3: view.isHudMode = false on immutable 'let view' succeeded")

        // Test 3: Verify searchCategory(_:) on 'let view'
        view.destinationText = ""
        view.isProgrammaticTextChange = false
        view.searchCategory("Groceries")
        assert(view.destinationText == "Groceries", "view.destinationText should be 'Groceries', got '\(view.destinationText)'")
        assert(view.viewModel.destinationText == "Groceries", "viewModel.destinationText should be 'Groceries'")
        print("PASS 4: view.searchCategory('Groceries') executed on immutable 'let view'")

        // Test 4: Verify all 37 forwarding properties on 'let view' can be read and written
        view.appMode = .placeDetail
        assert(view.appMode == .placeDetail)

        let testPlace = SearchResult(id: 42, name: "Test Spot", lat: 64.84, lon: -147.72, category: "cafe")
        view.selectedPlace = testPlace
        assert(view.selectedPlace?.id == 42)

        let step = NavigationStep(
            instruction: "Turn right",
            distanceMiles: 0.5,
            durationSeconds: 30,
            maneuverType: 2,
            streetName: "2nd Ave",
            startIndex: 0,
            endIndex: 1
        )
        let details = RouteDetails(
            coordinates: [CLLocationCoordinate2D(latitude: 64.84, longitude: -147.72)],
            totalDistanceMiles: 0.5,
            totalDurationSeconds: 30,
            steps: [step]
        )
        view.routeDetails = details
        assert(view.routeDetails?.steps.count == 1)

        view.selectedTravelMode = "pedestrian"
        assert(view.selectedTravelMode == "pedestrian")

        view.showStepsSheet = true
        assert(view.showStepsSheet == true)

        view.useMetric = true
        assert(view.useMetric == true)

        view.isVoiceMuted = true
        assert(view.isVoiceMuted == true)

        view.searchResults = [testPlace]
        assert(view.searchResults.count == 1)

        view.isSearching = true
        assert(view.isSearching == true)

        view.searchTask = nil
        assert(view.searchTask == nil)

        view.isProgrammaticTextChange = true
        assert(view.isProgrammaticTextChange == true)

        let coord = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        view.selectedCoordinate = coord
        assert(view.selectedCoordinate?.latitude == coord.latitude)

        view.routeCoordinates = [coord]
        assert(view.routeCoordinates?.count == 1)

        view.simulatedUserCoordinate = coord
        assert(view.simulatedUserCoordinate?.latitude == coord.latitude)

        view.userLocationCenter = coord
        assert(view.userLocationCenter?.latitude == coord.latitude)

        view.simulatedHeading = 180.0
        assert(view.simulatedHeading == 180.0)

        view.zoomStep = 15.0
        assert(view.zoomStep == 15.0)

        view.isNavigating = true
        assert(view.isNavigating == true)

        view.isSimulating = true
        assert(view.isSimulating == true)

        view.currentStepIndex = 3
        assert(view.currentStepIndex == 3)

        view.currentCoordIndex = 7
        assert(view.currentCoordIndex == 7)

        view.simulatedSpeedMph = 45
        assert(view.simulatedSpeedMph == 45)

        view.simulationSpeedMultiplier = 2.0
        assert(view.simulationSpeedMultiplier == 2.0)

        view.isRecalculating = true
        assert(view.isRecalculating == true)

        view.consecutiveRerouteFailures = 2
        assert(view.consecutiveRerouteFailures == 2)

        let now = Date()
        view.lastRerouteTime = now
        assert(view.lastRerouteTime == now)

        let reqId = UUID()
        view.activeRouteRequestId = reqId
        assert(view.activeRouteRequestId == reqId)

        view.remainingStepDistanceMiles = 1.25
        assert(view.remainingStepDistanceMiles == 1.25)

        view.remainingRouteDistanceMiles = 5.5
        assert(view.remainingRouteDistanceMiles == 5.5)

        view.remainingRouteDurationSeconds = 450.0
        assert(view.remainingRouteDurationSeconds == 450.0)

        view.dynamicArrivalDate = now
        assert(view.dynamicArrivalDate == now)

        view.hasAnnouncedAdvanceTurn = true
        assert(view.hasAnnouncedAdvanceTurn == true)

        view.errorMessage = "Test Error"
        assert(view.errorMessage == "Test Error")

        view.showErrorAlert = true
        assert(view.showErrorAlert == true)

        view.isMapDataMissing = true
        assert(view.isMapDataMissing == true)

        print("PASS 5: All 37 forwarding properties confirmed nonmutating set and read/write verified!")

        // Test 5: Verify lifecycle methods
        view.dismissSearch()
        assert(view.isSearching == false)
        assert(view.searchResults.isEmpty)

        view.clearSearch()
        assert(view.destinationText.isEmpty)

        view.resetToExplore()
        assert(view.appMode == .explore)
        assert(view.isNavigating == false)
        assert(view.isSimulating == false)

        print("PASS 6: dismissSearch, clearSearch, resetToExplore executed cleanly!")
        print("=== ALL IMMUTABILITY VERIFICATION CHECKS PASSED ===")
    }
}
