
import Foundation
import CoreLocation

@MainActor
func testForwardingProperties() {
    let vm = NavigationViewModel()
    let view = ContentView(viewModel: vm)

    // Test writing to all 37 properties on immutable let view!
    view.appMode = .searchList
    assert(view.appMode == .searchList)
    assert(vm.appMode == .searchList)

    view.selectedPlace = SearchResult(id: 1, name: "Test Place")
    assert(view.selectedPlace?.name == "Test Place")

    let dummyDetails = RouteDetails(totalDistanceMiles: 12.5)
    view.routeDetails = dummyDetails
    assert(view.routeDetails?.totalDistanceMiles == 12.5)

    view.selectedTravelMode = "pedestrian"
    assert(view.selectedTravelMode == "pedestrian")

    view.showStepsSheet = true
    assert(view.showStepsSheet == true)

    view.isHudMode = true
    assert(view.isHudMode == true)

    view.useMetric = true
    assert(view.useMetric == true)

    view.isVoiceMuted = true
    assert(view.isVoiceMuted == true)

    view.destinationText = "Fairbanks"
    assert(view.destinationText == "Fairbanks")

    view.searchResults = [SearchResult(id: 2, name: "Result 2")]
    assert(view.searchResults.count == 1)

    view.isSearching = true
    assert(view.isSearching == true)

    view.searchTask = nil

    view.isProgrammaticTextChange = true
    assert(view.isProgrammaticTextChange == true)

    let coord = CLLocationCoordinate2D(latitude: 64.0, longitude: -147.0)
    view.selectedCoordinate = coord
    assert(view.selectedCoordinate?.latitude == 64.0)

    view.routeCoordinates = [coord]
    assert(view.routeCoordinates?.count == 1)

    view.simulatedUserCoordinate = coord
    assert(view.simulatedUserCoordinate?.latitude == 64.0)

    view.userLocationCenter = coord
    assert(view.userLocationCenter?.latitude == 64.0)

    view.simulatedHeading = 90.0
    assert(view.simulatedHeading == 90.0)

    view.zoomStep = 1.0
    assert(view.zoomStep == 1.0)

    view.isNavigating = true
    assert(view.isNavigating == true)

    view.isSimulating = true
    assert(view.isSimulating == true)

    view.currentStepIndex = 3
    assert(view.currentStepIndex == 3)

    view.currentCoordIndex = 5
    assert(view.currentCoordIndex == 5)

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

    let uuid = UUID()
    view.activeRouteRequestId = uuid
    assert(view.activeRouteRequestId == uuid)

    view.remainingStepDistanceMiles = 1.2
    assert(view.remainingStepDistanceMiles == 1.2)

    view.remainingRouteDistanceMiles = 8.4
    assert(view.remainingRouteDistanceMiles == 8.4)

    view.remainingRouteDurationSeconds = 600.0
    assert(view.remainingRouteDurationSeconds == 600.0)

    view.dynamicArrivalDate = now
    assert(view.dynamicArrivalDate == now)

    view.hasAnnouncedAdvanceTurn = true
    assert(view.hasAnnouncedAdvanceTurn == true)

    view.errorMessage = "Error"
    assert(view.errorMessage == "Error")

    view.showErrorAlert = true
    assert(view.showErrorAlert == true)

    view.isMapDataMissing = true
    assert(view.isMapDataMissing == true)

    print("All 37 nonmutating setters on immutable let view PASSED!")
}
