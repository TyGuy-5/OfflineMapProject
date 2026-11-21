#if canImport(XCTest)
import XCTest
#else
import Foundation
public class XCTestCase {
    public init() {}
}
public func XCTAssert(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    assert(condition(), message(), file: file, line: line)
}
public func XCTAssertTrue(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    assert(condition(), message(), file: file, line: line)
}
public func XCTAssertFalse(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    assert(!condition(), message(), file: file, line: line)
}
public func XCTAssertEqual<T: Equatable>(_ lhs: @autoclosure () -> T, _ rhs: @autoclosure () -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    let l = lhs(), r = rhs()
    assert(l == r, "Expected \(l) == \(r). \(message())", file: file, line: line)
}
public func XCTAssertEqual<T: FloatingPoint>(_ lhs: @autoclosure () -> T, _ rhs: @autoclosure () -> T, accuracy: T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    let l = lhs(), r = rhs()
    assert(abs(l - r) <= accuracy, "Expected \(l) == \(r) within \(accuracy). \(message())", file: file, line: line)
}
public func XCTAssertEqual<T: FloatingPoint>(_ lhs: @autoclosure () -> T?, _ rhs: @autoclosure () -> T, accuracy: T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    guard let l = lhs() else {
        assert(false, "Expected non-nil value, got nil. \(message())", file: file, line: line)
        return
    }
    let r = rhs()
    assert(abs(l - r) <= accuracy, "Expected \(l) == \(r) within \(accuracy). \(message())", file: file, line: line)
}
public func XCTAssertNotNil(_ value: @autoclosure () -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    assert(value() != nil, message(), file: file, line: line)
}
public func XCTAssertNil(_ value: @autoclosure () -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    assert(value() == nil, message(), file: file, line: line)
}
public func XCTAssertGreaterThanOrEqual<T: Comparable>(_ lhs: @autoclosure () -> T, _ rhs: @autoclosure () -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    assert(lhs() >= rhs(), message(), file: file, line: line)
}
public func XCTAssertLessThan<T: Comparable>(_ lhs: @autoclosure () -> T, _ rhs: @autoclosure () -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    assert(lhs() < rhs(), message(), file: file, line: line)
}
public func XCTFail(_ message: String = "", file: StaticString = #file, line: UInt = #line) {
    assert(false, message, file: file, line: line)
}
#endif

import CoreLocation

#if canImport(MyOfflineMapApp)
@testable import MyOfflineMapApp
#endif

// MARK: - Test Mocks

public final class MockLocationManager: LocationManagerProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _currentLocation: CLLocation?

    public var currentLocation: CLLocation? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _currentLocation
        }
        set {
            lock.lock()
            _currentLocation = newValue
            lock.unlock()
        }
    }

    public init(currentLocation: CLLocation? = nil) {
        self._currentLocation = currentLocation
    }
}

public final class MockRoutingService: RoutingServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _calculateRouteCallCount: Int = 0
    private var _lastOrigin: CLLocationCoordinate2D?
    private var _lastDestination: CLLocationCoordinate2D?
    private var _lastCosting: String?

    public var calculateRouteCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _calculateRouteCallCount
    }

    public var lastOrigin: CLLocationCoordinate2D? {
        lock.lock()
        defer { lock.unlock() }
        return _lastOrigin
    }

    public var lastDestination: CLLocationCoordinate2D? {
        lock.lock()
        defer { lock.unlock() }
        return _lastDestination
    }

    public var lastCosting: String? {
        lock.lock()
        defer { lock.unlock() }
        return _lastCosting
    }

    public var simulatedDelayNanoseconds: UInt64 = 0
    public var shouldThrowError: Bool = false

    public init() {}

    private func recordCall(origin: CLLocationCoordinate2D, destination: CLLocationCoordinate2D, costing: String) -> (delay: UInt64, throwErr: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _calculateRouteCallCount += 1
        _lastOrigin = origin
        _lastDestination = destination
        _lastCosting = costing
        return (simulatedDelayNanoseconds, shouldThrowError)
    }

    public func calculateRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        costing: String
    ) async throws -> RouteResponse {
        let config = recordCall(origin: origin, destination: destination, costing: costing)

        if config.delay > 0 {
            try await Task.sleep(nanoseconds: config.delay)
        }

        if config.throwErr {
            throw RoutingError.routeNotFound
        }

        let originLoc = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let destLoc = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let dist = originLoc.distance(from: destLoc)

        return RouteResponse(
            coordinates: [origin, destination],
            distanceMeters: dist,
            durationSeconds: dist / 13.4,
            steps: [RouteStep(instruction: "Mock Step", distanceMeters: dist, durationSeconds: dist / 13.4)],
            summary: "Mock Route"
        )
    }
}

// MARK: - RoutePlanningTests

public final class RoutePlanningTests: XCTestCase {

    // MARK: - RouteEndpoint & PlaceLocation Tests

    public func testPlaceLocationEqualityAndHashing() {
        let coord1 = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let coord2 = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let place1 = PlaceLocation(id: "place-1", name: "SF", subtitle: "City", coordinate: coord1)
        let place2 = PlaceLocation(id: "place-1", name: "SF", subtitle: "City", coordinate: coord2)

        XCTAssertEqual(place1, place2)
        XCTAssertEqual(place1.hashValue, place2.hashValue)

        var set = Set<PlaceLocation>()
        set.insert(place1)
        XCTAssertTrue(set.contains(place2))
    }

    public func testPlaceLocationNegativeZeroEquivalence() {
        let p1 = PlaceLocation(id: "zero", name: "Null Island", coordinate: CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0))
        let p2 = PlaceLocation(id: "zero", name: "Null Island", coordinate: CLLocationCoordinate2D(latitude: -0.0, longitude: -0.0))

        XCTAssertEqual(p1, p2)
        XCTAssertEqual(p1.hashValue, p2.hashValue)
    }

    public func testRouteEndpointProperties() {
        let current = RouteEndpoint.currentLocation
        XCTAssertTrue(current.isCurrentLocation)
        XCTAssertEqual(current.displayName, "Current Location")

        let place = PlaceLocation(id: "place-2", name: "Oakland", coordinate: CLLocationCoordinate2D(latitude: 37.8044, longitude: -122.2712))
        let custom = RouteEndpoint.custom(place: place)
        XCTAssertFalse(custom.isCurrentLocation)
        XCTAssertEqual(custom.displayName, "Oakland")
    }

    // MARK: - Coordinate Parsing Tests

    public func testValidCoordinateParsing() {
        let testCases: [(String, Double, Double)] = [
            ("37.7749, -122.4194", 37.7749, -122.4194),
            ("37.7749,-122.4194", 37.7749, -122.4194),
            ("  45.5152 ,  -122.6784  ", 45.5152, -122.6784),
            ("0, 0", 0.0, 0.0),
            ("-33.8688, 151.2093", -33.8688, 151.2093),
            ("90.0, 180.0", 90.0, 180.0),
            ("-90.0, -180.0", -90.0, -180.0),
            ("+37.7749, -122.4194", 37.7749, -122.4194),
            ("37.7749, +122.4194", 37.7749, 122.4194),
            ("+45.5152, +122.6784", 45.5152, 122.6784)
        ]

        for (query, expectedLat, expectedLon) in testCases {
            let parsed = SearchService.parseCoordinateString(query)
            XCTAssertNotNil(parsed, "Failed to parse valid coordinate string: \(query)")
            if let coord = parsed {
                XCTAssertEqual(coord.latitude, expectedLat, accuracy: 0.0001)
                XCTAssertEqual(coord.longitude, expectedLon, accuracy: 0.0001)
            }
        }
    }

    public func testInvalidCoordinateParsing() {
        let invalidInputs = [
            "91.0, -122.4194",       // Latitude > 90
            "-95.0, -122.4194",      // Latitude < -90
            "37.7749, 181.0",        // Longitude > 180
            "37.7749, -190.0",       // Longitude < -180
            "37.7749",               // Missing longitude
            ", -122.4194",           // Missing latitude
            "abc, def",              // Non-numeric
            "",                      // Empty
            "   ",                   // Whitespace only
            "37.7749, -122.4194, 100", // Extra component
            "37.7749, -122.4194\n",  // Trailing newline
            "\n37.7749, -122.4194",  // Leading newline
            "37.7749; -122.4194"     // Semicolon separator
        ]

        for input in invalidInputs {
            let parsed = SearchService.parseCoordinateString(input)
            XCTAssertNil(parsed, "Expected nil for invalid coordinate input: \(input)")
        }
    }

    public func testCoordinateReDoSPerformance() {
        let longMalformedString = String(repeating: "9", count: 10_000) + ", " + String(repeating: "9", count: 10_000)
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = SearchService.parseCoordinateString(longMalformedString)
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime

        XCTAssertNil(result)
        XCTAssertLessThan(elapsed, 0.05, "Regex took too long to fail on large input; potential ReDoS vulnerability!")
    }

    public func testSearchServiceSyntheticCoordinateResult() async {
        let searchService = SearchService()
        let query = "37.7749, -122.4194"
        let results = await searchService.search(query: query)

        XCTAssertFalse(results.isEmpty)
        guard let first = results.first else { return }
        XCTAssertEqual(first.title, "Coordinates")
        XCTAssertEqual(first.coordinate.latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(first.coordinate.longitude, -122.4194, accuracy: 0.0001)
    }

    // MARK: - Genuine NavigationViewModel Business Logic Tests

    @MainActor
    public func testNavigationViewModelCoordinateResolution() {
        let mockLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let mockLocationManager = MockLocationManager(currentLocation: mockLocation)
        let mockRoutingService = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLocationManager, routingService: mockRoutingService)

        // Test currentLocation resolution
        guard let resolvedCurrent = vm.resolveCoordinate(for: .currentLocation) else {
            XCTFail("Failed to resolve current location coordinate")
            return
        }
        XCTAssertEqual(resolvedCurrent.latitude, 37.7749, accuracy: 0.0001)
        XCTAssertEqual(resolvedCurrent.longitude, -122.4194, accuracy: 0.0001)

        // Test custom place resolution
        let customPlace = PlaceLocation(id: "custom", name: "Tahoe", coordinate: CLLocationCoordinate2D(latitude: 39.0968, longitude: -120.0324))
        guard let resolvedCustom = vm.resolveCoordinate(for: .custom(place: customPlace)) else {
            XCTFail("Failed to resolve custom place coordinate")
            return
        }
        XCTAssertEqual(resolvedCustom.latitude, 39.0968, accuracy: 0.0001)
        XCTAssertEqual(resolvedCustom.longitude, -120.0324, accuracy: 0.0001)
    }

    @MainActor
    public func testNavigationViewModelSwapOriginDestination() async {
        let mockLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let mockLocationManager = MockLocationManager(currentLocation: mockLocation)
        let mockRoutingService = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLocationManager, routingService: mockRoutingService)

        let destPlace = PlaceLocation(id: "dest", name: "San Jose", coordinate: CLLocationCoordinate2D(latitude: 37.3382, longitude: -121.8863))
        vm.destinationEndpoint = .custom(place: destPlace)
        vm.originText = "San Francisco"
        vm.destinationText = "San Jose"

        // Execute swap
        vm.swapOriginDestination()

        // Assert endpoints were swapped on the view model
        XCTAssertEqual(vm.originEndpoint.displayName, "San Jose")
        XCTAssertTrue(vm.destinationEndpoint?.isCurrentLocation == true)

        // Assert UI string bindings were synchronized
        XCTAssertEqual(vm.originText, "San Jose")
        XCTAssertEqual(vm.destinationText, "San Francisco")

        // Wait briefly for asynchronous route calculation task to finish
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertGreaterThanOrEqual(mockRoutingService.calculateRouteCallCount, 1)
        XCTAssertEqual(mockRoutingService.lastOrigin?.latitude, 37.3382, accuracy: 0.0001)
        XCTAssertEqual(mockRoutingService.lastDestination?.latitude, 37.7749, accuracy: 0.0001)
    }

    @MainActor
    public func testNavigationViewModelResetOriginToCurrentLocation() async {
        let mockLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let mockLocationManager = MockLocationManager(currentLocation: mockLocation)
        let mockRoutingService = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLocationManager, routingService: mockRoutingService)

        let remotePlace = PlaceLocation(id: "remote", name: "Reno", coordinate: CLLocationCoordinate2D(latitude: 39.5296, longitude: -119.8138))
        vm.originEndpoint = .custom(place: remotePlace)
        vm.originText = "Reno"
        vm.isRoutePreviewMode = true

        // Simulate GPS temporarily becoming nil
        mockLocationManager.currentLocation = nil

        // Reset origin to current location
        vm.resetOriginToCurrentLocation()

        // Assert origin was reset and preview mode was immediately cleared
        XCTAssertTrue(vm.originEndpoint.isCurrentLocation)
        XCTAssertEqual(vm.originText, "")
        XCTAssertFalse(vm.isRoutePreviewMode, "resetOriginToCurrentLocation must clear isRoutePreviewMode immediately even if GPS is nil!")
    }

    @MainActor
    public func testNavigationViewModelIsRemoteOriginCalculation() {
        let userLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let mockLocationManager = MockLocationManager(currentLocation: userLocation)
        let mockRoutingService = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLocationManager, routingService: mockRoutingService)

        // 1. Current location origin is never remote
        vm.originEndpoint = .currentLocation
        XCTAssertFalse(vm.isRemoteOrigin(thresholdMeters: 200.0))

        // 2. Custom origin within 100m (~0.0009 deg lat) is near
        let nearCoord = CLLocationCoordinate2D(latitude: 37.7757, longitude: -122.4194)
        let nearPlace = PlaceLocation(id: "near", name: "Near Place", coordinate: nearCoord)
        vm.originEndpoint = .custom(place: nearPlace)
        XCTAssertFalse(vm.isRemoteOrigin(thresholdMeters: 200.0))

        // 3. Custom origin 500m away is remote
        let remoteCoord = CLLocationCoordinate2D(latitude: 37.7794, longitude: -122.4194)
        let remotePlace = PlaceLocation(id: "remote", name: "Remote Place", coordinate: remoteCoord)
        vm.originEndpoint = .custom(place: remotePlace)
        XCTAssertTrue(vm.isRemoteOrigin(thresholdMeters: 200.0))
    }

    @MainActor
    public func testNavigationViewModelPreviewModeLifecycleTransition() {
        // User starts at San Francisco (37.7749, -122.4194)
        let initialUserLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let mockLocationManager = MockLocationManager(currentLocation: initialUserLocation)
        let mockRoutingService = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLocationManager, routingService: mockRoutingService)

        // Remote origin in Berkeley (~16km away)
        let remoteCoord = CLLocationCoordinate2D(latitude: 37.8715, longitude: -122.2730)
        let originPlace = PlaceLocation(id: "origin", name: "Berkeley", coordinate: remoteCoord)
        vm.originEndpoint = .custom(place: originPlace)

        let destCoord = CLLocationCoordinate2D(latitude: 37.8044, longitude: -122.2712)
        let destPlace = PlaceLocation(id: "dest", name: "Oakland", coordinate: destCoord)
        vm.destinationEndpoint = .custom(place: destPlace)

        // Set in preview mode
        vm.isRoutePreviewMode = true

        // 1. User updates location still remote from origin (SF -> SF waterfront, ~15km from Berkeley)
        let stillRemoteLocation = CLLocation(latitude: 37.7900, longitude: -122.4000)
        vm.handleLocationUpdate(stillRemoteLocation)

        // Assert preview mode is still true and rerouting was suppressed
        XCTAssertTrue(vm.isRoutePreviewMode, "Preview mode should remain active while user is remote from origin")
        XCTAssertEqual(vm.rerouteCount, 0, "Off-route rerouting must be suppressed while in preview mode")

        // 2. User arrives near Berkeley origin (< 200m away, e.g. Berkeley coordinate + ~50m)
        let arrivedLocation = CLLocation(latitude: 37.8718, longitude: -122.2730)
        vm.handleLocationUpdate(arrivedLocation)

        // Assert preview mode automatically transitions to false!
        XCTAssertFalse(vm.isRoutePreviewMode, "isRoutePreviewMode must automatically transition to false when user arrives within 200m of origin!")
    }

    @MainActor
    public func testNavigationViewModelRouteToStart() {
        let mockLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let mockLocationManager = MockLocationManager(currentLocation: mockLocation)
        let mockRoutingService = MockRoutingService()
        let vm = NavigationViewModel(locationManager: mockLocationManager, routingService: mockRoutingService)

        let tahoe = PlaceLocation(id: "tahoe", name: "Lake Tahoe", coordinate: CLLocationCoordinate2D(latitude: 39.0968, longitude: -120.0324))
        let reno = PlaceLocation(id: "reno", name: "Reno", coordinate: CLLocationCoordinate2D(latitude: 39.5296, longitude: -119.8138))

        vm.originEndpoint = .custom(place: tahoe)
        vm.destinationEndpoint = .custom(place: reno)
        vm.originText = "Lake Tahoe"
        vm.destinationText = "Reno"
        vm.isRoutePreviewMode = true

        // User taps "Route to Start"
        vm.routeToStart()

        // Destination should now be Lake Tahoe, origin should be Current Location, and preview mode should be cleared
        XCTAssertEqual(vm.destinationEndpoint?.displayName, "Lake Tahoe")
        XCTAssertTrue(vm.originEndpoint.isCurrentLocation)
        XCTAssertFalse(vm.isRoutePreviewMode)
        XCTAssertEqual(vm.destinationText, "Lake Tahoe")
        XCTAssertEqual(vm.originText, "")
    }

    @MainActor
    public func testNavigationViewModelConcurrencyCancellation() async {
        let mockLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        let mockLocationManager = MockLocationManager(currentLocation: mockLocation)
        let mockRoutingService = MockRoutingService()
        mockRoutingService.simulatedDelayNanoseconds = 100_000_000 // 100ms
        let vm = NavigationViewModel(locationManager: mockLocationManager, routingService: mockRoutingService)

        let placeA = PlaceLocation(id: "A", name: "Point A", coordinate: CLLocationCoordinate2D(latitude: 37.77, longitude: -122.41))
        let placeB = PlaceLocation(id: "B", name: "Point B", coordinate: CLLocationCoordinate2D(latitude: 37.80, longitude: -122.27))

        vm.originEndpoint = .custom(place: placeA)
        vm.destinationEndpoint = .custom(place: placeB)

        // Rapidly swap twice
        vm.swapOriginDestination()
        // Wait 10ms, then swap again
        try? await Task.sleep(nanoseconds: 10_000_000)
        vm.swapOriginDestination()

        // Wait for all tasks to complete
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Endpoints should match the second swap (Point A -> Point B)
        XCTAssertEqual(vm.originEndpoint.displayName, "Point A")
        XCTAssertEqual(vm.destinationEndpoint?.displayName, "Point B")
    }
}
