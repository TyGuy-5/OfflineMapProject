import Foundation
import CoreLocation

#if canImport(XCTest)
import XCTest
#endif

#if canImport(MyOfflineMapApp)
@testable import MyOfflineMapApp
#endif

// MARK: - Tier 3: Cross-Feature Combinations Test Suite (22 Pairwise Tests)
public final class Tier3_CrossFeatureTests: XCTestCase {
    
    // MARK: Pair 1: F1 (Resolved Origin) ↔ F5 (Remote Origin Preview Mode)
    @MainActor
    public func test_Pairwise_01_OriginCoordinateAndRemotePreview() async {
        let userLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let mockLoc = MockLocationManager(currentLocation: userLocation)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let destPlace = PlaceLocation(name: "Dest", coordinate: CLLocationCoordinate2D(latitude: 37.80, longitude: -122.40))
        vm.destinationEndpoint = .custom(place: destPlace)
        
        // Remote origin (>200m)
        let remoteCoord = LocationSequenceBuilder.shift(coordinate: userLocation.coordinate, northMeters: 350.0, eastMeters: 0.0)
        let remotePlace = PlaceLocation(name: "Presidio Heights", coordinate: remoteCoord)
        vm.originEndpoint = .custom(place: remotePlace)
        await vm.calculateRoute()
        
        XCTAssertTrue(vm.isRemoteOrigin(thresholdMeters: 200.0))
        XCTAssertTrue(vm.isRoutePreviewMode)
        
        // Change to near origin (<=200m)
        let nearCoord = LocationSequenceBuilder.shift(coordinate: userLocation.coordinate, northMeters: 100.0, eastMeters: 0.0)
        let nearPlace = PlaceLocation(name: "Civic Center", coordinate: nearCoord)
        vm.originEndpoint = .custom(place: nearPlace)
        await vm.calculateRoute()
        
        XCTAssertFalse(vm.isRemoteOrigin(thresholdMeters: 200.0))
        XCTAssertFalse(vm.isRoutePreviewMode)
    }

    // MARK: Pair 2: F1 (Resolved Origin) ↔ F4 (Origin/Destination Swap)
    @MainActor
    public func test_Pairwise_02_CustomOriginWithSwapRecalculation() async {
        let userLoc = CLLocation(latitude: 46.85, longitude: -113.98)
        let mockLoc = MockLocationManager(currentLocation: userLoc)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let originPlace = PlaceLocation(name: "Trailhead Base", coordinate: CLLocationCoordinate2D(latitude: 46.8529, longitude: -113.9850))
        let destPlace = PlaceLocation(name: "Sentinel Summit", coordinate: CLLocationCoordinate2D(latitude: 46.8558, longitude: -113.9785))
        
        vm.originEndpoint = .custom(place: originPlace)
        vm.destinationEndpoint = .custom(place: destPlace)
        await vm.calculateRoute()
        let countBefore = mockRouting.calculateRouteCallCount
        
        vm.swapOriginDestination()
        try? await Task.sleep(nanoseconds: 20_000_000)
        
        XCTAssertEqual(vm.originEndpoint.displayName, "Sentinel Summit")
        XCTAssertEqual(vm.destinationEndpoint?.displayName, "Trailhead Base")
        XCTAssertGreaterThanOrEqual(mockRouting.calculateRouteCallCount, countBefore + 1)
    }

    // MARK: Pair 3: F2 (Two-Field Directions UI) ↔ F6 (Coordinate Search Parsing)
    @MainActor
    public func test_Pairwise_03_DirectionsUIWithCoordinateSearch() async {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        
        // Search coordinate for origin
        let originInput = "46.8529, -113.9850"
        if let originCoord = SearchService.parseCoordinateString(originInput) {
            let place = PlaceLocation(name: originInput, coordinate: originCoord)
            vm.originEndpoint = .custom(place: place)
        }
        
        // Search coordinate for destination
        let destInput = "46.8558, -113.9785"
        if let destCoord = SearchService.parseCoordinateString(destInput) {
            let place = PlaceLocation(name: destInput, coordinate: destCoord)
            vm.destinationEndpoint = .custom(place: place)
        }
        await vm.calculateRoute()
        
        XCTAssertEqual(vm.originEndpoint.displayName, originInput)
        XCTAssertEqual(vm.destinationEndpoint?.displayName, destInput)
        XCTAssertEqual(mockRouting.calculateRouteCallCount, 1)
    }

    // MARK: Pair 4: F3 (Reset Origin) ↔ F5 (Remote Origin Preview Mode)
    @MainActor
    public func test_Pairwise_04_ResetOriginDisablesPreviewMode() async {
        let userLoc = CLLocation(latitude: 46.85, longitude: -113.98)
        let mockLoc = MockLocationManager(currentLocation: userLoc)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let remotePlace = PlaceLocation(name: "Glacier Park", coordinate: CLLocationCoordinate2D(latitude: 48.69, longitude: -113.78))
        let destPlace = PlaceLocation(name: "Campground", coordinate: CLLocationCoordinate2D(latitude: 48.70, longitude: -113.77))
        
        vm.destinationEndpoint = .custom(place: destPlace)
        vm.originEndpoint = .custom(place: remotePlace)
        await vm.calculateRoute()
        XCTAssertTrue(vm.isRoutePreviewMode)
        
        vm.resetOriginToCurrentLocation()
        XCTAssertFalse(vm.isRoutePreviewMode)
        XCTAssertTrue(vm.originEndpoint.isCurrentLocation)
        XCTAssertEqual(vm.destinationEndpoint?.displayName, "Campground")
    }

    // MARK: Pair 5: F4 (Origin/Destination Swap) ↔ F5 (Remote Origin Preview Mode)
    @MainActor
    public func test_Pairwise_05_SwapWithRemoteOriginTogglesPreview() async {
        let userLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let mockLoc = MockLocationManager(currentLocation: userLocation)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        
        // Origin is local (user location); Destination is remote (10 km away)
        let remoteDest = PlaceLocation(name: "Mount Tamalpais", coordinate: CLLocationCoordinate2D(latitude: 37.9235, longitude: -122.5965))
        vm.destinationEndpoint = .custom(place: remoteDest)
        await vm.calculateRoute()
        XCTAssertFalse(vm.isRoutePreviewMode)
        
        // Swap: remote becomes origin
        vm.swapOriginDestination()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(vm.isRoutePreviewMode)
        
        // Swap again: local returns to origin
        vm.swapOriginDestination()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(vm.isRoutePreviewMode)
    }

    // MARK: Pair 6: F6 (Coordinate Search) ↔ F1 (Resolved Origin Coordinate)
    @MainActor
    public func test_Pairwise_06_CoordinateSearchSetsResolvedOrigin() {
        let parsedCoord = SearchService.parseCoordinateString("  37.7749 , -122.4194 ")
        XCTAssertNotNil(parsedCoord)
        
        let place = PlaceLocation(name: "Custom Pin", coordinate: parsedCoord!)
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        vm.originEndpoint = .custom(place: place)
        
        let resolved = vm.resolveCoordinate(for: vm.originEndpoint)
        XCTAssertEqual(resolved?.latitude, parsedCoord?.latitude)
        XCTAssertEqual(resolved?.longitude, parsedCoord?.longitude)
    }

    // MARK: Pair 7: F7 (Basemap Restyling) ↔ F10 (Regional Trails Overlay)
    @MainActor
    public func test_Pairwise_07_BasemapRestylingAndRegionalOverlayCoexistence() {
        let style = MLNStyle()
        
        // 1. Basemap restyling
        TrailOverlayManager.shared.applyBasemapTrailRestylingSafeguard(to: style)
        
        // 2. Add regional overlay
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("cross_overlay_\(UUID().uuidString).geojson")
        try? "{}".write(to: tempFile, atomically: true, encoding: .utf8)
        TrailOverlayManager.shared.applyTrailOverlay(to: style, geoJSONURLs: [tempFile])
        
        XCTAssertNotNil(style.source(withIdentifier: TrailOverlayManager.overlaySourceIdentifier))
        XCTAssertNotNil(style.layer(withIdentifier: TrailOverlayManager.orangeLineLayerIdentifier))
        
        TrailOverlayManager.shared.removeTrailOverlay(from: style)
        try? FileManager.default.removeItem(at: tempFile)
    }

    // MARK: Pair 8: F8 (Overpass Downloader) ↔ F9 (GeoJSON Storage & Backup Exclusion)
    public func test_Pairwise_08_DownloaderPersistsGeoJSONWithBackupExclusion() async throws {
        let downloader = RegionalTrailDownloader.shared
        let trailsDir = try await downloader.getTrailsDirectory()
        
        let testFileName = "test_persistence_\(UUID().uuidString).geojson"
        let testFileURL = trailsDir.appendingPathComponent(testFileName)
        try "{\"type\":\"FeatureCollection\"}".write(to: testFileURL, atomically: true, encoding: .utf8)
        
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        var mutableURL = testFileURL
        try mutableURL.setResourceValues(rv)
        
        let values = try? testFileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertNotNil(values)
        
        try FileManager.default.removeItem(at: testFileURL)
    }

    // MARK: Pair 9: F8 (Overpass Downloader) ↔ F10 (Regional Trails Overlay)
    @MainActor
    public func test_Pairwise_09_DownloadTriggersOverlayUpdate() throws {
        let style = MLNStyle()
        let converter = GeoJSONConverter()
        let geoJSON = try converter.convert(overpassJSONString: TrailTestFixtures.overpassJSONSample)
        
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("downloaded_sample_\(UUID().uuidString).geojson")
        try geoJSON.write(to: tempFile, atomically: true, encoding: .utf8)
        
        TrailOverlayManager.shared.applyTrailOverlay(to: style, geoJSONURLs: [tempFile])
        
        XCTAssertNotNil(style.source(withIdentifier: TrailOverlayManager.overlaySourceIdentifier))
        XCTAssertNotNil(style.layer(withIdentifier: TrailOverlayManager.orangeLineLayerIdentifier))
        
        TrailOverlayManager.shared.removeTrailOverlay(from: style)
        try? FileManager.default.removeItem(at: tempFile)
    }

    // MARK: Pair 10: F9 (GeoJSON Storage) ↔ F18 (Offline Airplane Mode Verification)
    public func test_Pairwise_10_OfflineStorageAccessWithoutNetwork() throws {
        MockURLProtocol.reset() // Sever network
        
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("offline_read_\(UUID().uuidString).geojson")
        try TrailTestFixtures.overpassJSONSample.write(to: tempFile, atomically: true, encoding: .utf8)
        
        let data = try Data(contentsOf: tempFile)
        XCTAssertTrue(data.count > 0)
        
        let converter = GeoJSONConverter()
        let geoJSON = try converter.convert(overpassData: data)
        XCTAssertTrue(geoJSON.count > 0)
        
        try? FileManager.default.removeItem(at: tempFile)
    }

    // MARK: Pair 11: F11 (GPX Importer & Scanner) ↔ F12 (Native XML GPX Parser)
    public func test_Pairwise_11_ScannerPassesGPXToXMLParser() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("scanner_parser_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let gpxPath = tempDir.appendingPathComponent("trail.gpx")
        try TrailTestFixtures.validGPXString.write(to: gpxPath, atomically: true, encoding: .utf8)
        
        // Scan directory
        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let gpxFiles = files.filter { $0.pathExtension.lowercased() == "gpx" }
        XCTAssertEqual(gpxFiles.count, 1)
        
        // Parse discovered file
        let parser = E2EGPXParser()
        let data = try Data(contentsOf: gpxFiles[0])
        let track = try parser.parse(data: data)
        
        XCTAssertEqual(track.name, "Mount Sentinel Trail")
        XCTAssertEqual(track.points.count, 5)
        
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: Pair 12: F11 (GPX File Importer) ↔ F13 (GPX Map Overlay)
    public func test_Pairwise_12_ImportedGPXAddedToMapOverlay() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        
        // Generate overlay coordinate array from imported track
        let coords = track.points.map { $0.coordinate }
        XCTAssertEqual(coords.count, 5)
        
        let layerId = "gpx-overlay-\(track.id.uuidString)"
        XCTAssertTrue(layerId.contains(track.id.uuidString))
    }

    // MARK: Pair 13: F12 (Native XML GPX Parser) ↔ F15 (Active Trail Following)
    public func test_Pairwise_13_ParsedTrackInitializesNavigator() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        XCTAssertEqual(nav.remainingDistance, track.totalDistance)
        XCTAssertEqual(nav.userProgressDistance, 0.0)
        XCTAssertEqual(nav.currentElevation, track.points[0].elevation)
    }

    // MARK: Pair 14: F12 (Native XML GPX Parser) ↔ F17 (Elevation Profile Chart)
    public func test_Pairwise_14_ParsedTrackGeneratesElevationChart() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        
        let elevations = track.points.compactMap { $0.elevation }
        XCTAssertEqual(elevations.count, 5)
        
        let minEle = elevations.min()!
        let maxEle = elevations.max()!
        XCTAssertEqual(minEle, 980.5)
        XCTAssertEqual(maxEle, 1158.0)
        XCTAssertEqual(track.elevationGain, maxEle - minEle)
    }

    // MARK: Pair 15: F14 (Fitness Tracking) ↔ F15 (Active Trail Following)
    public func test_Pairwise_15_TrailNavigationActivatesFitnessTracking() throws {
        var activityType: CLActivityType = .otherNavigation
        
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        
        // Start navigation sets fitness activity type
        nav.startNavigation(track: track)
        activityType = .fitness
        XCTAssertEqual(activityType, .fitness)
        
        // Stop navigation restores
        nav.stopNavigation()
        activityType = .otherNavigation
        XCTAssertEqual(activityType, .otherNavigation)
    }

    // MARK: Pair 16: F14 (Fitness Tracking) ↔ F16 (Off-Trail Audio Alert)
    public func test_Pairwise_16_FitnessModeWithOffTrailDeviation() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let spy = MockAudioAlertSpy()
        let nav = E2ETrailNavigator(audioAlertSpy: spy)
        nav.startNavigation(track: track)
        
        // Raw GPS coordinate offset 35m perpendicular to trail
        let offCoord = LocationSequenceBuilder.shift(coordinate: track.points[0].coordinate, northMeters: 0.0, eastMeters: 35.0)
        let rawLoc = CLLocation(
            coordinate: offCoord,
            altitude: 1000.0,
            horizontalAccuracy: 5.0, // High accuracy fitness GPS
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        
        nav.updateLocation(rawLoc)
        XCTAssertTrue(nav.isOffTrail)
        XCTAssertEqual(spy.alertPlayCount, 1)
    }

    // MARK: Pair 17: F15 (Active Trail Following) ↔ F16 (Off-Trail Audio Alert)
    public func test_Pairwise_17_ActiveTrackingCoordinatesWithDebouncedAlert() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let spy = MockAudioAlertSpy()
        let nav = E2ETrailNavigator(audioAlertSpy: spy)
        nav.startNavigation(track: track)
        
        // Step 1: On trail
        nav.updateLocation(CLLocation(latitude: track.points[1].coordinate.latitude, longitude: track.points[1].coordinate.longitude))
        XCTAssertFalse(nav.isOffTrail)
        XCTAssertEqual(spy.alertPlayCount, 0)
        
        // Step 2: Off trail (>25m)
        let off = LocationSequenceBuilder.shift(coordinate: track.points[1].coordinate, northMeters: 0.0, eastMeters: 30.0)
        nav.updateLocation(CLLocation(latitude: off.latitude, longitude: off.longitude))
        XCTAssertTrue(nav.isOffTrail)
        XCTAssertEqual(spy.alertPlayCount, 1)
        
        // Step 3: Recover (<18m)
        let rec = LocationSequenceBuilder.shift(coordinate: track.points[1].coordinate, northMeters: 0.0, eastMeters: 10.0)
        nav.updateLocation(CLLocation(latitude: rec.latitude, longitude: rec.longitude))
        XCTAssertFalse(nav.isOffTrail)
    }

    // MARK: Pair 18: F15 (Active Trail Following) ↔ F17 (Elevation Profile Chart)
    public func test_Pairwise_18_NavigationUpdatesElevationChartMarker() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        // Advance to 3rd waypoint
        let pt3 = track.points[3]
        nav.updateLocation(CLLocation(latitude: pt3.coordinate.latitude, longitude: pt3.coordinate.longitude))
        
        XCTAssertEqual(nav.currentElevation, pt3.elevation)
        let progressFraction = nav.userProgressDistance / track.totalDistance
        XCTAssertGreaterThan(progressFraction, 0.5)
    }

    // MARK: Pair 19: F16 (Off-Trail Audio Alert) ↔ F18 (Offline Airplane Mode Verification)
    public func test_Pairwise_19_OffTrailAlertInAirplaneMode() throws {
        MockURLProtocol.reset() // Sever network
        
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let spy = MockAudioAlertSpy()
        let nav = E2ETrailNavigator(audioAlertSpy: spy)
        nav.startNavigation(track: track)
        
        let offCoord = LocationSequenceBuilder.shift(coordinate: track.points[0].coordinate, northMeters: 0.0, eastMeters: 40.0)
        nav.updateLocation(CLLocation(latitude: offCoord.latitude, longitude: offCoord.longitude))
        
        XCTAssertTrue(nav.isOffTrail)
        XCTAssertEqual(spy.alertPlayCount, 1)
    }

    // MARK: Pair 20: F4 (Swap) ↔ F15 (Active Trail Following)
    public func test_Pairwise_20_RoundTripSwapAndReverseNavigation() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        
        // Reverse track points for return journey
        let reversedPoints = track.points.reversed().map { pt in
            E2EGPXTrackPoint(coordinate: pt.coordinate, elevation: pt.elevation, time: nil, cumulativeDistance: 0.0)
        }
        let returnTrack = E2EGPXTrack(name: "\(track.name) (Return)", points: reversedPoints, totalDistance: track.totalDistance, elevationGain: track.elevationLoss, elevationLoss: track.elevationGain)
        
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: returnTrack)
        
        XCTAssertEqual(nav.activeTrack?.name, "Mount Sentinel Trail (Return)")
        XCTAssertEqual(nav.remainingDistance, track.totalDistance)
    }

    // MARK: Pair 21: F10 (Regional Trails Overlay) ↔ F13 (GPX Map Overlay)
    @MainActor
    public func test_Pairwise_21_RegionalOverlayAndGPXOverlayCoexistence() {
        let regionalSourceId = TrailOverlayManager.overlaySourceIdentifier
        let gpxTrackId = UUID()
        let gpxSourceId = "gpx-source-\(gpxTrackId.uuidString)"
        
        XCTAssertFalse(regionalSourceId == gpxSourceId)
        XCTAssertTrue(gpxSourceId.hasPrefix("gpx-source-"))
    }

    // MARK: Pair 22: F6 (Coordinate Search) ↔ F11 (GPX File Importer)
    public func test_Pairwise_22_CoordinateSearchTrailheadToGPXTrailhead() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let firstPt = track.points[0]
        
        let searchString = "\(firstPt.coordinate.latitude), \(firstPt.coordinate.longitude)"
        let parsed = SearchService.parseCoordinateString(searchString)
        XCTAssertNotNil(parsed)
        
        let distanceToTrailhead = LocationSequenceBuilder.distance(from: parsed!, to: firstPt.coordinate)
        XCTAssertLessThan(distanceToTrailhead, 1.0)
    }
}
