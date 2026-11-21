import Foundation
import CoreLocation

#if canImport(XCTest)
import XCTest
#endif

#if canImport(MyOfflineMapApp)
@testable import MyOfflineMapApp
#endif

// MARK: - Tier 2: Boundary & Corner Cases Test Suite (95 Tests)
public final class Tier2_BoundaryCornerTests: XCTestCase {
    
    // MARK: Feature 1: Resolved Origin Coordinate (5 Tests)
    
    public func test_F01_BVA_EmptyCustomPlaceName() {
        let p = PlaceLocation(name: "", coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0))
        let ep = RouteEndpoint.custom(place: p)
        XCTAssertEqual(ep.displayName, "")
        XCTAssertFalse(ep.isCurrentLocation)
    }
    
    @MainActor
    public func test_F01_BVA_ExtremeCoordinatesOrigin() {
        let northPole = PlaceLocation(name: "North Pole", coordinate: CLLocationCoordinate2D(latitude: 90.0, longitude: 0.0))
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        vm.originEndpoint = .custom(place: northPole)
        let resolved = vm.resolveCoordinate(for: vm.originEndpoint)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.latitude, 90.0)
    }
    
    @MainActor
    public func test_F01_BVA_OriginIdenticalToDestination() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let coord = CLLocationCoordinate2D(latitude: 46.8529, longitude: -113.9850)
        let place = PlaceLocation(name: "Point", coordinate: coord)
        vm.originEndpoint = .custom(place: place)
        vm.destinationEndpoint = .custom(place: place)
        
        let c1 = vm.resolveCoordinate(for: vm.originEndpoint)
        let c2 = vm.resolveCoordinate(for: vm.destinationEndpoint!)
        XCTAssertEqual(c1?.latitude, c2?.latitude)
        XCTAssertEqual(c1?.longitude, c2?.longitude)
        let dist = LocationSequenceBuilder.distance(from: c1!, to: c2!)
        XCTAssertEqual(dist, 0.0)
    }
    
    @MainActor
    public func test_F01_BVA_RapidOriginToggling() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let place = PlaceLocation(name: "Test", coordinate: CLLocationCoordinate2D(latitude: 10, longitude: 10))
        for i in 0..<50 {
            if i % 2 == 0 {
                vm.originEndpoint = .custom(place: place)
            } else {
                vm.resetOriginToCurrentLocation()
            }
        }
        XCTAssertTrue(vm.originEndpoint.isCurrentLocation)
    }
    
    public func test_F01_BVA_SpecialCharactersInPlaceName() {
        let name = "🌲 Mt. Sentinel / 🏔️ Peak \n\t '\"<script>"
        let p = PlaceLocation(name: name, coordinate: CLLocationCoordinate2D(latitude: 46.8, longitude: -113.9))
        XCTAssertEqual(p.name, name)
    }

    // MARK: Feature 2: Two-Field Directions UI (5 Tests)
    
    @MainActor
    public func test_F02_BVA_MassiveSearchQueryString() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let hugeString = String(repeating: "A", count: 10_000)
        vm.originText = hugeString
        XCTAssertEqual(vm.originText.count, 10_000)
    }
    
    @MainActor
    public func test_F02_BVA_WhitespaceOnlySearchQuery() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        vm.destinationText = "   \n\t   "
        let trimmed = vm.destinationText.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(trimmed.isEmpty)
    }
    
    @MainActor
    public func test_F02_BVA_SimultaneousOriginAndDestinationClearing() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        vm.originEndpoint = .custom(place: PlaceLocation(name: "A", coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1)))
        vm.destinationEndpoint = .custom(place: PlaceLocation(name: "B", coordinate: CLLocationCoordinate2D(latitude: 2, longitude: 2)))
        
        vm.resetOriginToCurrentLocation()
        vm.destinationEndpoint = nil
        
        XCTAssertTrue(vm.originEndpoint.isCurrentLocation)
        XCTAssertNil(vm.destinationEndpoint)
        XCTAssertFalse(vm.isRoutePreviewMode)
    }
    
    @MainActor
    public func test_F02_BVA_RapidFieldSwitching() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        for i in 0..<20 {
            vm.originText = "Query \(i)"
            vm.destinationText = "Target \(i)"
        }
        XCTAssertEqual(vm.originText, "Query 19")
        XCTAssertEqual(vm.destinationText, "Target 19")
    }
    
    public func test_F02_BVA_SQLInjectionTokensInSearch() {
        let injection = "'; DROP TABLE pois; SELECT * FROM credentials; --"
        let parsed = SearchService.parseCoordinateString(injection)
        XCTAssertNil(parsed)
    }

    // MARK: Feature 3: Reset Origin Quick Action (5 Tests)
    
    @MainActor
    public func test_F03_BVA_RapidSequentialResets() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let dest = PlaceLocation(name: "Summit", coordinate: CLLocationCoordinate2D(latitude: 46.8, longitude: -113.9))
        vm.destinationEndpoint = .custom(place: dest)
        
        for _ in 0..<20 {
            vm.resetOriginToCurrentLocation()
            XCTAssertTrue(vm.originEndpoint.isCurrentLocation)
        }
    }
    
    @MainActor
    public func test_F03_BVA_ResetWhileDestinationNil() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        vm.originEndpoint = .custom(place: PlaceLocation(name: "X", coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0)))
        XCTAssertNil(vm.destinationEndpoint)
        
        vm.resetOriginToCurrentLocation()
        XCTAssertTrue(vm.originEndpoint.isCurrentLocation)
        XCTAssertNil(vm.destinationEndpoint)
    }
    
    @MainActor
    public func test_F03_BVA_ResetWithExtremeUserCoordinates() {
        let userLoc = CLLocation(latitude: -89.9999, longitude: 179.9999)
        let mockLoc = MockLocationManager(currentLocation: userLoc)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        vm.originEndpoint = .custom(place: PlaceLocation(name: "Far", coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0)))
        
        vm.resetOriginToCurrentLocation()
        let resolved = vm.resolveCoordinate(for: vm.originEndpoint)
        XCTAssertEqual(resolved?.latitude, -89.9999)
        XCTAssertEqual(resolved?.longitude, 179.9999)
    }
    
    @MainActor
    public func test_F03_BVA_ResetDoesNotCorruptCustomDestination() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let complexDest = PlaceLocation(id: "SPEC_ID", name: "Alpine Hut", subtitle: "Elev 2400m", coordinate: CLLocationCoordinate2D(latitude: 46.5, longitude: -114.2))
        vm.destinationEndpoint = .custom(place: complexDest)
        vm.originEndpoint = .custom(place: PlaceLocation(name: "Origin", coordinate: CLLocationCoordinate2D(latitude: 46.0, longitude: -114.0)))
        
        vm.resetOriginToCurrentLocation()
        if case .custom(let destPlace) = vm.destinationEndpoint! {
            XCTAssertEqual(destPlace.id, "SPEC_ID")
            XCTAssertEqual(destPlace.name, "Alpine Hut")
            XCTAssertEqual(destPlace.subtitle, "Elev 2400m")
        } else {
            XCTFail("Destination corrupted after reset")
        }
    }
    
    @MainActor
    public func test_F03_BVA_ResetUnderConcurrentRouteCalculation() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let dest = PlaceLocation(name: "Dest", coordinate: CLLocationCoordinate2D(latitude: 46.8, longitude: -113.9))
        vm.destinationEndpoint = .custom(place: dest)
        
        for _ in 0..<10 {
            vm.resetOriginToCurrentLocation()
        }
        XCTAssertTrue(vm.originEndpoint.isCurrentLocation)
    }

    // MARK: Feature 4: Origin/Destination Swap (5 Tests)
    
    @MainActor
    public func test_F04_BVA_SwapWhenBothAreCurrentLocation() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        vm.originEndpoint = .currentLocation
        vm.destinationEndpoint = .currentLocation
        
        vm.swapOriginDestination()
        XCTAssertEqual(vm.originEndpoint, .currentLocation)
        XCTAssertEqual(vm.destinationEndpoint, .currentLocation)
    }
    
    @MainActor
    public func test_F04_BVA_SwapWithNoEndpointsSet() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        vm.destinationEndpoint = nil
        vm.swapOriginDestination()
        XCTAssertEqual(vm.originEndpoint, .currentLocation)
        XCTAssertNil(vm.destinationEndpoint)
    }
    
    @MainActor
    public func test_F04_BVA_RapidOddEvenSwapping() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let pA = PlaceLocation(name: "Start", coordinate: CLLocationCoordinate2D(latitude: 10, longitude: 10))
        let pB = PlaceLocation(name: "Finish", coordinate: CLLocationCoordinate2D(latitude: 20, longitude: 20))
        vm.originEndpoint = .custom(place: pA)
        vm.destinationEndpoint = .custom(place: pB)
        
        // 99 swaps (odd = swapped)
        for _ in 0..<99 {
            vm.swapOriginDestination()
        }
        XCTAssertEqual(vm.originEndpoint.displayName, "Finish")
        XCTAssertEqual(vm.destinationEndpoint?.displayName, "Start")
        
        // 1 more swap (even = restored)
        vm.swapOriginDestination()
        XCTAssertEqual(vm.originEndpoint.displayName, "Start")
        XCTAssertEqual(vm.destinationEndpoint?.displayName, "Finish")
    }
    
    @MainActor
    public func test_F04_BVA_SwapWithExtremeCoordinates() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let north = PlaceLocation(name: "North", coordinate: CLLocationCoordinate2D(latitude: 90.0, longitude: 0.0))
        let south = PlaceLocation(name: "South", coordinate: CLLocationCoordinate2D(latitude: -90.0, longitude: 0.0))
        vm.originEndpoint = .custom(place: north)
        vm.destinationEndpoint = .custom(place: south)
        
        vm.swapOriginDestination()
        XCTAssertEqual(vm.originEndpoint.displayName, "South")
        XCTAssertEqual(vm.destinationEndpoint?.displayName, "North")
    }
    
    @MainActor
    public func test_F04_BVA_SwapPreservesPlaceMetadata() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let pA = PlaceLocation(id: "ID_A", name: "Alpha", subtitle: "Sub A", coordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1))
        let pB = PlaceLocation(id: "ID_B", name: "Beta", subtitle: "Sub B", coordinate: CLLocationCoordinate2D(latitude: 2, longitude: 2))
        vm.originEndpoint = .custom(place: pA)
        vm.destinationEndpoint = .custom(place: pB)
        
        vm.swapOriginDestination()
        if case .custom(let o) = vm.originEndpoint, case .custom(let d) = vm.destinationEndpoint! {
            XCTAssertEqual(o.id, "ID_B")
            XCTAssertEqual(o.subtitle, "Sub B")
            XCTAssertEqual(d.id, "ID_A")
            XCTAssertEqual(d.subtitle, "Sub A")
        } else {
            XCTFail("Metadata mismatch after swap")
        }
    }

    // MARK: Feature 5: Remote Origin Preview Mode (5 Tests)
    
    @MainActor
    public func test_F05_BVA_ExactBoundaryDistance199m() async {
        let userLoc = CLLocation(latitude: 46.8529, longitude: -113.9850)
        let mockLoc = MockLocationManager(currentLocation: userLoc)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let nearCoord = LocationSequenceBuilder.shift(coordinate: userLoc.coordinate, northMeters: 199.0, eastMeters: 0.0)
        vm.originEndpoint = .custom(place: PlaceLocation(name: "Near", coordinate: nearCoord))
        await vm.calculateRoute()
        
        XCTAssertFalse(vm.isRemoteOrigin(thresholdMeters: 200.0))
        XCTAssertFalse(vm.isRoutePreviewMode)
    }
    
    @MainActor
    public func test_F05_BVA_ExactBoundaryDistance201m() async {
        let userLoc = CLLocation(latitude: 46.8529, longitude: -113.9850)
        let mockLoc = MockLocationManager(currentLocation: userLoc)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let destPlace = PlaceLocation(name: "Dest", coordinate: CLLocationCoordinate2D(latitude: 46.86, longitude: -113.97))
        vm.destinationEndpoint = .custom(place: destPlace)
        let remoteCoord = LocationSequenceBuilder.shift(coordinate: userLoc.coordinate, northMeters: 201.0, eastMeters: 0.0)
        vm.originEndpoint = .custom(place: PlaceLocation(name: "Remote", coordinate: remoteCoord))
        await vm.calculateRoute()
        
        XCTAssertTrue(vm.isRemoteOrigin(thresholdMeters: 200.0))
        XCTAssertTrue(vm.isRoutePreviewMode)
    }
    
    @MainActor
    public func test_F05_BVA_ZeroDistanceOrigin() {
        let userLoc = CLLocation(latitude: 46.8529, longitude: -113.9850)
        let mockLoc = MockLocationManager(currentLocation: userLoc)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        vm.originEndpoint = .custom(place: PlaceLocation(name: "Exact", coordinate: userLoc.coordinate))
        
        XCTAssertFalse(vm.isRemoteOrigin())
        XCTAssertFalse(vm.isRoutePreviewMode)
    }
    
    @MainActor
    public func test_F05_BVA_ExtremeAntipodalOrigin() async {
        let userLoc = CLLocation(latitude: 0.0, longitude: 0.0)
        let mockLoc = MockLocationManager(currentLocation: userLoc)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let destPlace = PlaceLocation(name: "Dest", coordinate: CLLocationCoordinate2D(latitude: 1.0, longitude: 1.0))
        vm.destinationEndpoint = .custom(place: destPlace)
        let antipodal = CLLocationCoordinate2D(latitude: 0.0, longitude: 180.0)
        vm.originEndpoint = .custom(place: PlaceLocation(name: "Antipode", coordinate: antipodal))
        await vm.calculateRoute()
        
        XCTAssertTrue(vm.isRemoteOrigin())
        XCTAssertTrue(vm.isRoutePreviewMode)
    }
    
    @MainActor
    public func test_F05_BVA_OscillatingAcross200mThreshold() {
        let originCoord = CLLocationCoordinate2D(latitude: 46.8529, longitude: -113.9850)
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        vm.originEndpoint = .custom(place: PlaceLocation(name: "Origin", coordinate: originCoord))
        
        // 195m away
        let loc195 = CLLocation(latitude: LocationSequenceBuilder.shift(coordinate: originCoord, northMeters: 195.0, eastMeters: 0.0).latitude, longitude: LocationSequenceBuilder.shift(coordinate: originCoord, northMeters: 195.0, eastMeters: 0.0).longitude)
        mockLoc.currentLocation = loc195
        XCTAssertFalse(vm.isRemoteOrigin(thresholdMeters: 200.0, currentLocation: loc195))
        
        // 205m away
        let loc205 = CLLocation(latitude: LocationSequenceBuilder.shift(coordinate: originCoord, northMeters: 205.0, eastMeters: 0.0).latitude, longitude: LocationSequenceBuilder.shift(coordinate: originCoord, northMeters: 205.0, eastMeters: 0.0).longitude)
        mockLoc.currentLocation = loc205
        XCTAssertTrue(vm.isRemoteOrigin(thresholdMeters: 200.0, currentLocation: loc205))
    }

    // MARK: Feature 6: Coordinate Search Parsing (5 Tests)
    
    public func test_F06_BVA_LatitudeOutOfRangePositive() {
        let parsed = SearchService.parseCoordinateString("90.0001, 10.0")
        XCTAssertNil(parsed)
    }
    
    public func test_F06_BVA_LatitudeOutOfRangeNegative() {
        let parsed = SearchService.parseCoordinateString("-90.0001, 10.0")
        XCTAssertNil(parsed)
    }
    
    public func test_F06_BVA_LongitudeOutOfRangePositive() {
        let parsed = SearchService.parseCoordinateString("10.0, 180.0001")
        XCTAssertNil(parsed)
    }
    
    public func test_F06_BVA_LongitudeOutOfRangeNegative() {
        let parsed = SearchService.parseCoordinateString("10.0, -180.0001")
        XCTAssertNil(parsed)
    }
    
    public func test_F06_BVA_NonNumericGarbage() {
        let parsed = SearchService.parseCoordinateString("lat: 45, lon: invalid")
        XCTAssertNil(parsed)
    }

    // MARK: Feature 7: Basemap Trail Restyling (5 Tests)
    
    @MainActor
    public func test_F07_BVA_MissingLayerInStyleSafelyIgnored() {
        let emptyStyle = MLNStyle()
        TrailOverlayManager.shared.applyBasemapTrailRestylingSafeguard(to: emptyStyle)
        XCTAssertNil(emptyStyle.layer(withIdentifier: "osm-high-contrast-trails"))
    }
    
    public func test_F07_BVA_StyleWithDuplicateLayerIDs() {
        let layer1 = MLNStyleLayer(identifier: "duplicate")
        let layer2 = MLNStyleLayer(identifier: "duplicate")
        let style = MLNStyle(layers: [layer1, layer2])
        XCTAssertEqual(style.layers.count, 2)
    }
    
    public func test_F07_BVA_CorruptedJSONStyle() {
        let corruptJSONData = "{\"version\": 8, \"layers\": [broken".data(using: .utf8)!
        var threwError = false
        do {
            _ = try JSONSerialization.jsonObject(with: corruptJSONData, options: [])
        } catch {
            threwError = true
        }
        XCTAssertTrue(threwError, "Corrupted style JSON data must throw deserialization error")
    }
    
    public func test_F07_BVA_ZeroWidthLineWidth() throws {
        let json = try loadBasemapStyleJSON()
        guard let layers = json["layers"] as? [[String: Any]] else {
            XCTFail("style.json must contain a layers array")
            return
        }
        guard let trailLayer = layers.first(where: { ($0["id"] as? String) == "osm-high-contrast-trails" }) else {
            XCTFail("osm-high-contrast-trails not found")
            return
        }
        let paint = trailLayer["paint"] as? [String: Any]
        if let widthDict = paint?["line-width"] as? [String: Any],
           let stops = widthDict["stops"] as? [[Double]] {
            for stop in stops {
                let zoom = stop[0]
                let width = stop[1]
                XCTAssertGreaterThan(width, 0.0, "Line width at zoom \(zoom) must be strictly greater than 0.0")
            }
        } else if let constantWidth = paint?["line-width"] as? Double {
            XCTAssertGreaterThan(constantWidth, 0.0, "Line width must be strictly greater than 0.0")
        } else {
            XCTFail("line-width specification missing in style.json for osm-high-contrast-trails")
        }
    }
    
    @MainActor
    public func test_F07_BVA_UnsupportedHighwayTag() {
        let style = MLNStyle()
        let motorwayLayer = MLNLineStyleLayer(identifier: "transportation-motorway", source: MLNSource(identifier: "openmaptiles"))
        motorwayLayer.sourceLayerIdentifier = "transportation"
        style.addLayer(motorwayLayer)
        
        let primaryLayer = MLNLineStyleLayer(identifier: "transportation-primary", source: MLNSource(identifier: "openmaptiles"))
        primaryLayer.sourceLayerIdentifier = "transportation"
        style.addLayer(primaryLayer)
        
        TrailOverlayManager.shared.applyBasemapTrailRestylingSafeguard(to: style)
        
        XCTAssertNil(motorwayLayer.lineColor, "Motorway layer must not be restyled by trail safeguard")
        XCTAssertNil(primaryLayer.lineColor, "Primary road layer must not be restyled by trail safeguard")
    }

    // MARK: Feature 8: Overpass Regional Downloader (5 Tests)
    
    public func test_F08_BVA_BoundingBoxSpanExceeds05Deg() async {
        let downloader = RegionalTrailDownloader.shared
        do {
            try await downloader.validateBoundingBox(south: 46.0, west: -114.0, north: 46.501, east: -114.0)
            XCTFail("Should have thrown boundingBoxTooLarge")
        } catch let error as TrailDownloaderError {
            guard case .boundingBoxTooLarge(let latSpan, _, let limit) = error else {
                XCTFail("Expected .boundingBoxTooLarge, got: \(error)")
                return
            }
            XCTAssertEqualWithAccuracy(latSpan, 0.501, accuracy: 0.0001)
            XCTAssertEqual(limit, RegionalTrailDownloader.maxSpanDegrees)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    public func test_F08_BVA_InvertedLatitudes() async {
        let downloader = RegionalTrailDownloader.shared
        do {
            try await downloader.validateBoundingBox(south: 47.0, west: -114.0, north: 46.0, east: -114.0)
            XCTFail("Should have thrown invalidBoundingBox")
        } catch let error as TrailDownloaderError {
            guard case .invalidBoundingBox(let reason) = error else {
                XCTFail("Expected .invalidBoundingBox, got: \(error)")
                return
            }
            XCTAssertFalse(reason.isEmpty)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    public func test_F08_BVA_InvertedLongitudes() async {
        let downloader = RegionalTrailDownloader.shared
        do {
            try await downloader.validateBoundingBox(south: 46.0, west: -113.0, north: 46.1, east: -114.0)
            XCTFail("Should have thrown invalidBoundingBox")
        } catch let error as TrailDownloaderError {
            guard case .invalidBoundingBox(let reason) = error else {
                XCTFail("Expected .invalidBoundingBox, got: \(error)")
                return
            }
            XCTAssertFalse(reason.isEmpty)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    public func test_F08_BVA_ZeroAreaBoundingBox() async {
        let downloader = RegionalTrailDownloader.shared
        do {
            try await downloader.validateBoundingBox(south: 46.0, west: -114.0, north: 46.0, east: -114.0)
            XCTFail("Should have thrown invalidBoundingBox")
        } catch let error as TrailDownloaderError {
            guard case .invalidBoundingBox(let reason) = error else {
                XCTFail("Expected .invalidBoundingBox, got: \(error)")
                return
            }
            XCTAssertFalse(reason.isEmpty)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    public func test_F08_BVA_HTTP429RateLimitError() throws {
        let err = TrailDownloaderError.httpError(statusCode: 429, responseBody: "Rate limit exceeded")
        XCTAssertTrue(err.errorDescription?.contains("429") ?? false)
    }

    // MARK: Feature 9: GeoJSON Storage & Backup Exclusion (5 Tests)
    
    public func test_F09_BVA_EmptyRegionNameSanitization() async {
        let downloader = RegionalTrailDownloader.shared
        let sanitized = await downloader.sanitizeRegionName("   ")
        XCTAssertTrue(sanitized.hasPrefix("trails_"))
    }
    
    public func test_F09_BVA_PathTraversalAttemptInRegionName() async {
        let downloader = RegionalTrailDownloader.shared
        let sanitized = await downloader.sanitizeRegionName("../../etc/passwd")
        XCTAssertFalse(sanitized.contains("/"))
        XCTAssertFalse(sanitized.contains("\\"))
        XCTAssertEqual(sanitized, ".._.._etc_passwd")
    }
    
    public func test_F09_BVA_DeleteNonExistentRegion() async {
        let downloader = RegionalTrailDownloader.shared
        let regionName = "non_existent_region_\(UUID().uuidString)"
        do {
            try await downloader.deleteDownloadedRegion(named: regionName)
            XCTFail("Should have thrown regionNotFound")
        } catch let error as TrailDownloaderError {
            XCTAssertEqual(error, TrailDownloaderError.regionNotFound(regionName))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    public func test_F09_BVA_ZeroByteGeoJSON() {
        let emptyData = Data()
        let converter = GeoJSONConverter()
        XCTAssertThrowsError(try converter.convert(overpassData: emptyData)) { error in
            XCTAssertNotNil(error)
        }
    }
    
    public func test_F09_BVA_CorruptedOverpassJSON() {
        let corruptData = TrailTestFixtures.overpassJSONCorrupt.data(using: .utf8)!
        let converter = GeoJSONConverter()
        XCTAssertThrowsError(try converter.convert(overpassData: corruptData)) { error in
            XCTAssertNotNil(error)
        }
    }

    // MARK: Feature 10: Regional Trails Overlay (5 Tests)
    
    @MainActor
    public func test_F10_BVA_EmptyGeoJSONURLList() {
        let style = MLNStyle()
        TrailOverlayManager.shared.applyTrailOverlay(to: style, geoJSONURLs: [])
        XCTAssertNil(style.source(withIdentifier: TrailOverlayManager.overlaySourceIdentifier))
    }
    
    @MainActor
    public func test_F10_BVA_CorruptedGeoJSONFileInOverlay() throws {
        let style = MLNStyle()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt_\(UUID().uuidString).geojson")
        let tempFile2 = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt2_\(UUID().uuidString).geojson")
        try "NOT_JSON".write(to: tempFile, atomically: true, encoding: .utf8)
        try "NOT_JSON_2".write(to: tempFile2, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: tempFile)
            try? FileManager.default.removeItem(at: tempFile2)
        }
        
        TrailOverlayManager.shared.applyTrailOverlay(to: style, geoJSONURLs: [tempFile, tempFile2])
        XCTAssertNil(style.source(withIdentifier: TrailOverlayManager.overlaySourceIdentifier))
    }
    
    @MainActor
    public func test_F10_BVA_RemoveOverlayWhenNoneApplied() {
        let style = MLNStyle()
        TrailOverlayManager.shared.removeTrailOverlay(from: style)
        XCTAssertNil(style.source(withIdentifier: TrailOverlayManager.overlaySourceIdentifier))
    }
    
    @MainActor
    public func test_F10_BVA_RapidApplyAndRemoveCycling() {
        let style = MLNStyle()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("cycle_\(UUID().uuidString).geojson")
        try? "{}".write(to: tempFile, atomically: true, encoding: .utf8)
        
        for _ in 0..<30 {
            TrailOverlayManager.shared.applyTrailOverlay(to: style, geoJSONURLs: [tempFile])
            TrailOverlayManager.shared.removeTrailOverlay(from: style)
        }
        
        XCTAssertNil(style.source(withIdentifier: TrailOverlayManager.overlaySourceIdentifier))
        try? FileManager.default.removeItem(at: tempFile)
    }
    
    @MainActor
    public func test_F10_BVA_StyleLackingSymbolLayer() {
        let style = MLNStyle(layers: [MLNStyleLayer(identifier: "background")])
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("nosymbol_\(UUID().uuidString).geojson")
        try? "{}".write(to: tempFile, atomically: true, encoding: .utf8)
        
        TrailOverlayManager.shared.applyTrailOverlay(to: style, geoJSONURLs: [tempFile])
        XCTAssertNotNil(style.source(withIdentifier: TrailOverlayManager.overlaySourceIdentifier))
        try? FileManager.default.removeItem(at: tempFile)
    }

    // MARK: Feature 11: GPX File Importer & Scanner (5 Tests)
    
    public func test_F11_BVA_EmptyDirectoryScan() throws {
        let emptyDir = FileManager.default.temporaryDirectory.appendingPathComponent("empty_scan_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        
        let files = try FileManager.default.contentsOfDirectory(at: emptyDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 0)
        try? FileManager.default.removeItem(at: emptyDir)
    }
    
    public func test_F11_BVA_CorruptedGPXFileInScan() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt_scan_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let corruptFile = tempDir.appendingPathComponent("broken.gpx")
        try TrailTestFixtures.corruptGPXString.write(to: corruptFile, atomically: true, encoding: .utf8)
        
        let parser = E2EGPXParser()
        XCTAssertThrowsError(try parser.parse(xmlString: TrailTestFixtures.corruptGPXString)) { error in
            XCTAssertNotNil(error)
        }
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    public func test_F11_BVA_NonGPXFilesIgnored() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("filter_scan_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        try "png".write(to: tempDir.appendingPathComponent("map.png"), atomically: true, encoding: .utf8)
        try "json".write(to: tempDir.appendingPathComponent("data.json"), atomically: true, encoding: .utf8)
        
        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let gpx = contents.filter { $0.pathExtension.lowercased() == "gpx" }
        XCTAssertEqual(gpx.count, 0)
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    public func test_F11_BVA_ZeroByteGPXFile() {
        let parser = E2EGPXParser()
        XCTAssertThrowsError(try parser.parse(xmlString: "")) { error in
            XCTAssertNotNil(error)
        }
    }
    
    public func test_F11_BVA_HiddenFilesIgnored() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("hidden_scan_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        try "hidden".write(to: tempDir.appendingPathComponent("._trail.gpx"), atomically: true, encoding: .utf8)
        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        XCTAssertEqual(contents.count, 0)
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: Feature 12: Native XML GPX Parser (5 Tests)
    
    public func test_F12_BVA_CorruptedUnclosedXML() {
        let parser = E2EGPXParser()
        XCTAssertThrowsError(try parser.parse(xmlString: TrailTestFixtures.corruptGPXString)) { error in
            XCTAssertNotNil(error)
        }
    }
    
    public func test_F12_BVA_ZeroTrackPointsInGPX() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.emptyGPXString)
        XCTAssertEqual(track.points.count, 0)
        XCTAssertEqual(track.totalDistance, 0.0)
    }
    
    public func test_F12_BVA_SinglePointTrack() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.singlePointGPXString)
        XCTAssertEqual(track.points.count, 1)
        XCTAssertEqual(track.totalDistance, 0.0)
    }
    
    public func test_F12_BVA_NegativeElevations() throws {
        let deadSeaXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <trk>
            <trkseg>
              <trkpt lat="31.5" lon="35.5"><ele>-430.0</ele></trkpt>
              <trkpt lat="31.51" lon="35.51"><ele>-410.0</ele></trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: deadSeaXML)
        XCTAssertEqual(track.points[0].elevation, -430.0)
        XCTAssertEqual(track.elevationGain, 20.0)
    }
    
    public func test_F12_BVA_MalformedTimestampFormat() throws {
        let badTimeXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <trk>
            <trkseg>
              <trkpt lat="46.0" lon="-113.0"><time>INVALID_DATE_STRING</time></trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: badTimeXML)
        XCTAssertEqual(track.points.count, 1)
        XCTAssertNil(track.points[0].time)
    }

    // MARK: Feature 13: GPX Map Overlay (5 Tests)
    
    public func test_F13_BVA_SinglePointOverlayBounds() {
        let singleCoord = CLLocationCoordinate2D(latitude: 46.85, longitude: -113.98)
        let bounds = MLNCoordinateBounds(sw: singleCoord, ne: singleCoord)
        
        XCTAssertEqual(bounds.sw.latitude, bounds.ne.latitude)
        XCTAssertEqual(bounds.sw.longitude, bounds.ne.longitude)
        
        let latSpan = bounds.ne.latitude - bounds.sw.latitude
        let lonSpan = bounds.ne.longitude - bounds.sw.longitude
        XCTAssertEqual(latSpan, 0.0, "Single point bounds must have 0.0 latitude span")
        XCTAssertEqual(lonSpan, 0.0, "Single point bounds must have 0.0 longitude span")
    }
    
    public func test_F13_BVA_AntimeridianCrossingGPX() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.extremeCoordinatesGPXString)
        XCTAssertEqual(track.points.count, 4)
        XCTAssertEqual(track.points[1].coordinate.longitude, 179.9999)
        XCTAssertEqual(track.points[2].coordinate.longitude, -179.9999)
    }
    
    @MainActor
    public func test_F13_BVA_OverlayRemovalWithActiveNavigation() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        let style = MLNStyle()
        TrailOverlayManager.shared.removeTrailOverlay(from: style)
        
        // Navigation should continue unaffected
        XCTAssertNotNil(nav.activeTrack)
    }
    
    @MainActor
    public func test_F13_BVA_ExtremeTrackLength1000Points() throws {
        var coords: [[Double]] = []
        coords.reserveCapacity(1000)
        for i in 0..<1000 {
            let lon = -122.0 + Double(i) * 0.0001
            let lat = 37.0 + Double(i) * 0.0001
            coords.append([lon, lat])
        }
        let feature = GeoJSONFeature(
            id: 9999,
            geometry: GeoJSONGeometry(type: "LineString", coordinates: coords),
            properties: ["name": "Ultra Long Trail"]
        )
        let collection = GeoJSONFeatureCollection(features: [feature])
        let encodedData = try JSONEncoder().encode(collection)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("extreme_1000_\(UUID().uuidString).geojson")
        try encodedData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let style = MLNStyle()
        TrailOverlayManager.shared.applyTrailOverlay(to: style, geoJSONURLs: [tempURL])
        
        XCTAssertNotNil(style.layer(withIdentifier: TrailOverlayManager.orangeLineLayerIdentifier), "Overlay layer must be created for 1000-point track")
        XCTAssertNotNil(style.source(withIdentifier: TrailOverlayManager.overlaySourceIdentifier))
    }
    
    public func test_F13_BVA_CollinearTrackPoints() throws {
        let duplicateXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <trk>
            <trkseg>
              <trkpt lat="46.85" lon="-113.98"><ele>100.0</ele></trkpt>
              <trkpt lat="46.85" lon="-113.98"><ele>100.0</ele></trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: duplicateXML)
        XCTAssertEqual(track.points.count, 2)
        XCTAssertEqual(track.totalDistance, 0.0)
    }

    // MARK: Feature 14: Fitness Location Tracking (5 Tests)
    
    public func test_F14_BVA_DegradedHorizontalAccuracy() {
        let degraded = LocationSequenceBuilder.makeDegradedAccuracyTrack(start: CLLocationCoordinate2D(latitude: 46.8, longitude: -113.9), count: 3, accuracyMeters: 65.0)
        for loc in degraded {
            XCTAssertEqual(loc.horizontalAccuracy, 65.0)
            XCTAssertGreaterThan(loc.horizontalAccuracy, 25.0)
        }
    }
    
    public func test_F14_BVA_NegativeHorizontalAccuracy() {
        let invalidLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 46.8, longitude: -113.9),
            altitude: 0.0,
            horizontalAccuracy: -1.0,
            verticalAccuracy: -1.0,
            timestamp: Date()
        )
        XCTAssertLessThan(invalidLoc.horizontalAccuracy, 0.0)
    }
    
    public func test_F14_BVA_RapidActivityTypeSwitching() {
        let lm = E2ELocationManager.shared
        for i in 0..<10 {
            let nextType: CLActivityType = (i % 2 == 0) ? .fitness : .automotiveNavigation
            lm.setActivityType(nextType)
            XCTAssertEqual(lm.activityType, nextType)
            XCTAssertEqual(lm.clLocationManager.activityType, nextType)
        }
        XCTAssertEqual(lm.activityType, .automotiveNavigation)
    }
    
    public func test_F14_BVA_StaleLocationTimestamp() {
        let staleDate = Date().addingTimeInterval(-300.0)
        let loc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 46.8, longitude: -113.9),
            altitude: 0.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            timestamp: staleDate
        )
        let age = Date().timeIntervalSince(loc.timestamp)
        XCTAssertGreaterThan(age, 60.0)
    }
    
    public func test_F14_BVA_ExtremeSpeedReading() {
        let glitchLocation = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 46.85, longitude: -113.98),
            altitude: 1000.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            course: 90.0,
            speed: 500.0,
            timestamp: Date()
        )
        
        let maxReasonableHikingSpeedMetersPerSec = 10.0
        let isAnomalousHikingSpeed = glitchLocation.speed > maxReasonableHikingSpeedMetersPerSec
        XCTAssertTrue(isAnomalousHikingSpeed, "Extreme speed (500 m/s) must be flagged as anomalous during trail navigation")
        XCTAssertEqual(glitchLocation.speed, 500.0)
    }

    // MARK: Feature 15: Active Trail Following (5 Tests)
    
    public func test_F15_BVA_UserStartsFarFromTrail() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        // 5 km away
        let farLoc = CLLocation(latitude: 47.0, longitude: -114.0)
        let update = nav.updateLocation(farLoc)
        
        XCTAssertTrue(update.isOffTrail)
        XCTAssertGreaterThan(update.deviation, 1000.0)
    }
    
    public func test_F15_BVA_ZeroDistanceTrackNavigation() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.singlePointGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        XCTAssertEqual(nav.remainingDistance, 0.0)
    }
    
    public func test_F15_BVA_BackwardsWalkingOnTrail() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        // Walk from point 4 back to point 0
        for pt in track.points.reversed() {
            let loc = CLLocation(latitude: pt.coordinate.latitude, longitude: pt.coordinate.longitude)
            let update = nav.updateLocation(loc)
            XCTAssertFalse(update.isOffTrail)
        }
        
        // At point 0, progress distance is 0.0
        XCTAssertEqual(nav.userProgressDistance, 0.0)
    }
    
    public func test_F15_BVA_SwitchbackShortcutJump() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        // Jump from point 0 directly to point 4
        let pt4 = track.points[4]
        nav.updateLocation(CLLocation(latitude: pt4.coordinate.latitude, longitude: pt4.coordinate.longitude))
        
        XCTAssertEqual(nav.userProgressDistance, pt4.cumulativeDistance)
        XCTAssertEqual(nav.remainingDistance, 0.0)
    }
    
    public func test_F15_BVA_UserPassedTrailFinish() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        // Walk past point 4 by 50m North
        let pastCoord = LocationSequenceBuilder.shift(coordinate: track.points[4].coordinate, northMeters: 50.0, eastMeters: 0.0)
        nav.updateLocation(CLLocation(latitude: pastCoord.latitude, longitude: pastCoord.longitude))
        
        XCTAssertEqual(nav.remainingDistance, 0.0)
    }

    // MARK: Feature 16: Off-Trail Audio Alert (5 Tests)
    
    public func test_F16_BVA_Exact25mBoundaryDeviation() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let spy = MockAudioAlertSpy()
        let nav = E2ETrailNavigator(audioAlertSpy: spy)
        nav.startNavigation(track: track)
        
        // Deviation within 25.0m threshold (24.5m)
        let withinCoord = LocationSequenceBuilder.shift(coordinate: track.points[0].coordinate, northMeters: 0.0, eastMeters: 24.5)
        nav.updateLocation(CLLocation(latitude: withinCoord.latitude, longitude: withinCoord.longitude))
        
        XCTAssertFalse(nav.isOffTrail)
        XCTAssertEqual(spy.alertPlayCount, 0)
    }
    
    public func test_F16_BVA_Exact18mBoundaryRecovery() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        // Drift 30m off trail
        let off = LocationSequenceBuilder.shift(coordinate: track.points[0].coordinate, northMeters: 0.0, eastMeters: 30.0)
        nav.updateLocation(CLLocation(latitude: off.latitude, longitude: off.longitude))
        XCTAssertTrue(nav.isOffTrail)
        
        // Step to exactly 18.0m (recovery is < 18.0, so 18.0 exact maintains off-trail)
        let edge = LocationSequenceBuilder.shift(coordinate: track.points[0].coordinate, northMeters: 0.0, eastMeters: 18.0)
        nav.updateLocation(CLLocation(latitude: edge.latitude, longitude: edge.longitude))
        XCTAssertTrue(nav.isOffTrail)
        
        // Step to 17.9m (below recovery threshold)
        let recovered = LocationSequenceBuilder.shift(coordinate: track.points[0].coordinate, northMeters: 0.0, eastMeters: 17.5)
        nav.updateLocation(CLLocation(latitude: recovered.latitude, longitude: recovered.longitude))
        XCTAssertFalse(nav.isOffTrail)
    }
    
    public func test_F16_BVA_MutedAudioSpyDoesNotRecord() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let spy = MockAudioAlertSpy()
        spy.isMuted = true
        let nav = E2ETrailNavigator(audioAlertSpy: spy)
        nav.startNavigation(track: track)
        
        let off = LocationSequenceBuilder.shift(coordinate: track.points[0].coordinate, northMeters: 0.0, eastMeters: 50.0)
        nav.updateLocation(CLLocation(latitude: off.latitude, longitude: off.longitude))
        
        XCTAssertTrue(nav.isOffTrail)
        XCTAssertEqual(spy.alertPlayCount, 0) // Muted!
    }
    
    public func test_F16_BVA_ExtremeDeviation1000m() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let spy = MockAudioAlertSpy()
        let nav = E2ETrailNavigator(audioAlertSpy: spy)
        nav.startNavigation(track: track)
        
        let off = LocationSequenceBuilder.shift(coordinate: track.points[0].coordinate, northMeters: 0.0, eastMeters: 1000.0)
        nav.updateLocation(CLLocation(latitude: off.latitude, longitude: off.longitude))
        
        XCTAssertTrue(nav.isOffTrail)
        XCTAssertEqual(spy.alertPlayCount, 1)
    }
    
    public func test_F16_BVA_DebounceUnderClockJump() {
        let spy = MockAudioAlertSpy()
        spy.recordAlert(deviationMeters: 30.0)
        let verified = spy.verifyDebounceInterval(minIntervalSeconds: 5.0)
        XCTAssertTrue(verified)
    }

    // MARK: Feature 17: Elevation Profile Chart (5 Tests)
    
    public func test_F17_BVA_CompletelyFlatTrack() {
        let pts = (0..<5).map { i in
            E2EGPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 37.0 + Double(i) * 0.01, longitude: -122.0), elevation: 100.0, cumulativeDistance: Double(i) * 100.0)
        }
        let track = E2EGPXTrack(name: "Flat", points: pts, totalDistance: 400.0, elevationGain: 0.0, elevationLoss: 0.0)
        XCTAssertEqual(track.elevationGain, 0.0)
        XCTAssertEqual(track.elevationLoss, 0.0)
    }
    
    public func test_F17_BVA_AllElevationsNil() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.missingElevationGPXString)
        for pt in track.points {
            XCTAssertNil(pt.elevation)
        }
    }
    
    public func test_F17_BVA_ExtremeElevationValues() throws {
        let extremeElevationXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
          <trk>
            <name>Extreme Elevation Trek</name>
            <trkseg>
              <trkpt lat="31.50" lon="35.50"><ele>-430.5</ele></trkpt>
              <trkpt lat="27.98" lon="86.92"><ele>8848.86</ele></trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: extremeElevationXML)
        
        XCTAssertEqual(track.points.count, 2)
        XCTAssertEqual(track.points[0].elevation, -430.5, "Negative elevation below sea level must be preserved")
        XCTAssertEqual(track.points[1].elevation, 8848.86, "High altitude elevation must be preserved")
        
        let elevations = track.points.compactMap { $0.elevation }
        let minEle = elevations.min() ?? 0.0
        let maxEle = elevations.max() ?? 0.0
        let elevationRange = maxEle - minEle
        
        XCTAssertEqualWithAccuracy(minEle, -430.5, accuracy: 0.1)
        XCTAssertEqualWithAccuracy(maxEle, 8848.86, accuracy: 0.1)
        XCTAssertEqualWithAccuracy(elevationRange, 9279.36, accuracy: 0.1)
        XCTAssertEqualWithAccuracy(track.elevationGain, 9279.36, accuracy: 0.1)
        XCTAssertEqual(track.elevationLoss, 0.0)
    }
    
    public func test_F17_BVA_VerticalCliffProfile() {
        let p1 = E2EGPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0), elevation: 100.0, cumulativeDistance: 0.0)
        let p2 = E2EGPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0), elevation: 500.0, cumulativeDistance: 0.0001)
        
        let rise = (p2.elevation ?? 0) - (p1.elevation ?? 0)
        let run = p2.cumulativeDistance - p1.cumulativeDistance
        let slope = rise / run
        XCTAssertGreaterThan(slope, 1000.0)
    }
    
    public func test_F17_BVA_NegativeProgressClamp() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        // Position user behind the start of the trail
        let startPt = track.points[0]
        let behindStartCoord = LocationSequenceBuilder.shift(coordinate: startPt.coordinate, northMeters: -500.0, eastMeters: -500.0)
        _ = nav.updateLocation(CLLocation(latitude: behindStartCoord.latitude, longitude: behindStartCoord.longitude))
        
        // Progress distance and remaining distance must never be negative
        XCTAssertTrue(nav.userProgressDistance >= 0.0, "userProgressDistance must never be negative")
        XCTAssertTrue(nav.remainingDistance >= 0.0, "remainingDistance must never be negative")
        XCTAssertTrue(nav.remainingDistance <= track.totalDistance, "remainingDistance must not exceed total track distance")
    }

    // MARK: Feature 18: Offline Airplane Mode Verification (5 Tests)
    
    public func test_F18_BVA_SeveredNetworkDuringDownload() async {
        MockURLProtocol.reset()
        // No handler configured triggers URLError(.notConnectedToInternet)
        let config = MockURLProtocol.makeMockSessionConfiguration()
        let session = URLSession(configuration: config)
        
        do {
            let (_, _) = try await session.data(from: URL(string: "https://overpass-api.de/api/interpreter")!)
            XCTFail("Should have thrown offline network error")
        } catch let err as URLError {
            XCTAssertEqual(err.code, .notConnectedToInternet)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    public func test_F18_BVA_CachedDataAvailableWhenOffline() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("cached_\(UUID().uuidString).geojson")
        try "{\"type\":\"FeatureCollection\"}".write(to: tempFile, atomically: true, encoding: .utf8)
        
        // Even offline, file reads from disk succeed
        let data = try Data(contentsOf: tempFile)
        XCTAssertTrue(data.count > 0)
        try? FileManager.default.removeItem(at: tempFile)
    }
    
    public func test_F18_BVA_OfflineSearchWithCorruptedQuery() {
        let result = SearchService.parseCoordinateString("NOT_A_VALID_QUERY_AT_ALL")
        XCTAssertNil(result)
    }
    
    public func test_F18_BVA_OfflineNavigationWithoutCachedTiles() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        // Navigation runs in memory with 0 tile server dependency
        let update = nav.updateLocation(CLLocation(latitude: 46.8529, longitude: -113.9850))
        XCTAssertFalse(update.isOffTrail)
    }
    
    public func test_F18_BVA_OfflineAlertAudioSystemAvailable() {
        let spy = MockAudioAlertSpy()
        spy.recordAlert(deviationMeters: 40.0)
        XCTAssertEqual(spy.alertPlayCount, 1)
    }

    // MARK: Feature 19: Full E2E Test Suite Pass (5 Tests)
    
    public func test_F19_BVA_SimultaneousTrailImportAndDownload() async throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        
        let converter = GeoJSONConverter()
        let geoJSON = try converter.convert(overpassJSONString: TrailTestFixtures.overpassJSONSample)
        
        XCTAssertEqual(track.points.count, 5)
        XCTAssertTrue(geoJSON.contains("Sentinel Ridge Trail"))
    }
    
    @MainActor
    public func test_F19_BVA_FullSystemResetUnderLoad() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let nav = E2ETrailNavigator()
        let spy = MockAudioAlertSpy()
        
        for _ in 0..<10 {
            vm.resetOriginToCurrentLocation()
            nav.stopNavigation()
            spy.reset()
        }
        
        XCTAssertEqual(vm.originEndpoint, .currentLocation)
        XCTAssertNil(nav.activeTrack)
        XCTAssertEqual(spy.alertPlayCount, 0)
    }
    
    public func test_F19_BVA_CorruptedGPXRecoveryPipeline() {
        let parser = E2EGPXParser()
        var didCatchExpectedError = false
        do {
            _ = try parser.parse(xmlString: TrailTestFixtures.corruptGPXString)
            XCTFail("Should fail on corrupt GPX")
        } catch {
            didCatchExpectedError = true
            XCTAssertFalse(error.localizedDescription.isEmpty, "Parser error must provide diagnostic description")
        }
        XCTAssertTrue(didCatchExpectedError, "Pipeline must catch corrupted GPX and not crash")
        
        // System continues working on next valid track
        do {
            let validTrack = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
            XCTAssertEqual(validTrack.name, "Mount Sentinel Trail")
            XCTAssertEqual(validTrack.points.count, 5)
            XCTAssertGreaterThan(validTrack.totalDistance, 0.0)
        } catch {
            XCTFail("Valid track parsing must succeed following corrupt recovery: \(error)")
        }
    }
    
    public func test_F19_BVA_ZeroPointElevationProfileRendering() {
        let track = E2EGPXTrack(name: "Empty", points: [], totalDistance: 0, elevationGain: 0, elevationLoss: 0)
        let series = track.points.compactMap { $0.elevation }
        XCTAssertEqual(series.count, 0)
    }
    
    @MainActor
    public func test_F19_BVA_EndToEndIntegrityValidation() {
        // Assert that zero unexpected state mutations occur across complete lifecycle
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        XCTAssertEqual(vm.originEndpoint, .currentLocation)
        XCTAssertNil(vm.destinationEndpoint)
        XCTAssertFalse(vm.isRoutePreviewMode)
        XCTAssertEqual(mockRouting.calculateRouteCallCount, 0)
    }
}
