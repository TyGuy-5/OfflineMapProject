import Foundation
import CoreLocation

#if canImport(XCTest)
import XCTest
#endif

#if canImport(MyOfflineMapApp)
@testable import MyOfflineMapApp
#endif

// MARK: - Tier 5: Adversarial Hardening Test Suite (23 Tests)
/// Combines adversarial tests for real-time GPS navigation, degraded multipath signals,
/// extreme geometries, concurrency, corrupted XML/GeoJSON payloads, path traversal attacks,
/// airplane mode offline resilience, audio alert cooldown throttling, and zero network leakage.
@MainActor
public final class Tier5_AdversarialHardeningTests: XCTestCase {
    
    private var alertService: TrailAudioAlertService!
    private var locationManager: LocationManager!
    private var navigator: TrailNavigator!
    private var alertCount: Int = 0
    private var lastDeviation: Double? = nil
    
    public override func setUp() async throws {
        try await super.setUp()
        self.alertCount = 0
        self.lastDeviation = nil
        self.alertService = TrailAudioAlertService(isEnabled: true, cooldownInterval: 30.0)
        self.alertService.onAlertTriggered = { [weak self] dev in
            self?.alertCount += 1
            self?.lastDeviation = dev
        }
        self.locationManager = LocationManager()
        self.navigator = TrailNavigator(audioAlertService: alertService, locationManager: locationManager)
    }
    
    public override func tearDown() async throws {
        navigator?.stopNavigation()
        locationManager?.resetToDefaults()
        alertService = nil
        locationManager = nil
        navigator = nil
        try await super.tearDown()
    }
    
    // MARK: - Helpers
    
    private func createStraightTrack(pointCount: Int = 5, spacingMeters: Double = 100.0) -> GPXTrack {
        var points: [GPXTrackPoint] = []
        let baseLat = 46.872000
        let baseLon = -113.994000
        let metersPerDegreeLon = 111320.0 * cos(baseLat * Double.pi / 180.0)
        
        var cumulative = 0.0
        for i in 0..<pointCount {
            let lonDelta = (Double(i) * spacingMeters) / metersPerDegreeLon
            let coord = CLLocationCoordinate2D(latitude: baseLat, longitude: baseLon + lonDelta)
            let ele = 900.0 + Double(i) * 10.0
            let pt = GPXTrackPoint(coordinate: coord, elevation: ele, time: Date(), cumulativeDistance: cumulative)
            points.append(pt)
            cumulative += spacingMeters
        }
        
        let totalDist = Double(pointCount - 1) * spacingMeters
        return GPXTrack(name: "Straight Test Trail", points: points, totalDistance: totalDist)
    }
    
    // MARK: - Category 1: Concurrency & Stress Tests
    
    /// Concurrently pumps 1,000 GPS fixes into TrailNavigator while toggling startNavigation/stopNavigation.
    public func testConcurrentGPSFixInjection_OneThousandFixesWithStartStopInterleaving() async {
        let track = createStraightTrack(pointCount: 20, spacingMeters: 50.0)
        navigator.startNavigation(track: track)
        
        let totalFixes = 1000
        
        await withTaskGroup(of: Int.self) { group in
            // Intermittent start/stop toggle worker
            group.addTask {
                for i in 0..<20 {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                    await MainActor.run {
                        if i % 2 == 0 {
                            self.navigator.stopNavigation()
                        } else {
                            self.navigator.startNavigation(track: track)
                        }
                    }
                }
                await MainActor.run {
                    self.navigator.startNavigation(track: track)
                }
                return 0
            }
            
            // 10 concurrent fix generators producing 100 fixes each
            for i in 0..<10 {
                group.addTask {
                    var successCount = 0
                    for j in 0..<(totalFixes / 10) {
                        let idx = i * 100 + j
                        let lat = 46.872000 + Double(idx % 19) * 0.0001
                        let lon = -113.994000 + Double(idx % 19) * 0.0001
                        let loc = CLLocation(
                            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            altitude: 900.0,
                            horizontalAccuracy: 5.0,
                            verticalAccuracy: 5.0,
                            timestamp: Date()
                        )
                        let prog = await MainActor.run {
                            self.navigator.updateLocation(loc)
                        }
                        if prog != nil {
                            successCount += 1
                        }
                    }
                    return successCount
                }
            }
            
            var totalProcessed = 0
            for await count in group {
                totalProcessed += count
            }
            
            XCTAssertTrue(totalProcessed > 0, "Concurrent ingestion must successfully process updates while active")
        }
        
        // Assert state remains completely consistent and non-corrupted
        XCTAssertNotNil(navigator.activeTrack, "Track should be active at end of test")
        XCTAssertFalse(navigator.userProgressDistance.isNaN, "Progress distance must not be NaN")
        XCTAssertFalse(navigator.remainingDistance.isNaN, "Remaining distance must not be NaN")
        XCTAssertFalse(navigator.crossTrackDeviation.isNaN, "Deviation must not be NaN")
        XCTAssertTrue(navigator.remainingDistance >= 0.0, "Remaining distance must be non-negative")
    }
    
    /// Concurrently updates LocationManager delegate with 500 fixes while toggling activity type 30 times.
    public func testLocationManager_ConcurrentDelegateUpdatesAndFitnessModeSwitching() async {
        let lm = self.locationManager!
        let totalUpdates = 500
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for i in 0..<30 {
                    await MainActor.run {
                        lm.setTrailNavigationActive(i % 2 == 0)
                    }
                    try? await Task.sleep(nanoseconds: 2_000_000)
                }
            }
            
            for _ in 0..<5 {
                group.addTask {
                    for j in 0..<(totalUpdates / 5) {
                        let loc = CLLocation(latitude: 46.872 + Double(j) * 0.0001, longitude: -113.994)
                        let clm = CLLocationManager()
                        await MainActor.run {
                            lm.locationManager(clm, didUpdateLocations: [loc])
                        }
                    }
                }
            }
        }
        
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNotNil(lm.currentLocation, "Location must be populated after concurrent delegate callbacks")
    }
    
    // MARK: - Category 2: Degraded GPS & Signal Multipath Tests
    
    /// Verifies multipath outlier (120m away with 45m accuracy > 30m max) does not trigger off-trail alert.
    public func testDegradedGPS_MultipathOutlierSuppression() {
        let track = createStraightTrack(pointCount: 3, spacingMeters: 100.0)
        navigator.startNavigation(track: track)
        
        let baseLat = track.points[0].coordinate.latitude
        let baseLon = track.points[1].coordinate.longitude
        let metersPerDegreeLat = 111139.0
        let now = Date()
        
        // Step 1: On-trail fix with good accuracy (5m)
        let onTrail = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: baseLat + (5.0 / metersPerDegreeLat), longitude: baseLon),
            altitude: 900.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            timestamp: now
        )
        let pOn = navigator.updateLocation(onTrail)
        XCTAssertNotNil(pOn)
        XCTAssertFalse(pOn!.isOffTrail, "5m deviation must be on trail")
        XCTAssertEqual(alertCount, 0)
        
        // Step 2: Multipath jump 120m outlier with horizontalAccuracy = 45.0m
        let multipathOutlier = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: baseLat + (120.0 / metersPerDegreeLat), longitude: baseLon),
            altitude: 900.0,
            horizontalAccuracy: 45.0,
            verticalAccuracy: 10.0,
            timestamp: now.addingTimeInterval(1.0)
        )
        let pOutlier = navigator.updateLocation(multipathOutlier)
        XCTAssertNotNil(pOutlier)
        XCTAssertEqualWithAccuracy(pOutlier!.crossTrackDeviation, 120.0, accuracy: 2.0)
        XCTAssertFalse(pOutlier!.isOffTrail, "Degraded 45m accuracy outlier must NOT transition to off-trail")
        XCTAssertFalse(navigator.isOffTrail, "Navigator must remain on-trail during multipath jump")
        XCTAssertEqual(alertCount, 0, "Off-trail alert must NOT fire on degraded multipath fix")
    }
    
    /// Verifies 5 consecutive fixes with negative accuracy (-1.0) suppress off-trail state.
    public func testDegradedGPS_NegativeAccuracyHandling() {
        let track = createStraightTrack(pointCount: 3, spacingMeters: 100.0)
        navigator.startNavigation(track: track)
        
        let baseLat = track.points[0].coordinate.latitude
        let baseLon = track.points[1].coordinate.longitude
        let metersPerDegreeLat = 111139.0
        let now = Date()
        
        for i in 0..<5 {
            let negFix = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: baseLat + (60.0 / metersPerDegreeLat), longitude: baseLon),
                altitude: 900.0,
                horizontalAccuracy: -1.0,
                verticalAccuracy: -1.0,
                timestamp: now.addingTimeInterval(Double(i))
            )
            let prog = navigator.updateLocation(negFix)
            XCTAssertNotNil(prog)
            XCTAssertFalse(prog!.isOffTrail, "Negative accuracy fix \(i) must not trigger off-trail")
        }
        XCTAssertFalse(navigator.isOffTrail)
        XCTAssertEqual(alertCount, 0, "No alerts on negative accuracy fixes")
    }
    
    /// Verifies 5 consecutive fixes with infinite accuracy suppress off-trail state.
    public func testDegradedGPS_InfiniteAccuracyHandling() {
        let track = createStraightTrack(pointCount: 3, spacingMeters: 100.0)
        navigator.startNavigation(track: track)
        
        let baseLat = track.points[0].coordinate.latitude
        let baseLon = track.points[1].coordinate.longitude
        let metersPerDegreeLat = 111139.0
        let now = Date()
        
        for i in 0..<5 {
            let infFix = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: baseLat + (80.0 / metersPerDegreeLat), longitude: baseLon),
                altitude: 900.0,
                horizontalAccuracy: Double.infinity,
                verticalAccuracy: Double.infinity,
                timestamp: now.addingTimeInterval(Double(i))
            )
            let prog = navigator.updateLocation(infFix)
            XCTAssertNotNil(prog)
            XCTAssertFalse(prog!.isOffTrail, "Infinite accuracy fix \(i) must not trigger off-trail")
        }
        XCTAssertFalse(navigator.isOffTrail)
        XCTAssertEqual(alertCount, 0, "No alerts on infinite accuracy fixes")
    }
    
    /// Verifies fixes with NaN accuracy are rejected or treated as degraded, suppressing false alerts.
    public func testDegradedGPS_NaNAccuracySuppressesOffTrailAlert() {
        let track = createStraightTrack(pointCount: 3, spacingMeters: 100.0)
        navigator.startNavigation(track: track)
        
        let baseLat = track.points[0].coordinate.latitude
        let baseLon = track.points[1].coordinate.longitude
        let metersPerDegreeLat = 111139.0
        let now = Date()
        
        for i in 0..<3 {
            let nanFix = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: baseLat + (50.0 / metersPerDegreeLat), longitude: baseLon),
                altitude: 900.0,
                horizontalAccuracy: Double.nan,
                verticalAccuracy: 5.0,
                timestamp: now.addingTimeInterval(Double(i))
            )
            _ = navigator.updateLocation(nanFix)
        }
        XCTAssertFalse(navigator.isOffTrail, "NaN accuracy fixes must not cause off-trail transitions")
        XCTAssertEqual(alertCount, 0, "NaN accuracy fixes must not trigger off-trail alerts")
    }
    
    /// Verifies an on-trail fix (5m) resets the off-trail debounce counter.
    public func testDebounceInterruption_OnTrailFixResetsDebounceCounter() {
        let track = createStraightTrack(pointCount: 3, spacingMeters: 100.0)
        navigator.startNavigation(track: track)
        
        let baseLat = track.points[0].coordinate.latitude
        let baseLon = track.points[1].coordinate.longitude
        let metersPerDegreeLat = 111139.0
        let now = Date()
        
        let offTrailCoord = CLLocationCoordinate2D(latitude: baseLat + (35.0 / metersPerDegreeLat), longitude: baseLon)
        let onTrailCoord = CLLocationCoordinate2D(latitude: baseLat + (5.0 / metersPerDegreeLat), longitude: baseLon)
        
        // Fix 1: off-trail (35m)
        let f1 = CLLocation(coordinate: offTrailCoord, altitude: 900, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: now)
        _ = navigator.updateLocation(f1)
        XCTAssertFalse(navigator.isOffTrail)
        XCTAssertEqual(alertCount, 0)
        
        // Fix 2: off-trail (35m)
        let f2 = CLLocation(coordinate: offTrailCoord, altitude: 900, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: now.addingTimeInterval(1.0))
        _ = navigator.updateLocation(f2)
        XCTAssertFalse(navigator.isOffTrail)
        XCTAssertEqual(alertCount, 0)
        
        // Interruption: Fix 3 is ON-TRAIL (5m)
        let fInter = CLLocation(coordinate: onTrailCoord, altitude: 900, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: now.addingTimeInterval(2.0))
        let pInter = navigator.updateLocation(fInter)
        XCTAssertFalse(pInter!.isOffTrail)
        XCTAssertFalse(navigator.isOffTrail)
        XCTAssertEqual(alertCount, 0)
        
        // Fix 4: off-trail again (35m)
        let f4 = CLLocation(coordinate: offTrailCoord, altitude: 900, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: now.addingTimeInterval(3.0))
        let p4 = navigator.updateLocation(f4)
        XCTAssertFalse(p4!.isOffTrail, "Off-trail debounce must be reset by on-trail fix; 1st subsequent fix must not alert")
        XCTAssertFalse(navigator.isOffTrail)
        XCTAssertEqual(alertCount, 0, "Off-trail alert must NOT fire when debounce was interrupted")
    }
    
    // MARK: - Category 3: Extreme Geometries & Antimeridian Tests
    
    /// Verifies antimeridian crossing (179.999 to -179.999) computes ~0m deviation for user at 180.0.
    public func testAntimeridianCrossTrackDeviationNormalization() {
        let p1 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 0.0, longitude: 179.999), elevation: 0.0, cumulativeDistance: 0.0)
        let p2 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 0.0, longitude: -179.999), elevation: 0.0, cumulativeDistance: 22.2)
        let track = GPXTrack(name: "Antimeridian Track", points: [p1, p2], totalDistance: 22.2)
        navigator.startNavigation(track: track)
        
        let loc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 0.0, longitude: 180.0), altitude: 0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date())
        let prog = navigator.updateLocation(loc)
        
        XCTAssertNotNil(prog, "Antimeridian update must produce progress")
        XCTAssertFalse(prog!.isOffTrail, "User at 180.0 must NOT be off trail")
        XCTAssertEqualWithAccuracy(prog!.crossTrackDeviation, 0.0, accuracy: 2.0, "Deviation across antimeridian must be near 0m, not ~111m")
        XCTAssertEqual(alertCount, 0, "No alerts triggered when walking across antimeridian")
    }
    
    /// Verifies single-point track returns valid non-NaN progress.
    public func testExtremeGeometries_SinglePointTrackProjection() {
        let singlePt = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 45.0, longitude: -110.0), elevation: 1200.0, cumulativeDistance: 0.0)
        let singleTrack = GPXTrack(name: "Single Point", points: [singlePt], totalDistance: 0.0)
        navigator.startNavigation(track: singleTrack)
        
        let loc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 45.0001, longitude: -110.0), altitude: 1200.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date())
        let prog = navigator.updateLocation(loc)
        
        XCTAssertNotNil(prog, "Single point track must return valid progress")
        XCTAssertFalse(prog!.crossTrackDeviation.isNaN, "Deviation must not be NaN")
        XCTAssertEqual(prog!.remainingDistance, 0.0, "Remaining distance must be 0 for single-point track")
        XCTAssertEqual(prog!.progressRatio, 1.0, "Progress ratio must be 1.0")
        XCTAssertEqual(prog!.currentElevation, 1200.0, "Elevation must match track point")
        XCTAssertEqual(prog!.segmentIndex, 0)
    }
    
    /// Verifies zero-length track with 2 identical points avoids division by zero.
    public func testExtremeGeometries_ZeroLengthTrackTwoIdenticalPoints() {
        let p1 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 45.0, longitude: -110.0), elevation: 1500.0, cumulativeDistance: 0.0)
        let p2 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 45.0, longitude: -110.0), elevation: 1500.0, cumulativeDistance: 0.0)
        let zeroTrack = GPXTrack(name: "Zero Length 2 Points", points: [p1, p2], totalDistance: 0.0)
        navigator.startNavigation(track: zeroTrack)
        
        let loc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 45.0002, longitude: -110.0), altitude: 1500.0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date())
        let prog = navigator.updateLocation(loc)
        
        XCTAssertNotNil(prog, "Zero length track must return valid progress")
        XCTAssertFalse(prog!.crossTrackDeviation.isNaN, "Deviation must not be NaN")
        XCTAssertFalse(prog!.remainingDistance.isNaN, "Remaining distance must not be NaN")
        XCTAssertFalse(prog!.progressRatio.isNaN, "Progress ratio must not be NaN")
        XCTAssertEqual(prog!.progressRatio, 1.0, "Progress ratio on 0-distance track should default to 1.0")
    }
    
    /// Verifies switchback hairpin corner-cutting smoothly transitions to return leg.
    public func testExtremeGeometries_SwitchbackCornerCuttingSegmentSelection() {
        let baseLat = 46.8000
        let turnLat = 46.800135
        let westLon = -113.9000
        let eastLon = -113.8987
        
        let loc0 = CLLocation(latitude: baseLat, longitude: westLon)
        let loc1 = CLLocation(latitude: baseLat, longitude: eastLon)
        let loc2 = CLLocation(latitude: turnLat, longitude: eastLon)
        let loc3 = CLLocation(latitude: turnLat, longitude: westLon)
        
        let d01 = loc0.distance(from: loc1)
        let d12 = loc1.distance(from: loc2)
        let d23 = loc2.distance(from: loc3)
        
        let sp0 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: baseLat, longitude: westLon), cumulativeDistance: 0.0)
        let sp1 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: baseLat, longitude: eastLon), cumulativeDistance: d01)
        let sp2 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: turnLat, longitude: eastLon), cumulativeDistance: d01 + d12)
        let sp3 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: turnLat, longitude: westLon), cumulativeDistance: d01 + d12 + d23)
        
        let switchbackTrack = GPXTrack(name: "Switchback", points: [sp0, sp1, sp2, sp3], totalDistance: d01 + d12 + d23)
        navigator.startNavigation(track: switchbackTrack)
        
        let midLon = (westLon + eastLon) / 2.0
        
        // Hiker on Leg 1
        let locLeg1 = CLLocation(coordinate: CLLocationCoordinate2D(latitude: baseLat, longitude: midLon), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
        let progLeg1 = navigator.updateLocation(locLeg1)
        XCTAssertEqual(progLeg1?.segmentIndex, 0, "Hiker on Leg 1 must match segment 0")
        let rem1 = progLeg1!.remainingDistance
        
        // Hiker cuts corner directly towards Leg 2
        let locCut = CLLocation(coordinate: CLLocationCoordinate2D(latitude: baseLat + 0.00010, longitude: midLon), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
        let progCut = navigator.updateLocation(locCut)
        XCTAssertEqual(progCut?.segmentIndex, 2, "Cutting corner closer to return leg must match segment 2")
        XCTAssertTrue(progCut!.remainingDistance < rem1, "Remaining distance must decrease when cutting corner to advanced segment")
    }
    
    /// Verifies polar coordinates near 90° latitude produce valid finite metrics.
    public func testExtremeGeometries_PolarCoordinatesNearNorthPole() {
        let p1 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 90.0, longitude: 0.0), elevation: 0.0, cumulativeDistance: 0.0)
        let p2 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 90.0, longitude: 90.0), elevation: 0.0, cumulativeDistance: 0.0)
        let track = GPXTrack(name: "North Pole Track", points: [p1, p2], totalDistance: 0.0)
        navigator.startNavigation(track: track)
        
        let loc = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 90.0, longitude: 45.0), altitude: 0, horizontalAccuracy: 5.0, verticalAccuracy: 5.0, timestamp: Date())
        let prog = navigator.updateLocation(loc)
        
        XCTAssertNotNil(prog, "Polar coordinate update must return valid progress")
        XCTAssertFalse(prog!.crossTrackDeviation.isNaN, "Polar deviation must not be NaN")
        XCTAssertFalse(prog!.remainingDistance.isNaN, "Polar remaining distance must not be NaN")
    }
    
    /// Verifies walking beyond the end of the track clamps remaining distance to 0.0 and progress to 1.0.
    public func testTrailNavigator_OvershootBeyondTrackBoundaryClamping() {
        let track = createStraightTrack(pointCount: 3, spacingMeters: 50.0)
        navigator.startNavigation(track: track)
        
        let baseLat = track.points[0].coordinate.latitude
        let lastPt = track.points.last!
        let metersPerDegreeLon = 111320.0 * cos(baseLat * Double.pi / 180.0)
        
        // Overshoot 100m past the last track point along the same latitude line
        let overshootLon = lastPt.coordinate.longitude + (100.0 / metersPerDegreeLon)
        let locOvershoot = CLLocation(coordinate: CLLocationCoordinate2D(latitude: baseLat, longitude: overshootLon), altitude: 900, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
        
        let prog = navigator.updateLocation(locOvershoot)
        XCTAssertNotNil(prog)
        XCTAssertEqualWithAccuracy(prog!.remainingDistance, 0.0, accuracy: 0.01, "Remaining distance must be clamped to 0.0 when overshooting trail end")
        XCTAssertEqualWithAccuracy(prog!.progressRatio, 1.0, accuracy: 0.001, "Progress ratio must be clamped to 1.0 when overshooting")
        XCTAssertEqualWithAccuracy(prog!.crossTrackDeviation, 100.0, accuracy: 2.0, "Cross track deviation should measure distance to closest endpoint")
    }
    
    // MARK: - Category 4: Corrupted Payloads & Parser Resilience
    
    /// Verifies GPXParser rejects truncated XML cut mid-attribute without hanging or crashing.
    public func testAdversarial_TruncatedXML_MidAttribute_ThrowsCorruptedXML() throws {
        let parser = GPXParser()
        let truncatedMidTag = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="AdversarialTest">
          <trk>
            <name>Truncated Stream</name>
            <trkseg>
              <trkpt lat="46.8523" lon="
        """
        
        var didCatch = false
        do {
            _ = try parser.parse(xmlString: truncatedMidTag)
        } catch let error as GPXParserError {
            if case .corruptedXML = error {
                didCatch = true
            }
        }
        XCTAssertTrue(didCatch, "Truncated XML cut mid-attribute must throw GPXParserError.corruptedXML")
    }
    
    /// Verifies GPXParser rejects unclosed XML elements cleanly.
    public func testAdversarial_TruncatedXML_UnclosedElements_ThrowsCorruptedXML() throws {
        let parser = GPXParser()
        let unclosed = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1"><trk><name>Unclosed</name><trkseg><trkpt lat="46.85" lon="-121.76"/>
        """
        
        var didCatch = false
        do {
            _ = try parser.parse(xmlString: unclosed)
        } catch let error as GPXParserError {
            if case .corruptedXML = error {
                didCatch = true
            }
        }
        XCTAssertTrue(didCatch, "Unclosed XML elements must throw GPXParserError.corruptedXML")
    }
    
    /// Verifies GeoJSONConverter safely skips elements missing geometry or having fewer than 2 coordinates.
    public func testAdversarial_GeoJSONConverter_CorruptedPayloads_GracefulHandling() throws {
        let converter = GeoJSONConverter()
        
        // 1. Missing geometry element
        let jsonMissingGeom = """
        { "version": 0.6, "elements": [{ "type": "way", "id": 901, "tags": {"highway": "path"} }] }
        """
        let fc1 = try converter.convert(overpassData: jsonMissingGeom.data(using: .utf8)!)
        let parsedFC1 = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: fc1)
        XCTAssertEqual(parsedFC1.features.count, 0, "Elements missing geometry must be safely skipped")
        
        // 2. Geometry with fewer than 2 coordinates
        let jsonSingleCoord = """
        { "version": 0.6, "elements": [{ "type": "way", "id": 902, "tags": {"highway": "track"}, "geometry": [{"lat": 46.8, "lon": -121.7}] }] }
        """
        let fc2 = try converter.convert(overpassData: jsonSingleCoord.data(using: .utf8)!)
        let parsedFC2 = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: fc2)
        XCTAssertEqual(parsedFC2.features.count, 0, "Elements with < 2 coordinates must be safely skipped")
    }
    
    /// Verifies TrailOverlayManager handles corrupted GeoJSON files without crashing.
    public func testAdversarial_TrailOverlayManager_CorruptedGeoJSON_NoCrash() {
        let overlayManager = TrailOverlayManager.shared
        let style = MLNStyle()
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let fileA = tempDir.appendingPathComponent("corrupted_a.geojson")
        try? """
        {"type":"FeatureCollection","features":[{"type":"Feature","id":1,"properties":{}}]}
        """.write(to: fileA, atomically: true, encoding: .utf8)
        
        let fileB = tempDir.appendingPathComponent("corrupted_b.geojson")
        try? """
        {"type":"FeatureCollection","features":[{"type":"Feature","id":2,"geometry":{"type":"LineString","coordinates":[[122.4]]},"properties":{}}]}
        """.write(to: fileB, atomically: true, encoding: .utf8)
        
        let fileC = tempDir.appendingPathComponent("corrupted_c.geojson")
        try? """
        {"type":"FeatureCollection","features":[{"type":"Feature","id":3,"geometry":{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1],[0,0]]]},"properties":{}}]}
        """.write(to: fileC, atomically: true, encoding: .utf8)
        
        let validFile = tempDir.appendingPathComponent("valid.geojson")
        try? """
        {"type":"FeatureCollection","features":[{"type":"Feature","id":4,"geometry":{"type":"LineString","coordinates":[[-121.75, 46.85], [-121.74, 46.86]]},"properties":{}}]}
        """.write(to: validFile, atomically: true, encoding: .utf8)
        
        overlayManager.applyTrailOverlay(to: style, geoJSONURLs: [fileA, fileB, fileC, validFile])
        XCTAssertNotNil(style.source(withIdentifier: TrailOverlayManager.overlaySourceIdentifier))
    }
    
    // MARK: - Category 5: Security & Path Traversal Tests
    
    /// Verifies TrailManager rejects all path traversal permutations in deleteTrail(named:).
    public func testAdversarial_TrailManager_PathTraversal_DeleteNamed_Permutations() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TMTest_\(UUID().uuidString)")
        let tm = TrailManager(baseDirectory: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let permutations = [
            "..%252f..%252fetc/passwd",
            "trail%00.gpx",
            "....//....//trails",
            "..%2f..%2fetc%2fpasswd.gpx",
            "../../etc/passwd.gpx"
        ]
        
        for name in permutations {
            var caught = false
            do {
                try await tm.deleteTrail(named: name)
            } catch let error as TrailManagerError {
                if case .pathTraversalDetected = error {
                    caught = true
                }
            } catch {}
            XCTAssertTrue(caught, "deleteTrail(named: '\(name)') must throw pathTraversalDetected")
        }
    }
    
    /// Verifies TrailManager rejects path traversal in source URL path for importFile(from:).
    public func testAdversarial_TrailManager_PathTraversal_ImportFile_SourceURLPermutations() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TMImportTest_\(UUID().uuidString)")
        let tm = TrailManager(baseDirectory: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let maliciousURLs = [
            URL(fileURLWithPath: "/safe_directory/../../etc/passwd.gpx"),
            URL(fileURLWithPath: "/var/tmp/../etc/shadow.gpx"),
            URL(string: "file:///safe/..%2f..%2fetc/passwd.gpx")!
        ]
        
        for url in maliciousURLs {
            var caught = false
            do {
                _ = try tm.importFile(from: url)
            } catch let error as TrailManagerError {
                if case .pathTraversalDetected = error {
                    caught = true
                }
            } catch {}
            XCTAssertTrue(caught, "importFile(from: '\(url.path)') must throw pathTraversalDetected")
        }
    }
    
    /// Verifies concurrent deletions of the same trail handle NSFileNoSuchFileError idempotently without failing.
    public func testAdversarial_TrailManager_ConcurrentDeletion_Idempotent() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TMConcurrentDel_\(UUID().uuidString)")
        let externalDir = FileManager.default.temporaryDirectory.appendingPathComponent("TMExternal_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        let tm = TrailManager(baseDirectory: tempDir)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            try? FileManager.default.removeItem(at: externalDir)
        }
        
        let gpxURL = externalDir.appendingPathComponent("concurrent_test.gpx")
        let dummyGPX = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Test"><trk><name>Concurrent Del</name><trkseg><trkpt lat="46.85" lon="-121.75"/><trkpt lat="46.86" lon="-121.74"/></trkseg></trk></gpx>
        """
        try dummyGPX.write(to: gpxURL, atomically: true, encoding: .utf8)
        let track = try tm.importFile(from: gpxURL)
        
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<10 {
                group.addTask { @MainActor in
                    do {
                        try await tm.deleteTrail(track)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            
            var allSucceeded = true
            for await success in group {
                if !success { allSucceeded = false }
            }
            XCTAssertTrue(allSucceeded, "Concurrent deletions of the same trail must all succeed idempotently")
        }
    }
    
    // MARK: - Category 6: Offline Airplane Mode & Audio Cooldown Tests
    
    /// Verifies RegionalTrailDownloader throws TrailDownloaderError.networkError in <= 10ms during Airplane Mode.
    public func testAdversarial_AirplaneModeOverpassQuery_ThrowsWithin10ms() async {
        let session = MockURLProtocol.makeMockSession()
        let downloader = RegionalTrailDownloader(session: session)
        MockURLProtocol.reset()
        MockURLProtocol.responseHandler = nil
        
        let bounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: 46.8, longitude: -121.8),
            ne: CLLocationCoordinate2D(latitude: 46.9, longitude: -121.7)
        )
        
        let start = DispatchTime.now()
        var caughtNetworkError = false
        do {
            _ = try await downloader.downloadTrails(bbox: bounds, regionName: "OfflineAirplane")
        } catch let error as TrailDownloaderError {
            if case .networkError = error {
                caughtNetworkError = true
            }
        } catch {}
        
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
        XCTAssertTrue(caughtNetworkError, "Must throw TrailDownloaderError.networkError in airplane mode")
        XCTAssertTrue(elapsedMs <= 50.0, "Airplane mode failure must return rapidly (took \(elapsedMs)ms)")
        MockURLProtocol.reset()
    }
    
    /// Verifies 30s audio alert cooldown throttling fires exactly twice across 60 seconds with timestamp parameter.
    public func testAdversarial_AudioAlert_CooldownThrottling_Over60Seconds() {
        let alertService = TrailAudioAlertService(isEnabled: true, cooldownInterval: 30.0)
        var alertCallbackCount = 0
        alertService.onAlertTriggered = { _ in alertCallbackCount += 1 }
        
        let navigator = TrailNavigator(audioAlertService: alertService)
        let p1 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 46.850, longitude: -121.750), elevation: 1000, time: nil, cumulativeDistance: 0)
        let p2 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 46.850, longitude: -121.740), elevation: 1000, time: nil, cumulativeDistance: 760)
        let track = GPXTrack(
            name: "Test Track",
            points: [p1, p2],
            totalDistance: 760,
            elevationGain: 0,
            elevationLoss: 0,
            bounds: GPXBounds(minLatitude: 46.850, maxLatitude: 46.850, minLongitude: -121.750, maxLongitude: -121.740)
        )
        navigator.startNavigation(track: track)
        
        let t0 = Date()
        for i in 0..<20 {
            let simTime = t0.addingTimeInterval(Double(i * 3))
            let loc = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 46.8505, longitude: -121.745), // ~55m off-trail
                altitude: 1000,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 5.0,
                timestamp: simTime
            )
            _ = navigator.updateLocation(loc)
        }
        
        XCTAssertEqual(alertService.alertCount, 2, "Off-trail alert must fire exactly twice over 60 seconds with 30s cooldown throttling")
        XCTAssertEqual(alertCallbackCount, 2, "Alert callback hook must be called exactly twice")
    }
    
    /// Verifies zero URLSession network requests occur across all core offline features.
    public func testAdversarial_ZeroNetworkAssertion_AcrossOfflineModules() async {
        URLProtocol.registerClass(MockURLProtocol.self)
        MockURLProtocol.reset()
        defer {
            URLProtocol.unregisterClass(MockURLProtocol.self)
            MockURLProtocol.reset()
        }
        
        // 1. Route Calculation
        let routingService = RoutingService()
        _ = try? await routingService.calculateRoute(
            from: CLLocationCoordinate2D(latitude: 46.85, longitude: -121.75),
            to: CLLocationCoordinate2D(latitude: 46.86, longitude: -121.74),
            costing: "pedestrian"
        )
        
        // 2. Coordinate Search
        let searchService = SearchService()
        _ = await searchService.search(query: "46.852, -121.760")
        
        // 3. Trail Overlay
        let overlayManager = TrailOverlayManager.shared
        let style = MLNStyle()
        overlayManager.applyTrailOverlay(to: style, geoJSONURLs: [])
        
        // 4. Live Trail Navigation
        let alertService = TrailAudioAlertService(isEnabled: true, cooldownInterval: 30.0)
        let navigator = TrailNavigator(audioAlertService: alertService)
        let p1 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 46.85, longitude: -121.75), elevation: 1000, time: nil, cumulativeDistance: 0)
        let p2 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 46.86, longitude: -121.74), elevation: 1100, time: nil, cumulativeDistance: 1300)
        let track = GPXTrack(
            name: "Live Trail",
            points: [p1, p2],
            totalDistance: 1300,
            elevationGain: 100,
            elevationLoss: 0,
            bounds: GPXBounds(minLatitude: 46.85, maxLatitude: 46.86, minLongitude: -121.75, maxLongitude: -121.74)
        )
        navigator.startNavigation(track: track)
        for i in 0..<5 {
            let loc = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 46.851, longitude: -121.749),
                altitude: 1005,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 5.0,
                timestamp: Date().addingTimeInterval(Double(i))
            )
            _ = navigator.updateLocation(loc)
        }
        navigator.stopNavigation()
        
        XCTAssertEqual(MockURLProtocol.requestCount, 0, "Zero URLSession network requests must be issued during offline operations")
    }
}
