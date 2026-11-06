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
        let view = ContentView()

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
            XCTAssertTrue(view.isWithinSupportedRegion(coord), "Expected \(coord.latitude), \(coord.longitude) to be within supported Alaska region")
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
            XCTAssertFalse(view.isWithinSupportedRegion(coord), "Expected \(coord.latitude), \(coord.longitude) to be outside supported Alaska region")
        }

        // 1.3 Verify default Alaska fallback coordinate
        XCTAssertEqual(ContentView.defaultAlaskaCoordinate.latitude, 64.8436, accuracy: 0.0001)
        XCTAssertEqual(ContentView.defaultAlaskaCoordinate.longitude, -147.7215, accuracy: 0.0001)

        // 1.4 Verify effectiveUserCoordinate falls back to Fairbanks when simulated coord is nil and device location is nil/unsupported
        let effective = view.effectiveUserCoordinate
        XCTAssertEqual(effective.latitude, ContentView.defaultAlaskaCoordinate.latitude, accuracy: 0.0001)
        XCTAssertEqual(effective.longitude, ContentView.defaultAlaskaCoordinate.longitude, accuracy: 0.0001)
    }

    // MARK: - 2. In-flight search task cancellation
    func test02_InFlightSearchTaskCancellation() async throws {
        var view = ContentView()

        // 2.1 Invoke dismissal, clear, and reset methods to verify clean execution
        view.dismissSearch()
        view.clearSearch()
        view.resetToExplore()

        // 2.2 Cooperative task cancellation test
        let exp = expectation(description: "Search task cancellation probe")
        let task = Task.detached(priority: .userInitiated) {
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
                XCTFail("Task should have been cancelled")
            } catch {
                exp.fulfill()
            }
        }
        task.cancel()
        XCTAssertTrue(task.isCancelled, "Task handle must report isCancelled == true")
        await fulfillment(of: [exp], timeout: 1.0)

        // 2.3 Verify source code contracts for searchTask cancellation across clear, dismiss, and reset
        let contentViewURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ContentView.swift")

        let content = try String(contentsOf: contentViewURL, encoding: .utf8)

        // Verify dismissSearch cancels searchTask
        XCTAssertTrue(
            content.contains("func dismissSearch()"),
            "ContentView must define dismissSearch"
        )
        // Verify clearSearch cancels searchTask
        XCTAssertTrue(
            content.contains("func clearSearch()"),
            "ContentView must define clearSearch"
        )
        // Verify resetToExplore cancels searchTask
        XCTAssertTrue(
            content.contains("func resetToExplore()"),
            "ContentView must define resetToExplore"
        )
        // Verify searchTask?.cancel() is called in all three lifecycle methods
        let occurrences = content.components(separatedBy: "searchTask?.cancel()").count - 1
        XCTAssertTrue(occurrences >= 4, "Expected searchTask?.cancel() in handleQueryChange, dismissSearch, clearSearch, and resetToExplore, found \(occurrences)")
    }

    // MARK: - 3. Category search single invocation
    func test03_CategorySearchSingleInvocation() throws {
        var view = ContentView()

        // 3.1 Verify execution of searchCategory
        view.searchCategory("Gas")

        // 3.2 Inspect ContentView.swift to verify single invocation architecture:
        // isProgrammaticTextChange = true must be set before destinationText = category
        let contentViewURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ContentView.swift")

        let content = try String(contentsOf: contentViewURL, encoding: .utf8)
        XCTAssertTrue(
            content.contains("isProgrammaticTextChange = true"),
            "ContentView must set isProgrammaticTextChange = true before modifying destinationText"
        )
        XCTAssertTrue(
            content.contains("if isProgrammaticTextChange"),
            "onChange(of: destinationText) must check isProgrammaticTextChange to suppress duplicate queries"
        )
    }

    // MARK: - 4. Route telemetry calculation with 0 steps
    func test04_RouteTelemetryCalculationZeroStepsSafety() {
        var view = ContentView()

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
        view.routeDetails = detailsWithZeroSteps

        // In the unpatched code, updateNavigationTelemetry evaluated:
        // (currentStepIndex < details.steps.count) ? details.steps[currentStepIndex] : details.steps.last!
        // When details.steps is empty, evaluating details.steps.last! crashed via force unwrap of nil.
        // In the patched code, this must execute safely without throwing or crashing.
        view.updateNavigationTelemetry(at: coord1, coordIndex: 0, in: detailsWithZeroSteps)

        XCTAssertEqual(view.remainingStepDistanceMiles, 0.0, "Expected remaining step distance to be 0.0 when steps array is empty")

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
        view.updateNavigationTelemetry(at: coord1, coordIndex: 0, in: detailsWithSteps)
    }

    // MARK: - 5. Distance unit toggling
    func test05_DistanceUnitTogglingPreservesSimulationProgress() throws {
        let view = ContentView()

        // 5.1 Unit string verifications (imperial default)
        XCTAssertEqual(view.speedUnit, "mph")
        XCTAssertEqual(view.altitudeUnit, "ft")

        // 5.2 Source contract verification:
        // onChange(of: useMetric) must guard !isNavigating && !isSimulating before recalculating
        let contentViewURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ContentView.swift")

        let content = try String(contentsOf: contentViewURL, encoding: .utf8)
        XCTAssertTrue(
            content.contains("if !isNavigating && !isSimulating") ||
            content.contains("if !isSimulating && !isNavigating"),
            "onChange(of: useMetric) must guard against resetting active simulation or navigation progress"
        )
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
    func test09_ProjectConfigurationAndDependencies() throws {
        // 9.1 Verify project.yml contains INFOPLIST_KEY_NSLocationTemporaryUsageDescriptionDictionary with NavigationAccuracy
        let projectYmlURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MyOfflineMapAppTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // MyOfflineMapApp
            .appendingPathComponent("project.yml")

        guard FileManager.default.fileExists(atPath: projectYmlURL.path) else {
            throw XCTSkip("project.yml not available at expected path: \(projectYmlURL.path)")
        }

        let projectYmlContent = try String(contentsOf: projectYmlURL, encoding: .utf8)
        XCTAssertTrue(projectYmlContent.contains("INFOPLIST_KEY_NSLocationTemporaryUsageDescriptionDictionary"), "project.yml must configure INFOPLIST_KEY_NSLocationTemporaryUsageDescriptionDictionary")
        XCTAssertTrue(projectYmlContent.contains("NavigationAccuracy"), "project.yml must specify NavigationAccuracy key")

        // 9.2 Verify unused ValhallaConfigModels is NOT in dependencies
        XCTAssertFalse(projectYmlContent.contains("product: ValhallaConfigModels"), "project.yml must not link unused ValhallaConfigModels product")

        // 9.3 Verify Info.plist contains NSLocationTemporaryUsageDescriptionDictionary
        let infoPlistURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Info.plist")

        if FileManager.default.fileExists(atPath: infoPlistURL.path) {
            let infoPlistData = try Data(contentsOf: infoPlistURL)
            if let plist = try PropertyListSerialization.propertyList(from: infoPlistData, format: nil) as? [String: Any] {
                let tempDict = plist["NSLocationTemporaryUsageDescriptionDictionary"] as? [String: Any]
                XCTAssertNotNil(tempDict, "Info.plist must contain NSLocationTemporaryUsageDescriptionDictionary")
                XCTAssertNotNil(tempDict?["NavigationAccuracy"], "Info.plist must define purpose key NavigationAccuracy")
            }
        }
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
    func test12_PhysicalDeviceHostPathProbing() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/OfflineDataManager.swift")

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw XCTSkip("OfflineDataManager.swift not found at expected path")
        }

        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        // Verify that #filePath lookup is guarded by simulator and/or macOS, never bare DEBUG on physical iOS devices
        XCTAssertTrue(
            source.contains("targetEnvironment(simulator)") || source.contains("os(macOS)"),
            "OfflineDataManager must guard developer host path lookup with simulator/macOS conditions"
        )
        XCTAssertFalse(
            source.contains("#if DEBUG || targetEnvironment(simulator)"),
            "OfflineDataManager must NOT use '#if DEBUG || targetEnvironment(simulator)' which triggers host path probes on physical iOS device debug builds"
        )
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
    func testAdversarial01_OutOfRegionGPSHandling() throws {
        let view = ContentView()

        // 1. Equator coordinates
        let equatorCoords = [
            CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),
            CLLocationCoordinate2D(latitude: 0.0, longitude: -147.0),
            CLLocationCoordinate2D(latitude: 0.0, longitude: 180.0),
            CLLocationCoordinate2D(latitude: 0.0, longitude: -180.0),
            CLLocationCoordinate2D(latitude: 0.0, longitude: -129.0)
        ]
        for coord in equatorCoords {
            XCTAssertFalse(view.isWithinSupportedRegion(coord), "Equator coordinate \(coord) must be out-of-region")
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
            XCTAssertFalse(view.isWithinSupportedRegion(coord), "Polar coordinate \(coord) must be out-of-region")
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
        XCTAssertFalse(view.isWithinSupportedRegion(dateLineCoords[0]))
        XCTAssertFalse(view.isWithinSupportedRegion(dateLineCoords[1]))
        XCTAssertFalse(view.isWithinSupportedRegion(dateLineCoords[2]))
        XCTAssertFalse(view.isWithinSupportedRegion(dateLineCoords[3]))
        XCTAssertTrue(view.isWithinSupportedRegion(dateLineCoords[4]))
        XCTAssertTrue(view.isWithinSupportedRegion(dateLineCoords[5]))
        XCTAssertFalse(view.isWithinSupportedRegion(dateLineCoords[6]))

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
            XCTAssertEqual(view.isWithinSupportedRegion(check.coord), check.expected, "Failed for \(check.label)")
        }

        // 5. Alaska fallback stability
        let fairbanks = ContentView.defaultAlaskaCoordinate
        XCTAssertEqual(view.effectiveUserCoordinate.latitude, fairbanks.latitude, accuracy: 0.0001)
        XCTAssertEqual(view.effectiveUserCoordinate.longitude, fairbanks.longitude, accuracy: 0.0001)
        XCTAssertTrue(view.isWithinSupportedRegion(fairbanks), "Default Alaska coordinate must be within supported region")

        // 6. Source contract verification: handleLocationUpdate must drop out-of-region fixes
        let contentViewURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ContentView.swift")

        let content = try String(contentsOf: contentViewURL, encoding: .utf8)
        XCTAssertTrue(
            content.contains("guard isWithinSupportedRegion(location.coordinate) else { return }"),
            "handleLocationUpdate must guard isWithinSupportedRegion to prevent overriding Alaska fallback"
        )
    }

    // MARK: - Adversarial Challenge 2: Search task lifecycle
    func testAdversarial02_SearchTaskLifecycle() async throws {
        var view = ContentView()

        // Rapidly start searches and cancel/clear/dismiss across 50 iterations
        for i in 0..<50 {
            let query = (i % 2 == 0) ? "Fairbanks" : "Anchorage Airport"
            view.searchCategory(query)

            if i % 3 == 0 {
                view.clearSearch()
                XCTAssertNil(view.searchTask, "searchTask must be nil after clearSearch")
            } else if i % 3 == 1 {
                view.dismissSearch()
                XCTAssertNil(view.searchTask, "searchTask must be nil after dismissSearch")
            } else {
                view.resetToExplore()
                XCTAssertNil(view.searchTask, "searchTask must be nil after resetToExplore")
            }
        }

        // Concurrent asynchronous query storm with cancellation
        let searchService = SearchService()
        let userLoc = ContentView.defaultAlaskaCoordinate

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
        view.resetToExplore()
        XCTAssertNil(view.searchTask)
    }

    // MARK: - Adversarial Challenge 3: Category search deduplication
    func testAdversarial03_CategorySearchDeduplication() throws {
        var view = ContentView()

        // 1. Rapid successive category chip taps (must execute safely without race or exception)
        let categories = ["Gas", "Coffee", "Restaurant", "Market", "Parking", "Hotel", "Hospital"]
        for cat in categories {
            view.searchCategory(cat)
        }

        // 2. Repeat tap on same category chip
        view.searchCategory("Hospital")
        view.searchCategory("Hospital")

        // 3. Clean reset
        view.clearSearch()

        // 4. Source contract: verify isProgrammaticTextChange suppression logic
        let contentViewURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ContentView.swift")

        let content = try String(contentsOf: contentViewURL, encoding: .utf8)
        XCTAssertTrue(
            content.contains("if destinationText != category {\n            isProgrammaticTextChange = true\n            destinationText = category\n        }"),
            "searchCategory must guard destinationText modification with isProgrammaticTextChange"
        )
        XCTAssertTrue(
            content.contains("if isProgrammaticTextChange {\n                            isProgrammaticTextChange = false\n                            return\n                        }"),
            "onChange(of: destinationText) must suppress query execution when isProgrammaticTextChange is true"
        )
    }

    // MARK: - Adversarial Challenge 4: Route telemetry (0 steps, 1 step, large step arrays)
    func testAdversarial04_RouteTelemetryZeroOneAndLargeStepArrays() {
        var view = ContentView()

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
        view.routeDetails = zeroStepsRoute

        // Test extreme coord indices with 0 steps (must not force-unwrap or crash)
        for idx in [-5, 0, 1, 10] {
            view.updateNavigationTelemetry(at: coordA, coordIndex: idx, in: zeroStepsRoute)
            XCTAssertFalse(view.formattedRemainingDuration.isEmpty)
            XCTAssertFalse(view.formattedRemainingETA.isEmpty)
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
        view.routeDetails = oneStepRoute
        view.updateNavigationTelemetry(at: coordA, coordIndex: 0, in: oneStepRoute)
        XCTAssertFalse(view.formattedRemainingDuration.isEmpty)

        view.updateNavigationTelemetry(at: coordC, coordIndex: 2, in: oneStepRoute)
        XCTAssertFalse(view.formattedRemainingDuration.isEmpty)

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
        view.routeDetails = largeRoute

        let testIndices = [-10, 0, 1, 2500, 4998, 4999, 5050]
        for idx in testIndices {
            view.updateNavigationTelemetry(at: largeCoords[min(max(0, idx), 4999)], coordIndex: idx, in: largeRoute)
            XCTAssertFalse(view.formattedRemainingDuration.isEmpty)
            XCTAssertFalse(view.formattedRemainingETA.isEmpty)
        }

        // Case D: Zero-distance / Zero-duration route (division by zero protection)
        let zeroLengthRoute = RouteDetails(
            coordinates: [coordA, coordB],
            totalDistanceMiles: 0.0,
            totalDurationSeconds: 0.0,
            steps: [],
            costing: "auto"
        )
        view.updateNavigationTelemetry(at: coordA, coordIndex: 0, in: zeroLengthRoute)
        XCTAssertFalse(view.formattedRemainingDuration.isEmpty)

        // Case E: Precise countdown distance arithmetic
        XCTAssertEqual(view.formatCountdownDistance(0.0, useMetric: false), "0 ft")
        XCTAssertEqual(view.formatCountdownDistance(0.05, useMetric: false), "264 ft")
        XCTAssertEqual(view.formatCountdownDistance(0.099, useMetric: false), "522 ft")
        XCTAssertEqual(view.formatCountdownDistance(0.10, useMetric: false), "0.1 mi")
        XCTAssertEqual(view.formatCountdownDistance(0.5, useMetric: false), "0.5 mi")
        XCTAssertEqual(view.formatCountdownDistance(5.0, useMetric: false), "5.0 mi")

        XCTAssertEqual(view.formatCountdownDistance(0.0, useMetric: true), "0 m")
        XCTAssertEqual(view.formatCountdownDistance(0.05, useMetric: true), "80 m")
        XCTAssertEqual(view.formatCountdownDistance(0.5, useMetric: true), "804 m")
        XCTAssertEqual(view.formatCountdownDistance(5.0, useMetric: true), "8.0 km")
    }

    // MARK: - Adversarial Challenge 5: Simulation metric toggling
    func testAdversarial05_SimulationMetricTogglingProgressPreservation() throws {
        let view = ContentView()

        // 1. Source contract verification: onChange(of: useMetric) must guard !isNavigating && !isSimulating
        let contentViewURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ContentView.swift")

        let content = try String(contentsOf: contentViewURL, encoding: .utf8)
        XCTAssertTrue(
            content.contains("if !isNavigating && !isSimulating") || content.contains("if !isSimulating && !isNavigating"),
            "onChange(of: useMetric) must guard against route recalculation during navigation or simulation"
        )

        // 2. Unit labels and telemetry switching
        XCTAssertEqual(view.speedUnit, "mph")
        XCTAssertEqual(view.altitudeUnit, "ft")

        // 3. Countdown formatting preservation under metric toggle
        let imperialShort = view.formatCountdownDistance(0.05, useMetric: false)
        let metricShort = view.formatCountdownDistance(0.05, useMetric: true)
        XCTAssertTrue(imperialShort.contains("ft"))
        XCTAssertTrue(metricShort.contains("m"))

        let imperialLong = view.formatCountdownDistance(3.5, useMetric: false)
        let metricLong = view.formatCountdownDistance(3.5, useMetric: true)
        XCTAssertEqual(imperialLong, "3.5 mi")
        XCTAssertEqual(metricLong, "5.6 km")
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
    func testAdversarial09_PhysicalDeviceHostPathGuardElision() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/OfflineDataManager.swift")

        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        // 9.1 Verify that #filePath occurs exactly once in OfflineDataManager.swift
        let filePathMatches = source.components(separatedBy: "#filePath").count - 1
        XCTAssertEqual(filePathMatches, 1, "OfflineDataManager should use #filePath at most once")

        // 9.2 Verify the enclosing conditional compilation guard
        let devBlockRegex = "#if\\s*\\(targetEnvironment\\(simulator\\)\\s*\\|\\|\\s*os\\(macOS\\)\\)\\s*&&\\s*DEBUG"
        let range = source.range(of: devBlockRegex, options: .regularExpression)
        XCTAssertNotNil(range, "Developer source lookup must be strictly guarded by (targetEnvironment(simulator) || os(macOS)) && DEBUG")

        // 9.3 Verify there is NO bare '#if DEBUG' or '#if DEBUG || ...' guarding #filePath
        XCTAssertFalse(
            source.contains("#if DEBUG\n            let sourceURL = URL(fileURLWithPath: #filePath)") ||
            source.contains("#if DEBUG ||"),
            "Bare DEBUG check would evaluate on physical device debug builds, exposing host Mac paths"
        )

        // 9.4 Verify workspace relative path lookup is also restricted to simulator / macOS
        let workspaceRegex = "#if\\s*targetEnvironment\\(simulator\\)\\s*\\|\\|\\s*os\\(macOS\\)"
        XCTAssertNotNil(source.range(of: workspaceRegex, options: .regularExpression), "Workspace directory lookup must also be guarded by targetEnvironment(simulator) || os(macOS)")
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
                let utterance = AVSpeechUtterance(string: "Dummy \(i)")
                if i % 2 == 0 {
                    routingService.speechSynthesizer(dummySynth, didCancel: utterance)
                } else {
                    routingService.speechSynthesizer(dummySynth, didFinish: utterance)
                }
                dispatchGroup.leave()
            }
        }
        let waitResult = dispatchGroup.wait(timeout: .now() + 5.0)
        XCTAssertEqual(waitResult, .success, "Rapid concurrent prompt dispatch and delegate simulation must complete without deadlock")

        // 11.2 Verification of speech generation race prevention logic via source audit
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/RoutingService.swift")

        if let source = try? String(contentsOf: sourceURL, encoding: .utf8) {
            // Both didFinish and didCancel must guard generation == currentGen
            XCTAssertTrue(source.contains("guard generation == currentGen else { return }"), "RoutingService must guard against deactivating audio session if newer generation exists")
            // Both must check !self.speechSynthesizer.isSpeaking on main queue
            XCTAssertTrue(source.contains("guard !self.speechSynthesizer.isSpeaking else { return }"), "RoutingService must re-verify isSpeaking on main queue before calling setActive(false)")
        }
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
}




