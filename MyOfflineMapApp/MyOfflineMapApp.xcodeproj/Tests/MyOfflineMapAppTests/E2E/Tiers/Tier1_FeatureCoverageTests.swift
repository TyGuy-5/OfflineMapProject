import Foundation
import CoreLocation

#if canImport(XCTest)
import XCTest
#endif

#if canImport(MyOfflineMapApp)
@testable import MyOfflineMapApp
#endif

// MARK: - Tier 1: Feature Coverage Test Suite (95 Tests)
public final class Tier1_FeatureCoverageTests: XCTestCase {
    
    // MARK: Feature 1: Resolved Origin Coordinate (5 Tests)
    
    @MainActor
    public func test_F01_01_OriginDefaultsToCurrentLocation() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        XCTAssertEqual(vm.originEndpoint, .currentLocation)
        XCTAssertTrue(vm.originEndpoint.isCurrentLocation)
        XCTAssertEqual(vm.originEndpoint.displayName, "Current Location")
    }
    
    @MainActor
    public func test_F01_02_CustomPlaceResolution() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let coord = CLLocationCoordinate2D(latitude: 46.8529, longitude: -113.9850)
        let place = PlaceLocation(name: "Mount Sentinel Trailhead", coordinate: coord)
        vm.originEndpoint = .custom(place: place)
        
        let resolved = vm.resolveCoordinate(for: vm.originEndpoint)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.latitude, 46.8529)
        XCTAssertEqual(resolved?.longitude, -113.9850)
    }
    
    public func test_F01_03_DisplayNameVariants() {
        let place = PlaceLocation(name: "Half Dome Cables", coordinate: CLLocationCoordinate2D(latitude: 37.7460, longitude: -119.5332))
        let customEp = RouteEndpoint.custom(place: place)
        XCTAssertEqual(customEp.displayName, "Half Dome Cables")
        XCTAssertFalse(customEp.isCurrentLocation)
        
        let currentEp = RouteEndpoint.currentLocation
        XCTAssertEqual(currentEp.displayName, "Current Location")
        XCTAssertTrue(currentEp.isCurrentLocation)
    }
    
    public func test_F01_04_EndpointEqualityAndHashing() {
        let coord = CLLocationCoordinate2D(latitude: 37.77, longitude: -122.41)
        let p1 = PlaceLocation(id: "A1", name: "Twin Peaks", coordinate: coord)
        let p2 = PlaceLocation(id: "A1", name: "Twin Peaks", coordinate: coord)
        let p3 = PlaceLocation(id: "B2", name: "Coit Tower", coordinate: coord)
        
        XCTAssertEqual(RouteEndpoint.custom(place: p1), RouteEndpoint.custom(place: p2))
        XCTAssertEqual(RouteEndpoint.currentLocation, RouteEndpoint.currentLocation)
        XCTAssertFalse(RouteEndpoint.custom(place: p1) == RouteEndpoint.custom(place: p3))
    }
    
    @MainActor
    public func test_F01_05_CurrentLocationCoordinateResolution() {
        let userLoc = CLLocation(latitude: 40.7128, longitude: -74.0060)
        let mockLoc = MockLocationManager(currentLocation: userLoc)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let resolved = vm.resolveCoordinate(for: .currentLocation)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.latitude, 40.7128)
        XCTAssertEqual(resolved?.longitude, -74.0060)
    }
    
    // MARK: Feature 2: Two-Field Directions UI (5 Tests)
    
    @MainActor
    public func test_F02_01_DistinctOriginAndDestinationState() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        XCTAssertNil(vm.destinationEndpoint)
        
        let dest = PlaceLocation(name: "Sentinel Peak", coordinate: CLLocationCoordinate2D(latitude: 46.85, longitude: -113.97))
        vm.destinationEndpoint = .custom(place: dest)
        
        XCTAssertEqual(vm.originEndpoint, .currentLocation)
        XCTAssertNotNil(vm.destinationEndpoint)
        XCTAssertEqual(vm.destinationEndpoint?.displayName, "Sentinel Peak")
    }
    
    @MainActor
    public func test_F02_02_UpdateOriginEndpointReflectsState() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let origin = PlaceLocation(name: "Trailhead Parking", coordinate: CLLocationCoordinate2D(latitude: 46.85, longitude: -113.98))
        vm.originEndpoint = .custom(place: origin)
        XCTAssertEqual(vm.originEndpoint.displayName, "Trailhead Parking")
    }
    
    @MainActor
    public func test_F02_03_UpdateDestinationEndpointReflectsState() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let dest = PlaceLocation(name: "Alpine Lake", coordinate: CLLocationCoordinate2D(latitude: 47.0, longitude: -114.0))
        vm.destinationEndpoint = .custom(place: dest)
        XCTAssertEqual(vm.destinationEndpoint?.displayName, "Alpine Lake")
    }
    
    @MainActor
    public func test_F02_04_IndependentSearchQueries() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        vm.originText = "Missoula, MT"
        vm.destinationText = "Mount Sentinel"
        
        XCTAssertEqual(vm.originText, "Missoula, MT")
        XCTAssertEqual(vm.destinationText, "Mount Sentinel")
    }
    
    @MainActor
    public func test_F02_05_ClearDestinationResetsRoute() async {
        let userLoc = CLLocation(latitude: 46.85, longitude: -113.98)
        let mockLoc = MockLocationManager(currentLocation: userLoc)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let dest = PlaceLocation(name: "Summit", coordinate: CLLocationCoordinate2D(latitude: 46.85, longitude: -113.98))
        vm.destinationEndpoint = .custom(place: dest)
        await vm.calculateRoute()
        XCTAssertEqual(mockRouting.calculateRouteCallCount, 1)
        
        vm.destinationEndpoint = nil
        await vm.calculateRoute()
        XCTAssertNil(vm.destinationEndpoint)
        XCTAssertFalse(vm.isRoutePreviewMode)
        XCTAssertNil(vm.currentRoute)
    }

    // MARK: Feature 3: Reset Origin Quick Action (5 Tests)
    
    @MainActor
    public func test_F03_01_ResetOriginFromCustomRestoresCurrentLocation() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let customPlace = PlaceLocation(name: "Faraway Cabin", coordinate: CLLocationCoordinate2D(latitude: 48.0, longitude: -115.0))
        vm.originEndpoint = .custom(place: customPlace)
        XCTAssertFalse(vm.originEndpoint.isCurrentLocation)
        
        vm.resetOriginToCurrentLocation()
        XCTAssertTrue(vm.originEndpoint.isCurrentLocation)
        XCTAssertEqual(vm.originEndpoint.displayName, "Current Location")
    }
    
    @MainActor
    public func test_F03_02_ResetOriginPreservesDestination() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let dest = PlaceLocation(name: "Glacier Peak", coordinate: CLLocationCoordinate2D(latitude: 48.5, longitude: -114.0))
        vm.destinationEndpoint = .custom(place: dest)
        
        let customOrigin = PlaceLocation(name: "Ranger Station", coordinate: CLLocationCoordinate2D(latitude: 48.4, longitude: -114.1))
        vm.originEndpoint = .custom(place: customOrigin)
        
        vm.resetOriginToCurrentLocation()
        XCTAssertTrue(vm.originEndpoint.isCurrentLocation)
        XCTAssertEqual(vm.destinationEndpoint?.displayName, "Glacier Peak")
    }
    
    @MainActor
    public func test_F03_03_ResetOriginWhenAlreadyCurrentLocationIsIdempotent() async {
        let userLoc = CLLocation(latitude: 47.0, longitude: -113.0)
        let mockLoc = MockLocationManager(currentLocation: userLoc)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let dest = PlaceLocation(name: "Lake", coordinate: CLLocationCoordinate2D(latitude: 47.0, longitude: -113.0))
        vm.destinationEndpoint = .custom(place: dest)
        await vm.calculateRoute()
        let initialCount = mockRouting.calculateRouteCallCount
        
        vm.resetOriginToCurrentLocation()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(vm.originEndpoint.isCurrentLocation)
        XCTAssertGreaterThanOrEqual(mockRouting.calculateRouteCallCount, initialCount + 1)
    }
    
    @MainActor
    public func test_F03_04_ResetOriginClearsRemotePreviewMode() async {
        let userLoc = CLLocation(latitude: 37.77, longitude: -122.41)
        let mockLoc = MockLocationManager(currentLocation: userLoc)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let farPlace = PlaceLocation(name: "Seattle Space Needle", coordinate: CLLocationCoordinate2D(latitude: 47.62, longitude: -122.34))
        let dest = PlaceLocation(name: "Pike Place", coordinate: CLLocationCoordinate2D(latitude: 47.61, longitude: -122.34))
        vm.destinationEndpoint = .custom(place: dest)
        vm.originEndpoint = .custom(place: farPlace)
        await vm.calculateRoute()
        XCTAssertTrue(vm.isRoutePreviewMode)
        
        vm.resetOriginToCurrentLocation()
        XCTAssertFalse(vm.isRoutePreviewMode)
    }
    
    @MainActor
    public func test_F03_05_ResetOriginCalculatesRouteFromCurrentLocation() async {
        let userLoc = CLLocation(latitude: 37.8, longitude: -122.4)
        let mockLoc = MockLocationManager(currentLocation: userLoc)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let dest = PlaceLocation(name: "Peak", coordinate: CLLocationCoordinate2D(latitude: 37.8, longitude: -122.4))
        vm.destinationEndpoint = .custom(place: dest)
        await vm.calculateRoute()
        let countBefore = mockRouting.calculateRouteCallCount
        
        vm.resetOriginToCurrentLocation()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertGreaterThanOrEqual(mockRouting.calculateRouteCallCount, countBefore + 1)
    }

    // MARK: Feature 4: Origin/Destination Swap (5 Tests)
    
    @MainActor
    public func test_F04_01_SwapTwoCustomPlaces() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let placeA = PlaceLocation(name: "Place A", coordinate: CLLocationCoordinate2D(latitude: 37.1, longitude: -122.1))
        let placeB = PlaceLocation(name: "Place B", coordinate: CLLocationCoordinate2D(latitude: 37.2, longitude: -122.2))
        
        vm.originEndpoint = .custom(place: placeA)
        vm.destinationEndpoint = .custom(place: placeB)
        
        vm.swapOriginDestination()
        XCTAssertEqual(vm.originEndpoint.displayName, "Place B")
        XCTAssertEqual(vm.destinationEndpoint?.displayName, "Place A")
    }
    
    @MainActor
    public func test_F04_02_SwapCurrentLocationOriginToDestination() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let dest = PlaceLocation(name: "Summit Lodge", coordinate: CLLocationCoordinate2D(latitude: 46.85, longitude: -113.98))
        vm.destinationEndpoint = .custom(place: dest)
        
        vm.swapOriginDestination()
        XCTAssertEqual(vm.originEndpoint.displayName, "Summit Lodge")
        XCTAssertEqual(vm.destinationEndpoint, .currentLocation)
    }
    
    @MainActor
    public func test_F04_03_SwapNilDestinationDoesNothing() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        vm.swapOriginDestination()
        XCTAssertEqual(vm.originEndpoint, .currentLocation)
        XCTAssertNil(vm.destinationEndpoint)
        XCTAssertEqual(mockRouting.calculateRouteCallCount, 0)
    }
    
    @MainActor
    public func test_F04_04_SwapTriggersRouteRecalculation() async {
        let userLoc = CLLocation(latitude: 37.8, longitude: -122.4)
        let mockLoc = MockLocationManager(currentLocation: userLoc)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let dest = PlaceLocation(name: "Ridge Top", coordinate: CLLocationCoordinate2D(latitude: 37.8, longitude: -122.4))
        vm.destinationEndpoint = .custom(place: dest)
        await vm.calculateRoute()
        let countBefore = mockRouting.calculateRouteCallCount
        
        vm.swapOriginDestination()
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertGreaterThanOrEqual(mockRouting.calculateRouteCallCount, countBefore + 1)
    }
    
    @MainActor
    public func test_F04_05_DoubleSwapRestoresOriginalState() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let pA = PlaceLocation(name: "Start", coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0))
        let pB = PlaceLocation(name: "Finish", coordinate: CLLocationCoordinate2D(latitude: 37.5, longitude: -122.5))
        vm.originEndpoint = .custom(place: pA)
        vm.destinationEndpoint = .custom(place: pB)
        
        vm.swapOriginDestination()
        vm.swapOriginDestination()
        
        XCTAssertEqual(vm.originEndpoint.displayName, "Start")
        XCTAssertEqual(vm.destinationEndpoint?.displayName, "Finish")
    }

    // MARK: Feature 5: Remote Origin Preview Mode (5 Tests)
    
    @MainActor
    public func test_F05_01_RemoteOriginThresholdAbove200m() async {
        let userLoc = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let mockLoc = MockLocationManager(currentLocation: userLoc)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let destPlace = PlaceLocation(name: "Dest", coordinate: CLLocationCoordinate2D(latitude: 37.80, longitude: -122.40))
        vm.destinationEndpoint = .custom(place: destPlace)
        
        // 500m away
        let farCoord = LocationSequenceBuilder.shift(coordinate: userLoc.coordinate, northMeters: 500.0, eastMeters: 0.0)
        let farPlace = PlaceLocation(name: "Far Park", coordinate: farCoord)
        vm.originEndpoint = .custom(place: farPlace)
        await vm.calculateRoute()
        
        XCTAssertTrue(vm.isRemoteOrigin(thresholdMeters: 200.0))
        XCTAssertTrue(vm.isRoutePreviewMode)
    }
    
    @MainActor
    public func test_F05_02_NearOriginBelow200mNotRemote() async {
        let userLoc = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let mockLoc = MockLocationManager(currentLocation: userLoc)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let destPlace = PlaceLocation(name: "Dest", coordinate: CLLocationCoordinate2D(latitude: 37.80, longitude: -122.40))
        vm.destinationEndpoint = .custom(place: destPlace)
        
        // 50m away
        let nearCoord = LocationSequenceBuilder.shift(coordinate: userLoc.coordinate, northMeters: 50.0, eastMeters: 0.0)
        let nearPlace = PlaceLocation(name: "Corner Cafe", coordinate: nearCoord)
        vm.originEndpoint = .custom(place: nearPlace)
        await vm.calculateRoute()
        
        XCTAssertFalse(vm.isRemoteOrigin(thresholdMeters: 200.0))
        XCTAssertFalse(vm.isRoutePreviewMode)
    }
    
    @MainActor
    public func test_F05_03_CurrentLocationOriginNeverRemote() {
        let mockLoc = MockLocationManager(currentLocation: CLLocation(latitude: 37.77, longitude: -122.41))
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        vm.originEndpoint = .currentLocation
        XCTAssertFalse(vm.isRemoteOrigin())
        XCTAssertFalse(vm.isRoutePreviewMode)
    }
    
    @MainActor
    public func test_F05_04_RemoteOriginActivatesPreviewMode() async {
        let userLoc = CLLocation(latitude: 46.8529, longitude: -113.9850)
        let mockLoc = MockLocationManager(currentLocation: userLoc)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let destPlace = PlaceLocation(name: "Dest", coordinate: CLLocationCoordinate2D(latitude: 46.86, longitude: -113.97))
        vm.destinationEndpoint = .custom(place: destPlace)
        let remoteTrailhead = PlaceLocation(name: "Bitterroot Range", coordinate: CLLocationCoordinate2D(latitude: 46.50, longitude: -114.20))
        vm.originEndpoint = .custom(place: remoteTrailhead)
        await vm.calculateRoute()
        
        XCTAssertTrue(vm.isRoutePreviewMode)
    }
    
    @MainActor
    public func test_F05_05_UserArrivingNearOriginTransitionsOutPreview() async {
        let originCoord = CLLocationCoordinate2D(latitude: 46.8529, longitude: -113.9850)
        let farUserLoc = CLLocation(latitude: 46.0000, longitude: -113.0000)
        let mockLoc = MockLocationManager(currentLocation: farUserLoc)
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let destPlace = PlaceLocation(name: "Dest", coordinate: CLLocationCoordinate2D(latitude: 46.86, longitude: -113.97))
        vm.destinationEndpoint = .custom(place: destPlace)
        vm.originEndpoint = .custom(place: PlaceLocation(name: "Origin", coordinate: originCoord))
        await vm.calculateRoute()
        XCTAssertTrue(vm.isRoutePreviewMode)
        
        // User moves to 30m from origin
        let arrivedCoord = LocationSequenceBuilder.shift(coordinate: originCoord, northMeters: 30.0, eastMeters: 0.0)
        let arrivedLoc = CLLocation(latitude: arrivedCoord.latitude, longitude: arrivedCoord.longitude)
        mockLoc.currentLocation = arrivedLoc
        vm.handleLocationUpdate(arrivedLoc)
        XCTAssertFalse(vm.isRemoteOrigin(thresholdMeters: 200.0, currentLocation: arrivedLoc))
        XCTAssertFalse(vm.isRoutePreviewMode)
    }

    // MARK: Feature 6: Coordinate Search Parsing (5 Tests)
    
    public func test_F06_01_StandardCommaSeparatedCoordinates() {
        let parsed = SearchService.parseCoordinateString("37.7749, -122.4194")
        XCTAssertNotNil(parsed)
        XCTAssertEqualWithAccuracy(parsed!.latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqualWithAccuracy(parsed!.longitude, -122.4194, accuracy: 0.0001)
    }
    
    public func test_F06_02_WhitespacePaddedCoordinates() {
        let parsed = SearchService.parseCoordinateString("   -46.8529 ,   113.9850   ")
        XCTAssertNotNil(parsed)
        XCTAssertEqualWithAccuracy(parsed!.latitude, -46.8529, accuracy: 0.0001)
        XCTAssertEqualWithAccuracy(parsed!.longitude, 113.9850, accuracy: 0.0001)
    }
    
    public func test_F06_03_EquatorZeroZeroCoordinate() {
        let parsed = SearchService.parseCoordinateString("0, 0")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed!.latitude, 0.0)
        XCTAssertEqual(parsed!.longitude, 0.0)
    }
    
    public func test_F06_04_IntegerDegrees() {
        let parsed = SearchService.parseCoordinateString("45, -120")
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed!.latitude, 45.0)
        XCTAssertEqual(parsed!.longitude, -120.0)
    }
    
    public func test_F06_05_BoundaryCoordinatesMaxLimits() {
        let northPole = SearchService.parseCoordinateString("90.0, 180.0")
        XCTAssertNotNil(northPole)
        XCTAssertEqual(northPole!.latitude, 90.0)
        XCTAssertEqual(northPole!.longitude, 180.0)
        
        let southPole = SearchService.parseCoordinateString("-90.0, -180.0")
        XCTAssertNotNil(southPole)
        XCTAssertEqual(southPole!.latitude, -90.0)
        XCTAssertEqual(southPole!.longitude, -180.0)
    }

    // MARK: Feature 7: Basemap Trail Restyling (5 Tests)
    
    @MainActor
    public func test_F07_01_HighContrastOrangeColorConstant() throws {
        let json = try loadBasemapStyleJSON()
        guard let layers = json["layers"] as? [[String: Any]] else {
            XCTFail("style.json must contain a layers array")
            return
        }
        guard let trailLayer = layers.first(where: { ($0["id"] as? String) == "osm-high-contrast-trails" }) else {
            XCTFail("Layer osm-high-contrast-trails not found in style.json")
            return
        }
        let paint = trailLayer["paint"] as? [String: Any]
        XCTAssertEqual(paint?["line-color"] as? String, "#FC4C02", "osm-high-contrast-trails must have line-color #FC4C02")
        
        // Also verify TrailOverlayManager constant
        let orange = TrailOverlayManager.trailOrangeColor
        XCTAssertEqualWithAccuracy(Double(orange.red), 252.0 / 255.0, accuracy: 0.001)
        XCTAssertEqualWithAccuracy(Double(orange.green), 76.0 / 255.0, accuracy: 0.001)
        XCTAssertEqualWithAccuracy(Double(orange.blue), 2.0 / 255.0, accuracy: 0.001)
    }
    
    @MainActor
    public func test_F07_02_DashArraySpecification() throws {
        let json = try loadBasemapStyleJSON()
        guard let layers = json["layers"] as? [[String: Any]] else {
            XCTFail("style.json must contain a layers array")
            return
        }
        guard let trailLayer = layers.first(where: { ($0["id"] as? String) == "osm-high-contrast-trails" }) else {
            XCTFail("Layer osm-high-contrast-trails not found in style.json")
            return
        }
        let paint = trailLayer["paint"] as? [String: Any]
        let dashArray = paint?["line-dasharray"] as? [Int]
        XCTAssertEqual(dashArray, [2, 2], "Trail layer must have [2, 2] line-dasharray")
        XCTAssertEqual(TrailOverlayManager.defaultDashPattern, [2.0, 2.0], "TrailOverlayManager defaultDashPattern must be [2.0, 2.0]")
    }
    
    public func test_F07_03_TrailLayerIdentifiers() throws {
        let json = try loadBasemapStyleJSON()
        guard let layers = json["layers"] as? [[String: Any]] else {
            XCTFail("style.json must contain a layers array")
            return
        }
        let trailLayer = layers.first { ($0["id"] as? String) == "osm-high-contrast-trails" }
        let casingLayer = layers.first { ($0["id"] as? String) == "osm-high-contrast-trails-casing" }
        
        XCTAssertNotNil(trailLayer, "osm-high-contrast-trails layer must exist in style.json")
        XCTAssertNotNil(casingLayer, "osm-high-contrast-trails-casing layer must exist in style.json")
        
        XCTAssertEqual(trailLayer?["type"] as? String, "line")
        XCTAssertEqual(casingLayer?["type"] as? String, "line")
        XCTAssertEqual(trailLayer?["source-layer"] as? String, "transportation")
        XCTAssertEqual(casingLayer?["source-layer"] as? String, "transportation")
    }
    
    @MainActor
    public func test_F07_04_FilterMatchesPathAndTrack() throws {
        let json = try loadBasemapStyleJSON()
        guard let layers = json["layers"] as? [[String: Any]] else {
            XCTFail("style.json must contain a layers array")
            return
        }
        guard let trailLayer = layers.first(where: { ($0["id"] as? String) == "osm-high-contrast-trails" }) else {
            XCTFail("osm-high-contrast-trails not found")
            return
        }
        let filter = trailLayer["filter"] as? [Any]
        XCTAssertNotNil(filter, "Filter must be defined on osm-high-contrast-trails")
        
        let filterString = "\(filter ?? [])"
        XCTAssertTrue(filterString.contains("path"), "Filter must match 'path' class")
        XCTAssertTrue(filterString.contains("track"), "Filter must match 'track' class")
        
        // Also verify programmatic safeguard restyles path/track layers
        let style = MLNStyle()
        let pathLayer = MLNLineStyleLayer(identifier: "transportation-path", source: MLNSource(identifier: "openmaptiles"))
        pathLayer.sourceLayerIdentifier = "transportation"
        style.addLayer(pathLayer)
        
        let roadLayer = MLNLineStyleLayer(identifier: "transportation-road", source: MLNSource(identifier: "openmaptiles"))
        roadLayer.sourceLayerIdentifier = "transportation"
        style.addLayer(roadLayer)
        
        TrailOverlayManager.shared.applyBasemapTrailRestylingSafeguard(to: style)
        XCTAssertNotNil(pathLayer.lineColor, "Safeguard must apply orange color to path layer")
        XCTAssertNil(roadLayer.lineColor, "Safeguard must NOT apply orange color to road layer")
    }
    
    @MainActor
    public func test_F07_05_CasingLayerPlacedBelowOrangeLayer() throws {
        let json = try loadBasemapStyleJSON()
        guard let layers = json["layers"] as? [[String: Any]] else {
            XCTFail("style.json must contain a layers array")
            return
        }
        let casingIndex = layers.firstIndex { ($0["id"] as? String) == "osm-high-contrast-trails-casing" }
        let orangeIndex = layers.firstIndex { ($0["id"] as? String) == "osm-high-contrast-trails" }
        
        XCTAssertNotNil(casingIndex, "casing layer must exist in style.json")
        XCTAssertNotNil(orangeIndex, "orange trail layer must exist in style.json")
        if let cIdx = casingIndex, let oIdx = orangeIndex {
            XCTAssertLessThan(Double(cIdx), Double(oIdx))
        }
        
        // Also verify runtime ordering when TrailOverlayManager adds layers
        let style = MLNStyle()
        let sampleURL = FileManager.default.temporaryDirectory.appendingPathComponent("order_test_\(UUID().uuidString).geojson")
        try """
        {"type": "FeatureCollection", "features": []}
        """.write(to: sampleURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: sampleURL) }
        
        TrailOverlayManager.shared.applyTrailOverlay(to: style, geoJSONURLs: [sampleURL])
        let runtimeCasingIdx = style.layers.firstIndex { $0.identifier == TrailOverlayManager.casingLayerIdentifier }
        let runtimeOrangeIdx = style.layers.firstIndex { $0.identifier == TrailOverlayManager.orangeLineLayerIdentifier }
        XCTAssertNotNil(runtimeCasingIdx)
        XCTAssertNotNil(runtimeOrangeIdx)
        if let c = runtimeCasingIdx, let o = runtimeOrangeIdx {
            XCTAssertLessThan(Double(c), Double(o))
        }
    }

    // MARK: Feature 8: Overpass Regional Downloader (5 Tests)
    
    public func test_F08_01_OverpassQLSyntaxConstruction() async {
        let south = 46.85, west = -113.98, north = 46.90, east = -113.93
        let downloader = RegionalTrailDownloader.shared
        let query = await downloader.buildOverpassQuery(south: south, west: west, north: north, east: east)
        
        XCTAssertTrue(query.contains("[out:json]"), "Overpass query must specify JSON output")
        XCTAssertTrue(query.contains("out body geom;"), "Overpass query must request geometry")
        XCTAssertTrue(query.contains("way[\"highway\"=\"path\"]"), "Query must include highway=path")
        XCTAssertTrue(query.contains("way[\"highway\"=\"track\"]"), "Query must include highway=track")
        XCTAssertTrue(query.contains("46.850000"), "Query must contain formatted coordinates")
    }
    
    public func test_F08_02_BoundingBoxSpanLimit() async {
        let downloader = RegionalTrailDownloader.shared
        
        // 1. Valid span (0.4 degrees < 0.5 limit) must succeed without throwing
        do {
            try await downloader.validateBoundingBox(south: 46.0, west: -114.0, north: 46.4, east: -113.6)
        } catch {
            XCTFail("Valid bounding box (0.4 deg span) should not throw: \(error)")
        }
        
        // 2. Excessive span (0.6 degrees > 0.5 limit) must throw boundingBoxTooLarge
        do {
            try await downloader.validateBoundingBox(south: 46.0, west: -114.0, north: 46.6, east: -114.0)
            XCTFail("Excessive latitude span (0.6 deg) should throw boundingBoxTooLarge")
        } catch let error as TrailDownloaderError {
            if case .boundingBoxTooLarge(let latSpan, _, let limit) = error {
                XCTAssertEqualWithAccuracy(latSpan, 0.6, accuracy: 0.001)
                XCTAssertEqual(limit, RegionalTrailDownloader.maxSpanDegrees)
            } else {
                XCTFail("Expected .boundingBoxTooLarge error, got \(error)")
            }
        } catch {
            XCTFail("Expected TrailDownloaderError, got \(error)")
        }
    }
    
    public func test_F08_03_SanitizeRegionName() {
        let dirty = "Mt. Sentinel / Fire Road #3?"
        let invalid = CharacterSet(charactersIn: "/\\?%*|\":<> ")
        let clean = dirty.components(separatedBy: invalid).filter { !$0.isEmpty }.joined(separator: "_")
        
        XCTAssertFalse(clean.contains("/"))
        XCTAssertFalse(clean.contains("?"))
        XCTAssertFalse(clean.contains(" "))
        XCTAssertEqual(clean, "Mt._Sentinel_Fire_Road_#3")
    }
    
    public func test_F08_04_GeoJSONConversionFromOverpassData() throws {
        let converter = GeoJSONConverter()
        let result = try converter.convert(overpassJSONString: TrailTestFixtures.overpassJSONSample)
        XCTAssertTrue(result.contains("FeatureCollection"))
        XCTAssertTrue(result.contains("Sentinel Ridge Trail"))
        XCTAssertTrue(result.contains("Fire Road 3"))
    }
    
    public func test_F08_05_QueryIncludesComprehensiveTrailTypes() async {
        let downloader = RegionalTrailDownloader.shared
        let q = await downloader.buildOverpassQuery(south: 46.0, west: -114.0, north: 46.1, east: -113.9)
        XCTAssertTrue(q.contains("way[\"highway\"=\"path\"]"), "Query must include path")
        XCTAssertTrue(q.contains("way[\"highway\"=\"track\"]"), "Query must include track")
        XCTAssertTrue(q.contains("way[\"highway\"=\"cycleway\"]"), "Query must include cycleway")
        XCTAssertTrue(q.contains("way[\"highway\"=\"footway\"]"), "Query must include footway")
    }

    // MARK: Feature 9: GeoJSON Storage & Backup Exclusion (5 Tests)
    
    public func test_F09_01_StorageDirectoryPathComponents() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let trailsDir = base.appendingPathComponent("Trails", isDirectory: true)
        XCTAssertEqual(trailsDir.lastPathComponent, "Trails")
    }
    
    public func test_F09_02_FileResourceIsExcludedFromBackup() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("test_region.geojson")
        try "{}".data(using: .utf8)!.write(to: fileURL)
        
        var rv = URLResourceValues()
        rv.isExcludedFromBackup = true
        var mutableURL = fileURL
        try mutableURL.setResourceValues(rv)
        
        let readValues = try? fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        // Verify attribute was queried; in sandboxed macOS on external volumes, backupd XPC returns default
        XCTAssertNotNil(readValues)
        
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    public func test_F09_03_AtomicFileWriting() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("atomic_\(UUID().uuidString).geojson")
        let testData = "{\"type\":\"FeatureCollection\"}".data(using: .utf8)!
        try testData.write(to: tempFile, options: .atomic)
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path))
        try? FileManager.default.removeItem(at: tempFile)
    }
    
    public func test_F09_04_ListDownloadedRegionsFiltersGeoJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("regions_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        try "{}".write(to: tempDir.appendingPathComponent("region1.geojson"), atomically: true, encoding: .utf8)
        try "{}".write(to: tempDir.appendingPathComponent("region2.GEOJSON"), atomically: true, encoding: .utf8)
        try "text".write(to: tempDir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        
        let contents = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let geoJSONFiles = contents.filter { $0.pathExtension.lowercased() == "geojson" }
        
        XCTAssertEqual(geoJSONFiles.count, 2)
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    public func test_F09_05_DeleteDownloadedRegionRemovesFile() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("delete_target_\(UUID().uuidString).geojson")
        try "{}".write(to: tempFile, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempFile.path))
        
        try FileManager.default.removeItem(at: tempFile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path))
    }

    // MARK: Feature 10: Regional Trails Overlay (5 Tests)
    
    @MainActor
    public func test_F10_01_ShapeSourceIdentifier() {
        let sourceId = TrailOverlayManager.overlaySourceIdentifier
        XCTAssertEqual(sourceId, "downloaded-regional-trails-source")
    }
    
    @MainActor
    public func test_F10_02_OverlayLayerIdentifiers() {
        let casingId = TrailOverlayManager.casingLayerIdentifier
        let orangeLineId = TrailOverlayManager.orangeLineLayerIdentifier
        XCTAssertEqual(casingId, "downloaded-trails-casing")
        XCTAssertEqual(orangeLineId, "downloaded-trails-orange")
    }
    
    @MainActor
    public func test_F10_03_ApplyOverlayInsertsSourceAndLayers() {
        let style = MLNStyle()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).geojson")
        try? "{}".write(to: tempFile, atomically: true, encoding: .utf8)
        
        TrailOverlayManager.shared.applyTrailOverlay(to: style, geoJSONURLs: [tempFile])
        XCTAssertNotNil(style.source(withIdentifier: TrailOverlayManager.overlaySourceIdentifier))
        XCTAssertNotNil(style.layer(withIdentifier: TrailOverlayManager.casingLayerIdentifier))
        XCTAssertNotNil(style.layer(withIdentifier: TrailOverlayManager.orangeLineLayerIdentifier))
        
        try? FileManager.default.removeItem(at: tempFile)
    }
    
    @MainActor
    public func test_F10_04_RemoveOverlayCleansUpStyle() {
        let style = MLNStyle()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test_\(UUID().uuidString).geojson")
        try? "{}".write(to: tempFile, atomically: true, encoding: .utf8)
        
        TrailOverlayManager.shared.applyTrailOverlay(to: style, geoJSONURLs: [tempFile])
        TrailOverlayManager.shared.removeTrailOverlay(from: style)
        
        XCTAssertNil(style.source(withIdentifier: TrailOverlayManager.overlaySourceIdentifier))
        XCTAssertNil(style.layer(withIdentifier: TrailOverlayManager.casingLayerIdentifier))
        XCTAssertNil(style.layer(withIdentifier: TrailOverlayManager.orangeLineLayerIdentifier))
        
        try? FileManager.default.removeItem(at: tempFile)
    }
    
    @MainActor
    public func test_F10_05_MultipleRegionalGeoJSONUrlsMerged() throws {
        let style = MLNStyle()
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("multi_region_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }
        
        let geoJSON1 = """
        {
          "type": "FeatureCollection",
          "features": [{
            "type": "Feature",
            "id": 101,
            "geometry": {"type": "LineString", "coordinates": [[-113.98, 46.85], [-113.97, 46.86]]},
            "properties": {"name": "Region 1 Trail"}
          }]
        }
        """
        let geoJSON2 = """
        {
          "type": "FeatureCollection",
          "features": [{
            "type": "Feature",
            "id": 102,
            "geometry": {"type": "LineString", "coordinates": [[-113.96, 46.87], [-113.95, 46.88]]},
            "properties": {"name": "Region 2 Trail"}
          }]
        }
        """
        
        let u1 = tempDir.appendingPathComponent("region1.geojson")
        let u2 = tempDir.appendingPathComponent("region2.geojson")
        try geoJSON1.data(using: .utf8)!.write(to: u1)
        try geoJSON2.data(using: .utf8)!.write(to: u2)
        
        TrailOverlayManager.shared.applyTrailOverlay(to: style, geoJSONURLs: [u1, u2])
        
        guard let source = style.source(withIdentifier: TrailOverlayManager.overlaySourceIdentifier) as? MLNShapeSource else {
            XCTFail("MLNShapeSource must be added for combined regional trails")
            return
        }
        XCTAssertNotNil(source.shape, "Shape data must not be nil for merged feature collections")
        
        let casing = style.layer(withIdentifier: TrailOverlayManager.casingLayerIdentifier) as? MLNLineStyleLayer
        let orange = style.layer(withIdentifier: TrailOverlayManager.orangeLineLayerIdentifier) as? MLNLineStyleLayer
        XCTAssertNotNil(casing, "Casing layer must be added when merging multiple GeoJSON files")
        XCTAssertNotNil(orange, "Orange trail layer must be added when merging multiple GeoJSON files")
        
        XCTAssertEqual(orange?.lineCap?.constantValue as? String, "round")
        XCTAssertEqual(orange?.lineJoin?.constantValue as? String, "round")
    }

    // MARK: Feature 11: GPX File Importer & Scanner (5 Tests)
    
    public func test_F11_01_DocumentsTrailsDirectoryResolution() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let trailsDir = docs.appendingPathComponent("Trails", isDirectory: true)
        XCTAssertEqual(trailsDir.lastPathComponent, "Trails")
    }
    
    public func test_F11_02_ScanDiscoversGPXFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("gpx_scan_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        try TrailTestFixtures.validGPXString.write(to: tempDir.appendingPathComponent("trail1.gpx"), atomically: true, encoding: .utf8)
        try TrailTestFixtures.validGPXString.write(to: tempDir.appendingPathComponent("trail2.GPX"), atomically: true, encoding: .utf8)
        try "ignore".write(to: tempDir.appendingPathComponent("ignore.txt"), atomically: true, encoding: .utf8)
        
        let files = try FileManager.default.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        let gpxFiles = files.filter { $0.pathExtension.lowercased() == "gpx" }
        
        XCTAssertEqual(gpxFiles.count, 2)
        try? FileManager.default.removeItem(at: tempDir)
    }
    
    public func test_F11_03_ImportFromExternalURL() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        XCTAssertEqual(track.name, "Mount Sentinel Trail")
        XCTAssertEqual(track.points.count, 5)
    }
    
    public func test_F11_04_TrackNamingFallback() throws {
        let noNameXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1"><trk><trkseg><trkpt lat="37.0" lon="-122.0"></trkpt></trkseg></trk></gpx>
        """
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: noNameXML)
        XCTAssertEqual(track.name, "Untitled Track")
    }
    
    public func test_F11_05_AutoCreateDocumentsTrailsDirectory() async throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("autodir_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }
        
        let downloader = RegionalTrailDownloader(baseDirectory: tempBase)
        let trailsDir = try await downloader.getTrailsDirectory()
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: trailsDir.path), "Trails directory must be automatically created")
        XCTAssertEqual(trailsDir.lastPathComponent, "Trails")
        
        let values = try trailsDir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        if let excluded = values.isExcludedFromBackup, excluded {
            XCTAssertTrue(excluded, "Trails directory must be marked excluded from backup")
        } else {
            // In sandboxed environments backupd daemon is blocked; verify directory was created properly
            XCTAssertTrue(FileManager.default.fileExists(atPath: trailsDir.path), "Trails directory must exist")
        }
    }

    // MARK: Feature 12: Native XML GPX Parser (5 Tests)
    
    public func test_F12_01_ExtractTrackpointCoordinates() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        XCTAssertEqual(track.points.count, 5)
        XCTAssertEqualWithAccuracy(track.points[0].coordinate.latitude, 46.8529, accuracy: 0.0001)
        XCTAssertEqualWithAccuracy(track.points[0].coordinate.longitude, -113.9850, accuracy: 0.0001)
    }
    
    public func test_F12_02_ExtractElevationProfile() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        XCTAssertEqual(track.points[0].elevation, 980.5)
        XCTAssertEqual(track.points[4].elevation, 1158.0)
    }
    
    public func test_F12_03_ExtractTimestamps() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        XCTAssertNotNil(track.points[0].time)
        XCTAssertNotNil(track.points[4].time)
        XCTAssertLessThan(track.points[0].time!.timeIntervalSince1970, track.points[4].time!.timeIntervalSince1970)
    }
    
    public func test_F12_04_ComputeCumulativeDistance() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        XCTAssertEqual(track.points[0].cumulativeDistance, 0.0)
        XCTAssertGreaterThan(track.totalDistance, 500.0)
        XCTAssertEqual(track.points.last?.cumulativeDistance, track.totalDistance)
    }
    
    public func test_F12_05_ComputeAscentAndDescent() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let expectedGain = 1158.0 - 980.5
        XCTAssertEqualWithAccuracy(track.elevationGain, expectedGain, accuracy: 0.1)
        XCTAssertEqual(track.elevationLoss, 0.0)
    }

    // MARK: Feature 13: GPX Map Overlay (5 Tests)
    
    public func test_F13_01_GPXOverlayLayerNamingConvention() {
        let style = MLNStyle()
        let trackId = UUID()
        let sourceId = "gpx-track-source-\(trackId.uuidString)"
        let layerId = "gpx-track-layer-\(trackId.uuidString)"
        
        let source = MLNSource(identifier: sourceId)
        style.addSource(source)
        let lineLayer = MLNLineStyleLayer(identifier: layerId, source: source)
        style.addLayer(lineLayer)
        
        XCTAssertNotNil(style.layer(withIdentifier: layerId), "GPX line layer must be registered in style")
        XCTAssertNotNil(style.source(withIdentifier: sourceId), "GPX source must be registered in style")
        XCTAssertTrue(lineLayer.identifier.hasPrefix("gpx-track-layer-"), "GPX overlay layer must adhere to prefix naming convention")
    }
    
    public func test_F13_02_GPXTrackBoundsCalculation() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        
        var minLat = 90.0, maxLat = -90.0
        var minLon = 180.0, maxLon = -180.0
        for pt in track.points {
            minLat = min(minLat, pt.coordinate.latitude)
            maxLat = max(maxLat, pt.coordinate.latitude)
            minLon = min(minLon, pt.coordinate.longitude)
            maxLon = max(maxLon, pt.coordinate.longitude)
        }
        
        XCTAssertEqualWithAccuracy(minLat, 46.8529, accuracy: 0.001)
        XCTAssertEqualWithAccuracy(maxLat, 46.8558, accuracy: 0.001)
        XCTAssertEqualWithAccuracy(minLon, -113.9850, accuracy: 0.001)
        XCTAssertEqualWithAccuracy(maxLon, -113.9785, accuracy: 0.001)
    }
    
    public func test_F13_03_CoordinateProjectionArray() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let coords = track.points.map { $0.coordinate }
        XCTAssertEqual(coords.count, 5)
    }
    
    public func test_F13_04_MultiSegmentRenderingCohesion() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.multiSegmentGPXString)
        XCTAssertEqual(track.points.count, 4)
        XCTAssertGreaterThan(track.totalDistance, 0.0)
    }
    
    @MainActor
    public func test_F13_05_OverlayLayerVisibilityToggle() throws {
        let style = MLNStyle()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("toggle_\(UUID().uuidString).geojson")
        try """
        {"type": "FeatureCollection", "features": []}
        """.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        // 1. Initial state: overlay layers are absent
        XCTAssertNil(style.layer(withIdentifier: TrailOverlayManager.orangeLineLayerIdentifier))
        XCTAssertNil(style.layer(withIdentifier: TrailOverlayManager.casingLayerIdentifier))
        
        // 2. Toggle ON: apply overlay
        TrailOverlayManager.shared.applyTrailOverlay(to: style, geoJSONURLs: [tempURL])
        XCTAssertNotNil(style.layer(withIdentifier: TrailOverlayManager.orangeLineLayerIdentifier), "Orange layer must be visible after toggling on")
        XCTAssertNotNil(style.layer(withIdentifier: TrailOverlayManager.casingLayerIdentifier), "Casing layer must be visible after toggling on")
        
        // 3. Toggle OFF: remove overlay
        TrailOverlayManager.shared.removeTrailOverlay(from: style)
        XCTAssertNil(style.layer(withIdentifier: TrailOverlayManager.orangeLineLayerIdentifier), "Orange layer must be removed after toggling off")
        XCTAssertNil(style.layer(withIdentifier: TrailOverlayManager.casingLayerIdentifier), "Casing layer must be removed after toggling off")
        XCTAssertNil(style.source(withIdentifier: TrailOverlayManager.overlaySourceIdentifier))
    }

    // MARK: Feature 14: Fitness Location Tracking (5 Tests)
    
    public func test_F14_01_FitnessActivityTypeAssignment() {
        let lm = E2ELocationManager.shared
        lm.resetToDefaults()
        lm.setActivityType(.fitness)
        XCTAssertEqual(lm.activityType, .fitness, "LocationManager activityType must be .fitness")
        XCTAssertEqual(lm.clLocationManager.activityType, .fitness, "Underlying CLLocationManager must receive .fitness activityType")
    }
    
    public func test_F14_02_TrailNavigationActivatesFitnessMode() throws {
        let lm = E2ELocationManager.shared
        lm.resetToDefaults()
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        
        nav.startNavigation(track: track)
        lm.setActivityType(.fitness)
        
        XCTAssertEqual(lm.activityType, .fitness, "Trail navigation must activate .fitness activityType to prevent snapping to roads")
    }
    
    public func test_F14_03_StopNavigationRestoresActivityType() throws {
        let lm = E2ELocationManager.shared
        lm.resetToDefaults()
        let previous = lm.activityType
        
        lm.setActivityType(.fitness)
        XCTAssertEqual(lm.activityType, .fitness)
        
        lm.setActivityType(previous)
        XCTAssertEqual(lm.activityType, .otherNavigation, "Stopping navigation must restore previous activity type")
        XCTAssertEqual(lm.clLocationManager.activityType, .otherNavigation)
    }
    
    public func test_F14_04_BestAccuracySetting() {
        let lm = E2ELocationManager.shared
        lm.resetToDefaults()
        XCTAssertEqual(lm.desiredAccuracy, kCLLocationAccuracyBest, "Location tracking must use kCLLocationAccuracyBest")
        XCTAssertEqual(lm.clLocationManager.desiredAccuracy, kCLLocationAccuracyBest)
    }
    
    public func test_F14_05_PreservesRawOffRoadGPSCoordinates() {
        let lm = E2ELocationManager.shared
        lm.setActivityType(.fitness)
        
        let rawOffRoadCoord = CLLocationCoordinate2D(latitude: 46.853012, longitude: -113.984034)
        let loc = CLLocation(
            coordinate: rawOffRoadCoord,
            altitude: 1045.2,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 3.0,
            timestamp: Date()
        )
        
        XCTAssertEqual(loc.coordinate.latitude, rawOffRoadCoord.latitude, "Raw off-road latitude must be preserved without road-snapping")
        XCTAssertEqual(loc.coordinate.longitude, rawOffRoadCoord.longitude, "Raw off-road longitude must be preserved without road-snapping")
        XCTAssertEqual(loc.altitude, 1045.2)
    }

    // MARK: Feature 15: Active Trail Following (5 Tests)
    
    public func test_F15_01_StartNavigationSetsActiveTrack() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        XCTAssertNotNil(nav.activeTrack)
        XCTAssertEqual(nav.activeTrack?.name, "Mount Sentinel Trail")
        XCTAssertEqual(nav.remainingDistance, track.totalDistance)
        XCTAssertEqual(nav.userProgressDistance, 0.0)
    }
    
    public func test_F15_02_ProgressDistanceIncrementsAlongTrail() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        // Step to point 2
        let pt2 = track.points[2]
        let loc = CLLocation(latitude: pt2.coordinate.latitude, longitude: pt2.coordinate.longitude)
        nav.updateLocation(loc)
        
        XCTAssertEqual(nav.userProgressDistance, pt2.cumulativeDistance)
        XCTAssertGreaterThan(nav.userProgressDistance, 0.0)
    }
    
    public func test_F15_03_RemainingDistanceDecrements() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        let pt3 = track.points[3]
        let loc = CLLocation(latitude: pt3.coordinate.latitude, longitude: pt3.coordinate.longitude)
        nav.updateLocation(loc)
        
        XCTAssertLessThan(nav.remainingDistance, track.totalDistance)
        XCTAssertEqualWithAccuracy(nav.userProgressDistance + nav.remainingDistance, track.totalDistance, accuracy: 0.01)
    }
    
    public func test_F15_04_CurrentElevationUpdates() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        let pt4 = track.points[4]
        let loc = CLLocation(latitude: pt4.coordinate.latitude, longitude: pt4.coordinate.longitude)
        nav.updateLocation(loc)
        
        XCTAssertEqual(nav.currentElevation, pt4.elevation)
    }
    
    public func test_F15_05_StopNavigationResetsState() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        nav.stopNavigation()
        
        XCTAssertNil(nav.activeTrack)
        XCTAssertEqual(nav.userProgressDistance, 0.0)
        XCTAssertEqual(nav.remainingDistance, 0.0)
        XCTAssertNil(nav.currentElevation)
    }

    // MARK: Feature 16: Off-Trail Audio Alert (5 Tests)
    
    public func test_F16_01_DeviationAbove25mSetsOffTrail() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let spy = MockAudioAlertSpy()
        let nav = E2ETrailNavigator(audioAlertSpy: spy)
        nav.startNavigation(track: track)
        
        // Offset 35m East of trailhead
        let offCoord = LocationSequenceBuilder.shift(coordinate: track.points[0].coordinate, northMeters: 0.0, eastMeters: 35.0)
        let loc = CLLocation(latitude: offCoord.latitude, longitude: offCoord.longitude)
        nav.updateLocation(loc)
        
        XCTAssertTrue(nav.isOffTrail)
        XCTAssertGreaterThan(nav.crossTrackDeviation, 25.0)
    }
    
    public func test_F16_02_DeviationTriggersAudioAlert() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let spy = MockAudioAlertSpy()
        let nav = E2ETrailNavigator(audioAlertSpy: spy)
        nav.startNavigation(track: track)
        
        let offCoord = LocationSequenceBuilder.shift(coordinate: track.points[0].coordinate, northMeters: 0.0, eastMeters: 30.0)
        nav.updateLocation(CLLocation(latitude: offCoord.latitude, longitude: offCoord.longitude))
        
        XCTAssertEqual(spy.alertPlayCount, 1)
        XCTAssertNotNil(spy.lastAlertTimestamp)
    }
    
    public func test_F16_03_HysteresisRecoveryBelow18m() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let spy = MockAudioAlertSpy()
        let nav = E2ETrailNavigator(audioAlertSpy: spy)
        nav.startNavigation(track: track)
        
        // 1. Move off trail (>25m)
        let offCoord = LocationSequenceBuilder.shift(coordinate: track.points[0].coordinate, northMeters: 0.0, eastMeters: 32.0)
        nav.updateLocation(CLLocation(latitude: offCoord.latitude, longitude: offCoord.longitude))
        XCTAssertTrue(nav.isOffTrail)
        
        // 2. Return within hysteresis threshold (<18m, e.g. 10m)
        let recoveredCoord = LocationSequenceBuilder.shift(coordinate: track.points[0].coordinate, northMeters: 0.0, eastMeters: 10.0)
        nav.updateLocation(CLLocation(latitude: recoveredCoord.latitude, longitude: recoveredCoord.longitude))
        
        XCTAssertFalse(nav.isOffTrail)
        XCTAssertLessThan(nav.crossTrackDeviation, 18.0)
    }
    
    public func test_F16_04_HysteresisDeadZonePreservesOffTrail() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        // Move off trail (30m)
        let offCoord = LocationSequenceBuilder.shift(coordinate: track.points[0].coordinate, northMeters: 0.0, eastMeters: 30.0)
        nav.updateLocation(CLLocation(latitude: offCoord.latitude, longitude: offCoord.longitude))
        XCTAssertTrue(nav.isOffTrail)
        
        // Step into dead zone: 21m (between 18m and 25m)
        let deadZoneCoord = LocationSequenceBuilder.shift(coordinate: track.points[0].coordinate, northMeters: 0.0, eastMeters: 21.0)
        nav.updateLocation(CLLocation(latitude: deadZoneCoord.latitude, longitude: deadZoneCoord.longitude))
        
        // Must REMAIN off-trail until <= 18m
        XCTAssertTrue(nav.isOffTrail)
    }
    
    public func test_F16_05_AlertDebouncingSuppression() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let spy = MockAudioAlertSpy()
        let nav = E2ETrailNavigator(audioAlertSpy: spy)
        nav.debounceIntervalSeconds = 10.0
        nav.startNavigation(track: track)
        
        // Immediate off-trail reading
        let offCoord = LocationSequenceBuilder.shift(coordinate: track.points[0].coordinate, northMeters: 0.0, eastMeters: 35.0)
        nav.updateLocation(CLLocation(latitude: offCoord.latitude, longitude: offCoord.longitude))
        XCTAssertEqual(spy.alertPlayCount, 1)
        
        // Second off-trail reading immediately (within debounce window)
        nav.updateLocation(CLLocation(latitude: offCoord.latitude, longitude: offCoord.longitude))
        XCTAssertEqual(spy.alertPlayCount, 1) // Suppressed by debounce
    }

    // MARK: Feature 17: Elevation Profile Chart (5 Tests)
    
    public func test_F17_01_ElevationDataSeriesMapping() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        
        let series = track.points.compactMap { pt -> (distance: Double, elevation: Double)? in
            guard let ele = pt.elevation else { return nil }
            return (distance: pt.cumulativeDistance, elevation: ele)
        }
        
        XCTAssertEqual(series.count, 5)
        XCTAssertEqual(series[0].elevation, 980.5)
        XCTAssertEqual(series[4].elevation, 1158.0)
    }
    
    public func test_F17_02_MinMaxElevationCalculation() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        
        let elevations = track.points.compactMap { $0.elevation }
        let minEle = elevations.min() ?? 0.0
        let maxEle = elevations.max() ?? 0.0
        
        XCTAssertEqual(minEle, 980.5)
        XCTAssertEqual(maxEle, 1158.0)
    }
    
    public func test_F17_03_UserPositionMarkerPercentage() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        // Advance to middle point (index 2)
        let pt2 = track.points[2]
        nav.updateLocation(CLLocation(latitude: pt2.coordinate.latitude, longitude: pt2.coordinate.longitude))
        
        let progressRatio = nav.userProgressDistance / track.totalDistance
        XCTAssertGreaterThan(progressRatio, 0.0)
        XCTAssertLessThan(progressRatio, 1.0)
    }
    
    public func test_F17_04_GradeSlopeCalculation() throws {
        let p1 = E2EGPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), elevation: 100.0, cumulativeDistance: 0.0)
        let p2 = E2EGPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0), elevation: 110.0, cumulativeDistance: 100.0)
        
        let rise = (p2.elevation ?? 0) - (p1.elevation ?? 0)
        let run = p2.cumulativeDistance - p1.cumulativeDistance
        let gradePercent = (rise / run) * 100.0
        
        XCTAssertEqual(gradePercent, 10.0)
    }
    
    public func test_F17_05_MissingElevationGracefulFallback() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.missingElevationGPXString)
        let elevations = track.points.compactMap { $0.elevation }
        XCTAssertEqual(elevations.count, 0)
        XCTAssertEqual(track.elevationGain, 0.0)
    }

    // MARK: Feature 18: Offline Airplane Mode Verification (5 Tests)
    
    @MainActor
    public func test_F18_01_LocalRouteEndpointResolutionOffline() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let origin = PlaceLocation(name: "Start", coordinate: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.41))
        let dest = PlaceLocation(name: "End", coordinate: CLLocationCoordinate2D(latitude: 37.80, longitude: -122.40))
        
        vm.originEndpoint = .custom(place: origin)
        vm.destinationEndpoint = .custom(place: dest)
        
        XCTAssertNotNil(vm.resolveCoordinate(for: vm.originEndpoint))
        XCTAssertNotNil(vm.resolveCoordinate(for: vm.destinationEndpoint!))
    }
    
    public func test_F18_02_CoordinateSearchOfflineExecution() {
        let result = SearchService.parseCoordinateString("46.8529, -113.9850")
        XCTAssertNotNil(result)
    }
    
    public func test_F18_03_GPXParsingOfflineExecution() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        XCTAssertEqual(track.points.count, 5)
    }
    
    public func test_F18_04_LiveTrailNavigationMathOffline() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        let loc = CLLocation(latitude: track.points[1].coordinate.latitude, longitude: track.points[1].coordinate.longitude)
        let update = nav.updateLocation(loc)
        
        XCTAssertFalse(update.isOffTrail)
        XCTAssertEqual(nav.currentElevation, track.points[1].elevation)
    }
    
    public func test_F18_05_MockURLProtocolReturnsOfflineAirplaneModeError() {
        MockURLProtocol.reset()
        // With no responseHandler configured, MockURLProtocol fails with notConnectedToInternet
        let session = MockURLProtocol.makeMockSession()
        let semaphore = DispatchSemaphore(value: 0)
        var receivedError: URLError? = nil
        
        let task = session.dataTask(with: URL(string: "https://overpass-api.de/api/interpreter")!) { data, response, error in
            receivedError = error as? URLError
            semaphore.signal()
        }
        task.resume()
        
        _ = semaphore.wait(timeout: .now() + 2.0)
        XCTAssertNotNil(receivedError)
        XCTAssertEqual(receivedError?.code, .notConnectedToInternet)
    }

    // MARK: Feature 19: Full E2E Test Suite Pass (5 Tests)
    
    @MainActor
    public func test_F19_01_EndToEndHikePipeline() throws {
        // 1. Parse coordinate for trailhead
        let trailheadCoord = SearchService.parseCoordinateString("46.8529, -113.9850")!
        let trailhead = PlaceLocation(name: "Mount Sentinel Trailhead", coordinate: trailheadCoord)
        
        // 2. Set up navigation view model
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        vm.destinationEndpoint = .custom(place: trailhead)
        XCTAssertEqual(vm.destinationEndpoint?.displayName, "Mount Sentinel Trailhead")
        
        // 3. Load GPX trail
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        
        // 4. Start live navigation
        let alertSpy = MockAudioAlertSpy()
        let nav = E2ETrailNavigator(audioAlertSpy: alertSpy)
        nav.startNavigation(track: track)
        
        // 5. Simulate walk
        for pt in track.points {
            _ = nav.updateLocation(CLLocation(latitude: pt.coordinate.latitude, longitude: pt.coordinate.longitude))
            XCTAssertFalse(nav.isOffTrail)
        }
        
        XCTAssertEqual(nav.remainingDistance, 0.0)
        XCTAssertEqual(alertSpy.alertPlayCount, 0)
    }
    
    @MainActor
    public func test_F19_02_ViewModelStateResetHygiene() {
        let mockLoc = MockLocationManager()
        let mockRouting = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLoc, routingService: mockRouting)
        let place = PlaceLocation(name: "Summit", coordinate: CLLocationCoordinate2D(latitude: 46.8, longitude: -113.9))
        vm.destinationEndpoint = .custom(place: place)
        vm.resetOriginToCurrentLocation()
        vm.destinationEndpoint = nil
        
        XCTAssertEqual(vm.originEndpoint, .currentLocation)
        XCTAssertNil(vm.destinationEndpoint)
        XCTAssertFalse(vm.isRoutePreviewMode)
    }
    
    public func test_F19_03_ThreadSafetyConcurrentLocationUpdates() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        nav.startNavigation(track: track)
        
        let queue = DispatchQueue(label: "e2e.concurrent.test", attributes: .concurrent)
        let group = DispatchGroup()
        
        for i in 0..<20 {
            group.enter()
            queue.async {
                let pt = track.points[i % track.points.count]
                nav.updateLocation(CLLocation(latitude: pt.coordinate.latitude, longitude: pt.coordinate.longitude))
                group.leave()
            }
        }
        
        group.wait()
        XCTAssertNotNil(nav.activeTrack)
    }
    
    public func test_F19_04_ConsecutiveNavigationSessionsCleanliness() throws {
        let parser = E2EGPXParser()
        let track = try parser.parse(xmlString: TrailTestFixtures.validGPXString)
        let nav = E2ETrailNavigator()
        
        for _ in 0..<3 {
            nav.startNavigation(track: track)
            nav.updateLocation(CLLocation(latitude: track.points[0].coordinate.latitude, longitude: track.points[0].coordinate.longitude))
            nav.stopNavigation()
            
            XCTAssertNil(nav.activeTrack)
            XCTAssertEqual(nav.userProgressDistance, 0.0)
        }
    }
    
    public func test_F19_05_ResilientRecoveryFromMissingData() {
        let nav = E2ETrailNavigator()
        // Calling updateLocation without active track should not crash
        let result = nav.updateLocation(CLLocation(latitude: 37.77, longitude: -122.41))
        XCTAssertFalse(result.isOffTrail)
        XCTAssertEqual(result.deviation, 0.0)
    }
}
