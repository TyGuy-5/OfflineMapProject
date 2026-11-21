import Foundation
import CoreLocation
import SwiftUI

#if canImport(XCTest)
import XCTest
#else
// Standalone test harness shim for compilation without XCTest framework
@MainActor
open class XCTestCase {
    public required init() {}
    open func setUp() async throws {}
    open func tearDown() async throws {}
    open func setUp() {}
    open func tearDown() {}
}

public var trailNavigatorTestFailuresCount = 0

public func XCTAssert(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition() {
        trailNavigatorTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): \(message())")
    }
}

public func XCTAssertTrue(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    XCTAssert(condition(), message(), file: file, line: line)
}

public func XCTAssertFalse(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    XCTAssert(!condition(), message(), file: file, line: line)
}

public func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    let v1 = a()
    let v2 = b()
    if v1 != v2 {
        trailNavigatorTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): [\(v1)] != [\(v2)] - \(message())")
    }
}

public func XCTAssertNotNil(_ a: @autoclosure () -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    if a() == nil {
        trailNavigatorTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): Value is nil - \(message())")
    }
}

public func XCTAssertNil(_ a: @autoclosure () -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    if a() != nil {
        trailNavigatorTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): Value is not nil - \(message())")
    }
}

public func XCTAssertGreaterThan<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    let v1 = a(), v2 = b()
    if !(v1 > v2) {
        trailNavigatorTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): [\(v1)] not > [\(v2)] - \(message())")
    }
}

public func XCTAssertLessThanOrEqual<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    let v1 = a(), v2 = b()
    if !(v1 <= v2) {
        trailNavigatorTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): [\(v1)] not <= [\(v2)] - \(message())")
    }
}

public func XCTAssertLessThan<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    let v1 = a(), v2 = b()
    if !(v1 < v2) {
        trailNavigatorTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): [\(v1)] not < [\(v2)] - \(message())")
    }
}

public func XCTAssertEqualWithAccuracy(_ a: Double, _ b: Double, accuracy: Double, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if abs(a - b) > accuracy {
        trailNavigatorTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): |\(a) - \(b)| = \(abs(a - b)) > \(accuracy) - \(message)")
    }
}

public func XCTFail(_ message: String, file: StaticString = #file, line: UInt = #line) {
    trailNavigatorTestFailuresCount += 1
    print("❌ XCTFail at \(file):\(line): \(message)")
}
#endif

// MARK: - Test Suite

@MainActor
public class TrailNavigatorTests: XCTestCase {
    
    private var alertService: TrailAudioAlertService!
    private var locationManager: LocationManager!
    private var navigator: TrailNavigator!
    
    open override func setUp() async throws {
        try await super.setUp()
        self.alertService = TrailAudioAlertService(isEnabled: true, cooldownInterval: 30.0)
        self.locationManager = LocationManager()
        self.navigator = TrailNavigator(audioAlertService: alertService, locationManager: locationManager)
    }
    
    open override func tearDown() async throws {
        navigator.stopNavigation()
        locationManager.resetToDefaults()
        try await super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    /// Creates a straight east-west track in Missoula, MT (approx 46.872°N, -113.994°W).
    private func createStraightTrack(pointCount: Int = 5, spacingMeters: Double = 100.0) -> GPXTrack {
        var points: [GPXTrackPoint] = []
        let baseLat = 46.872000
        let baseLon = -113.994000
        let metersPerDegreeLon = 111320.0 * cos(baseLat * Double.pi / 180.0)
        
        var cumulative = 0.0
        for i in 0..<pointCount {
            let lonDelta = (Double(i) * spacingMeters) / metersPerDegreeLon
            let coord = CLLocationCoordinate2D(latitude: baseLat, longitude: baseLon + lonDelta)
            let ele = 900.0 + Double(i) * 10.0 // 900m to 940m
            let pt = GPXTrackPoint(coordinate: coord, elevation: ele, time: Date(), cumulativeDistance: cumulative)
            points.append(pt)
            cumulative += spacingMeters
        }
        
        let totalDist = Double(pointCount - 1) * spacingMeters
        let bounds = GPXBounds(
            minLatitude: baseLat,
            maxLatitude: baseLat,
            minLongitude: baseLon,
            maxLongitude: points.last!.coordinate.longitude
        )
        return GPXTrack(name: "Straight Test Trail", points: points, totalDistance: totalDist, bounds: bounds)
    }
    
    /// Creates a 90-degree corner track (North then East).
    private func createCornerTrack() -> GPXTrack {
        let p0 = CLLocationCoordinate2D(latitude: 46.870000, longitude: -113.994000)
        let p1 = CLLocationCoordinate2D(latitude: 46.871000, longitude: -113.994000) // ~111m North
        let p2 = CLLocationCoordinate2D(latitude: 46.871000, longitude: -113.992000) // ~152m East
        
        let loc0 = CLLocation(latitude: p0.latitude, longitude: p0.longitude)
        let loc1 = CLLocation(latitude: p1.latitude, longitude: p1.longitude)
        let loc2 = CLLocation(latitude: p2.latitude, longitude: p2.longitude)
        
        let d01 = loc0.distance(from: loc1)
        let d12 = loc1.distance(from: loc2)
        
        let pt0 = GPXTrackPoint(coordinate: p0, elevation: 900.0, time: Date(), cumulativeDistance: 0.0)
        let pt1 = GPXTrackPoint(coordinate: p1, elevation: 920.0, time: Date(), cumulativeDistance: d01)
        let pt2 = GPXTrackPoint(coordinate: p2, elevation: 940.0, time: Date(), cumulativeDistance: d01 + d12)
        
        let bounds = GPXBounds(minLatitude: p0.latitude, maxLatitude: p1.latitude, minLongitude: p0.longitude, maxLongitude: p2.longitude)
        return GPXTrack(name: "Corner Trail", points: [pt0, pt1, pt2], totalDistance: d01 + d12, bounds: bounds)
    }
    
    // MARK: - F14: LocationManager Activity Type Tests
    
    public func testLocationManager_ActivityTypeSwitchingAndRestoration() {
        XCTAssertEqual(locationManager.activeActivityType, .automotiveNavigation)
        XCTAssertEqual(locationManager.clLocationManager.activityType, .automotiveNavigation)
        
        // Manual activity type switch
        locationManager.setActivityType(.otherNavigation)
        XCTAssertEqual(locationManager.activeActivityType, .otherNavigation)
        XCTAssertEqual(locationManager.clLocationManager.activityType, .otherNavigation)
        
        // Activate trail navigation -> should switch to .fitness
        locationManager.setTrailNavigationActive(true)
        XCTAssertEqual(locationManager.activeActivityType, .fitness)
        XCTAssertEqual(locationManager.clLocationManager.activityType, .fitness)
        
        // Redundant activation -> retains previously stored type (.otherNavigation)
        locationManager.setTrailNavigationActive(true)
        XCTAssertEqual(locationManager.activeActivityType, .fitness)
        
        // Deactivate trail navigation -> restores to .otherNavigation
        locationManager.setTrailNavigationActive(false)
        XCTAssertEqual(locationManager.activeActivityType, .otherNavigation)
        XCTAssertEqual(locationManager.clLocationManager.activityType, .otherNavigation)
        
        // Reset defaults
        locationManager.resetToDefaults()
        XCTAssertEqual(locationManager.activeActivityType, .automotiveNavigation)
    }
    
    public func testLocationManager_RapidSwitchingIntegrity() {
        for i in 0..<20 {
            let targetType: CLActivityType = (i % 2 == 0) ? .fitness : .automotiveNavigation
            locationManager.setActivityType(targetType)
            XCTAssertEqual(locationManager.activeActivityType, targetType)
            XCTAssertEqual(locationManager.clLocationManager.activityType, targetType)
        }
    }
    
    // MARK: - F15: Cross-Track Projection & Progress Engine Tests
    
    public func testCrossTrackProjection_StraightTrail() {
        let track = createStraightTrack(pointCount: 3, spacingMeters: 100.0)
        navigator.startNavigation(track: track)
        
        // Point exactly on midpoint of first segment
        let midLon = (track.points[0].coordinate.longitude + track.points[1].coordinate.longitude) / 2.0
        let userLocOnTrail = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: track.points[0].coordinate.latitude, longitude: midLon),
            altitude: 905.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        
        guard let progress = navigator.updateLocation(userLocOnTrail) else {
            XCTFail("Failed to get progress from on-trail location")
            return
        }
        
        XCTAssertEqualWithAccuracy(progress.crossTrackDeviation, 0.0, accuracy: 2.0, "Deviation on trail should be ~0m")
        XCTAssertEqualWithAccuracy(progress.distanceTraversed, 50.0, accuracy: 3.0, "Traversed distance should be ~50m")
        XCTAssertEqualWithAccuracy(progress.remainingDistance, 150.0, accuracy: 3.0, "Remaining distance should be ~150m")
        XCTAssertEqualWithAccuracy(progress.progressRatio, 0.25, accuracy: 0.05, "Progress ratio should be ~0.25")
        XCTAssertFalse(progress.isOffTrail)
        XCTAssertEqual(progress.segmentIndex, 0)
    }
    
    public func testCrossTrackProjection_AngledTrail() {
        let track = createCornerTrack()
        navigator.startNavigation(track: track)
        
        // User on the second segment (heading East)
        let p1 = track.points[1].coordinate
        let p2 = track.points[2].coordinate
        let midLon = (p1.longitude + p2.longitude) / 2.0
        let userLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: p1.latitude, longitude: midLon),
            altitude: 930.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        
        guard let progress = navigator.updateLocation(userLoc) else {
            XCTFail("Failed to update location on corner track")
            return
        }
        
        XCTAssertEqual(progress.segmentIndex, 1, "Closest segment should be the second (eastward) leg")
        XCTAssertEqualWithAccuracy(progress.crossTrackDeviation, 0.0, accuracy: 2.0, "Deviation on east leg should be ~0m")
        XCTAssertGreaterThan(progress.distanceTraversed, track.points[1].cumulativeDistance)
        XCTAssertFalse(progress.isOffTrail)
    }
    
    public func testMonotonicRemainingDistanceDecrease() {
        let track = createStraightTrack(pointCount: 6, spacingMeters: 50.0)
        navigator.startNavigation(track: track)
        
        var previousRemaining = Double.infinity
        let baseLat = track.points[0].coordinate.latitude
        let baseLon = track.points[0].coordinate.longitude
        let endLon = track.points.last!.coordinate.longitude
        
        // Step forward across 10 sample positions
        for step in 0...10 {
            let t = Double(step) / 10.0
            let lon = baseLon + t * (endLon - baseLon)
            let loc = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: baseLat, longitude: lon),
                altitude: 900.0,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 5.0,
                timestamp: Date()
            )
            guard let progress = navigator.updateLocation(loc) else {
                XCTFail("Location update returned nil at step \(step)")
                continue
            }
            
            XCTAssertLessThanOrEqual(progress.remainingDistance, previousRemaining + 0.001, "Remaining distance must monotonically decrease as user advances")
            previousRemaining = progress.remainingDistance
        }
        XCTAssertEqualWithAccuracy(previousRemaining, 0.0, accuracy: 2.0, "At final step remaining distance should be ~0m")
    }
    
    public func testInterpolatedElevationCalculations() {
        let p0 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 46.8, longitude: -113.9), elevation: 500.0, cumulativeDistance: 0.0)
        let p1 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 46.801, longitude: -113.9), elevation: 600.0, cumulativeDistance: 111.0)
        let track = GPXTrack(name: "Elevation Track", points: [p0, p1], totalDistance: 111.0)
        
        navigator.startNavigation(track: track)
        
        // Exact midpoint (latitude 46.8005) -> expected elevation: 550.0m
        let midLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 46.8005, longitude: -113.9),
            altitude: 0.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        let progress = navigator.updateLocation(midLoc)
        XCTAssertNotNil(progress?.currentElevation)
        XCTAssertEqualWithAccuracy(progress!.currentElevation!, 550.0, accuracy: 1.0, "Midpoint elevation should interpolate to 550m")
    }
    
    public func testInterpolatedElevation_GracefulFallbackWhenMissing() {
        // Point 0 has elevation, Point 1 has nil
        let p0 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 46.8, longitude: -113.9), elevation: 500.0, cumulativeDistance: 0.0)
        let p1 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 46.801, longitude: -113.9), elevation: nil, cumulativeDistance: 111.0)
        let track = GPXTrack(name: "Partial Ele Track", points: [p0, p1], totalDistance: 111.0)
        
        navigator.startNavigation(track: track)
        let loc = CLLocation(latitude: 46.8005, longitude: -113.9)
        let progress = navigator.updateLocation(loc)
        XCTAssertEqual(progress?.currentElevation, 500.0, "Should fall back to non-nil elevation")
        
        // Both points have nil elevation
        let pNil0 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 46.8, longitude: -113.9), elevation: nil, cumulativeDistance: 0.0)
        let pNil1 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 46.801, longitude: -113.9), elevation: nil, cumulativeDistance: 111.0)
        let trackNoEle = GPXTrack(name: "No Ele Track", points: [pNil0, pNil1], totalDistance: 111.0)
        navigator.startNavigation(track: trackNoEle)
        let progressNoEle = navigator.updateLocation(loc)
        XCTAssertNil(progressNoEle?.currentElevation, "Should be nil when all points lack elevation")
    }
    
    // MARK: - F16: Off-Trail Detection, Debounce, Hysteresis, Audio Alert Tests
    
    public func testOffTrailDetection_GraduatedDeviations() {
        let track = createStraightTrack(pointCount: 3, spacingMeters: 100.0)
        navigator.startNavigation(track: track)
        
        let baseLat = track.points[0].coordinate.latitude
        let midLon = (track.points[0].coordinate.longitude + track.points[1].coordinate.longitude) / 2.0
        let metersPerDegreeLat = 111139.0
        
        // 5m North: firmly on trail
        let loc5m = CLLocation(latitude: baseLat + (5.0 / metersPerDegreeLat), longitude: midLon)
        let p5m = navigator.updateLocation(loc5m)
        XCTAssertEqualWithAccuracy(p5m!.crossTrackDeviation, 5.0, accuracy: 1.0)
        XCTAssertFalse(p5m!.isOffTrail)
        
        // 20m North: still below 25m threshold -> on trail
        let loc20m = CLLocation(latitude: baseLat + (20.0 / metersPerDegreeLat), longitude: midLon)
        let p20m = navigator.updateLocation(loc20m)
        XCTAssertEqualWithAccuracy(p20m!.crossTrackDeviation, 20.0, accuracy: 1.0)
        XCTAssertFalse(p20m!.isOffTrail)
    }
    
    public func testOffTrailDebounce_ThreeConsecutiveFixes() {
        let track = createStraightTrack(pointCount: 3, spacingMeters: 100.0)
        navigator.startNavigation(track: track)
        
        var alertTriggerCount = 0
        alertService.onAlertTriggered = { dev in
            alertTriggerCount += 1
        }
        
        let baseLat = track.points[0].coordinate.latitude
        let midLon = (track.points[0].coordinate.longitude + track.points[1].coordinate.longitude) / 2.0
        let metersPerDegreeLat = 111139.0
        
        // Fix at 35m North (> 25m off-trail threshold)
        let offTrailCoord = CLLocationCoordinate2D(latitude: baseLat + (35.0 / metersPerDegreeLat), longitude: midLon)
        let now = Date()
        
        // Fix 1: >= 25m, but 1st fix -> should NOT trigger off-trail
        let fix1 = CLLocation(coordinate: offTrailCoord, altitude: 900.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: now)
        let p1 = navigator.updateLocation(fix1)
        XCTAssertFalse(p1!.isOffTrail, "Fix 1 should be debounced")
        XCTAssertEqual(alertTriggerCount, 0)
        
        // Fix 2: >= 25m, 2nd fix -> should NOT trigger off-trail
        let fix2 = CLLocation(coordinate: offTrailCoord, altitude: 900.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: now.addingTimeInterval(1.0))
        let p2 = navigator.updateLocation(fix2)
        XCTAssertFalse(p2!.isOffTrail, "Fix 2 should be debounced")
        XCTAssertEqual(alertTriggerCount, 0)
        
        // Fix 3: >= 25m, 3rd consecutive fix -> OFF-TRAIL TRIGGERED!
        let fix3 = CLLocation(coordinate: offTrailCoord, altitude: 900.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: now.addingTimeInterval(2.0))
        let p3 = navigator.updateLocation(fix3)
        XCTAssertTrue(p3!.isOffTrail, "Fix 3 must trigger isOffTrail = true")
        XCTAssertEqual(alertTriggerCount, 1, "Audio alert must be triggered on 3rd fix")
    }
    
    public func testOffTrailDebounce_SustainedDuration() {
        let track = createStraightTrack(pointCount: 3, spacingMeters: 100.0)
        navigator.startNavigation(track: track)
        
        var alertTriggerCount = 0
        alertService.onAlertTriggered = { dev in
            alertTriggerCount += 1
        }
        
        let baseLat = track.points[0].coordinate.latitude
        let midLon = (track.points[0].coordinate.longitude + track.points[1].coordinate.longitude) / 2.0
        let metersPerDegreeLat = 111139.0
        let offTrailCoord = CLLocationCoordinate2D(latitude: baseLat + (35.0 / metersPerDegreeLat), longitude: midLon)
        let t0 = Date()
        
        // Fix 1 at T=0s
        let fix1 = CLLocation(coordinate: offTrailCoord, altitude: 900.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: t0)
        _ = navigator.updateLocation(fix1)
        XCTAssertFalse(navigator.isOffTrail)
        
        // Fix 2 at T=4.5s (duration >= 4.0s) -> should trigger by duration
        let fix2 = CLLocation(coordinate: offTrailCoord, altitude: 900.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: t0.addingTimeInterval(4.5))
        let p2 = navigator.updateLocation(fix2)
        XCTAssertTrue(p2!.isOffTrail, "Sustained duration >= 4.0s must trigger off-trail")
        XCTAssertEqual(alertTriggerCount, 1)
    }
    
    public func testHysteresisBehavior() {
        let track = createStraightTrack(pointCount: 3, spacingMeters: 100.0)
        navigator.startNavigation(track: track)
        
        let baseLat = track.points[0].coordinate.latitude
        let midLon = (track.points[0].coordinate.longitude + track.points[1].coordinate.longitude) / 2.0
        let metersPerDegreeLat = 111139.0
        let now = Date()
        
        // Step 1: Trigger off-trail with 3 fixes at 35m
        let offTrailCoord35m = CLLocationCoordinate2D(latitude: baseLat + (35.0 / metersPerDegreeLat), longitude: midLon)
        for i in 0..<3 {
            let loc = CLLocation(coordinate: offTrailCoord35m, altitude: 900.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: now.addingTimeInterval(Double(i)))
            navigator.updateLocation(loc)
        }
        XCTAssertTrue(navigator.isOffTrail, "Navigator must be in off-trail state")
        
        // Step 2: User moves to 22m deviation (in hysteresis corridor: 18m <= dev < 25m)
        let coord22m = CLLocationCoordinate2D(latitude: baseLat + (22.0 / metersPerDegreeLat), longitude: midLon)
        let loc22m = CLLocation(coordinate: coord22m, altitude: 900.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: now.addingTimeInterval(10.0))
        let p22m = navigator.updateLocation(loc22m)
        XCTAssertTrue(p22m!.isOffTrail, "User at 22m must remain off-trail due to hysteresis (threshold is < 18m)")
        
        // Step 3: User moves to 19m deviation (still >= 18m)
        let coord19m = CLLocationCoordinate2D(latitude: baseLat + (19.0 / metersPerDegreeLat), longitude: midLon)
        let loc19m = CLLocation(coordinate: coord19m, altitude: 900.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: now.addingTimeInterval(15.0))
        let p19m = navigator.updateLocation(loc19m)
        XCTAssertTrue(p19m!.isOffTrail, "User at 19m must remain off-trail")
        
        // Step 4: User recovers to 17m deviation (< 18m recovery threshold) -> RESETS to false!
        let coord17m = CLLocationCoordinate2D(latitude: baseLat + (17.0 / metersPerDegreeLat), longitude: midLon)
        let loc17m = CLLocation(coordinate: coord17m, altitude: 900.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: now.addingTimeInterval(20.0))
        let p17m = navigator.updateLocation(loc17m)
        XCTAssertFalse(p17m!.isOffTrail, "User at 17m (< 18m) must reset isOffTrail to false")
        
        // Step 5: Verify debounce is reset: a single fix at 35m must NOT re-trigger immediately
        let pRecheck = navigator.updateLocation(CLLocation(coordinate: offTrailCoord35m, altitude: 900.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: now.addingTimeInterval(25.0)))
        XCTAssertFalse(pRecheck!.isOffTrail, "Single fix after recovery must not immediately re-trigger off-trail")
    }
    
    public func testDegradedGPSAccuracySuppression() {
        let track = createStraightTrack(pointCount: 3, spacingMeters: 100.0)
        navigator.startNavigation(track: track)
        
        var alertCount = 0
        alertService.onAlertTriggered = { _ in alertCount += 1 }
        
        let baseLat = track.points[0].coordinate.latitude
        let midLon = (track.points[0].coordinate.longitude + track.points[1].coordinate.longitude) / 2.0
        let metersPerDegreeLat = 111139.0
        let offTrailCoord = CLLocationCoordinate2D(latitude: baseLat + (40.0 / metersPerDegreeLat), longitude: midLon)
        let now = Date()
        
        // 5 consecutive fixes at 40m, but with degraded accuracy (45.0m > 30.0m limit)
        for i in 0..<5 {
            let degradedLoc = CLLocation(
                coordinate: offTrailCoord,
                altitude: 900.0,
                horizontalAccuracy: 45.0,
                verticalAccuracy: 10.0,
                timestamp: now.addingTimeInterval(Double(i))
            )
            navigator.updateLocation(degradedLoc)
        }
        XCTAssertFalse(navigator.isOffTrail, "Degraded GPS (accuracy 45m) must suppress off-trail transition")
        XCTAssertEqual(alertCount, 0, "No alerts should fire on degraded GPS")
        
        // Test negative horizontalAccuracy (< 0 is invalid GPS fix in CoreLocation)
        for i in 0..<5 {
            let invalidLoc = CLLocation(
                coordinate: offTrailCoord,
                altitude: 900.0,
                horizontalAccuracy: -1.0,
                verticalAccuracy: -1.0,
                timestamp: now.addingTimeInterval(Double(i + 10))
            )
            navigator.updateLocation(invalidLoc)
        }
        XCTAssertFalse(navigator.isOffTrail, "Invalid GPS (accuracy < 0) must suppress off-trail transition")
        XCTAssertEqual(alertCount, 0)
    }
    
    public func testAudioAlertService_CooldownThrottling() {
        let service = TrailAudioAlertService(isEnabled: true, cooldownInterval: 30.0)
        var playCount = 0
        service.onAlertTriggered = { _ in playCount += 1 }
        
        // First trigger -> fires
        service.triggerOffTrailAlert(deviation: 30.0)
        XCTAssertEqual(playCount, 1)
        XCTAssertEqual(service.alertCount, 1)
        XCTAssertNotNil(service.lastAlertDate)
        
        // Second trigger immediately -> throttled by cooldown
        service.triggerOffTrailAlert(deviation: 35.0)
        XCTAssertEqual(playCount, 1, "Immediate subsequent trigger must be throttled")
        
        // Trigger within cooldown (e.g. 15s) -> throttled
        // Reset cooldown -> immediate trigger succeeds
        service.resetCooldown()
        service.triggerOffTrailAlert(deviation: 40.0)
        XCTAssertEqual(playCount, 2, "Trigger after resetCooldown must succeed")
        
        // Test muting / disabling
        service.isEnabled = false
        service.resetCooldown()
        service.triggerOffTrailAlert(deviation: 50.0)
        XCTAssertEqual(playCount, 2, "Trigger when isEnabled = false must be suppressed")
    }
    
    // MARK: - Lifecycle, Edge Cases & UI Tests
    
    public func testNavigationLifecycle_StartAndStop() {
        let track = createStraightTrack(pointCount: 4, spacingMeters: 50.0)
        locationManager.setActivityType(.automotiveNavigation)
        
        navigator.startNavigation(track: track)
        XCTAssertEqual(navigator.activeTrack?.id, track.id)
        XCTAssertEqual(locationManager.activeActivityType, .fitness, "Starting navigation must enable .fitness")
        XCTAssertEqual(navigator.remainingDistance, track.totalDistance)
        XCTAssertEqual(navigator.userProgressDistance, 0.0)
        
        navigator.stopNavigation()
        XCTAssertNil(navigator.activeTrack)
        XCTAssertEqual(locationManager.activeActivityType, .automotiveNavigation, "Stopping navigation must restore previous mode")
        XCTAssertEqual(navigator.remainingDistance, 0.0)
        XCTAssertEqual(navigator.userProgressDistance, 0.0)
    }
    
    public func testEdgeCase_SinglePointTrack() {
        let pt = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 46.8, longitude: -113.9), elevation: 950.0)
        let track = GPXTrack(name: "Single Point Track", points: [pt], totalDistance: 0.0)
        navigator.startNavigation(track: track)
        
        let loc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 46.8001, longitude: -113.9), altitude: 950.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date())
        guard let progress = navigator.updateLocation(loc) else {
            XCTFail("Single point track should return valid progress")
            return
        }
        
        XCTAssertEqual(progress.distanceTraversed, 0.0)
        XCTAssertEqual(progress.remainingDistance, 0.0)
        XCTAssertEqual(progress.progressRatio, 1.0)
        XCTAssertEqual(progress.currentElevation, 950.0)
        XCTAssertGreaterThan(progress.crossTrackDeviation, 0.0)
    }
    
    public func testEdgeCase_EmptyTrackAndInvalidCoordinates() {
        // Empty track
        let emptyTrack = GPXTrack(name: "Empty Track", points: [], totalDistance: 0.0)
        navigator.startNavigation(track: emptyTrack)
        let loc = CLLocation(latitude: 46.8, longitude: -113.9)
        XCTAssertNil(navigator.updateLocation(loc), "Empty track should return nil progress")
        
        // Track with points, but invalid coordinates passed in location
        let normalTrack = createStraightTrack(pointCount: 3)
        navigator.startNavigation(track: normalTrack)
        
        let nanLoc = CLLocation(latitude: Double.nan, longitude: -113.9)
        XCTAssertNil(navigator.updateLocation(nanLoc), "NaN coordinates must be rejected")
        
        let oobLoc = CLLocation(latitude: 100.0, longitude: -113.9)
        XCTAssertNil(navigator.updateLocation(oobLoc), "Out-of-bounds latitude must be rejected")
    }
    
    public func testTrailProgress_EquatableConformance() {
        let coord = CLLocationCoordinate2D(latitude: 46.8, longitude: -113.9)
        let p1 = TrailProgress(distanceTraversed: 100.0, remainingDistance: 200.0, progressRatio: 0.33, currentElevation: 900.0, crossTrackDeviation: 4.5, isOffTrail: false, closestCoordinate: coord, segmentIndex: 1)
        let p2 = TrailProgress(distanceTraversed: 100.0, remainingDistance: 200.0, progressRatio: 0.33, currentElevation: 900.0, crossTrackDeviation: 4.5, isOffTrail: false, closestCoordinate: coord, segmentIndex: 1)
        let pDiff = TrailProgress(distanceTraversed: 120.0, remainingDistance: 180.0, progressRatio: 0.40, currentElevation: 910.0, crossTrackDeviation: 10.0, isOffTrail: false, closestCoordinate: coord, segmentIndex: 1)
        
        XCTAssertEqual(p1, p2)
        XCTAssertTrue(p1 != pDiff)
    }
    
    public func testUIViews_InstantiationAndState() {
        let track = createStraightTrack(pointCount: 4)
        navigator.startNavigation(track: track)
        
        // ElevationProfileView with valid points
        let profileView = ElevationProfileView(points: track.points, userProgressDistance: 50.0, currentElevation: 910.0)
        XCTAssertNotNil(profileView.body)
        
        // ElevationProfileView with empty points
        let emptyProfileView = ElevationProfileView(points: [], userProgressDistance: 0.0, currentElevation: nil)
        XCTAssertNotNil(emptyProfileView.body)
        
        // TrailNavigationHUD
        var stopCallbackCalled = false
        let hud = TrailNavigationHUD(navigator: navigator) {
            stopCallbackCalled = true
        }
        XCTAssertNotNil(hud.body)
        XCTAssertFalse(stopCallbackCalled)
    }
    
    public func testNegativeElevationInterpolation() {
        let p0 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 36.5, longitude: -116.8), elevation: -80.0, cumulativeDistance: 0.0)
        let p1 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 36.501, longitude: -116.8), elevation: -40.0, cumulativeDistance: 111.0)
        let track = GPXTrack(name: "Sub-sea Trail", points: [p0, p1], totalDistance: 111.0)
        navigator.startNavigation(track: track)
        
        // Midpoint at latitude 36.5005 -> expected elevation: -60.0m
        let midLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 36.5005, longitude: -116.8),
            altitude: -60.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        let progress = navigator.updateLocation(midLoc)
        XCTAssertNotNil(progress?.currentElevation)
        XCTAssertEqualWithAccuracy(progress!.currentElevation!, -60.0, accuracy: 1.0, "Sub-sea elevation should interpolate to -60m")
    }
    
    public func testInterspersedDegradedGPSResetsDebounce() {
        let track = createStraightTrack(pointCount: 3, spacingMeters: 100.0)
        navigator.startNavigation(track: track)
        
        let baseLat = track.points[0].coordinate.latitude
        let midLon = (track.points[0].coordinate.longitude + track.points[1].coordinate.longitude) / 2.0
        let metersPerDegreeLat = 111139.0
        let offTrailCoord = CLLocationCoordinate2D(latitude: baseLat + (35.0 / metersPerDegreeLat), longitude: midLon)
        let now = Date()
        
        // Fix 1: off-trail with accurate GPS (accuracy 5m) -> count = 1
        let fix1 = CLLocation(coordinate: offTrailCoord, altitude: 900.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: now)
        _ = navigator.updateLocation(fix1)
        XCTAssertFalse(navigator.isOffTrail)
        
        // Fix 2: degraded GPS (accuracy 45m > 30m) -> must reset debounce count!
        let fixDegraded = CLLocation(coordinate: offTrailCoord, altitude: 900.0, horizontalAccuracy: 45.0, verticalAccuracy: 5.0, timestamp: now.addingTimeInterval(1.0))
        _ = navigator.updateLocation(fixDegraded)
        XCTAssertFalse(navigator.isOffTrail)
        
        // Fix 3: off-trail with accurate GPS -> should be count = 1, NOT count = 3!
        let fix3 = CLLocation(coordinate: offTrailCoord, altitude: 900.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: now.addingTimeInterval(2.0))
        _ = navigator.updateLocation(fix3)
        XCTAssertFalse(navigator.isOffTrail, "Degraded GPS fix must have reset debounce counter, preventing premature alert")
    }
    
    public func testSwitchbackHairpinTrailProjection() {
        // Switchback: East 100m, North 10m, West 100m
        let p0 = CLLocationCoordinate2D(latitude: 46.8000, longitude: -113.900)
        let p1 = CLLocationCoordinate2D(latitude: 46.8000, longitude: -113.898) // ~150m East
        let p2 = CLLocationCoordinate2D(latitude: 46.8001, longitude: -113.898) // ~11m North
        let p3 = CLLocationCoordinate2D(latitude: 46.8001, longitude: -113.900) // ~150m West
        
        let loc0 = CLLocation(latitude: p0.latitude, longitude: p0.longitude)
        let loc1 = CLLocation(latitude: p1.latitude, longitude: p1.longitude)
        let loc2 = CLLocation(latitude: p2.latitude, longitude: p2.longitude)
        let loc3 = CLLocation(latitude: p3.latitude, longitude: p3.longitude)
        
        let d01 = loc0.distance(from: loc1)
        let d12 = loc1.distance(from: loc2)
        let d23 = loc2.distance(from: loc3)
        
        let pt0 = GPXTrackPoint(coordinate: p0, cumulativeDistance: 0.0)
        let pt1 = GPXTrackPoint(coordinate: p1, cumulativeDistance: d01)
        let pt2 = GPXTrackPoint(coordinate: p2, cumulativeDistance: d01 + d12)
        let pt3 = GPXTrackPoint(coordinate: p3, cumulativeDistance: d01 + d12 + d23)
        
        let track = GPXTrack(name: "Switchback Trail", points: [pt0, pt1, pt2, pt3], totalDistance: d01 + d12 + d23)
        navigator.startNavigation(track: track)
        
        // User on first leg (heading East, closer to segment 0)
        let userFirstLeg = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 46.79998, longitude: -113.899), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
        let prog1 = navigator.updateLocation(userFirstLeg)
        XCTAssertEqual(prog1?.segmentIndex, 0, "User should match segment 0 on the first switchback leg")
        
        // User on return leg (heading West, closer to segment 2)
        let userReturnLeg = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 46.80012, longitude: -113.899), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
        let prog2 = navigator.updateLocation(userReturnLeg)
        XCTAssertEqual(prog2?.segmentIndex, 2, "User should match segment 2 on the return switchback leg")
    }
    
    public func testLargeTrackScalabilityAndPerformance() {
        // Track with 500 points
        var points: [GPXTrackPoint] = []
        var cum = 0.0
        for i in 0..<500 {
            let lat = 46.8 + Double(i) * 0.0001
            let lon = -113.9 + Double(i) * 0.00005
            let pt = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), elevation: 1000.0 + Double(i), cumulativeDistance: cum)
            points.append(pt)
            cum += 12.0
        }
        let largeTrack = GPXTrack(name: "Large Track", points: points, totalDistance: cum)
        navigator.startNavigation(track: largeTrack)
        
        let start = Date()
        for i in stride(from: 0, to: 500, by: 25) {
            let samplePt = points[i]
            let loc = CLLocation(coordinate: samplePt.coordinate, altitude: 1000.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date())
            let prog = navigator.updateLocation(loc)
            XCTAssertNotNil(prog)
            XCTAssertFalse(prog!.isOffTrail)
        }
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 2.0, "500-point track projections must execute under 2 seconds")
    }
    
    public func testLocationManager_DelegateLocationUpdates() async {
        let lm = LocationManager()
        let testLocation = CLLocation(latitude: 46.872, longitude: -113.994)
        
        lm.locationManager(lm.clLocationManager, didUpdateLocations: [testLocation])
        
        // Allow MainActor Task to complete
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(lm.currentLocation?.coordinate.latitude, testLocation.coordinate.latitude)
        XCTAssertEqual(lm.currentLocation?.coordinate.longitude, testLocation.coordinate.longitude)
    }
}
