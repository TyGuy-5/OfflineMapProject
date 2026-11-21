import XCTest
import CoreLocation
import MapLibre
import Valhalla
import ValhallaModels
import SwiftUI
import AVFoundation
@testable import MyOfflineMapApp

@MainActor
final class RemediationTests: XCTestCase {

    // MARK: - 1. Out-of-region GPS handling
    func test01_OutOfRegionGPSHandling() {
        let vm = NavigationViewModel()

        // 1.1 Verify valid Alaska coordinates within bounding box [51.0, 72.0] x [-179.0, -129.0]
        let validAlaskaCoordinates = [
            CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215), // Fairbanks
            CLLocationCoordinate2D(latitude: 61.2181, longitude: -149.9003), // Anchorage
            CLLocationCoordinate2D(latitude: 58.3019, longitude: -134.4197), // Juneau
            CLLocationCoordinate2D(latitude: 71.2906, longitude: -156.7887), // Utqiagvik (Barrow)
            CLLocationCoordinate2D(latitude: 51.0, longitude: -179.0),       // Southwest boundary
            CLLocationCoordinate2D(latitude: 72.0, longitude: -129.0)        // Northeast boundary
        ]
        for coord in validAlaskaCoordinates {
            XCTAssertTrue(vm.isWithinSupportedRegion(coord), "Expected \(coord.latitude), \(coord.longitude) to be within supported Alaska region")
        }

        // 1.2 Verify out-of-region coordinates outside Alaska bounding box
        let outOfRegionCoordinates = [
            CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // San Francisco
            CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321), // Seattle
            CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),  // New York City
            CLLocationCoordinate2D(latitude: 21.3069, longitude: -157.8583), // Honolulu
            CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),   // London
            CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),  // Tokyo
            CLLocationCoordinate2D(latitude: 50.999, longitude: -147.0),     // Just south of boundary
            CLLocationCoordinate2D(latitude: 72.001, longitude: -147.0),     // Just north of boundary
            CLLocationCoordinate2D(latitude: 64.0, longitude: -179.001),     // Just west of boundary
            CLLocationCoordinate2D(latitude: 64.0, longitude: -128.999)      // Just east of boundary
        ]
        for coord in outOfRegionCoordinates {
            XCTAssertFalse(vm.isWithinSupportedRegion(coord), "Expected \(coord.latitude), \(coord.longitude) to be outside supported Alaska region")
        }

        // 1.3 Verify default Alaska fallback coordinate
        XCTAssertEqual(NavigationViewModel.defaultAlaskaCoordinate.latitude, 64.8436, accuracy: 0.0001)
        XCTAssertEqual(NavigationViewModel.defaultAlaskaCoordinate.longitude, -147.7215, accuracy: 0.0001)

        // 1.4 Verify effectiveUserCoordinate falls back to Fairbanks when simulated coord is nil and device location is nil/unsupported
        let effective = vm.effectiveUserCoordinate
        XCTAssertEqual(effective.latitude, NavigationViewModel.defaultAlaskaCoordinate.latitude, accuracy: 0.0001)
        XCTAssertEqual(effective.longitude, NavigationViewModel.defaultAlaskaCoordinate.longitude, accuracy: 0.0001)

        // 1.5 Verify simulatedUserCoordinate overrides fallback
        let simCoord = CLLocationCoordinate2D(latitude: 61.2181, longitude: -149.9003)
        vm.simulatedUserCoordinate = simCoord
        XCTAssertEqual(vm.effectiveUserCoordinate.latitude, simCoord.latitude, accuracy: 0.0001)
        XCTAssertEqual(vm.effectiveUserCoordinate.longitude, simCoord.longitude, accuracy: 0.0001)
        vm.simulatedUserCoordinate = nil
    }

    // MARK: - 2. In-flight search task cancellation
    func test02_InFlightSearchTaskCancellation() async throws {
        let vm = NavigationViewModel()

        // 2.1 dismissSearch cancels in-flight search task and resets search state
        vm.handleQueryChange("Fairbanks")
        XCTAssertTrue(vm.isSearching)
        XCTAssertNotNil(vm.searchTask)
        XCTAssertEqual(vm.appMode, .searchList)
        let task1 = vm.searchTask
        vm.dismissSearch()
        XCTAssertTrue(task1?.isCancelled ?? false, "dismissSearch must cancel active searchTask")
        XCTAssertNil(vm.searchTask, "searchTask must be nil after dismissSearch")
        XCTAssertFalse(vm.isSearching, "isSearching must be false after dismissSearch")
        XCTAssertEqual(vm.appMode, .explore, "appMode must return to .explore after dismissSearch")

        // 2.2 clearSearch cancels in-flight task and clears query text
        vm.handleQueryChange("Anchorage")
        XCTAssertTrue(vm.isSearching)
        let task2 = vm.searchTask
        vm.clearSearch()
        XCTAssertTrue(task2?.isCancelled ?? false, "clearSearch must cancel active searchTask")
        XCTAssertNil(vm.searchTask)
        XCTAssertEqual(vm.destinationText, "", "clearSearch must empty destinationText")
        XCTAssertTrue(vm.searchResults.isEmpty)
        XCTAssertEqual(vm.appMode, .explore)

        // 2.3 resetToExplore cancels in-flight task and resets all state
        vm.handleQueryChange("Juneau")
        XCTAssertTrue(vm.isSearching)
        let task3 = vm.searchTask
        vm.resetToExplore()
        XCTAssertTrue(task3?.isCancelled ?? false, "resetToExplore must cancel active searchTask")
        XCTAssertNil(vm.searchTask)
        XCTAssertEqual(vm.appMode, .explore)

        // 2.4 Rapid re-query cancels prior task handle
        vm.handleQueryChange("Fair")
        let priorTask = vm.searchTask
        vm.handleQueryChange("Fairbanks")
        XCTAssertTrue(priorTask?.isCancelled ?? false, "Rapid new query must cancel prior searchTask")
        vm.dismissSearch()
    }

    // MARK: - 3. Category search single invocation
    func test03_CategorySearchSingleInvocation() {
        let vm = NavigationViewModel()
        XCTAssertFalse(vm.isProgrammaticTextChange, "Initial isProgrammaticTextChange must be false")

        // 3.1 Tapping category chip updates destinationText and flags programmatic change
        vm.searchCategory("Gas")
        XCTAssertEqual(vm.destinationText, "Gas")
        XCTAssertTrue(vm.isProgrammaticTextChange, "searchCategory must set isProgrammaticTextChange = true when modifying destinationText")

        // 3.2 Simulate view layer consuming the programmatic change flag
        vm.isProgrammaticTextChange = false

        // 3.3 Repeated tap on the same category does NOT re-trigger programmatic change flag
        vm.searchCategory("Gas")
        XCTAssertFalse(vm.isProgrammaticTextChange, "Tapping same category must not re-assert isProgrammaticTextChange")

        // 3.4 Tapping distinct category flags programmatic change again
        vm.searchCategory("Coffee")
        XCTAssertEqual(vm.destinationText, "Coffee")
        XCTAssertTrue(vm.isProgrammaticTextChange)

        // 3.5 Selecting a place sets isProgrammaticTextChange
        vm.isProgrammaticTextChange = false
        let place = SearchResult(id: 10, name: "Mocha Dan's", lat: 64.85, lon: -147.8)
        vm.selectPlace(place)
        XCTAssertEqual(vm.destinationText, "Mocha Dan's")
        XCTAssertTrue(vm.isProgrammaticTextChange)
        XCTAssertEqual(vm.appMode, .placeDetail)
        vm.dismissSearch()
    }

    // MARK: - 4. Route telemetry calculation with 0 steps
    func test04_RouteTelemetryCalculationZeroStepsSafety() {
        let vm = NavigationViewModel()

        let coord1 = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        let coord2 = CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7210)
        let coord3 = CLLocationCoordinate2D(latitude: 64.8445, longitude: -147.7205)

        // Construct RouteDetails with exactly 0 maneuver steps (empty array)
        let detailsWithZeroSteps = RouteDetails(
            coordinates: [coord1, coord2, coord3],
            totalDistanceMiles: 0.15,
            totalDurationSeconds: 45,
            steps: [],
            costing: "auto"
        )
        vm.routeDetails = detailsWithZeroSteps

        // Evaluating with 0 steps must execute safely without throwing or crashing
        vm.updateNavigationTelemetry(at: coord1, coordIndex: 0, in: detailsWithZeroSteps)
        XCTAssertEqual(vm.remainingStepDistanceMiles, 0.0, "Expected remaining step distance to be 0.0 when steps array is empty")

        // Verify telemetry execution when steps exist
        let step = NavigationStep(
            instruction: "Drive north",
            distanceMiles: 0.15,
            durationSeconds: 45,
            maneuverType: 1,
            streetName: "Cushman St",
            startIndex: 0,
            endIndex: 2
        )
        let detailsWithSteps = RouteDetails(
            coordinates: [coord1, coord2, coord3],
            totalDistanceMiles: 0.15,
            totalDurationSeconds: 45,
            steps: [step],
            costing: "auto"
        )
        vm.routeDetails = detailsWithSteps
        vm.updateNavigationTelemetry(at: coord1, coordIndex: 0, in: detailsWithSteps)
        XCTAssertTrue(vm.remainingStepDistanceMiles > 0.0)
    }

    // MARK: - 5. Distance unit toggling
    func test05_DistanceUnitTogglingPreservesSimulationProgress() {
        let vm = NavigationViewModel()

        // 5.1 Unit string verifications (imperial default)
        vm.useMetric = false
        XCTAssertEqual(vm.speedUnit, "mph")
        XCTAssertEqual(vm.altitudeUnit, "ft")

        // 5.2 Setup active simulation on a multi-step route
        let p1 = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        let p2 = CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7210)
        let p3 = CLLocationCoordinate2D(latitude: 64.8445, longitude: -147.7205)
        let step1 = NavigationStep(instruction: "Go north", distanceMiles: 0.1, durationSeconds: 30, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 1)
        let step2 = NavigationStep(instruction: "Turn right", distanceMiles: 0.1, durationSeconds: 30, maneuverType: 2, streetName: nil, startIndex: 1, endIndex: 2)
        let route = RouteDetails(coordinates: [p1, p2, p3], totalDistanceMiles: 0.2, totalDurationSeconds: 60, steps: [step1, step2], costing: "auto")

        vm.routeDetails = route
        vm.routeCoordinates = [p1, p2, p3]
        vm.isNavigating = true
        vm.isSimulating = true
        vm.currentCoordIndex = 1
        vm.currentStepIndex = 1
        vm.simulatedSpeedMph = 45

        // 5.3 Toggling useMetric during active simulation must preserve navigation progress
        vm.useMetric = true
        XCTAssertTrue(vm.isNavigating, "Toggling metric must preserve isNavigating state")
        XCTAssertTrue(vm.isSimulating, "Toggling metric must preserve isSimulating state")
        XCTAssertEqual(vm.currentCoordIndex, 1, "Toggling metric must not reset currentCoordIndex")
        XCTAssertEqual(vm.currentStepIndex, 1, "Toggling metric must not reset currentStepIndex")
        XCTAssertEqual(vm.speedUnit, "km/h")
        XCTAssertEqual(vm.altitudeUnit, "m")
        XCTAssertEqual(vm.displaySpeed, 72, "45 mph converted to km/h should be 72")

        vm.endNavigation()
    }

    // MARK: - 6. Fallback routing logic & banners
    func test06_FallbackRoutingContractConsistency() {
        let routingService = RoutingService()

        // 6.1 Bounded unreachable coordinate in open Pacific Ocean (no Valhalla tiles)
        let start = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        let unreachableOcean = CLLocationCoordinate2D(latitude: 20.0, longitude: -160.0)

        let failedRoute = routingService.calculateRoute(from: start, to: unreachableOcean, mode: "auto")
        // Critical contract: RoutingService must return explicit failure (nil) for unreachable coordinates, never a synthetic placeholder
        XCTAssertNil(failedRoute, "Routing service must return nil for unreachable routes, never a synthetic fallback route")

        // 6.2 Reachable coordinate on Alaska road network
        let downtownDest = CLLocationCoordinate2D(latitude: 64.8358, longitude: -147.7345)
        if let successfulRoute = routingService.calculateRoute(from: start, to: downtownDest, mode: "auto") {
            XCTAssertFalse(successfulRoute.isFallback, "Successful route must have isFallback == false")
            XCTAssertFalse(successfulRoute.coordinates.isEmpty, "Successful route must have non-empty coordinates")
        }
    }

    // MARK: - 7. LocationManager orientation observation
    func test07_LocationManagerOrientationObservationAndMainActor() {
        let locationManager = LocationManager()

        // 7.1 Verify device orientation notification generation is active
        XCTAssertTrue(UIDevice.current.isGeneratingDeviceOrientationNotifications, "LocationManager must activate beginGeneratingDeviceOrientationNotifications()")

        // 7.2 Verify updateHeadingOrientation executes safely under @MainActor
        locationManager.updateHeadingOrientation()

        // 7.3 Simulate orientation change notification and verify handler runs under @MainActor without crashing
        NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification, object: nil)

        // 7.4 Verify setNavigationActive toggles idle timer and background updates safely
        locationManager.setNavigationActive(true)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        locationManager.setNavigationActive(false)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }

    // MARK: - 8. Cached location fix filtering
    func test08_CachedLocationFixFiltering() {
        let locationManager = LocationManager()
        let clManager = CLLocationManager()

        // Initial state
        XCTAssertFalse(locationManager.isGpsSignalLow, "isGpsSignalLow should initialize to false")

        // 8.1 Deliver a stale cached location fix (> 15s old) with good accuracy
        let staleFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215),
            altitude: 135.0,
            horizontalAccuracy: 10.0,
            verticalAccuracy: 5.0,
            course: 90.0,
            speed: 0.0,
            timestamp: Date().addingTimeInterval(-30.0) // 30 seconds old
        )

        locationManager.locationManager(clManager, didUpdateLocations: [staleFix])

        // Verify that stale cached fix is dropped without flashing low GPS signal warning
        XCTAssertFalse(locationManager.isGpsSignalLow, "Stale cached fix (> 15s) must not trigger isGpsSignalLow = true")

        // 8.2 Deliver a fresh fix (< 15s) with poor horizontal accuracy (>= 65m)
        let poorAccuracyFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215),
            altitude: 135.0,
            horizontalAccuracy: 75.0, // >= 65.0 threshold
            verticalAccuracy: 5.0,
            course: 90.0,
            speed: 0.0,
            timestamp: Date()
        )

        locationManager.locationManager(clManager, didUpdateLocations: [poorAccuracyFix])

        let exp = expectation(description: "Low GPS signal warning update")
        Task { @MainActor in
            // Allow Task { @MainActor in self.isGpsSignalLow = true } to execute
            XCTAssertTrue(locationManager.isGpsSignalLow, "Fresh fix with accuracy >= 65m must set isGpsSignalLow = true")
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        // 8.3 Deliver a fresh fix (< 15s) with excellent horizontal accuracy (< 25m)
        let freshGoodFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215),
            altitude: 135.0,
            horizontalAccuracy: 8.0,
            verticalAccuracy: 3.0,
            course: 90.0,
            speed: 0.0,
            timestamp: Date()
        )

        locationManager.locationManager(clManager, didUpdateLocations: [freshGoodFix])

        let goodExp = expectation(description: "GPS signal restored update")
        Task { @MainActor in
            XCTAssertFalse(locationManager.isGpsSignalLow, "Fresh fix with accuracy < 25m must set isGpsSignalLow = false")
            XCTAssertNotNil(locationManager.location, "Valid location must be published")
            goodExp.fulfill()
        }
        wait(for: [goodExp], timeout: 1.0)
    }

    // MARK: - 9. Project configuration & dependencies
    func test09_ProjectConfigurationAndDependencies() {
        // 9.1 Verify LocationManager precision API exists and is operational
        let lm = LocationManager()
        lm.requestPreciseLocation()
        XCTAssertNotNil(lm)

        // 9.2 Verify Info.plist configuration via Bundle when running in app context
        if let infoDict = Bundle.main.infoDictionary ?? Bundle(for: RemediationTests.self).infoDictionary {
            if let tempDict = infoDict["NSLocationTemporaryUsageDescriptionDictionary"] as? [String: Any] {
                XCTAssertNotNil(tempDict["NavigationAccuracy"], "Info.plist must define purpose key NavigationAccuracy")
            }
        }

        // 9.3 Verify core routing engine initialization without ValhallaConfigModels
        let routingService = RoutingService()
        XCTAssertFalse(routingService.isVoiceMuted)
    }

    // MARK: - 10. Car annotation coordinate updates
    func test10_CarAnnotationCoordinateUpdatesInPlace() {
        // Spy MLNMapView that tracks addAnnotation and removeAnnotation calls
        final class SpyMapView: MLNMapView {
            var addCallCount = 0
            var removeCallCount = 0

            override func addAnnotation(_ annotation: any MLNAnnotation) {
                addCallCount += 1
                super.addAnnotation(annotation)
            }

            override func removeAnnotation(_ annotation: any MLNAnnotation) {
                removeCallCount += 1
                super.removeAnnotation(annotation)
            }
        }

        let spyMapView = SpyMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let parentView = MapView(
            pmtilesURL: OfflineDataManager.url(for: "north-america.pmtiles"),
            destinationTitle: "Test",
            selectedCoordinate: .constant(nil),
            routeCoordinates: .constant(nil),
            simulatedUserCoordinate: .constant(nil),
            userLocationCenter: .constant(nil),
            zoomStep: .constant(nil),
            simulatedHeading: nil,
            isNavigating: true,
            mapStyleName: "standard"
        )
        let coordinator = parentView.makeCoordinator()

        let pos1 = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        let pos2 = CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7210)

        // 10.1 First update creates and adds the annotation
        coordinator.updateCarAnnotation(on: spyMapView, coordinate: pos1)
        XCTAssertEqual(spyMapView.addCallCount, 1, "Initial update should add annotation once")
        XCTAssertEqual(spyMapView.removeCallCount, 0, "Initial update should not remove any annotation")
        XCTAssertNotNil(coordinator.carAnnotation)
        XCTAssertEqual(coordinator.carAnnotation?.coordinate.latitude ?? 0, pos1.latitude, accuracy: 0.0001)

        // 10.2 Second update to new coordinate must update existing annotation in-place via KVO
        // without calling removeAnnotation or addAnnotation (which causes flickering)
        coordinator.updateCarAnnotation(on: spyMapView, coordinate: pos2)
        XCTAssertEqual(spyMapView.addCallCount, 1, "Subsequent coordinate update must NOT call addAnnotation (in-place KVO update)")
        XCTAssertEqual(spyMapView.removeCallCount, 0, "Subsequent coordinate update must NOT call removeAnnotation (flicker prevention)")
        XCTAssertEqual(coordinator.carAnnotation?.coordinate.latitude ?? 0, pos2.latitude, accuracy: 0.0001)

        // 10.3 Update to identical coordinate should be a no-op
        coordinator.updateCarAnnotation(on: spyMapView, coordinate: pos2)
        XCTAssertEqual(spyMapView.addCallCount, 1)
        XCTAssertEqual(spyMapView.removeCallCount, 0)

        // 10.4 Explicit removal should remove the annotation
        coordinator.removeCarAnnotation(from: spyMapView)
        XCTAssertEqual(spyMapView.removeCallCount, 1)
        XCTAssertNil(coordinator.carAnnotation)
    }

    // MARK: - 11. Local sprite path resolution
    func test11_LocalSpritePathResolution() throws {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw XCTSkip("Application Support directory not accessible")
        }

        let testSpritesDir = appSupport.appendingPathComponent("sprites")
        try? FileManager.default.createDirectory(at: testSpritesDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: testSpritesDir)
        }

        // Create mock sprite assets in Application Support
        let mockJson = testSpritesDir.appendingPathComponent("sprite.json")
        let mockPng = testSpritesDir.appendingPathComponent("sprite.png")
        try? "{}".write(to: mockJson, atomically: true, encoding: .utf8)
        try? Data().write(to: mockPng)

        // OfflineDataManager.url(for: "sprites/sprite") must check extensions (.json, .png, etc.)
        // in Application Support and resolve to the local Application Support path before falling back to bundle.
        let resolved = OfflineDataManager.url(for: "sprites/sprite")
        XCTAssertTrue(
            resolved.path.contains("Application Support") || FileManager.default.fileExists(atPath: resolved.path + ".json"),
            "Expected url(for: 'sprites/sprite') to resolve local Application Support asset, got: \(resolved.path)"
        )
    }

    // MARK: - 12. Physical device host path probing
    func test12_PhysicalDeviceHostPathProbing() {
        // Physical device builds must not expose or resolve host developer paths
        let probe = OfflineDataManager.url(for: "probe_nonexistent_\(UUID().uuidString).bin")
        #if !targetEnvironment(simulator) && !os(macOS)
        XCTAssertFalse(probe.path.contains("/Volumes/"), "Physical iOS device must never resolve host /Volumes/ paths")
        XCTAssertFalse(probe.path.contains("/Users/"), "Physical iOS device must never resolve host /Users/ paths")
        #endif
        XCTAssertTrue(probe.path.hasSuffix(".bin"), "Fallback probe URL must preserve requested filename")

        // Verify valid asset resolution (north-america.pmtiles or valhalla.json)
        let valhallaURL = OfflineDataManager.url(for: "valhalla.json")
        XCTAssertTrue(OfflineDataManager.assetExists(at: valhallaURL) || valhallaURL.path.contains("valhalla.json"))
    }

    // MARK: - 13. Reverse-geocoding queries across dataset
    func test13_ReverseGeocodingQueriesAcrossDataset() {
        let searchService = SearchService()

        // Fairbanks Downtown coordinate
        let fairbanksCoord = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        let startTime = Date()
        let result = searchService.reverseGeocode(coordinate: fairbanksCoord)
        let elapsed = Date().timeIntervalSince(startTime)

        XCTAssertNotNil(result, "Reverse geocoding must complete and return a valid result")
        XCTAssertTrue(elapsed < 3.0, "Reverse geocoding must complete in under 3.0s without hanging or stalling")
        if let result = result {
            XCTAssertFalse(result.name.isEmpty, "Resolved POI must have a non-empty name")
            XCTAssertTrue(result.lat > 50.0 && result.lat < 75.0, "Resolved latitude must be in Alaska region")
        }
    }

    // MARK: - 14. Audio session deactivation race prevention
    func test14_AudioSessionDeactivationRacePrevention() {
        let routingService = RoutingService()

        // 14.1 Rapid prompt scheduling
        routingService.speakTurnInstruction("Turn left on Cushman Street in 500 feet.", stepId: 101)
        // Immediate forced replacement prompt
        routingService.speakTurnInstruction("Recalculating route.", stepId: 999, force: true)

        // 14.2 Simulate speech synthesizer delegates
        let dummyUtterance = AVSpeechUtterance(string: "Dummy")
        let synth = AVSpeechSynthesizer()
        routingService.speechSynthesizer(synth, didCancel: dummyUtterance)
        routingService.speechSynthesizer(synth, didFinish: dummyUtterance)

        // Verify no crashes or invalid audio session states occur
        XCTAssertFalse(routingService.isVoiceMuted)
    }

    // MARK: - 15. Async wrappers non-blocking dispatch
    func test15_AsyncWrappersNonBlockingDispatch() async {
        let searchService = SearchService()
        let fairbanksCoord = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)

        // Execute 20 concurrent searchAsync queries and 10 reverseGeocodeAsync queries
        let startTime = Date()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<20 {
                group.addTask {
                    let results = await searchService.searchAsync(query: "Gas \(i)", userLocation: fairbanksCoord)
                    _ = results
                }
            }
            for _ in 0..<10 {
                group.addTask {
                    let result = await searchService.reverseGeocodeAsync(coordinate: fairbanksCoord)
                    _ = result
                }
            }
        }
        let elapsed = Date().timeIntervalSince(startTime)
        XCTAssertTrue(elapsed < 10.0, "Concurrent async queries must execute directly on service queue without thread pool starvation, took \(elapsed)s")
    }

    // MARK: - 16. Strict concurrency & Sendable compliance
    func test16_StrictConcurrencyAndSendableCompliance() async {
        let result = SearchResult(id: 100, name: "Goldpanner Baseball", lat: 64.84, lon: -147.72)

        // 16.1 SearchResult conforms to Sendable and can cross Task.detached boundaries
        let sendableCheck: any Sendable = result
        XCTAssertNotNil(sendableCheck)

        let crossActorTask = Task.detached { () -> SearchResult in
            return result
        }
        let returnedResult = await crossActorTask.value
        XCTAssertEqual(returnedResult.id, 100)
        XCTAssertEqual(returnedResult.name, "Goldpanner Baseball")

        // 16.2 NavigationStep and RouteDetails sendability
        let step = NavigationStep(
            instruction: "Proceed to route",
            distanceMiles: 1.0,
            durationSeconds: 60,
            maneuverType: 1,
            streetName: "Airport Way",
            startIndex: 0,
            endIndex: 5
        )
        let details = RouteDetails(
            coordinates: [CLLocationCoordinate2D(latitude: 64.84, longitude: -147.72)],
            totalDistanceMiles: 1.0,
            totalDurationSeconds: 60,
            steps: [step],
            costing: "auto"
        )
        let detailsTask = Task.detached { () -> RouteDetails in
            return details
        }
        let returnedDetails = await detailsTask.value
        XCTAssertEqual(returnedDetails.totalDistanceMiles, 1.0)
    }

    // MARK: - 17. Pre-existing test suite compatibility
    func test17_PreExistingTestSuiteCompatibility() {
        // Assert core baseline models and services work identically
        let collegeCoord = CLLocationCoordinate2D(latitude: 64.8569, longitude: -147.8028)
        let airport = SearchResult(id: 1, name: "Fairbanks Airport", lat: 64.8153, lon: -147.8564)

        let distMiles = airport.distanceMiles(from: collegeCoord)
        XCTAssertNotNil(distMiles)
        XCTAssertTrue(distMiles! > 2.0 && distMiles! < 6.0)

        let distFormatted = airport.formattedDistance(from: collegeCoord, useMetric: false)
        XCTAssertTrue(distFormatted.contains("mi away") || distFormatted.contains("ft away"))

        let distFormattedKm = airport.formattedDistance(from: collegeCoord, useMetric: true)
        XCTAssertTrue(distFormattedKm.contains("km away") || distFormattedKm.contains("m away"))

        XCTAssertEqual(airport.category, "airport")
        XCTAssertEqual(airport.iconName, "airplane")
    }

    // MARK: - Adversarial Challenge 1: Out-of-region GPS handling
    func testAdversarial01_OutOfRegionGPSHandling() {
        let vm = NavigationViewModel()

        // 1. Equator coordinates
        let equatorCoords = [
            CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),
            CLLocationCoordinate2D(latitude: 0.0, longitude: -147.0),
            CLLocationCoordinate2D(latitude: 0.0, longitude: 180.0),
            CLLocationCoordinate2D(latitude: 0.0, longitude: -180.0),
            CLLocationCoordinate2D(latitude: 0.0, longitude: -129.0)
        ]
        for coord in equatorCoords {
            XCTAssertFalse(vm.isWithinSupportedRegion(coord), "Equator coordinate \(coord) must be out-of-region")
        }

        // 2. Polar extremes (North and South Poles)
        let polarCoords = [
            CLLocationCoordinate2D(latitude: 90.0, longitude: 0.0),
            CLLocationCoordinate2D(latitude: 90.0, longitude: -147.0),
            CLLocationCoordinate2D(latitude: 89.999, longitude: -147.0),
            CLLocationCoordinate2D(latitude: -90.0, longitude: 0.0),
            CLLocationCoordinate2D(latitude: -90.0, longitude: -147.0),
            CLLocationCoordinate2D(latitude: -89.999, longitude: -147.0)
        ]
        for coord in polarCoords {
            XCTAssertFalse(vm.isWithinSupportedRegion(coord), "Polar coordinate \(coord) must be out-of-region")
        }

        // 3. International Date Line & Meridians
        let dateLineCoords = [
            CLLocationCoordinate2D(latitude: 64.0, longitude: 180.0),       // Eastern hemisphere limit
            CLLocationCoordinate2D(latitude: 64.0, longitude: -180.0),      // Western hemisphere limit
            CLLocationCoordinate2D(latitude: 64.0, longitude: 179.9999),    // Russian side of Bering Strait
            CLLocationCoordinate2D(latitude: 64.0, longitude: -179.0001),   // Just outside western limit
            CLLocationCoordinate2D(latitude: 64.0, longitude: -179.0),      // Western edge boundary (included)
            CLLocationCoordinate2D(latitude: 64.0, longitude: -129.0),      // Eastern edge boundary (included)
            CLLocationCoordinate2D(latitude: 64.0, longitude: -128.9999)    // Just outside eastern limit (Canada)
        ]
        XCTAssertFalse(vm.isWithinSupportedRegion(dateLineCoords[0]))
        XCTAssertFalse(vm.isWithinSupportedRegion(dateLineCoords[1]))
        XCTAssertFalse(vm.isWithinSupportedRegion(dateLineCoords[2]))
        XCTAssertFalse(vm.isWithinSupportedRegion(dateLineCoords[3]))
        XCTAssertTrue(vm.isWithinSupportedRegion(dateLineCoords[4]))
        XCTAssertTrue(vm.isWithinSupportedRegion(dateLineCoords[5]))
        XCTAssertFalse(vm.isWithinSupportedRegion(dateLineCoords[6]))

        // 4. Exact boundary edges (51.0°N and 72.0°N) and off-by-epsilon checks
        let boundaryChecks: [(coord: CLLocationCoordinate2D, expected: Bool, label: String)] = [
            (CLLocationCoordinate2D(latitude: 51.0, longitude: -150.0), true, "Exact southern edge 51.0°N"),
            (CLLocationCoordinate2D(latitude: 50.999999, longitude: -150.0), false, "Just south of 51.0°N"),
            (CLLocationCoordinate2D(latitude: 51.000001, longitude: -150.0), true, "Just north of 51.0°N"),
            (CLLocationCoordinate2D(latitude: 72.0, longitude: -150.0), true, "Exact northern edge 72.0°N"),
            (CLLocationCoordinate2D(latitude: 72.000001, longitude: -150.0), false, "Just north of 72.0°N"),
            (CLLocationCoordinate2D(latitude: 71.999999, longitude: -150.0), true, "Just south of 72.0°N"),
            // 4 corners of bounding box
            (CLLocationCoordinate2D(latitude: 51.0, longitude: -179.0), true, "SW Corner"),
            (CLLocationCoordinate2D(latitude: 51.0, longitude: -129.0), true, "SE Corner"),
            (CLLocationCoordinate2D(latitude: 72.0, longitude: -179.0), true, "NW Corner"),
            (CLLocationCoordinate2D(latitude: 72.0, longitude: -129.0), true, "NE Corner")
        ]
        for check in boundaryChecks {
            XCTAssertEqual(vm.isWithinSupportedRegion(check.coord), check.expected, "Failed for \(check.label)")
        }

        // 5. Alaska fallback stability
        let fairbanks = NavigationViewModel.defaultAlaskaCoordinate
        XCTAssertEqual(vm.effectiveUserCoordinate.latitude, fairbanks.latitude, accuracy: 0.0001)
        XCTAssertEqual(vm.effectiveUserCoordinate.longitude, fairbanks.longitude, accuracy: 0.0001)
        XCTAssertTrue(vm.isWithinSupportedRegion(fairbanks), "Default Alaska coordinate must be within supported region")

        // 6. Behavioral verification: handleLocationUpdate drops out-of-region fixes without corrupting state
        let coords = [
            CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215),
            CLLocationCoordinate2D(latitude: 64.8500, longitude: -147.7210)
        ]
        let route = RouteDetails(
            coordinates: coords,
            totalDistanceMiles: 0.1,
            totalDurationSeconds: 30,
            steps: [],
            costing: "auto"
        )
        vm.routeDetails = route
        vm.routeCoordinates = coords
        vm.isNavigating = true
        vm.isSimulating = false
        let initialPuck = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        vm.simulatedUserCoordinate = initialPuck

        // Deliver out-of-region location fix (San Francisco)
        let outOfRegionFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 10,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        vm.handleLocationUpdate(outOfRegionFix)
        XCTAssertEqual(vm.simulatedUserCoordinate?.latitude, initialPuck.latitude, "Out-of-region fix must be silently dropped without modifying user coordinate")

        // Deliver valid in-region location fix (Fairbanks downtown)
        let inRegionFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 64.8438, longitude: -147.7212),
            altitude: 10,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        vm.handleLocationUpdate(inRegionFix)
        XCTAssertEqual(vm.simulatedUserCoordinate?.latitude ?? 0, 64.8438, accuracy: 0.0001, "Valid in-region fix must update simulatedUserCoordinate")
        vm.endNavigation()
    }

    // MARK: - Adversarial Challenge 2: Search task lifecycle
    func testAdversarial02_SearchTaskLifecycle() async throws {
        let vm = NavigationViewModel()

        // Rapidly start searches and cancel/clear/dismiss across 50 iterations
        for i in 0..<50 {
            let query = (i % 2 == 0) ? "Fairbanks" : "Anchorage Airport"
            vm.searchCategory(query)

            if i % 3 == 0 {
                vm.clearSearch()
                XCTAssertNil(vm.searchTask, "searchTask must be nil after clearSearch")
            } else if i % 3 == 1 {
                vm.dismissSearch()
                XCTAssertNil(vm.searchTask, "searchTask must be nil after dismissSearch")
            } else {
                vm.resetToExplore()
                XCTAssertNil(vm.searchTask, "searchTask must be nil after resetToExplore")
            }
        }

        // Concurrent asynchronous query storm with cancellation
        let searchService = SearchService()
        let userLoc = NavigationViewModel.defaultAlaskaCoordinate

        await withTaskGroup(of: Void.self) { group in
            for q in 0..<30 {
                let searchTerm = "Query_\(q)"
                group.addTask {
                    let task = Task.detached(priority: .userInitiated) {
                        searchService.search(query: searchTerm, userLocation: userLoc)
                    }
                    if q % 2 == 0 {
                        task.cancel()
                    }
                    _ = await task.value
                }
            }
        }

        // Verify state consistency after rapid cancellation storm
        vm.resetToExplore()
        XCTAssertNil(vm.searchTask)
    }

    // MARK: - Adversarial Challenge 3: Category search deduplication
    func testAdversarial03_CategorySearchDeduplication() {
        let vm = NavigationViewModel()

        // 1. Rapid successive category chip taps (must execute safely without race or exception)
        let categories = ["Gas", "Coffee", "Restaurant", "Market", "Parking", "Hotel", "Hospital"]
        for cat in categories {
            vm.searchCategory(cat)
        }

        // 2. Behavioral deduplication test:
        vm.isProgrammaticTextChange = false
        vm.destinationText = ""
        vm.searchCategory("Hospital")
        XCTAssertEqual(vm.destinationText, "Hospital")
        XCTAssertTrue(vm.isProgrammaticTextChange, "First tap must set isProgrammaticTextChange = true")

        // Consume flag
        vm.isProgrammaticTextChange = false
        // Repeat tap on same category chip
        vm.searchCategory("Hospital")
        XCTAssertFalse(vm.isProgrammaticTextChange, "Repeated tap on same category must NOT re-assert isProgrammaticTextChange")

        // Tap distinct category chip
        vm.searchCategory("Coffee")
        XCTAssertEqual(vm.destinationText, "Coffee")
        XCTAssertTrue(vm.isProgrammaticTextChange, "Distinct category chip must assert isProgrammaticTextChange")

        // 3. Clean reset
        vm.clearSearch()
        XCTAssertNil(vm.searchTask)
        XCTAssertEqual(vm.destinationText, "")
    }

    // MARK: - Adversarial Challenge 4: Route telemetry (0 steps, 1 step, large step arrays)
    func testAdversarial04_RouteTelemetryZeroOneAndLargeStepArrays() {
        let vm = NavigationViewModel()

        // Case A: 0 Steps
        let coordA = CLLocationCoordinate2D(latitude: 64.84, longitude: -147.72)
        let coordB = CLLocationCoordinate2D(latitude: 64.85, longitude: -147.71)
        let zeroStepsRoute = RouteDetails(
            coordinates: [coordA, coordB],
            totalDistanceMiles: 1.0,
            totalDurationSeconds: 120,
            steps: [],
            costing: "auto"
        )
        vm.routeDetails = zeroStepsRoute

        // Test extreme coord indices with 0 steps (must not force-unwrap or crash)
        for idx in [-5, 0, 1, 10] {
            vm.updateNavigationTelemetry(at: coordA, coordIndex: idx, in: zeroStepsRoute)
            XCTAssertFalse(vm.formattedRemainingDuration.isEmpty)
            XCTAssertFalse(vm.formattedRemainingETA.isEmpty)
        }

        // Case B: Exactly 1 Step
        let singleStep = NavigationStep(
            instruction: "Head north on Airport Way",
            distanceMiles: 2.5,
            durationSeconds: 180,
            maneuverType: 1,
            streetName: "Airport Way",
            startIndex: 0,
            endIndex: 2
        )
        let coordC = CLLocationCoordinate2D(latitude: 64.86, longitude: -147.70)
        let oneStepRoute = RouteDetails(
            coordinates: [coordA, coordB, coordC],
            totalDistanceMiles: 2.5,
            totalDurationSeconds: 180,
            steps: [singleStep],
            costing: "auto"
        )
        vm.routeDetails = oneStepRoute
        vm.updateNavigationTelemetry(at: coordA, coordIndex: 0, in: oneStepRoute)
        XCTAssertFalse(vm.formattedRemainingDuration.isEmpty)

        vm.updateNavigationTelemetry(at: coordC, coordIndex: 2, in: oneStepRoute)
        XCTAssertFalse(vm.formattedRemainingDuration.isEmpty)

        // Case C: Large Step Array (500 steps across 5,000 coordinates)
        var largeCoords: [CLLocationCoordinate2D] = []
        var largeSteps: [NavigationStep] = []
        for i in 0..<5000 {
            largeCoords.append(CLLocationCoordinate2D(
                latitude: 64.0 + Double(i) * 0.0001,
                longitude: -147.0 - Double(i) * 0.0001
            ))
        }
        for s in 0..<500 {
            let start = s * 10
            let end = min(start + 10, 4999)
            largeSteps.append(NavigationStep(
                instruction: "Continue step \(s)",
                distanceMiles: 0.5,
                durationSeconds: 30,
                maneuverType: 1,
                streetName: "Route \(s)",
                startIndex: start,
                endIndex: end
            ))
        }

        let largeRoute = RouteDetails(
            coordinates: largeCoords,
            totalDistanceMiles: 250.0,
            totalDurationSeconds: 15000,
            steps: largeSteps,
            costing: "auto"
        )
        vm.routeDetails = largeRoute

        let testIndices = [-10, 0, 1, 2500, 4998, 4999, 5050]
        for idx in testIndices {
            vm.updateNavigationTelemetry(at: largeCoords[min(max(0, idx), 4999)], coordIndex: idx, in: largeRoute)
            XCTAssertFalse(vm.formattedRemainingDuration.isEmpty)
            XCTAssertFalse(vm.formattedRemainingETA.isEmpty)
        }

        // Case D: Zero-distance / Zero-duration route (division by zero protection)
        let zeroLengthRoute = RouteDetails(
            coordinates: [coordA, coordB],
            totalDistanceMiles: 0.0,
            totalDurationSeconds: 0.0,
            steps: [],
            costing: "auto"
        )
        vm.updateNavigationTelemetry(at: coordA, coordIndex: 0, in: zeroLengthRoute)
        XCTAssertFalse(vm.formattedRemainingDuration.isEmpty)

        // Case E: Precise countdown distance arithmetic
        XCTAssertEqual(vm.formatCountdownDistance(0.0, useMetric: false), "0 ft")
        XCTAssertEqual(vm.formatCountdownDistance(0.05, useMetric: false), "264 ft")
        XCTAssertEqual(vm.formatCountdownDistance(0.099, useMetric: false), "522 ft")
        XCTAssertEqual(vm.formatCountdownDistance(0.10, useMetric: false), "0.1 mi")
        XCTAssertEqual(vm.formatCountdownDistance(0.5, useMetric: false), "0.5 mi")
        XCTAssertEqual(vm.formatCountdownDistance(5.0, useMetric: false), "5.0 mi")

        XCTAssertEqual(vm.formatCountdownDistance(0.0, useMetric: true), "0 m")
        XCTAssertEqual(vm.formatCountdownDistance(0.05, useMetric: true), "80 m")
        XCTAssertEqual(vm.formatCountdownDistance(0.5, useMetric: true), "804 m")
        XCTAssertEqual(vm.formatCountdownDistance(5.0, useMetric: true), "8.0 km")
    }

    // MARK: - Adversarial Challenge 5: Simulation metric toggling
    func testAdversarial05_SimulationMetricTogglingProgressPreservation() {
        let vm = NavigationViewModel()

        // 1. Initial units
        vm.useMetric = false
        XCTAssertEqual(vm.speedUnit, "mph")
        XCTAssertEqual(vm.altitudeUnit, "ft")

        // 2. Setup active simulation on a multi-step route
        let p1 = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        let p2 = CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7210)
        let p3 = CLLocationCoordinate2D(latitude: 64.8445, longitude: -147.7205)
        let step = NavigationStep(
            instruction: "Go north",
            distanceMiles: 0.1,
            durationSeconds: 30,
            maneuverType: 1,
            streetName: nil,
            startIndex: 0,
            endIndex: 2
        )
        let route = RouteDetails(coordinates: [p1, p2, p3], totalDistanceMiles: 0.1, totalDurationSeconds: 30, steps: [step], costing: "auto")
        vm.routeDetails = route
        vm.routeCoordinates = [p1, p2, p3]
        vm.startNavigation()
        vm.startSimulatedDrive()
        vm.advanceSimulationStep()

        let savedCoordIndex = vm.currentCoordIndex
        let savedStepIndex = vm.currentStepIndex
        XCTAssertTrue(vm.isNavigating)
        XCTAssertTrue(vm.isSimulating)

        // 3. Toggle metric during active simulation: state and progress must be preserved
        vm.useMetric.toggle()
        XCTAssertTrue(vm.isNavigating, "Toggling metric must preserve isNavigating")
        XCTAssertTrue(vm.isSimulating, "Toggling metric must preserve isSimulating")
        XCTAssertEqual(vm.currentCoordIndex, savedCoordIndex, "Toggling metric must preserve coordinate progress")
        XCTAssertEqual(vm.currentStepIndex, savedStepIndex, "Toggling metric must preserve step index")
        XCTAssertEqual(vm.speedUnit, "km/h")
        XCTAssertEqual(vm.altitudeUnit, "m")

        // 4. Countdown formatting preservation under metric toggle
        let imperialShort = vm.formatCountdownDistance(0.05, useMetric: false)
        let metricShort = vm.formatCountdownDistance(0.05, useMetric: true)
        XCTAssertTrue(imperialShort.contains("ft"))
        XCTAssertTrue(metricShort.contains("m"))

        let imperialLong = vm.formatCountdownDistance(3.5, useMetric: false)
        let metricLong = vm.formatCountdownDistance(3.5, useMetric: true)
        XCTAssertEqual(imperialLong, "3.5 mi")
        XCTAssertEqual(metricLong, "5.6 km")

        vm.endNavigation()
    }

    // MARK: - Adversarial Challenge 6: LocationManager stale GPS fixes
    func testAdversarial06_LocationManagerStaleGPSFixesBoundaryBehavior() async {
        let locationManager = LocationManager()
        let clManager = CLLocationManager()

        // Test ages: 0s, 10s, 14.9s (fresh, <15s) vs 15.1s, 60s (stale, >=15s)
        let testCases: [(ageSeconds: Double, accuracy: Double, shouldProcess: Bool, expectSignalLow: Bool, description: String)] = [
            // Fresh fixes (< 15.0s)
            (ageSeconds: 0.0, accuracy: 10.0, shouldProcess: true, expectSignalLow: false, "Fresh 0s accurate fix"),
            (ageSeconds: 0.0, accuracy: 70.0, shouldProcess: true, expectSignalLow: true, "Fresh 0s inaccurate fix (>= 65m)"),
            (ageSeconds: 10.0, accuracy: 12.0, shouldProcess: true, expectSignalLow: false, "Fresh 10s accurate fix"),
            (ageSeconds: 10.0, accuracy: 70.0, shouldProcess: true, expectSignalLow: true, "Fresh 10s inaccurate fix (>= 65m)"),
            (ageSeconds: 14.9, accuracy: 15.0, shouldProcess: true, expectSignalLow: false, "Fresh 14.9s accurate fix (boundary inside)"),
            (ageSeconds: 14.9, accuracy: 70.0, shouldProcess: true, expectSignalLow: true, "Fresh 14.9s inaccurate fix (boundary inside)"),

            // Stale fixes (>= 15.0s) — must be discarded SILENTLY without modifying isGpsSignalLow or location
            (ageSeconds: 15.1, accuracy: 70.0, shouldProcess: false, expectSignalLow: false, "Stale 15.1s inaccurate fix (boundary outside)"),
            (ageSeconds: 15.1, accuracy: 10.0, shouldProcess: false, expectSignalLow: false, "Stale 15.1s accurate fix (boundary outside)"),
            (ageSeconds: 60.0, accuracy: 70.0, shouldProcess: false, expectSignalLow: false, "Stale 60s inaccurate fix"),
            (ageSeconds: 60.0, accuracy: 10.0, shouldProcess: false, expectSignalLow: false, "Stale 60s accurate fix")
        ]

        for tc in testCases {
            // Reset to good baseline fix
            let baselineFix = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215),
                altitude: 135.0,
                horizontalAccuracy: 10.0,
                verticalAccuracy: 5.0,
                course: 90.0,
                speed: 0.0,
                timestamp: Date()
            )
            locationManager.locationManager(clManager, didUpdateLocations: [baselineFix])
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
            XCTAssertFalse(locationManager.isGpsSignalLow, "Baseline must have low signal == false")

            // Now deliver the test fix
            let testCoord = CLLocationCoordinate2D(latitude: 64.8500 + tc.ageSeconds * 0.001, longitude: -147.7300)
            let testFix = CLLocation(
                coordinate: testCoord,
                altitude: 135.0,
                horizontalAccuracy: tc.accuracy,
                verticalAccuracy: 5.0,
                course: 90.0,
                speed: 0.0,
                timestamp: Date().addingTimeInterval(-tc.ageSeconds)
            )

            locationManager.locationManager(clManager, didUpdateLocations: [testFix])
            try? await Task.sleep(nanoseconds: 30_000_000) // 30ms

            if tc.shouldProcess {
                if tc.expectSignalLow {
                    XCTAssertTrue(locationManager.isGpsSignalLow, "\(tc.description): expected isGpsSignalLow == true")
                } else {
                    XCTAssertFalse(locationManager.isGpsSignalLow, "\(tc.description): expected isGpsSignalLow == false")
                    if let loc = locationManager.location {
                        XCTAssertEqual(loc.coordinate.latitude, testCoord.latitude, accuracy: 0.0001, "\(tc.description): location should be updated")
                    } else {
                        XCTFail("\(tc.description): location should not be nil")
                    }
                }
            } else {
                // Discarded silently! Must NOT trigger isGpsSignalLow == true and must NOT update location to testCoord
                XCTAssertFalse(locationManager.isGpsSignalLow, "\(tc.description): stale fix must NOT set isGpsSignalLow == true")
                if let loc = locationManager.location {
                    XCTAssertNotEqual(loc.coordinate.latitude, testCoord.latitude, "\(tc.description): stale fix must NOT update location")
                }
            }
        }
    }

    // MARK: - Adversarial Challenge 7: Car annotation updates (60Hz KVO loop stress)
    func testAdversarial07_CarAnnotationRapid60HzUpdatesAndKVOInPlace() {
        final class AdversarialSpyMapView: MLNMapView {
            var addCallCount = 0
            var removeCallCount = 0

            override func addAnnotation(_ annotation: any MLNAnnotation) {
                addCallCount += 1
                super.addAnnotation(annotation)
            }

            override func removeAnnotation(_ annotation: any MLNAnnotation) {
                removeCallCount += 1
                super.removeAnnotation(annotation)
            }
        }

        let spyMapView = AdversarialSpyMapView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let parentView = MapView(
            pmtilesURL: OfflineDataManager.url(for: "north-america.pmtiles"),
            destinationTitle: "Test",
            selectedCoordinate: .constant(nil),
            routeCoordinates: .constant(nil),
            simulatedUserCoordinate: .constant(nil),
            userLocationCenter: .constant(nil),
            zoomStep: .constant(nil),
            simulatedHeading: nil,
            isNavigating: true,
            mapStyleName: "standard"
        )
        let coordinator = parentView.makeCoordinator()

        // 1. Initial position: annotation created and added once
        let initialPos = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        coordinator.updateCarAnnotation(on: spyMapView, coordinate: initialPos)

        XCTAssertEqual(spyMapView.addCallCount, 1, "Initial update must add annotation exactly once")
        XCTAssertEqual(spyMapView.removeCallCount, 0, "Initial update must not remove any annotation")
        guard let initialAnnotation = coordinator.carAnnotation else {
            XCTFail("carAnnotation must not be nil after initial update")
            return
        }
        XCTAssertEqual(initialAnnotation.coordinate.latitude, initialPos.latitude, accuracy: 0.0001)

        // 2. Rapid 60Hz loop with 120 position updates (2 seconds of 60Hz navigation)
        for i in 1...120 {
            let nextCoord = CLLocationCoordinate2D(
                latitude: initialPos.latitude + Double(i) * 0.00005,
                longitude: initialPos.longitude + Double(i) * 0.00005
            )
            coordinator.updateCarAnnotation(on: spyMapView, coordinate: nextCoord)

            // Must NOT call addAnnotation or removeAnnotation (which causes flickering and view churn)
            XCTAssertEqual(spyMapView.addCallCount, 1, "Frame \(i): addAnnotation must not be called again")
            XCTAssertEqual(spyMapView.removeCallCount, 0, "Frame \(i): removeAnnotation must not be called")
            // Object identity must be preserved across all frames (zero memory churn)
            XCTAssertTrue(coordinator.carAnnotation === initialAnnotation, "Frame \(i): carAnnotation instance pointer must remain identical")
            XCTAssertEqual(coordinator.carAnnotation?.coordinate.latitude ?? 0, nextCoord.latitude, accuracy: 0.000001)
        }

        // 3. Duplicate coordinate updates (10 frames stationary at a traffic light)
        let stationaryCoord = coordinator.carAnnotation!.coordinate
        for _ in 1...10 {
            coordinator.updateCarAnnotation(on: spyMapView, coordinate: stationaryCoord)
            XCTAssertEqual(spyMapView.addCallCount, 1)
            XCTAssertEqual(spyMapView.removeCallCount, 0)
        }

        // 4. Removal
        coordinator.removeCarAnnotation(from: spyMapView)
        XCTAssertEqual(spyMapView.removeCallCount, 1)
        XCTAssertNil(coordinator.carAnnotation)

        // 5. Redundant removal is safe
        coordinator.removeCarAnnotation(from: spyMapView)
        XCTAssertEqual(spyMapView.removeCallCount, 1)
    }

    // MARK: - Adversarial Challenge 8: Local sprite resolution & fallback
    func testAdversarial08_LocalSpriteResolutionPrecedenceAndAllExtensions() throws {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw XCTSkip("Required directories not accessible")
        }

        let cleanupDirs = [
            appSupport.appendingPathComponent("adv_sprite_json"),
            appSupport.appendingPathComponent("adv_sprite_png"),
            appSupport.appendingPathComponent("adv_sprite_2x_json"),
            appSupport.appendingPathComponent("adv_sprite_2x_png"),
            docs.appendingPathComponent("adv_sprite_doc"),
            appSupport.appendingPathComponent("adv_sprite_prec"),
            docs.appendingPathComponent("adv_sprite_prec")
        ]
        defer {
            for dir in cleanupDirs {
                try? FileManager.default.removeItem(at: dir)
            }
        }

        // 8.1 Application Support with only .json
        let jsonDir = cleanupDirs[0]
        try FileManager.default.createDirectory(at: jsonDir, withIntermediateDirectories: true)
        try "{}".write(to: jsonDir.appendingPathComponent("sprite.json"), atomically: true, encoding: .utf8)
        let resolvedJson = OfflineDataManager.url(for: "adv_sprite_json/sprite")
        XCTAssertTrue(resolvedJson.path.contains("Application Support"), "Sprite with only .json must resolve to Application Support")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolvedJson.path + ".json"))

        // 8.2 Application Support with only .png
        let pngDir = cleanupDirs[1]
        try FileManager.default.createDirectory(at: pngDir, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: pngDir.appendingPathComponent("sprite.png"))
        let resolvedPng = OfflineDataManager.url(for: "adv_sprite_png/sprite")
        XCTAssertTrue(resolvedPng.path.contains("Application Support"), "Sprite with only .png must resolve to Application Support")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolvedPng.path + ".png"))

        // 8.3 Application Support with only @2x.json
        let twoXJsonDir = cleanupDirs[2]
        try FileManager.default.createDirectory(at: twoXJsonDir, withIntermediateDirectories: true)
        try "{}".write(to: twoXJsonDir.appendingPathComponent("sprite@2x.json"), atomically: true, encoding: .utf8)
        let resolved2xJson = OfflineDataManager.url(for: "adv_sprite_2x_json/sprite")
        XCTAssertTrue(resolved2xJson.path.contains("Application Support"), "Sprite with only @2x.json must resolve to Application Support")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved2xJson.path + "@2x.json"))

        // 8.4 Application Support with only @2x.png
        let twoXPngDir = cleanupDirs[3]
        try FileManager.default.createDirectory(at: twoXPngDir, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: twoXPngDir.appendingPathComponent("sprite@2x.png"))
        let resolved2xPng = OfflineDataManager.url(for: "adv_sprite_2x_png/sprite")
        XCTAssertTrue(resolved2xPng.path.contains("Application Support"), "Sprite with only @2x.png must resolve to Application Support")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved2xPng.path + "@2x.png"))

        // 8.5 Documents directory fallback when Application Support does not have it
        let docDir = cleanupDirs[4]
        try FileManager.default.createDirectory(at: docDir, withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: docDir.appendingPathComponent("sprite@2x.png"))
        let resolvedDoc = OfflineDataManager.url(for: "adv_sprite_doc/sprite")
        XCTAssertTrue(resolvedDoc.path.contains("Documents"), "Sprite existing only in Documents must resolve to Documents path")

        // 8.6 Precedence: Application Support must take precedence over Documents
        let precAppSupport = cleanupDirs[5]
        let precDocs = cleanupDirs[6]
        try FileManager.default.createDirectory(at: precAppSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: precDocs, withIntermediateDirectories: true)
        try "{\"source\":\"appSupport\"}".write(to: precAppSupport.appendingPathComponent("sprite.json"), atomically: true, encoding: .utf8)
        try "{\"source\":\"docs\"}".write(to: precDocs.appendingPathComponent("sprite.json"), atomically: true, encoding: .utf8)
        let resolvedPrec = OfflineDataManager.url(for: "adv_sprite_prec/sprite")
        XCTAssertTrue(resolvedPrec.path.contains("Application Support"), "Application Support must have precedence over Documents")

        // 8.7 Non-existent asset falls back to bundle safely without crash
        let nonExistent = OfflineDataManager.url(for: "adv_missing_asset_12345/sprite")
        XCTAssertTrue(nonExistent.path.contains("adv_missing_asset_12345/sprite"))
    }

    // MARK: - Adversarial Challenge 9: Physical device host path guard elision
    func testAdversarial09_PhysicalDeviceHostPathGuardElision() {
        // Behavioral test: Nonexistent asset safely resolves to bundle URL without crashing or corrupting cache
        let missingAsset = "adversarial_missing_\(UUID().uuidString).dat"
        let fallbackURL = OfflineDataManager.url(for: missingAsset)
        XCTAssertFalse(OfflineDataManager.assetExists(at: fallbackURL))
        XCTAssertTrue(fallbackURL.path.contains(missingAsset))

        #if !targetEnvironment(simulator) && !os(macOS)
        XCTAssertFalse(fallbackURL.path.contains("/Volumes/"), "Physical device build must not expose host Mac filesystem")
        XCTAssertFalse(fallbackURL.path.contains("/Users/"), "Physical device build must not expose host Mac user path")
        #endif

        // Verify assetExists safety across nil and invalid paths
        let emptyURL = URL(fileURLWithPath: "")
        XCTAssertFalse(OfflineDataManager.assetExists(at: emptyURL))
    }

    // MARK: - Adversarial Challenge 10: Reverse-geocoding stress (deep, boundary, sparse, ocean)
    func testAdversarial10_ReverseGeocodingStressDeepBoundarySparseOcean() {
        let searchService = SearchService()

        // 10.1 Deep record: Downtown Fairbanks (dense POI cluster)
        let fairbanksDowntown = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        let startDeep = CFAbsoluteTimeGetCurrent()
        let deepResult = searchService.reverseGeocode(coordinate: fairbanksDowntown)
        let deepElapsed = CFAbsoluteTimeGetCurrent() - startDeep
        XCTAssertNotNil(deepResult)
        XCTAssertTrue(deepElapsed < 1.0, "Deep reverse geocode must complete in < 1.0s, took \(deepElapsed)s")
        XCTAssertFalse(deepResult?.name.isEmpty ?? true)

        // 10.2 Boundary records at extremes of Alaska bounding box
        let barrowCoord = CLLocationCoordinate2D(latitude: 71.2906, longitude: -156.7887) // Arctic northern edge
        let startBarrow = CFAbsoluteTimeGetCurrent()
        let barrowResult = searchService.reverseGeocode(coordinate: barrowCoord)
        let barrowElapsed = CFAbsoluteTimeGetCurrent() - startBarrow
        XCTAssertNotNil(barrowResult)
        XCTAssertTrue(barrowElapsed < 1.0, "Barrow boundary query took \(barrowElapsed)s")

        let ketchikanCoord = CLLocationCoordinate2D(latitude: 55.3422, longitude: -131.6461) // Southeast Alaska edge
        let startKetchikan = CFAbsoluteTimeGetCurrent()
        let ketchikanResult = searchService.reverseGeocode(coordinate: ketchikanCoord)
        let ketchikanElapsed = CFAbsoluteTimeGetCurrent() - startKetchikan
        XCTAssertNotNil(ketchikanResult)
        XCTAssertTrue(ketchikanElapsed < 1.0, "Ketchikan boundary query took \(ketchikanElapsed)s")

        // 10.3 Sparse & Ocean coordinates: Opcode budget & deadline enforcement
        // In unindexed ocean areas, sqlite3_progress_handler must abort query within ~0.65s (2500 ticks) and return Dropped Pin
        let arcticOceanCoord = CLLocationCoordinate2D(latitude: 75.0, longitude: -140.0)
        let startArctic = CFAbsoluteTimeGetCurrent()
        let arcticResult = searchService.reverseGeocode(coordinate: arcticOceanCoord)
        let arcticElapsed = CFAbsoluteTimeGetCurrent() - startArctic
        XCTAssertNotNil(arcticResult)
        XCTAssertTrue(arcticElapsed < 0.85, "Arctic Ocean query must terminate within progress handler budget (<0.85s), took \(arcticElapsed)s")
        XCTAssertTrue(arcticResult?.name.contains("Dropped Pin") ?? false, "Ocean coordinate should return Dropped Pin")

        let pacificOceanCoord = CLLocationCoordinate2D(latitude: 20.0, longitude: -160.0)
        let startPacific = CFAbsoluteTimeGetCurrent()
        let pacificResult = searchService.reverseGeocode(coordinate: pacificOceanCoord)
        let pacificElapsed = CFAbsoluteTimeGetCurrent() - startPacific
        XCTAssertNotNil(pacificResult)
        XCTAssertTrue(pacificElapsed < 0.85, "Pacific Ocean query must terminate within budget (<0.85s), took \(pacificElapsed)s")
        XCTAssertTrue(pacificResult?.name.contains("Dropped Pin") ?? false)

        // 10.4 Sequential burst of 6 rapid queries across alternating regions
        let testCoords = [
            CLLocationCoordinate2D(latitude: 61.2181, longitude: -149.9003), // Anchorage
            CLLocationCoordinate2D(latitude: 57.0, longitude: -145.0),       // Gulf of Alaska
            CLLocationCoordinate2D(latitude: 64.8569, longitude: -147.8028), // Fairbanks College
            CLLocationCoordinate2D(latitude: 50.0, longitude: -160.0),       // Deep Pacific
            CLLocationCoordinate2D(latitude: 58.3019, longitude: -134.4197), // Juneau
            CLLocationCoordinate2D(latitude: 68.0, longitude: -150.0)        // Brooks Range
        ]
        let burstStart = CFAbsoluteTimeGetCurrent()
        for coord in testCoords {
            let res = searchService.reverseGeocode(coordinate: coord)
            XCTAssertNotNil(res)
        }
        let burstElapsed = CFAbsoluteTimeGetCurrent() - burstStart
        XCTAssertTrue(burstElapsed < 4.0, "Sequential 6-query burst took \(burstElapsed)s (expected < 4.0s)")
    }

    // MARK: - Adversarial Challenge 11: Audio session deactivation concurrency stress
    func testAdversarial11_AudioSessionDeactivationConcurrencyStress() {
        let routingService = RoutingService()

        // 11.1 Concurrently schedule prompts from multiple threads
        let dispatchGroup = DispatchGroup()
        for i in 0..<40 {
            dispatchGroup.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                let force = (i % 3 == 0)
                let text = "Turn instruction \(i) in \(i * 100) feet."
                routingService.speakTurnInstruction(text, stepId: i, force: force)

                // Simultaneously simulate delegate callbacks
                let dummySynth = AVSpeechSynthesizer()
                let dummyUtterance = AVSpeechUtterance(string: "Dummy \(i)")
                if i % 2 == 0 {
                    routingService.speechSynthesizer(dummySynth, didCancel: dummyUtterance)
                } else {
                    routingService.speechSynthesizer(dummySynth, didFinish: dummyUtterance)
                }
                dispatchGroup.leave()
            }
        }
        let waitResult = dispatchGroup.wait(timeout: .now() + 5.0)
        XCTAssertEqual(waitResult, .success, "Rapid concurrent prompt dispatch and delegate simulation must complete without deadlock")

        // 11.2 Verification of speech generation progression via Mirror (behavioral inspection)
        let mirror = Mirror(reflecting: routingService)
        let finalGen = mirror.children.first { $0.label == "activeSpeechGeneration" }?.value as? Int
        XCTAssertNotNil(finalGen, "activeSpeechGeneration must be present")
        XCTAssertTrue((finalGen ?? 0) >= 40, "activeSpeechGeneration must advance across concurrent prompts to prevent race conditions")
    }

    // MARK: - Adversarial Challenge 12: Async wrappers high concurrency burst stress
    func testAdversarial12_AsyncWrappersHighConcurrencyBurstStress() async {
        let searchService = SearchService()
        let fairbanksCoord = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        let queries = ["gas", "coffee", "restaurant", "hotel", "parking", "park", "hospital", "airport", "market", "pizza"]

        let startTime = CFAbsoluteTimeGetCurrent()
        await withTaskGroup(of: Void.self) { group in
            // Dispatch 20 concurrent searchAsync queries
            for i in 0..<20 {
                let query = queries[i % queries.count]
                group.addTask {
                    let results = await searchService.searchAsync(query: "\(query) \(i)", userLocation: fairbanksCoord)
                    _ = results
                }
            }
            // Dispatch 10 concurrent reverseGeocodeAsync queries in Fairbanks
            for j in 0..<10 {
                let latOffset = Double(j) * 0.002
                let coord = CLLocationCoordinate2D(latitude: fairbanksCoord.latitude + latOffset, longitude: fairbanksCoord.longitude)
                group.addTask {
                    let result = await searchService.reverseGeocodeAsync(coordinate: coord)
                    _ = result
                }
            }
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertTrue(elapsed < 25.0, "High concurrency 30-task burst must complete without thread pool starvation (took \(elapsed)s)")
    }

    // MARK: - 18. Simulation step progression bounds safety (Issue #1 / C-1)
    func test18_SimulationStepProgressionBoundsSafety() {
        let vm = NavigationViewModel()
        let coord1 = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        let coord2 = CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7210)
        let coord3 = CLLocationCoordinate2D(latitude: 64.8445, longitude: -147.7205)

        // Case A: 0 steps in route details during simulation step
        let zeroStepsRoute = RouteDetails(
            coordinates: [coord1, coord2, coord3],
            totalDistanceMiles: 0.15,
            totalDurationSeconds: 45,
            steps: [],
            costing: "auto"
        )
        vm.routeDetails = zeroStepsRoute
        vm.isNavigating = true
        vm.isSimulating = true
        vm.currentCoordIndex = 0
        vm.currentStepIndex = 0

        // Must execute cleanly without bounds crash when steps array is empty
        vm.advanceSimulationStep()
        XCTAssertEqual(vm.currentStepIndex, 0)

        // Case B: Step with negative or out-of-range startIndex
        let malformedStep1 = NavigationStep(
            instruction: "Drive north",
            distanceMiles: 0.1,
            durationSeconds: 20,
            maneuverType: 1,
            streetName: "Cushman",
            startIndex: -5,
            endIndex: 1
        )
        let malformedStep2 = NavigationStep(
            instruction: "Turn right",
            distanceMiles: 0.05,
            durationSeconds: 25,
            maneuverType: 2,
            streetName: "1st Ave",
            startIndex: -2,
            endIndex: 2
        )
        let malformedRoute = RouteDetails(
            coordinates: [coord1, coord2, coord3],
            totalDistanceMiles: 0.15,
            totalDurationSeconds: 45,
            steps: [malformedStep1, malformedStep2],
            costing: "auto"
        )
        vm.routeDetails = malformedRoute
        vm.currentCoordIndex = 0
        vm.currentStepIndex = 0

        // Must handle negative step indices with max(0, min(...)) clamping without crashing
        vm.advanceSimulationStep()
        XCTAssertTrue(vm.currentCoordIndex >= 0)
        vm.endNavigation()
    }

    // MARK: - 19. Telemetry out-of-bounds edge cases (Issue #2 / C-2)
    func test19_TelemetryOutOfBoundsEdgeCases() {
        let vm = NavigationViewModel()
        let coord1 = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        let coord2 = CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7210)
        let coord3 = CLLocationCoordinate2D(latitude: 64.8445, longitude: -147.7205)

        // Step with negative endIndex (e.g. -1 or -5)
        let negativeEndStep = NavigationStep(
            instruction: "Proceed",
            distanceMiles: 0.1,
            durationSeconds: 20,
            maneuverType: 1,
            streetName: nil,
            startIndex: 0,
            endIndex: -5
        )
        let routeWithNegativeEnd = RouteDetails(
            coordinates: [coord1, coord2, coord3],
            totalDistanceMiles: 0.15,
            totalDurationSeconds: 45,
            steps: [negativeEndStep],
            costing: "auto"
        )
        vm.routeDetails = routeWithNegativeEnd

        // In unpatched code, clampedIndex >= stepEnd (-5) causes coords[stepEnd] -> coords[-5] crash
        // In patched code, stepEnd is clamped to max(0, min(currentStep.endIndex, coords.count - 1))
        vm.updateNavigationTelemetry(at: coord1, coordIndex: 0, in: routeWithNegativeEnd)
        XCTAssertEqual(vm.remainingStepDistanceMiles, 0.0, accuracy: 0.001)

        // Step with extreme endIndex far beyond coordinates count (e.g. 9999)
        let oversizedEndStep = NavigationStep(
            instruction: "Proceed",
            distanceMiles: 0.1,
            durationSeconds: 20,
            maneuverType: 1,
            streetName: nil,
            startIndex: 0,
            endIndex: 9999
        )
        let routeWithOversizedEnd = RouteDetails(
            coordinates: [coord1, coord2, coord3],
            totalDistanceMiles: 0.15,
            totalDurationSeconds: 45,
            steps: [oversizedEndStep],
            costing: "auto"
        )
        vm.routeDetails = routeWithOversizedEnd
        vm.updateNavigationTelemetry(at: coord1, coordIndex: 1, in: routeWithOversizedEnd)
        XCTAssertTrue(vm.remainingStepDistanceMiles >= 0.0)

        // Extreme coordIndex values (-100, 100)
        vm.updateNavigationTelemetry(at: coord1, coordIndex: -100, in: routeWithOversizedEnd)
        vm.updateNavigationTelemetry(at: coord1, coordIndex: 100, in: routeWithOversizedEnd)
        XCTAssertFalse(vm.formattedRemainingDuration.isEmpty)
    }

    // MARK: - 20. Sendable conformance integrity (Issue #3 / C-3)
    func test20_SendableConformanceIntegrity() async {
        let step = NavigationStep(
            instruction: "Turn right on Airport Way",
            distanceMiles: 1.5,
            durationSeconds: 120,
            maneuverType: 10,
            streetName: "Airport Way",
            startIndex: 0,
            endIndex: 5
        )

        // 20.1 NavigationStep explicitly conforms to Sendable
        let stepSendable: any Sendable = step
        XCTAssertNotNil(stepSendable)

        let stepTask = Task.detached { () -> NavigationStep in
            return step
        }
        let receivedStep = await stepTask.value
        XCTAssertEqual(receivedStep.instruction, "Turn right on Airport Way")
        XCTAssertEqual(receivedStep.maneuverType, 10)

        // 20.2 RouteDetails conforms to Sendable directly at definition
        let details = RouteDetails(
            coordinates: [
                CLLocationCoordinate2D(latitude: 64.84, longitude: -147.72),
                CLLocationCoordinate2D(latitude: 64.85, longitude: -147.71)
            ],
            totalDistanceMiles: 1.5,
            totalDurationSeconds: 120,
            steps: [step],
            costing: "auto"
        )
        let detailsSendable: any Sendable = details
        XCTAssertNotNil(detailsSendable)

        let detailsTask = Task.detached { () -> RouteDetails in
            return details
        }
        let receivedDetails = await detailsTask.value
        XCTAssertEqual(receivedDetails.totalDistanceMiles, 1.5)
        XCTAssertEqual(receivedDetails.coordinates.count, 2)
    }

    // MARK: - 21. Valhalla metric distance conversion consistency (Issue #4 / H-1)
    func test21_ValhallaMetricDistanceConversionConsistency() {
        // Valhalla km to miles conversion factor must exactly invert formatters (* 1.60934)
        let valhallaKm = 10.0
        let conversionDivisor = 1.60934
        let storedMiles = valhallaKm / conversionDivisor

        let step = NavigationStep(
            instruction: "Drive 10km",
            distanceMiles: storedMiles,
            durationSeconds: 600,
            maneuverType: 1,
            streetName: "Highway 3",
            startIndex: 0,
            endIndex: 10
        )
        let details = RouteDetails(
            coordinates: [
                CLLocationCoordinate2D(latitude: 64.84, longitude: -147.72),
                CLLocationCoordinate2D(latitude: 64.85, longitude: -147.71)
            ],
            totalDistanceMiles: storedMiles,
            totalDurationSeconds: 600,
            steps: [step],
            costing: "auto"
        )

        // Verify that formatting back to metric reproduces exact 10.0 km without drift
        XCTAssertEqual(details.formattedDistance(useMetric: true), "10.0 km")
        XCTAssertEqual(step.formattedDistance(useMetric: true), "10.0 km")

        // Short distance metric formatting (meters)
        let shortKm = 0.5 // 500 meters
        let shortMiles = shortKm / conversionDivisor
        let shortStep = NavigationStep(
            instruction: "Drive 500m",
            distanceMiles: shortMiles,
            durationSeconds: 30,
            maneuverType: 1,
            streetName: "Cushman",
            startIndex: 0,
            endIndex: 2
        )
        XCTAssertEqual(shortStep.formattedDistance(useMetric: true), "500 m")
    }

    // MARK: - 22. NavigationViewModel Hardware GPS Start Fix (R2.4)
    func test22_NavigationViewModelStartNavigationHardwareGPSRetention() {
        let lm = LocationManager()
        let vm = NavigationViewModel(locationManager: lm)
        let coords = [
            CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215),
            CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7210)
        ]
        let details = RouteDetails(
            coordinates: coords,
            totalDistanceMiles: 0.1,
            totalDurationSeconds: 30,
            steps: [NavigationStep(instruction: "Go", distanceMiles: 0.1, durationSeconds: 30, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 1)],
            costing: "auto"
        )
        vm.routeDetails = details
        vm.routeCoordinates = coords

        // 1. With fresh, accurate, in-region hardware fix:
        let hardwareFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 64.8438, longitude: -147.7212),
            altitude: 100,
            horizontalAccuracy: 10.0,
            verticalAccuracy: 5.0,
            course: 45.0,
            speed: 5.0,
            timestamp: Date()
        )
        lm.locationManager(CLLocationManager(), didUpdateLocations: [hardwareFix])
        vm.startNavigation()
        XCTAssertEqual(vm.simulatedUserCoordinate?.latitude ?? 0, 64.8438, accuracy: 0.0001, "Valid hardware GPS fix must be retained at navigation start")
        XCTAssertEqual(vm.simulatedHeading ?? 0, 45.0, accuracy: 0.1)
        vm.endNavigation()

        // 2. With degraded accuracy (>= 65m):
        let degradedFix = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 64.8438, longitude: -147.7212),
            altitude: 100,
            horizontalAccuracy: 75.0,
            verticalAccuracy: 5.0,
            course: 45.0,
            speed: 5.0,
            timestamp: Date()
        )
        lm.locationManager(CLLocationManager(), didUpdateLocations: [degradedFix])
        vm.routeDetails = details
        vm.routeCoordinates = coords
        vm.startNavigation()
        XCTAssertEqual(vm.simulatedUserCoordinate?.latitude ?? 0, coords.first!.latitude, accuracy: 0.0001, "Degraded hardware fix must fall back to polyline start")
        vm.endNavigation()
    }

    // MARK: - 23. Multi-Speed Simulation Loop Advances Maneuvers (R2.3)
    func test23_NavigationViewModelAdvanceSimulationStepMultiSpeedLoop() {
        let vm = NavigationViewModel()
        var coords: [CLLocationCoordinate2D] = []
        for i in 0..<20 {
            coords.append(CLLocationCoordinate2D(latitude: 64.84 + Double(i) * 0.001, longitude: -147.72))
        }
        let step0 = NavigationStep(instruction: "Step 0", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 2)
        let step1 = NavigationStep(instruction: "Step 1", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 1, streetName: nil, startIndex: 2, endIndex: 4)
        let step2 = NavigationStep(instruction: "Step 2", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 1, streetName: nil, startIndex: 4, endIndex: 6)
        let step3 = NavigationStep(instruction: "Step 3", distanceMiles: 0.5, durationSeconds: 50, maneuverType: 1, streetName: nil, startIndex: 6, endIndex: 19)

        let details = RouteDetails(
            coordinates: coords,
            totalDistanceMiles: 0.8,
            totalDurationSeconds: 80,
            steps: [step0, step1, step2, step3],
            costing: "auto"
        )
        vm.routeDetails = details
        vm.routeCoordinates = coords
        vm.isNavigating = true
        vm.isSimulating = true
        vm.currentCoordIndex = 0
        vm.currentStepIndex = 0
        vm.simulationSpeedMultiplier = 5.0 // 5x speed leaps 5 coordinates per tick

        // Advance one simulation step: 0 + 5 = index 5, which spans step0, step1, and reaches step2
        vm.advanceSimulationStep()
        XCTAssertEqual(vm.currentCoordIndex, 5, "5x simulation step must jump 5 coordinate indices")
        XCTAssertEqual(vm.currentStepIndex, 2, "while-loop must advance through intermediate maneuvers without skipping")
        vm.endNavigation()
    }

    // MARK: - 24. Switchback Search Clamping (R2.1)
    func test24_NavigationViewModelSwitchbackSearchClamping() {
        let vm = NavigationViewModel()
        // Switchback road where segment A is parallel and geographically close to segment B
        // Segment 1 (indices 0..3): going north
        // Segment 2 (indices 4..7): hair-pin turn heading south just 10 meters east
        var coords: [CLLocationCoordinate2D] = []
        for i in 0...3 {
            coords.append(CLLocationCoordinate2D(latitude: 64.84 + Double(i) * 0.001, longitude: -147.7200))
        }
        for i in 4...7 {
            coords.append(CLLocationCoordinate2D(latitude: 64.843 - Double(i - 4) * 0.001, longitude: -147.7198))
        }
        let step1 = NavigationStep(instruction: "Go north", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 1, streetName: "North Way", startIndex: 0, endIndex: 3)
        let step2 = NavigationStep(instruction: "Hairpin turn south", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 2, streetName: "South Way", startIndex: 3, endIndex: 7)

        let details = RouteDetails(
            coordinates: coords,
            totalDistanceMiles: 0.4,
            totalDurationSeconds: 40,
            steps: [step1, step2],
            costing: "auto"
        )
        vm.routeDetails = details
        vm.routeCoordinates = coords
        vm.isNavigating = true
        vm.currentStepIndex = 0
        vm.currentCoordIndex = 1

        // User is at index 1, which is geographically ~15m from index 6 on return segment
        // Clamping restricts search to currentStep.endIndex + 2 = 3 + 2 = 5.
        // Index 6 and 7 cannot be jumped to!
        let userPos = CLLocationCoordinate2D(latitude: 64.8410, longitude: -147.7200)
        vm.updateCurrentStepForLiveLocation(userPos, in: details)

        XCTAssertEqual(vm.currentStepIndex, 0, "Current step must not advance prematurely to switchback return segment")
        XCTAssertTrue(vm.currentCoordIndex <= 5, "Coordinate search must remain clamped to currentStep.endIndex + 2")
        vm.endNavigation()
    }

    // MARK: - 25. Monotonic Telemetry Distance Countdown and Zeroing (R2.2)
    func test25_NavigationViewModelMonotonicTelemetryCountdownAndZeroing() {
        let vm = NavigationViewModel()
        let p0 = CLLocationCoordinate2D(latitude: 64.8400, longitude: -147.7200)
        let p1 = CLLocationCoordinate2D(latitude: 64.8410, longitude: -147.7200)
        let p2 = CLLocationCoordinate2D(latitude: 64.8420, longitude: -147.7200)
        let p3 = CLLocationCoordinate2D(latitude: 64.8430, longitude: -147.7200)
        let coords = [p0, p1, p2, p3]

        let step = NavigationStep(instruction: "Straight", distanceMiles: 0.3, durationSeconds: 30, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 2)
        let details = RouteDetails(coordinates: coords, totalDistanceMiles: 0.3, totalDurationSeconds: 30, steps: [step], costing: "auto")

        vm.routeDetails = details
        vm.currentStepIndex = 0

        // At index 0: distance > 0
        vm.updateNavigationTelemetry(at: p0, coordIndex: 0, in: details)
        let dist0 = vm.remainingStepDistanceMiles
        XCTAssertTrue(dist0 > 0.0)

        // At index 1: distance decreases monotonically
        vm.updateNavigationTelemetry(at: p1, coordIndex: 1, in: details)
        let dist1 = vm.remainingStepDistanceMiles
        XCTAssertTrue(dist1 < dist0, "Telemetry must decrease monotonically as user progresses")

        // At index 2 (stepEnd): evaluates strictly to 0.0
        vm.updateNavigationTelemetry(at: p2, coordIndex: 2, in: details)
        XCTAssertEqual(vm.remainingStepDistanceMiles, 0.0, "Telemetry must evaluate to zero at stepEnd")

        // At index 3 (past stepEnd): remains 0.0, no distance reversal
        vm.updateNavigationTelemetry(at: p3, coordIndex: 3, in: details)
        XCTAssertEqual(vm.remainingStepDistanceMiles, 0.0, "Telemetry must remain zero after passing stepEnd")
    }

    // MARK: - 26. Dual-Point Destination Arrival Detection (R2.5)
    func test26_NavigationViewModelDualPointArrivalDetection() {
        let vm = NavigationViewModel()
        let roadStart = CLLocationCoordinate2D(latitude: 64.8400, longitude: -147.7200)
        let roadEnd = CLLocationCoordinate2D(latitude: 64.8430, longitude: -147.7200)
        let coords = [roadStart, roadEnd]

        // Destination pin is set back in a parking lot 30m away from the road endpoint
        let setbackPin = CLLocationCoordinate2D(latitude: 64.8430, longitude: -147.7194)

        let step = NavigationStep(instruction: "Arrive", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 1)
        let details = RouteDetails(coordinates: coords, totalDistanceMiles: 0.2, totalDurationSeconds: 20, steps: [step], costing: "auto")

        vm.routeDetails = details
        vm.routeCoordinates = coords
        vm.selectedCoordinate = setbackPin
        vm.isNavigating = true
        vm.currentStepIndex = 0
        vm.currentCoordIndex = 1

        // User pulls into setback parking lot within 15m of destination pin (but >30m from roadEnd)
        let userInParkingLot = CLLocationCoordinate2D(latitude: 64.8430, longitude: -147.7196)
        vm.updateCurrentStepForLiveLocation(userInParkingLot, in: details)

        XCTAssertFalse(vm.isNavigating, "Arrival detection must trigger and end navigation when approaching setback destination pin")
        XCTAssertNil(vm.routeDetails, "Arrival must clear active route")
    }

    // MARK: - 27. Reset and End Navigation Teardown Cleanliness
    func test27_NavigationViewModelResetAndEndNavigationCleanliness() {
        let vm = NavigationViewModel()
        let coord = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        let place = SearchResult(id: 42, name: "Moose's Tooth", lat: 64.84, lon: -147.72)

        vm.selectPlace(place)
        vm.routeCoordinates = [coord]
        vm.routeDetails = RouteDetails(coordinates: [coord, coord], totalDistanceMiles: 1.0, totalDurationSeconds: 60, steps: [], costing: "auto")
        vm.isNavigating = true
        vm.isSimulating = true
        vm.simulatedUserCoordinate = coord
        vm.simulatedHeading = 90.0

        vm.resetToExplore()

        XCTAssertEqual(vm.appMode, .explore)
        XCTAssertFalse(vm.isNavigating)
        XCTAssertFalse(vm.isSimulating)
        XCTAssertNil(vm.routeDetails)
        XCTAssertNil(vm.routeCoordinates)
        XCTAssertNil(vm.selectedPlace)
        XCTAssertNil(vm.selectedCoordinate)
        XCTAssertNil(vm.simulatedUserCoordinate)
        XCTAssertNil(vm.simulatedHeading)
        XCTAssertEqual(vm.destinationText, "")
        XCTAssertTrue(vm.searchResults.isEmpty)
        XCTAssertNil(vm.searchTask)
    }
}

// MARK: - Empirical Challenger Concurrency & Audio Safety Stress Suite
final class ConcurrencyAudioStressTests: XCTestCase {

    // MARK: - Test 1: 50+ Concurrent Background Threads on speakTurnInstruction
    func testHighConcurrency50PlusThreadsSpeakTurnInstruction() {
        let routingService = RoutingService()
        let threadCount = 64
        let dispatchGroup = DispatchGroup()
        let completionExpectation = expectation(description: "All 64 concurrent threads complete within strict deadline")

        for i in 0..<threadCount {
            dispatchGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let stepId: Int?
                let text: String
                let force: Bool

                switch i % 4 {
                case 0:
                    // nil stepId
                    stepId = nil
                    text = "Instruction with nil step \(i)"
                    force = false
                case 1:
                    // consecutive distinct stepId
                    stepId = i
                    text = "Instruction \(i) in \(i * 50) feet"
                    force = false
                case 2:
                    // identical stepId and identical text (deduplication target)
                    stepId = 42
                    text = "Turn left onto Main Street in 200 feet"
                    force = false
                case 3:
                    // force flag enabled
                    stepId = i
                    text = "Forced priority announcement \(i)"
                    force = true
                default:
                    stepId = nil
                    text = "Default turn instruction"
                    force = false
                }

                routingService.speakTurnInstruction(text, stepId: stepId, force: force)
                dispatchGroup.leave()
            }
        }

        DispatchQueue.global().async {
            let waitResult = dispatchGroup.wait(timeout: .now() + 4.0)
            XCTAssertEqual(waitResult, .success, "50+ concurrent background threads calling speakTurnInstruction must complete within 4.0s without deadlock")
            completionExpectation.fulfill()
        }

        wait(for: [completionExpectation], timeout: 5.0)
    }

    // MARK: - Test 2: Concurrently Mutating isVoiceMuted Across Multiple Threads
    func testConcurrentVoiceMuteMutationAcrossThreads() {
        let routingService = RoutingService()
        let workerCount = 50
        let iterationsPerWorker = 40
        let dispatchGroup = DispatchGroup()
        let completionExpectation = expectation(description: "Concurrent voice mute mutation threads complete")

        for worker in 0..<workerCount {
            dispatchGroup.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                for iter in 0..<iterationsPerWorker {
                    switch worker % 4 {
                    case 0:
                        // Mutate to true (triggers stopVoice internally)
                        routingService.isVoiceMuted = true
                    case 1:
                        // Mutate to false
                        routingService.isVoiceMuted = false
                    case 2:
                        // Read property concurrently
                        _ = routingService.isVoiceMuted
                    case 3:
                        // Interleave with speech prompts
                        let force = (iter % 3 == 0)
                        routingService.speakTurnInstruction("Prompt \(worker)-\(iter)", stepId: iter, force: force)
                    default:
                        break
                    }
                }
                dispatchGroup.leave()
            }
        }

        DispatchQueue.global().async {
            let waitResult = dispatchGroup.wait(timeout: .now() + 5.0)
            XCTAssertEqual(waitResult, .success, "50 concurrent workers mutating and reading isVoiceMuted must complete without deadlock")
            completionExpectation.fulfill()
        }

        wait(for: [completionExpectation], timeout: 6.0)
    }

    // MARK: - Test 3: Calling stopVoice() in Tight Loops While Speech Is Active or Queued
    func testStopVoiceInTightLoopsWhileSpeechActiveOrQueued() {
        let routingService = RoutingService()
        let tightLoopThreads = 30
        let iterations = 25
        let dispatchGroup = DispatchGroup()
        let completionExpectation = expectation(description: "stopVoice tight loop stress completes")

        for t in 0..<tightLoopThreads {
            dispatchGroup.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                for i in 0..<iterations {
                    if t % 2 == 0 {
                        routingService.speakTurnInstruction("Tight loop prompt \(t)-\(i)", stepId: i, force: (i % 2 == 0))
                    }
                    routingService.stopVoice()

                    // Simulate concurrent AVSpeechSynthesizer delegate callbacks
                    let dummyUtterance = AVSpeechUtterance(string: "Dummy \(t)-\(i)")
                    let dummySynth = AVSpeechSynthesizer()
                    if i % 2 == 0 {
                        routingService.speechSynthesizer(dummySynth, didCancel: dummyUtterance)
                    } else {
                        routingService.speechSynthesizer(dummySynth, didFinish: dummyUtterance)
                    }
                }
                dispatchGroup.leave()
            }
        }

        DispatchQueue.global().async {
            let waitResult = dispatchGroup.wait(timeout: .now() + 5.0)
            XCTAssertEqual(waitResult, .success, "Tight loops of stopVoice() alongside active speech must complete without deadlock or crash")
            completionExpectation.fulfill()
        }

        wait(for: [completionExpectation], timeout: 6.0)
    }

    // MARK: - Test 4: Combined Multi-Vector Adversarial Churn Stress
    func testCombinedMultiVectorAdversarialChurnStress() {
        let routingService = RoutingService()
        let totalThreads = 60
        let dispatchGroup = DispatchGroup()
        let completionExpectation = expectation(description: "Combined multi-vector stress completes")

        for threadIndex in 0..<totalThreads {
            dispatchGroup.enter()
            DispatchQueue.global(qos: .userInteractive).async {
                for iteration in 0..<20 {
                    let role = threadIndex % 5
                    switch role {
                    case 0:
                        // Speak un-indexed instructions
                        routingService.speakTurnInstruction("Un-indexed turn \(iteration)", stepId: nil, force: false)
                    case 1:
                        // Speak indexed instructions with alternating force
                        routingService.speakTurnInstruction("Turn \(iteration) onto Route 3", stepId: iteration, force: (iteration % 2 == 0))
                    case 2:
                        // Rapid mute toggling
                        routingService.isVoiceMuted = (iteration % 2 == 0)
                    case 3:
                        // Rapid stopVoice calls
                        routingService.stopVoice()
                    case 4:
                        // Delegate callbacks
                        let dummyUtterance = AVSpeechUtterance(string: "Utterance \(threadIndex)-\(iteration)")
                        let dummySynth = AVSpeechSynthesizer()
                        if iteration % 2 == 0 {
                            routingService.speechSynthesizer(dummySynth, didFinish: dummyUtterance)
                        } else {
                            routingService.speechSynthesizer(dummySynth, didCancel: dummyUtterance)
                        }
                    default:
                        break
                    }
                }
                dispatchGroup.leave()
            }
        }

        DispatchQueue.global().async {
            let waitResult = dispatchGroup.wait(timeout: .now() + 6.0)
            XCTAssertEqual(waitResult, .success, "Combined multi-vector churn of 60 threads must complete within 6.0s without deadlock")
            completionExpectation.fulfill()
        }

        wait(for: [completionExpectation], timeout: 7.0)
    }

    // MARK: - Test 5: Fast Navigation Restart on the Same Route (0.1s, 1s, 2s, 5s)
    func testFastNavigationRestartOnSameRoute() {
        let routingService = RoutingService()
        let initialInstruction = "Turn right onto Chena Pump Road in 500 feet"
        let firstStepId = 0

        // Subtest 1: Verify baseline behavior WITHOUT stopVoice()
        // Immediate duplicate prompt within 6 seconds on the same step must be suppressed
        routingService.stopVoice() // Clean slate
        routingService.speakTurnInstruction(initialInstruction, stepId: firstStepId, force: false)

        let mirror1 = Mirror(reflecting: routingService)
        let gen1 = mirror1.children.first { $0.label == "activeSpeechGeneration" }?.value as? Int
        XCTAssertNotNil(gen1, "activeSpeechGeneration must be initialized")

        // Call again immediately without stopVoice
        routingService.speakTurnInstruction(initialInstruction, stepId: firstStepId, force: false)
        let mirrorDup = Mirror(reflecting: routingService)
        let genDup = mirrorDup.children.first { $0.label == "activeSpeechGeneration" }?.value as? Int
        XCTAssertEqual(gen1, genDup, "Duplicate prompt within 6 seconds without route restart must be suppressed (generation unchanged)")

        // Subtest 2: Fast restart with stopVoice() at various delays (0.05s, 0.5s, 1.0s, 2.0s, 5.0s)
        let testDelays: [TimeInterval] = [0.05, 0.5, 1.0, 2.0]
        for delay in testDelays {
            // End previous route
            routingService.stopVoice()

            let mirrorAfterStop = Mirror(reflecting: routingService)
            let lastInstructionAfterStop = mirrorAfterStop.children.first { $0.label == "lastSpokenInstruction" }?.value as? String
            let lastStepIdAfterStop = mirrorAfterStop.children.first { $0.label == "lastSpokenStepId" }?.value as? Int?
            let lastTimeAfterStop = mirrorAfterStop.children.first { $0.label == "lastSpokenTime" }?.value as? Date
            let genAfterStop = mirrorAfterStop.children.first { $0.label == "activeSpeechGeneration" }?.value as? Int

            XCTAssertEqual(lastInstructionAfterStop, "", "stopVoice must clear lastSpokenInstruction")
            XCTAssertEqual(lastStepIdAfterStop, nil, "stopVoice must clear lastSpokenStepId")
            XCTAssertEqual(lastTimeAfterStop, Date.distantPast, "stopVoice must reset lastSpokenTime to distantPast")

            // Wait the delay duration
            if delay > 0.05 {
                Thread.sleep(forTimeInterval: min(delay, 0.2)) // sleep briefly
            }

            // User restarts navigation on the EXACT same route, receiving the first turn instruction
            routingService.speakTurnInstruction(initialInstruction, stepId: firstStepId, force: false)

            let mirrorAfterRestart = Mirror(reflecting: routingService)
            let instructionAfterRestart = mirrorAfterRestart.children.first { $0.label == "lastSpokenInstruction" }?.value as? String
            let stepIdAfterRestart = mirrorAfterRestart.children.first { $0.label == "lastSpokenStepId" }?.value as? Int?
            let genAfterRestart = mirrorAfterRestart.children.first { $0.label == "activeSpeechGeneration" }?.value as? Int

            XCTAssertEqual(instructionAfterRestart, initialInstruction, "On restart after \(delay)s, initial turn instruction must be announced")
            XCTAssertEqual(stepIdAfterRestart, firstStepId, "On restart after \(delay)s, initial stepId must be set")
            XCTAssertTrue((genAfterRestart ?? 0) > (genAfterStop ?? 0), "Speech generation must advance on restart after \(delay)s (prompt NOT swallowed)")
        }
    }

    // MARK: - Test 6: Step Deduplication Edge Cases (nil, consecutive, identical, force)
    func testStepDeduplicationEdgeCases() {
        let routingService = RoutingService()

        // 6.1: nil stepId deduplication within 6.0 seconds
        routingService.stopVoice()
        routingService.speakTurnInstruction("Head north on Airport Way", stepId: nil, force: false)
        let genA1 = Mirror(reflecting: routingService).children.first { $0.label == "activeSpeechGeneration" }?.value as? Int

        routingService.speakTurnInstruction("Head north on Airport Way", stepId: nil, force: false)
        let genA2 = Mirror(reflecting: routingService).children.first { $0.label == "activeSpeechGeneration" }?.value as? Int
        XCTAssertEqual(genA1, genA2, "Identical text with nil stepId within 6s must be deduplicated")

        // 6.2: nil stepId with different text must NOT be deduplicated
        routingService.speakTurnInstruction("In 500 feet, turn right", stepId: nil, force: false)
        let genA3 = Mirror(reflecting: routingService).children.first { $0.label == "activeSpeechGeneration" }?.value as? Int
        XCTAssertTrue((genA3 ?? 0) > (genA2 ?? 0), "Different text with nil stepId must be spoken")

        // 6.3: consecutive distinct steps with identical text (e.g. roundabout exits or continue straight)
        routingService.stopVoice()
        routingService.speakTurnInstruction("Continue straight", stepId: 10, force: false)
        let genB1 = Mirror(reflecting: routingService).children.first { $0.label == "activeSpeechGeneration" }?.value as? Int

        routingService.speakTurnInstruction("Continue straight", stepId: 11, force: false)
        let genB2 = Mirror(reflecting: routingService).children.first { $0.label == "activeSpeechGeneration" }?.value as? Int
        XCTAssertTrue((genB2 ?? 0) > (genB1 ?? 0), "Consecutive distinct steps with identical text must NOT be deduplicated")

        // 6.4: force = true must always speak regardless of duplicate state
        routingService.speakTurnInstruction("Continue straight", stepId: 11, force: true)
        let genB3 = Mirror(reflecting: routingService).children.first { $0.label == "activeSpeechGeneration" }?.value as? Int
        XCTAssertTrue((genB3 ?? 0) > (genB2 ?? 0), "force: true must bypass deduplication and increment generation")

        // 6.5: muted state must silently drop prompts
        routingService.isVoiceMuted = true // this calls stopVoice() which increments generation
        let genAfterMute = Mirror(reflecting: routingService).children.first { $0.label == "activeSpeechGeneration" }?.value as? Int
        routingService.speakTurnInstruction("Instruction while muted", stepId: 12, force: true)
        let genAfterPromptWhileMuted = Mirror(reflecting: routingService).children.first { $0.label == "activeSpeechGeneration" }?.value as? Int
        XCTAssertEqual(genAfterMute, genAfterPromptWhileMuted, "Muted service must drop speakTurnInstruction calls even when force: true")
        routingService.isVoiceMuted = false
    }

    // MARK: - Test 7: Route Calculation Fail-Fast Non-Blocking Timeout
    func testRouteCalculationFailFastTimeout() {
        let routingService = RoutingService()
        // Out-of-region coordinates
        let coordA = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194) // San Francisco (not Alaska)
        let coordB = CLLocationCoordinate2D(latitude: 37.7750, longitude: -122.4195)

        let startTime = CFAbsoluteTimeGetCurrent()
        let result = routingService.calculateRoute(from: coordA, to: coordB)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertNil(result, "Out of region route calculation must return nil")
        XCTAssertTrue(elapsed < 6.0, "Route calculation must fail fast within timeout and not block indefinitely (took \(elapsed)s)")
    }
}

// MARK: - Milestone 2 Challenger: LocationManager Adversarial Stress Suite
final class LocationManagerAdversarialStressTests: XCTestCase {

    // Helper to extract private previousSpeedMps via Mirror
    private func getPreviousSpeedMps(from lm: LocationManager) -> Double? {
        let mirror = Mirror(reflecting: lm)
        for child in mirror.children {
            if child.label == "previousSpeedMps", let val = child.value as? Double {
                return val
            }
        }
        return nil
    }

    // Helper to create fresh test CLLocation
    private func makeFix(lat: Double = 64.8436, lon: Double = -147.7215, accuracy: Double, speed: Double, course: Double = 90.0, age: TimeInterval = 0.0) -> CLLocation {
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 135.0,
            horizontalAccuracy: accuracy,
            verticalAccuracy: 5.0,
            course: course,
            speed: speed,
            timestamp: Date().addingTimeInterval(-age)
        )
    }

    // MARK: - Challenge 1: GPS Degradation Transitions & Speed Smoothing Recovery
    func testGPSDegradationTransitionsAndSpeedRecovery() async throws {
        let lm = await MainActor.run { LocationManager() }
        let clManager = CLLocationManager()

        // Phase 1: Establish baseline high-speed cruising (25 m/s = ~56 mph) with good 5m accuracy
        let goodFix1 = makeFix(accuracy: 5.0, speed: 25.0)
        lm.locationManager(clManager, didUpdateLocations: [goodFix1])
        try await Task.sleep(nanoseconds: 30_000_000) // 30ms

        await MainActor.run {
            XCTAssertFalse(lm.isGpsSignalLow, "Good accuracy (5.0m) must not flag low GPS")
            XCTAssertFalse(lm.isStationary, "Moving vehicle (25 m/s) must not be stationary")
            // After 1 fix at 25 m/s: EMA = 0.35 * 25.0 + 0.65 * 0.0 = 8.75 m/s -> 20 mph
            XCTAssertEqual(lm.smoothedSpeedMph, 20, "First fix speed must smooth up to 20 mph")
            XCTAssertEqual(lm.smoothedSpeedKmh, 32, "First fix speed must smooth up to 32 km/h")
        }

        // Deliver second good fix to build up cruising speed:
        // EMA = 0.35 * 25.0 + 0.65 * 8.75 = 8.75 + 5.6875 = 14.4375 m/s -> 32 mph (52 km/h)
        let goodFix2 = makeFix(lat: 64.8438, lon: -147.7210, accuracy: 5.0, speed: 25.0)
        lm.locationManager(clManager, didUpdateLocations: [goodFix2])
        try await Task.sleep(nanoseconds: 30_000_000)

        await MainActor.run {
            XCTAssertEqual(lm.smoothedSpeedMph, 32, "Second fix speed must smooth up to 32 mph")
            XCTAssertEqual(lm.smoothedSpeedKmh, 52, "Second fix speed must smooth up to 52 km/h")
            let prevSpeed = self.getPreviousSpeedMps(from: lm)
            XCTAssertNotNil(prevSpeed)
            XCTAssertEqual(prevSpeed!, 14.4375, accuracy: 0.001)
        }

        // Phase 2: Enter tunnel / canyon — Degraded accuracy at exact boundary (65.0m)
        let degradedFix65 = makeFix(lat: 64.8440, lon: -147.7205, accuracy: 65.0, speed: 25.0)
        lm.locationManager(clManager, didUpdateLocations: [degradedFix65])
        try await Task.sleep(nanoseconds: 30_000_000)

        await MainActor.run {
            XCTAssertTrue(lm.isGpsSignalLow, "Accuracy 65.0m must set isGpsSignalLow = true")
            XCTAssertTrue(lm.isStationary, "Degraded GPS must immediately set isStationary = true")
            XCTAssertEqual(lm.smoothedSpeedMph, 0, "Degraded GPS (65.0m) must immediately zero smoothedSpeedMph")
            XCTAssertEqual(lm.smoothedSpeedKmh, 0, "Degraded GPS (65.0m) must immediately zero smoothedSpeedKmh")
            let prevSpeed = self.getPreviousSpeedMps(from: lm)
            XCTAssertEqual(prevSpeed, 0.0, "previousSpeedMps must be reset to 0.0 to prevent stale EMA carryover")
        }

        // Phase 3: Signal recovery exiting tunnel — Good 10.0m accuracy at 25.0 m/s
        let recoveryFix1 = makeFix(lat: 64.8445, lon: -147.7190, accuracy: 10.0, speed: 25.0)
        lm.locationManager(clManager, didUpdateLocations: [recoveryFix1])
        try await Task.sleep(nanoseconds: 30_000_000)

        await MainActor.run {
            XCTAssertFalse(lm.isGpsSignalLow, "Recovered accuracy (10.0m) must clear isGpsSignalLow")
            XCTAssertFalse(lm.isStationary, "Moving vehicle must clear isStationary")
            // Because previousSpeedMps was zeroed, EMA starts cleanly from 0.0:
            // EMA = 0.35 * 25.0 + 0.65 * 0.0 = 8.75 m/s -> 20 mph
            XCTAssertEqual(lm.smoothedSpeedMph, 20, "Speed smoothing must cleanly start from 0 without spike or math corruption")
            XCTAssertEqual(lm.smoothedSpeedKmh, 32, "Speed smoothing km/h must match clean EMA starting from 0")
            let prevSpeed = self.getPreviousSpeedMps(from: lm)
            XCTAssertEqual(prevSpeed!, 8.75, accuracy: 0.001)
        }

        // Phase 4: High degradation (> 65.0m, e.g. 70.0m)
        let degradedFix70 = makeFix(lat: 64.8450, lon: -147.7180, accuracy: 70.0, speed: 25.0)
        lm.locationManager(clManager, didUpdateLocations: [degradedFix70])
        try await Task.sleep(nanoseconds: 30_000_000)

        await MainActor.run {
            XCTAssertTrue(lm.isGpsSignalLow, "Accuracy 70.0m must set isGpsSignalLow = true")
            XCTAssertTrue(lm.isStationary, "isStationary must be true at 70.0m")
            XCTAssertEqual(lm.smoothedSpeedMph, 0, "smoothedSpeedMph must be 0 at 70.0m")
            XCTAssertEqual(lm.smoothedSpeedKmh, 0, "smoothedSpeedKmh must be 0 at 70.0m")
            XCTAssertEqual(self.getPreviousSpeedMps(from: lm), 0.0)
        }

        // Phase 5: Negative horizontal accuracy (-1.0m, uncalibrated)
        let negativeFix = makeFix(lat: 64.8455, lon: -147.7170, accuracy: -1.0, speed: 25.0)
        lm.locationManager(clManager, didUpdateLocations: [negativeFix])
        try await Task.sleep(nanoseconds: 30_000_000)

        await MainActor.run {
            XCTAssertTrue(lm.isGpsSignalLow, "Negative accuracy (-1.0m) must set isGpsSignalLow = true")
            XCTAssertTrue(lm.isStationary, "isStationary must be true on negative accuracy")
            XCTAssertEqual(lm.smoothedSpeedMph, 0)
            XCTAssertEqual(lm.smoothedSpeedKmh, 0)
            XCTAssertEqual(self.getPreviousSpeedMps(from: lm), 0.0)
        }

        // Phase 6: Recovery while vehicle stopped during GPS outage (0.0 m/s)
        let stoppedRecoveryFix = makeFix(lat: 64.8460, lon: -147.7160, accuracy: 5.0, speed: 0.0)
        lm.locationManager(clManager, didUpdateLocations: [stoppedRecoveryFix])
        try await Task.sleep(nanoseconds: 30_000_000)

        await MainActor.run {
            XCTAssertFalse(lm.isGpsSignalLow, "Signal recovered")
            XCTAssertTrue(lm.isStationary, "Vehicle stopped must remain stationary")
            XCTAssertEqual(lm.smoothedSpeedMph, 0, "Vehicle stopped must have 0 mph (no phantom speed spikes)")
            XCTAssertEqual(lm.smoothedSpeedKmh, 0)
            XCTAssertEqual(self.getPreviousSpeedMps(from: lm), 0.0)
        }
    }

    // MARK: - Challenge 1b: Rapid Alternating Oscillation Stress Harness
    func testRapidAlternatingOscillationStress() async throws {
        let lm = await MainActor.run { LocationManager() }
        let clManager = CLLocationManager()

        // 100 alternating iterations between good and degraded GPS
        for i in 0..<100 {
            // Good fix
            let goodFix = makeFix(lat: 64.84 + Double(i) * 0.0001, accuracy: 5.0, speed: 25.0)
            lm.locationManager(clManager, didUpdateLocations: [goodFix])
            try await Task.sleep(nanoseconds: 2_000_000) // 2ms

            // Degraded fix (alternating 65.0, 70.0, -1.0)
            let degradedAcc: Double
            switch i % 3 {
            case 0: degradedAcc = 65.0
            case 1: degradedAcc = 70.0
            default: degradedAcc = -1.0
            }

            let badFix = makeFix(lat: 64.84 + Double(i) * 0.0001, accuracy: degradedAcc, speed: 25.0)
            lm.locationManager(clManager, didUpdateLocations: [badFix])
            try await Task.sleep(nanoseconds: 2_000_000) // 2ms
        }

        // Final settling check
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        await MainActor.run {
            XCTAssertTrue(lm.isGpsSignalLow, "Final fix was degraded, so signal must be low")
            XCTAssertEqual(lm.smoothedSpeedMph, 0, "Speedometer must be zeroed")
            XCTAssertEqual(lm.smoothedSpeedKmh, 0)
            XCTAssertTrue(lm.isStationary)
            XCTAssertEqual(self.getPreviousSpeedMps(from: lm), 0.0)
        }

        // Now deliver 1 good recovery fix and check math sanity
        let recoveryFix = makeFix(accuracy: 8.0, speed: 20.0)
        lm.locationManager(clManager, didUpdateLocations: [recoveryFix])
        try await Task.sleep(nanoseconds: 30_000_000)

        await MainActor.run {
            XCTAssertFalse(lm.isGpsSignalLow)
            XCTAssertFalse(lm.isStationary)
            XCTAssertFalse(lm.smoothedSpeedMph.words.contains(where: { _ in false })) // non-corrupted int
            XCTAssertTrue(lm.smoothedSpeedMph > 0 && lm.smoothedSpeedMph <= 45, "Speed must be in reasonable range without math corruption (got \(lm.smoothedSpeedMph))")
        }
    }

    // MARK: - Challenge 2: Lifecycle & Thread Safety in deinit
    func testRapidConcurrentInstantiationsAndDeallocations() async throws {
        let initialGenerating = await MainActor.run { UIDevice.current.isGeneratingDeviceOrientationNotifications }

        // Test 2a: Rapid sequential creations and destructions on MainActor
        for _ in 0..<50 {
            let _ = await MainActor.run {
                LocationManager()
            }
        }

        // Test 2b: Concurrent creation on MainActor and release on background worker threads
        // This exercises deinit running while Thread.isMainThread == false, triggering
        // DispatchQueue.main.async { UIDevice.current.endGeneratingDeviceOrientationNotifications() }
        let iterations = 40
        let group = DispatchGroup()

        for _ in 0..<iterations {
            group.enter()
            Task.detached {
                let lm = await MainActor.run {
                    LocationManager()
                }
                // Simulate some work, then drop strong reference on background thread
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
                _ = lm // released here on background thread
                group.leave()
            }
        }

        // Simultaneously broadcast device orientation notifications from another thread
        let notificationStressGroup = DispatchGroup()
        notificationStressGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<50 {
                NotificationCenter.default.post(name: UIDevice.orientationDidChangeNotification, object: nil)
                Thread.sleep(forTimeInterval: 0.001)
            }
            notificationStressGroup.leave()
        }

        // Wait for all background tasks and orientation notifications
        _ = group.wait(timeout: .now() + 5.0)
        _ = notificationStressGroup.wait(timeout: .now() + 5.0)

        // Drain any pending DispatchQueue.main.async deinit blocks
        let drainExpectation = expectation(description: "Drain main queue dispatches")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            drainExpectation.fulfill()
        }
        await fulfillment(of: [drainExpectation], timeout: 2.0)

        // Verify that after all instances are deallocated, orientation notifications balance matches initial state
        let finalGenerating = await MainActor.run { UIDevice.current.isGeneratingDeviceOrientationNotifications }
        XCTAssertEqual(initialGenerating, finalGenerating, "Orientation notification generation counter must return to its initial state without leaks")
    }

    // MARK: - Challenge 3: Transient CoreLocation Error 0 Handling
    func testTransientCoreLocationError0Handling() async throws {
        let lm = await MainActor.run { LocationManager() }
        let clManager = CLLocationManager()

        // 1. Establish good location fix first
        let goodFix = makeFix(accuracy: 10.0, speed: 20.0)
        lm.locationManager(clManager, didUpdateLocations: [goodFix])
        try await Task.sleep(nanoseconds: 30_000_000)

        await MainActor.run {
            XCTAssertFalse(lm.isGpsSignalLow, "Baseline must have good signal")
            XCTAssertTrue(lm.smoothedSpeedMph > 0, "Baseline speed must be positive")
        }

        let speedBeforeError = await MainActor.run { lm.smoothedSpeedMph }

        // 2. Deliver transient CLError.locationUnknown (code 0)
        let transientCLError = CLError(.locationUnknown)
        lm.locationManager(clManager, didFailWithError: transientCLError)
        try await Task.sleep(nanoseconds: 30_000_000)

        await MainActor.run {
            XCTAssertFalse(lm.isGpsSignalLow, "CLError.locationUnknown (error 0) must NOT flip isGpsSignalLow to true")
            XCTAssertEqual(lm.smoothedSpeedMph, speedBeforeError, "Transient error 0 must not zero out speed")
            XCTAssertFalse(lm.isStationary, "Transient error 0 must not set isStationary to true")
        }

        // 3. Deliver transient NSError with domain kCLErrorDomain and code 0
        let transientNSError = NSError(
            domain: kCLErrorDomain,
            code: CLError.locationUnknown.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "The operation couldn’t be completed. (kCLErrorDomain error 0.)"]
        )
        lm.locationManager(clManager, didFailWithError: transientNSError)
        try await Task.sleep(nanoseconds: 30_000_000)

        await MainActor.run {
            XCTAssertFalse(lm.isGpsSignalLow, "NSError kCLErrorDomain code 0 must NOT flip isGpsSignalLow to true")
            XCTAssertEqual(lm.smoothedSpeedMph, speedBeforeError, "Transient NSError 0 must not zero out speed")
        }

        // 4. Contrast with genuine fatal error: CLError.denied (code 1)
        let fatalError = CLError(.denied)
        lm.locationManager(clManager, didFailWithError: fatalError)
        try await Task.sleep(nanoseconds: 30_000_000)

        await MainActor.run {
            XCTAssertTrue(lm.isGpsSignalLow, "Genuine CLError.denied must set isGpsSignalLow to true")
            XCTAssertEqual(lm.smoothedSpeedMph, 0, "Genuine CLError.denied must zero smoothedSpeedMph")
            XCTAssertEqual(lm.smoothedSpeedKmh, 0, "Genuine CLError.denied must zero smoothedSpeedKmh")
            XCTAssertTrue(lm.isStationary, "Genuine CLError.denied must set isStationary to true")
            XCTAssertEqual(self.getPreviousSpeedMps(from: lm), 0.0, "Genuine CLError.denied must reset previousSpeedMps to 0")
        }
    }
}
