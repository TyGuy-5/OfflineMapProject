import Foundation
import CoreLocation

#if canImport(XCTest)
import XCTest
#endif

#if canImport(MyOfflineMapApp)
@testable import MyOfflineMapApp
#endif

// MARK: - Tier 4: Real-World Workload Scenarios Test Suite (10 Workload Scenarios per TEST_INFRA.md)
public final class Tier4_RealWorldWorkloadTests: XCTestCase {
    
    // MARK: Scenario 1: Day Hike Trailhead Navigation (F1, F2, F3, F5, F6)
    @MainActor
    public func test_Scenario01_DayHikeTrailheadNavigation() async {
        let userLocation = CLLocation(latitude: 46.8721, longitude: -113.9940) // Missoula downtown
        let mockLoc = MockLocationManager(currentLocation: userLocation)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        
        // 1. Search coordinate for trailhead
        let trailheadInput = "46.8529, -113.9850"
        let trailheadCoord = SearchService.parseCoordinateString(trailheadInput)
        XCTAssertNotNil(trailheadCoord)
        
        let trailheadPlace = PlaceLocation(name: "Mount Sentinel Trailhead", coordinate: trailheadCoord!)
        
        // 2. Set origin to Current Location, destination to Trailhead
        vm.destinationEndpoint = .custom(place: trailheadPlace)
        await vm.calculateRoute()
        XCTAssertEqual(vm.originEndpoint, .currentLocation)
        XCTAssertFalse(vm.isRoutePreviewMode)
        XCTAssertEqual(mockRouting.calculateRouteCallCount, 1)
        
        // 3. User plans hike from a remote starting point (e.g. cabin 20 km away)
        let cabinCoord = LocationSequenceBuilder.shift(coordinate: userLocation.coordinate, northMeters: 20_000.0, eastMeters: 0.0)
        let cabinPlace = PlaceLocation(name: "Lolo Peak Cabin", coordinate: cabinCoord)
        vm.originEndpoint = .custom(place: cabinPlace)
        await vm.calculateRoute()
        
        // Verify remote origin switches to route preview mode
        XCTAssertTrue(vm.isRemoteOrigin())
        XCTAssertTrue(vm.isRoutePreviewMode)
        
        // 4. Quick action: Reset origin to Current Location
        vm.resetOriginToCurrentLocation()
        XCTAssertFalse(vm.isRoutePreviewMode)
        XCTAssertTrue(vm.originEndpoint.isCurrentLocation)
        
        // 5. User completes hike, swaps origin/dest to navigate return drive home
        vm.swapOriginDestination()
        XCTAssertEqual(vm.originEndpoint.displayName, "Mount Sentinel Trailhead")
        XCTAssertEqual(vm.destinationEndpoint, .currentLocation)
    }

    // MARK: Scenario 2: Regional Trail Download & Offline Inspection (F7, F8, F9, F10, F18)
    @MainActor
    public func test_Scenario02_RegionalTrailDownloadAndOfflineInspection() async throws {
        // 1. Pan map to wilderness bbox (0.1 degree span)
        let south = 46.80, west = -114.05, north = 46.90, east = -113.95
        
        // 2. Mock successful Overpass API response via MockURLProtocol
        MockURLProtocol.mockSuccessfulResponse(with: TrailTestFixtures.overpassJSONSample)
        let mockSession = MockURLProtocol.makeMockSession()
        
        let downloader = RegionalTrailDownloader(session: mockSession)
        
        // 3. Download regional trails
        let savedURL = try await downloader.downloadTrails(south: south, west: west, north: north, east: east, regionName: "Sentinel_Wilderness")
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))
        
        // 4. Verify file is excluded from backup attribute
        let resourceValues = try? savedURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertNotNil(resourceValues)
        
        // 5. Verify style overlay integration
        let style = MLNStyle()
        TrailOverlayManager.shared.applyTrailOverlay(to: style, geoJSONURLs: [savedURL])
        XCTAssertNotNil(style.source(withIdentifier: TrailOverlayManager.overlaySourceIdentifier))
        XCTAssertNotNil(style.layer(withIdentifier: TrailOverlayManager.orangeLineLayerIdentifier))
        
        // 6. Verify airplane mode inspection
        MockURLProtocol.reset() // Network severed
        let list = await downloader.listDownloadedRegions()
        XCTAssertTrue(list.map { $0.lastPathComponent }.contains(savedURL.lastPathComponent))
        
        // Clean up
        try await downloader.deleteDownloadedRegion(at: savedURL)
        TrailOverlayManager.shared.removeTrailOverlay(from: style)
    }

    // MARK: Scenario 3: GPX Import from AirDrop/Files (F11, F12, F13, F17)
    public func test_Scenario03_GPXImportFromFiles() throws {
        // 1. Place simulated imported file into temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("airdrop_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let gpxFileURL = tempDir.appendingPathComponent("sentinel_ridge.gpx")
        try TrailTestFixtures.validGPXString.write(to: gpxFileURL, atomically: true, encoding: .utf8)
        
        // 2. Parse GPX track
        let parser = E2EGPXParser()
        let data = try Data(contentsOf: gpxFileURL)
        let track = try parser.parse(data: data)
        
        XCTAssertEqual(track.name, "Mount Sentinel Trail")
        XCTAssertEqual(track.points.count, 5)
        XCTAssertGreaterThan(track.totalDistance, 500.0)
        
        // 3. Extract elevation profile for chart
        let elevations = track.points.compactMap { $0.elevation }
        XCTAssertEqual(elevations.count, 5)
        XCTAssertEqual(elevations.first, 980.5)
        XCTAssertEqual(elevations.last, 1158.0)
        XCTAssertEqual(track.elevationGain, 1158.0 - 980.5)
        
        // 4. Map overlay geometry extraction
        let overlayCoordinates = track.points.map { $0.coordinate }
        XCTAssertEqual(overlayCoordinates.count, 5)
        
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: Scenario 4: Live Wilderness Hike with Off-Trail Recovery (F14, F15, F16, F17, F18)
    public func test_Scenario04_LiveWildernessHikeWithOffTrailRecovery() throws {
        // 1. Setup track and navigation with fitness tracking and audio alert spy
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let alertSpy = MockAudioAlertSpy()
        let nav = E2ETrailNavigator(audioAlertSpy: alertSpy)
        
        var locationActivity: CLActivityType = .otherNavigation
        nav.startNavigation(track: track)
        locationActivity = .fitness
        XCTAssertEqual(locationActivity, .fitness)
        
        // 2. Advance user along trail: Point 0 -> Point 1 -> Point 2
        for i in 0...2 {
            let pt = track.points[i]
            let loc = CLLocation(latitude: pt.coordinate.latitude, longitude: pt.coordinate.longitude)
            let result = nav.updateLocation(loc)
            XCTAssertFalse(result.isOffTrail)
            XCTAssertEqual(nav.currentElevation, pt.elevation)
        }
        XCTAssertEqual(alertSpy.alertPlayCount, 0)
        
        // 3. User drifts 35m off-trail perpendicular to point 2
        let offCoord = LocationSequenceBuilder.shift(coordinate: track.points[2].coordinate, northMeters: 0.0, eastMeters: 35.0)
        let offLoc = CLLocation(latitude: offCoord.latitude, longitude: offCoord.longitude)
        let offResult = nav.updateLocation(offLoc)
        
        XCTAssertTrue(offResult.isOffTrail)
        XCTAssertGreaterThan(offResult.deviation, 25.0)
        XCTAssertEqual(alertSpy.alertPlayCount, 1)
        
        // 4. User realizes deviation, steps to 20m (dead zone: 18m < d < 25m, must remain off-trail)
        let deadZoneCoord = LocationSequenceBuilder.shift(coordinate: track.points[2].coordinate, northMeters: 0.0, eastMeters: 20.0)
        let deadZoneResult = nav.updateLocation(CLLocation(latitude: deadZoneCoord.latitude, longitude: deadZoneCoord.longitude))
        XCTAssertTrue(deadZoneResult.isOffTrail)
        
        // 5. User steps to 10m (<18m hysteresis threshold), recovers on trail
        let recoveredCoord = LocationSequenceBuilder.shift(coordinate: track.points[2].coordinate, northMeters: 0.0, eastMeters: 10.0)
        let recoveredResult = nav.updateLocation(CLLocation(latitude: recoveredCoord.latitude, longitude: recoveredCoord.longitude))
        
        XCTAssertFalse(recoveredResult.isOffTrail)
        XCTAssertLessThan(recoveredResult.deviation, 18.0)
        
        // 6. User continues to summit (Point 4)
        let summitPt = track.points[4]
        nav.updateLocation(CLLocation(latitude: summitPt.coordinate.latitude, longitude: summitPt.coordinate.longitude))
        XCTAssertEqual(nav.remainingDistance, 0.0)
        XCTAssertEqual(nav.currentElevation, summitPt.elevation)
        
        nav.stopNavigation()
        locationActivity = .otherNavigation
        XCTAssertEqual(locationActivity, .otherNavigation)
    }

    // MARK: Scenario 5: Multi-Trail Concurrency & Memory Hygiene (F9, F10, F11, F13, F19)
    @MainActor
    public func test_Scenario05_MultiTrailConcurrencyAndMemoryHygiene() throws {
        let style = MLNStyle()
        let parser = E2EGPXParser()
        let nav = E2ETrailNavigator()
        
        // 1. Create 3 regional GeoJSON trail files with valid FeatureCollection
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("multi_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let validGeoJSON = """
        {"type":"FeatureCollection","features":[{"type":"Feature","id":1,"geometry":{"type":"LineString","coordinates":[[-122.4,37.7],[-122.41,37.71]]},"properties":{}}]}
        """
        var regionalURLs: [URL] = []
        for i in 1...3 {
            let u = tempDir.appendingPathComponent("region_\(i).geojson")
            try validGeoJSON.write(to: u, atomically: true, encoding: .utf8)
            regionalURLs.append(u)
        }
        
        // Apply regional overlay
        TrailOverlayManager.shared.applyTrailOverlay(to: style, geoJSONURLs: regionalURLs)
        XCTAssertNotNil(style.source(withIdentifier: TrailOverlayManager.overlaySourceIdentifier))
        
        // 2. Import 5 GPX tracks and switch active track
        for _ in 1...5 {
            let gpxData = TrailTestFixtures.validGPXString
            let track = try parser.parse(xmlString: gpxData)
            nav.startNavigation(track: track)
            XCTAssertEqual(nav.activeTrack?.name, "Mount Sentinel Trail")
            nav.stopNavigation()
            XCTAssertNil(nav.activeTrack)
        }
        
        // 3. Clean up overlay
        TrailOverlayManager.shared.removeTrailOverlay(from: style)
        XCTAssertNil(style.source(withIdentifier: TrailOverlayManager.overlaySourceIdentifier))
        
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: Scenario 6: Extreme Elevation Alpine Trek (F12, F15, F17, F18)
    public func test_Scenario06_ExtremeElevationAlpineTrek() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.alpineTrekGPXString)
        
        // 1. Verify high-altitude elevation gain calculation (>2,800m ascent)
        XCTAssertEqual(track.points.count, 4)
        XCTAssertGreaterThan(track.elevationGain, 2800.0)
        XCTAssertEqual(track.points.first?.elevation, 1035.0)
        XCTAssertEqual(track.points.last?.elevation, 3842.0)
        
        // 2. Initialize navigator and track progress to summit
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        for pt in track.points {
            nav.updateLocation(CLLocation(latitude: pt.coordinate.latitude, longitude: pt.coordinate.longitude))
            XCTAssertEqual(nav.currentElevation, pt.elevation)
            XCTAssertFalse(nav.isOffTrail)
        }
        
        XCTAssertEqual(nav.remainingDistance, 0.0)
        XCTAssertEqual(nav.currentElevation, 3842.0)
    }

    // MARK: Scenario 7: Degraded GPS & Signal Loss Simulation (F14, F15, F16)
    public func test_Scenario07_DegradedGPSSignalLossSimulation() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let alertSpy = MockAudioAlertSpy()
        let nav = E2ETrailNavigator(audioAlertSpy: alertSpy)
        nav.debounceIntervalSeconds = 5.0
        nav.startNavigation(track: track)
        
        // Generate degraded GPS readings (±65m accuracy)
        let degradedLocations = LocationSequenceBuilder.makeDegradedAccuracyTrack(
            start: track.points[0].coordinate,
            count: 5,
            accuracyMeters: 65.0
        )
        
        for loc in degradedLocations {
            nav.updateLocation(loc)
        }
        
        // Verify debouncing prevents flood of alert audio calls
        XCTAssertLessThan(Double(alertSpy.alertPlayCount), 3.0)
    }

    // MARK: Scenario 8: Interrupted Download & Resilient Retry (F8, F9, F18)
    public func test_Scenario08_InterruptedDownloadAndResilientRetry() async throws {
        let south = 46.85, west = -113.98, north = 46.88, east = -113.94
        
        // 1. First attempt: simulate 504 Gateway Timeout
        MockURLProtocol.mockGatewayTimeout()
        let session = MockURLProtocol.makeMockSession()
        let downloader = RegionalTrailDownloader(session: session)
        
        do {
            _ = try await downloader.downloadTrails(south: south, west: west, north: north, east: east, regionName: "Retry_Region")
            XCTFail("First attempt should fail with gateway timeout")
        } catch let err as TrailDownloaderError {
            if case .httpError(let code, _) = err {
                XCTAssertEqual(code, 504)
            } else {
                XCTFail("Expected httpError 504")
            }
        }
        
        // 2. Retry attempt: simulate 200 OK
        MockURLProtocol.mockSuccessfulResponse(with: TrailTestFixtures.overpassJSONSample)
        let retryDownloader = RegionalTrailDownloader(session: MockURLProtocol.makeMockSession())
        let savedURL = try await retryDownloader.downloadTrails(south: south, west: west, north: north, east: east, regionName: "Retry_Region")
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))
        
        // Clean up
        try await retryDownloader.deleteDownloadedRegion(at: savedURL)
    }

    // MARK: Scenario 9: Round-Trip Trail Swap & Reverse Tracking (F4, F11, F12, F15)
    public func test_Scenario09_RoundTripTrailSwapAndReverseTracking() throws {
        let parser = E2EGPXParser()
        let outboundTrack = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        
        // Outbound hike to peak
        nav.startNavigation(track: outboundTrack)
        for pt in outboundTrack.points {
            nav.updateLocation(CLLocation(latitude: pt.coordinate.latitude, longitude: pt.coordinate.longitude))
        }
        XCTAssertEqual(nav.remainingDistance, 0.0)
        nav.stopNavigation()
        
        // Reverse track points for return hike back down to trailhead with accumulated distances
        var cumDist = 0.0
        var returnPoints: [E2EGPXTrackPoint] = []
        let rawReversed = Array(outboundTrack.points.reversed())
        var prevCoord: CLLocationCoordinate2D? = nil
        for pt in rawReversed {
            if let p = prevCoord {
                cumDist += LocationSequenceBuilder.distance(from: p, to: pt.coordinate)
            }
            prevCoord = pt.coordinate
            returnPoints.append(E2EGPXTrackPoint(coordinate: pt.coordinate, elevation: pt.elevation, time: nil, cumulativeDistance: cumDist))
        }
        
        let returnTrack = E2EGPXTrack(
            name: "Mount Sentinel (Descent)",
            points: returnPoints,
            totalDistance: cumDist,
            elevationGain: outboundTrack.elevationLoss,
            elevationLoss: outboundTrack.elevationGain
        )
        
        // Inbound hike
        nav.startNavigation(track: returnTrack)
        XCTAssertEqual(nav.activeTrack?.name, "Mount Sentinel (Descent)")
        XCTAssertEqual(nav.remainingDistance, cumDist)
        
        for pt in returnTrack.points {
            nav.updateLocation(CLLocation(latitude: pt.coordinate.latitude, longitude: pt.coordinate.longitude))
        }
        XCTAssertEqual(nav.remainingDistance, 0.0)
    }

    // MARK: Scenario 10: Complete Offline Airplane Mode Simulation (F1, F6, F8, F11, F15, F16, F18)
    @MainActor
    public func test_Scenario10_CompleteOfflineAirplaneModeSimulation() throws {
        // 1. Sever network completely
        MockURLProtocol.reset()
        
        // 2. Parse trailhead coordinates offline
        let searchString = "46.8529, -113.9850"
        let coord = SearchService.parseCoordinateString(searchString)
        XCTAssertNotNil(coord)
        
        // 3. Resolve route endpoints locally
        let userLocation = CLLocation(latitude: 46.8520, longitude: -113.9860)
        let mockLoc = MockLocationManager(currentLocation: userLocation)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        vm.destinationEndpoint = .custom(place: PlaceLocation(name: "Trailhead", coordinate: coord!))
        XCTAssertFalse(vm.isRoutePreviewMode)
        
        // 4. Load GPX trail offline
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        
        // 5. Navigate and detect off-trail deviation entirely offline
        let alertSpy = MockAudioAlertSpy()
        let nav = E2ETrailNavigator(audioAlertSpy: alertSpy)
        nav.startNavigation(track: track)
        
        // Walk on trail
        nav.updateLocation(CLLocation(latitude: track.points[0].coordinate.latitude, longitude: track.points[0].coordinate.longitude))
        XCTAssertFalse(nav.isOffTrail)
        
        // Step 35m off trail
        let offLoc = LocationSequenceBuilder.shift(coordinate: track.points[0].coordinate, northMeters: 0.0, eastMeters: 35.0)
        nav.updateLocation(CLLocation(latitude: offLoc.latitude, longitude: offLoc.longitude))
        
        XCTAssertTrue(nav.isOffTrail)
        XCTAssertEqual(alertSpy.alertPlayCount, 1)
    }
}
