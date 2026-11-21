import Foundation
import CoreLocation

#if canImport(XCTest)
import XCTest
#else
// Standalone test harness shim for compilation without XCTest framework (e.g. macOS standalone test runner)
open class XCTestCase {
    public required init() {}
    open func setUp() async throws {}
    open func tearDown() async throws {}
    open func setUp() {}
    open func tearDown() {}
}

public var gpxTestFailuresCount = 0

public func XCTAssert(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition() {
        gpxTestFailuresCount += 1
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
        gpxTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): [\(v1)] != [\(v2)] - \(message())")
    }
}

public func XCTAssertNotNil(_ a: @autoclosure () -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    if a() == nil {
        gpxTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): Value is nil - \(message())")
    }
}

public func XCTAssertNil(_ a: @autoclosure () -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    if a() != nil {
        gpxTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): Value is not nil - \(message())")
    }
}

public func XCTFail(_ message: String, file: StaticString = #file, line: UInt = #line) {
    gpxTestFailuresCount += 1
    print("❌ XCTFail at \(file):\(line): \(message)")
}
#endif

// MARK: - GPXParserTests

public final class GPXParserTests: XCTestCase {
    
    private var tempDirectory: URL!
    private var parser: GPXParser!
    
    public override func setUp() async throws {
        try await super.setUp()
        parser = GPXParser()
        let unique = UUID().uuidString
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("GPXTests_\(unique)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    public override func tearDown() async throws {
        if let dir = tempDirectory, FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
        try await super.tearDown()
    }
    
    // MARK: - Test 1: Standard GPX Parsing (Tracks, Points, Elevation, Timestamps)
    
    public func testStandardGPXParsing() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="TeamworkTest">
            <metadata>
                <name>Metadata Trail Name</name>
                <desc>Metadata Trail Description</desc>
            </metadata>
            <trk>
                <name>Twin Peaks Trail</name>
                <desc>Scenic summit hike in San Francisco</desc>
                <trkseg>
                    <trkpt lat="37.7544" lon="-122.4477">
                        <ele>250.0</ele>
                        <time>2026-11-21T05:00:00Z</time>
                    </trkpt>
                    <trkpt lat="37.7550" lon="-122.4465">
                        <ele>270.5</ele>
                        <time>2026-11-21T05:05:00Z</time>
                    </trkpt>
                    <trkpt lat="37.7555" lon="-122.4455">
                        <ele>282.0</ele>
                        <time>2026-11-21T05:10:00Z</time>
                    </trkpt>
                </trkseg>
            </trk>
        </gpx>
        """
        
        let track = try parser.parse(xmlString: xml)
        
        XCTAssertEqual(track.name, "Twin Peaks Trail")
        XCTAssertEqual(track.trackDescription, "Scenic summit hike in San Francisco")
        XCTAssertEqual(track.points.count, 3)
        
        // Point 1
        XCTAssertEqual(track.points[0].coordinate.latitude, 37.7544)
        XCTAssertEqual(track.points[0].coordinate.longitude, -122.4477)
        XCTAssertEqual(track.points[0].elevation, 250.0)
        XCTAssertEqual(track.points[0].cumulativeDistance, 0.0)
        XCTAssertNotNil(track.points[0].time)
        
        // Point 2
        XCTAssertEqual(track.points[1].coordinate.latitude, 37.7550)
        XCTAssertEqual(track.points[1].coordinate.longitude, -122.4465)
        XCTAssertEqual(track.points[1].elevation, 270.5)
        XCTAssertTrue(track.points[1].cumulativeDistance > 0.0)
        
        // Point 3
        XCTAssertEqual(track.points[2].coordinate.latitude, 37.7555)
        XCTAssertEqual(track.points[2].coordinate.longitude, -122.4455)
        XCTAssertEqual(track.points[2].elevation, 282.0)
        XCTAssertTrue(track.points[2].cumulativeDistance > track.points[1].cumulativeDistance)
        
        // Track aggregates
        XCTAssertEqual(track.totalDistance, track.points[2].cumulativeDistance)
        XCTAssertEqual(track.minElevation, 250.0)
        XCTAssertEqual(track.maxElevation, 282.0)
        XCTAssertEqual(track.elevationGain, 32.0) // (270.5 - 250.0) + (282.0 - 270.5) = 20.5 + 11.5 = 32.0
        XCTAssertEqual(track.elevationLoss, 0.0)
    }
    
    // MARK: - Test 2: Route Fallback Parsing (<rte> -> <rtept>)
    
    public func testRouteFallbackParsing() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="TeamworkRouteTest">
            <rte>
                <name>Coastal Route 1</name>
                <desc>Scenic coastal route</desc>
                <rtept lat="37.8000" lon="-122.4500">
                    <ele>15.0</ele>
                </rtept>
                <rtept lat="37.8010" lon="-122.4510">
                    <ele>22.0</ele>
                </rtept>
            </rte>
        </gpx>
        """
        
        let track = try parser.parse(xmlString: xml)
        
        XCTAssertEqual(track.name, "Coastal Route 1")
        XCTAssertEqual(track.trackDescription, "Scenic coastal route")
        XCTAssertEqual(track.points.count, 2)
        XCTAssertEqual(track.points[0].coordinate.latitude, 37.8000)
        XCTAssertEqual(track.points[1].coordinate.latitude, 37.8010)
        XCTAssertTrue(track.totalDistance > 0.0)
        XCTAssertEqual(track.elevationGain, 7.0)
    }
    
    // MARK: - Test 3: Multi-Segment GPX Track (<trkseg>)
    
    public func testMultiSegmentGPX() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1">
            <trk>
                <name>Multi-Segment Loop</name>
                <trkseg>
                    <trkpt lat="37.7000" lon="-122.4000"><ele>10.0</ele></trkpt>
                    <trkpt lat="37.7010" lon="-122.4010"><ele>20.0</ele></trkpt>
                </trkseg>
                <trkseg>
                    <trkpt lat="37.7020" lon="-122.4020"><ele>15.0</ele></trkpt>
                    <trkpt lat="37.7030" lon="-122.4030"><ele>25.0</ele></trkpt>
                </trkseg>
            </trk>
        </gpx>
        """
        
        let track = try parser.parse(xmlString: xml)
        
        XCTAssertEqual(track.name, "Multi-Segment Loop")
        XCTAssertEqual(track.points.count, 4)
        
        // Verify continuity of cumulative distance across segments
        XCTAssertEqual(track.points[0].cumulativeDistance, 0.0)
        XCTAssertTrue(track.points[1].cumulativeDistance > track.points[0].cumulativeDistance)
        XCTAssertTrue(track.points[2].cumulativeDistance > track.points[1].cumulativeDistance)
        XCTAssertTrue(track.points[3].cumulativeDistance > track.points[2].cumulativeDistance)
        
        // Elevation calculations: 10->20 (+10), 20->15 (-5), 15->25 (+10) => Gain = 20, Loss = 5
        XCTAssertEqual(track.elevationGain, 20.0)
        XCTAssertEqual(track.elevationLoss, 5.0)
        XCTAssertEqual(track.minElevation, 10.0)
        XCTAssertEqual(track.maxElevation, 25.0)
    }
    
    // MARK: - Test 4: Cumulative Distance Calculation
    
    public func testCumulativeDistanceCalculation() throws {
        // Point A: (0, 0), Point B: (1, 0) -> 1 degree latitude ~ 111.19 km
        let d = GPXParser.haversineDistance(lat1: 0.0, lon1: 0.0, lat2: 1.0, lon2: 0.0)
        // 1 degree latitude on a sphere of radius 6371km is 6371 * pi / 180 ~ 111,194.9 meters
        XCTAssertTrue(abs(d - 111195.0) < 50.0, "Haversine distance should be ~111,195m for 1 deg latitude")
        
        let xml = """
        <gpx version="1.1">
            <trk>
                <name>Distance Test</name>
                <trkseg>
                    <trkpt lat="37.7749" lon="-122.4194"/>
                    <trkpt lat="37.7759" lon="-122.4194"/>
                    <trkpt lat="37.7769" lon="-122.4194"/>
                </trkseg>
            </trk>
        </gpx>
        """
        let track = try parser.parse(xmlString: xml)
        XCTAssertEqual(track.points.count, 3)
        XCTAssertEqual(track.points[0].cumulativeDistance, 0.0)
        XCTAssertTrue(track.points[1].cumulativeDistance > 100.0)
        XCTAssertTrue(track.points[2].cumulativeDistance > 200.0)
        XCTAssertEqual(track.totalDistance, track.points[2].cumulativeDistance)
    }
    
    // MARK: - Test 5: Elevation Gain & Loss Calculation
    
    public func testElevationGainAndLoss() throws {
        let xml = """
        <gpx version="1.1">
            <trk>
                <name>Rollercoaster</name>
                <trkseg>
                    <trkpt lat="37.0" lon="-122.0"><ele>100.0</ele></trkpt>
                    <trkpt lat="37.1" lon="-122.0"><ele>150.0</ele></trkpt>
                    <trkpt lat="37.2" lon="-122.0"><ele>120.0</ele></trkpt>
                    <trkpt lat="37.3" lon="-122.0"><ele>180.0</ele></trkpt>
                </trkseg>
            </trk>
        </gpx>
        """
        let track = try parser.parse(xmlString: xml)
        
        // 100 -> 150: +50 gain
        // 150 -> 120: +30 loss
        // 120 -> 180: +60 gain
        // Total Gain: 110, Total Loss: 30
        XCTAssertEqual(track.elevationGain, 110.0)
        XCTAssertEqual(track.elevationLoss, 30.0)
        XCTAssertEqual(track.minElevation, 100.0)
        XCTAssertEqual(track.maxElevation, 180.0)
    }
    
    // MARK: - Test 6: Negative Elevation Handling (e.g. Badwater Basin)
    
    public func testNegativeElevation() throws {
        let xml = """
        <gpx version="1.1">
            <trk>
                <name>Death Valley Trail</name>
                <trkseg>
                    <trkpt lat="36.2" lon="-116.8"><ele>-86.0</ele></trkpt>
                    <trkpt lat="36.3" lon="-116.8"><ele>-60.0</ele></trkpt>
                    <trkpt lat="36.4" lon="-116.8"><ele>-100.0</ele></trkpt>
                </trkseg>
            </trk>
        </gpx>
        """
        let track = try parser.parse(xmlString: xml)
        
        // -86 -> -60: +26 gain
        // -60 -> -100: +40 loss
        XCTAssertEqual(track.elevationGain, 26.0)
        XCTAssertEqual(track.elevationLoss, 40.0)
        XCTAssertEqual(track.minElevation, -100.0)
        XCTAssertEqual(track.maxElevation, -60.0)
    }
    
    // MARK: - Test 7: Missing Elevation Graceful Handling
    
    public func testMissingElevation() throws {
        let xml = """
        <gpx version="1.1">
            <trk>
                <name>Flat 2D Trail</name>
                <trkseg>
                    <trkpt lat="37.7749" lon="-122.4194"/>
                    <trkpt lat="37.7759" lon="-122.4194"/>
                </trkseg>
            </trk>
        </gpx>
        """
        let track = try parser.parse(xmlString: xml)
        
        XCTAssertEqual(track.points.count, 2)
        XCTAssertNil(track.points[0].elevation)
        XCTAssertNil(track.points[1].elevation)
        XCTAssertEqual(track.elevationGain, 0.0)
        XCTAssertEqual(track.elevationLoss, 0.0)
        XCTAssertNil(track.minElevation)
        XCTAssertNil(track.maxElevation)
        XCTAssertTrue(track.totalDistance > 0.0)
    }
    
    // MARK: - Test 8: Malformed Timestamps Graceful Handling
    
    public func testMalformedTimestamps() throws {
        let xml = """
        <gpx version="1.1">
            <trk>
                <name>Timestamp Resilience</name>
                <trkseg>
                    <trkpt lat="37.0" lon="-122.0">
                        <time>2026-11-21T05:40:00Z</time>
                    </trkpt>
                    <trkpt lat="37.1" lon="-122.0">
                        <time>invalid-timestamp-value</time>
                    </trkpt>
                </trkseg>
            </trk>
        </gpx>
        """
        let track = try parser.parse(xmlString: xml)
        
        XCTAssertEqual(track.points.count, 2)
        XCTAssertNotNil(track.points[0].time)
        XCTAssertNil(track.points[1].time, "Invalid date should parse as nil without crashing")
    }
    
    // MARK: - Test 9: Empty GPX Track (Zero Points)
    
    public func testEmptyGPXTrack() throws {
        let xml = """
        <gpx version="1.1">
            <trk>
                <name>Zero Points Trail</name>
                <trkseg></trkseg>
            </trk>
        </gpx>
        """
        let track = try parser.parse(xmlString: xml)
        
        XCTAssertEqual(track.name, "Zero Points Trail")
        XCTAssertEqual(track.points.count, 0)
        XCTAssertEqual(track.totalDistance, 0.0)
        XCTAssertEqual(track.elevationGain, 0.0)
        XCTAssertEqual(track.elevationLoss, 0.0)
        XCTAssertEqual(track.bounds, GPXBounds.zero)
    }
    
    // MARK: - Test 10: Corrupted XML Handling
    
    public func testCorruptedXML() {
        let corruptedXML = "<gpx><trk><trkseg><trkpt lat='1' lon='1'><ele>10</ele>" // unclosed tags
        
        do {
            _ = try parser.parse(xmlString: corruptedXML)
            XCTFail("Should throw an error on corrupted XML")
        } catch {
            XCTAssertTrue(error is GPXParserError)
        }
    }
    
    // MARK: - Test 11: Empty Data Handling
    
    public func testEmptyData() {
        do {
            _ = try parser.parse(data: Data())
            XCTFail("Should throw error on empty data")
        } catch let err as GPXParserError {
            XCTAssertEqual(err, GPXParserError.emptyData)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    // MARK: - Test 12: GPXBounds Calculations & Point Containment
    
    public func testGPXBounds() {
        let points = [
            GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.5)),
            GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 37.5, longitude: -122.0)),
            GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 37.2, longitude: -122.3))
        ]
        
        let bounds = GPXParser.calculateBounds(for: points)
        XCTAssertEqual(bounds.minLatitude, 37.0)
        XCTAssertEqual(bounds.maxLatitude, 37.5)
        XCTAssertEqual(bounds.minLongitude, -122.5)
        XCTAssertEqual(bounds.maxLongitude, -122.0)
        
        XCTAssertEqual(bounds.latitudeSpan, 0.5)
        XCTAssertEqual(bounds.longitudeSpan, 0.5)
        XCTAssertEqual(bounds.center.latitude, 37.25)
        XCTAssertEqual(bounds.center.longitude, -122.25)
        
        XCTAssertTrue(bounds.contains(CLLocationCoordinate2D(latitude: 37.25, longitude: -122.25)))
        XCTAssertFalse(bounds.contains(CLLocationCoordinate2D(latitude: 38.0, longitude: -122.0)))
        
        let coordBounds = bounds.toCoordinateBounds()
        XCTAssertEqual(coordBounds.sw.latitude, 37.0)
        XCTAssertEqual(coordBounds.ne.latitude, 37.5)
    }
    
    // MARK: - Test 13: GeoJSON Conversion Helper for Overlay Manager
    
    public func testGeoJSONFeatureGeneration() throws {
        let p1 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 37.7, longitude: -122.4), cumulativeDistance: 0.0)
        let p2 = GPXTrackPoint(coordinate: CLLocationCoordinate2D(latitude: 37.8, longitude: -122.3), cumulativeDistance: 15000.0)
        
        let track = GPXTrack(
            name: "Skyline Ridge",
            trackDescription: "Panoramic ridge trail",
            points: [p1, p2],
            totalDistance: 15000.0,
            elevationGain: 350.0,
            elevationLoss: 120.0
        )
        
        let feature = track.toGeoJSONFeature()
        XCTAssertEqual(feature.geometry.type, "LineString")
        XCTAssertEqual(feature.geometry.coordinates.count, 2)
        
        // Verify RFC 7946 coordinate ordering: [longitude, latitude]
        XCTAssertEqual(feature.geometry.coordinates[0][0], -122.4)
        XCTAssertEqual(feature.geometry.coordinates[0][1], 37.7)
        XCTAssertEqual(feature.geometry.coordinates[1][0], -122.3)
        XCTAssertEqual(feature.geometry.coordinates[1][1], 37.8)
        
        XCTAssertEqual(feature.properties["name"], "Skyline Ridge")
        XCTAssertEqual(feature.properties["points_count"], "2")
        
        let collection = track.toGeoJSONFeatureCollection()
        XCTAssertEqual(collection.type, "FeatureCollection")
        XCTAssertEqual(collection.features.count, 1)
        
        let jsonData = try track.toGeoJSONData()
        XCTAssertFalse(jsonData.isEmpty)
        
        let decoded = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: jsonData)
        XCTAssertEqual(decoded.features.count, 1)
        XCTAssertEqual(decoded.features[0].properties["name"], "Skyline Ridge")
    }
    
    // MARK: - Test 14: TrailManager Directory Creation & Local Scanning
    
    public func testTrailManager_DirectoryCreationAndScanning() async throws {
        let manager = await TrailManager(baseDirectory: tempDirectory, parser: parser, autoScan: false)
        
        // 1. Directory should exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.path))
        
        // 2. Initially empty
        let initialTracks = try await manager.scanTrails()
        XCTAssertEqual(initialTracks.count, 0)
        
        // 3. Create two valid GPX files and one non-GPX file
        let gpxContent1 = """
        <gpx version="1.1"><trk><name>Alpha Trail</name><trkseg><trkpt lat="37.1" lon="-122.1"/></trkseg></trk></gpx>
        """
        let gpxContent2 = """
        <gpx version="1.1"><trk><name>Beta Trail</name><trkseg><trkpt lat="37.2" lon="-122.2"/></trkseg></trk></gpx>
        """
        let nonGPXContent = "Plain text file content"
        
        try gpxContent1.write(to: tempDirectory.appendingPathComponent("alpha.gpx"), atomically: true, encoding: .utf8)
        try gpxContent2.write(to: tempDirectory.appendingPathComponent("beta.gpx"), atomically: true, encoding: .utf8)
        try nonGPXContent.write(to: tempDirectory.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        
        // 4. Scan
        let scanned = try await manager.scanTrails()
        XCTAssertEqual(scanned.count, 2)
        XCTAssertEqual(scanned[0].name, "Alpha Trail")
        XCTAssertEqual(scanned[1].name, "Beta Trail")
        
        let published = await manager.importedTrails
        XCTAssertEqual(published.count, 2)
    }
    
    // MARK: - Test 15: Case-Insensitive Extension Support (.gpx / .GPX)
    
    public func testTrailManager_CaseInsensitiveExtension() async throws {
        let manager = await TrailManager(baseDirectory: tempDirectory, parser: parser, autoScan: false)
        
        let gpxContentLower = """
        <gpx version="1.1"><trk><name>Lower Trail</name><trkseg><trkpt lat="37.1" lon="-122.1"/></trkseg></trk></gpx>
        """
        let gpxContentUpper = """
        <gpx version="1.1"><trk><name>Upper Trail</name><trkseg><trkpt lat="37.2" lon="-122.2"/></trkseg></trk></gpx>
        """
        
        try gpxContentLower.write(to: tempDirectory.appendingPathComponent("lower.gpx"), atomically: true, encoding: .utf8)
        try gpxContentUpper.write(to: tempDirectory.appendingPathComponent("upper.GPX"), atomically: true, encoding: .utf8)
        
        let scanned = try await manager.scanTrails()
        XCTAssertEqual(scanned.count, 2)
    }
    
    // MARK: - Test 16: Security-Scoped File Import
    
    public func testTrailManager_SecurityScopedImport() async throws {
        let manager = await TrailManager(baseDirectory: tempDirectory, parser: parser, autoScan: false)
        
        // Source file outside trailsDirectory (e.g. Downloads or iCloud simulation)
        let externalDir = FileManager.default.temporaryDirectory.appendingPathComponent("ExternalDownloads_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: externalDir) }
        
        let sourceURL = externalDir.appendingPathComponent("ImportMe.gpx")
        let content = """
        <gpx version="1.1"><trk><name>Imported Ridge</name><trkseg><trkpt lat="37.5" lon="-122.5"><ele>100</ele></trkpt></trkseg></trk></gpx>
        """
        try content.write(to: sourceURL, atomically: true, encoding: .utf8)
        
        // Import
        let importedTrack = try await manager.importTrail(from: sourceURL)
        XCTAssertEqual(importedTrack.name, "Imported Ridge")
        
        // Verify it copied into trailsDirectory
        let expectedLocalURL = tempDirectory.appendingPathComponent("ImportMe.gpx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedLocalURL.path))
        
        // Verify present in manager.importedTrails
        let list = await manager.importedTrails
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].name, "Imported Ridge")
    }
    
    // MARK: - Test 17: Trail Deletion
    
    public func testTrailManager_DeleteTrail() async throws {
        let manager = await TrailManager(baseDirectory: tempDirectory, parser: parser, autoScan: false)
        
        let gpxContent = """
        <gpx version="1.1"><trk><name>To Delete</name><trkseg><trkpt lat="37.1" lon="-122.1"/></trkseg></trk></gpx>
        """
        let fileURL = tempDirectory.appendingPathComponent("delete_me.gpx")
        try gpxContent.write(to: fileURL, atomically: true, encoding: .utf8)
        
        let scanned = try await manager.scanTrails()
        XCTAssertEqual(scanned.count, 1)
        
        try await manager.deleteTrail(scanned[0])
        
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let afterDelete = await manager.importedTrails
        XCTAssertEqual(afterDelete.count, 0)
    }
    
    // MARK: - Test 18: Path Traversal Defense on Import
    
    public func testTrailManager_PathTraversalDefense_Import() async throws {
        let manager = await TrailManager(baseDirectory: tempDirectory, parser: parser, autoScan: false)
        
        // Try importing non-gpx file
        let invalidFileURL = tempDirectory.appendingPathComponent("bad.exe")
        try "fake".write(to: invalidFileURL, atomically: true, encoding: .utf8)
        
        do {
            try await manager.importTrail(from: invalidFileURL)
            XCTFail("Should reject non-gpx file extension")
        } catch let err as TrailManagerError {
            XCTAssertEqual(err, TrailManagerError.invalidFileType("exe"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // Sanitizer strips ../ and keeps file inside trailsDirectory
        let sanitized = await manager.sanitizeFilename("../../escape.gpx")
        XCTAssertEqual(sanitized, "escape.gpx")
        
        let sanitizedNullByte = await manager.sanitizeFilename("test\0bad.gpx")
        XCTAssertFalse(sanitizedNullByte.contains("\0"))
    }
    
    // MARK: - Test 19: Path Traversal Defense on Deletion
    
    public func testTrailManager_PathTraversalDefense_Delete() async throws {
        let manager = await TrailManager(baseDirectory: tempDirectory, parser: parser, autoScan: false)
        
        // 1. Attempt relative path traversal with ../
        do {
            try await manager.deleteTrail(named: "../../etc/passwd")
            XCTFail("Should throw pathTraversalDetected error on relative traversal")
        } catch let err as TrailManagerError {
            switch err {
            case .pathTraversalDetected:
                XCTAssertTrue(true)
            default:
                XCTFail("Expected pathTraversalDetected, got \(err)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        // 2. Attempt deleting outside URL
        let outsideURL = URL(fileURLWithPath: "/etc/passwd")
        do {
            try await manager.deleteTrail(at: outsideURL)
            XCTFail("Should throw pathTraversalDetected error on outside URL")
        } catch let err as TrailManagerError {
            switch err {
            case .pathTraversalDetected:
                XCTAssertTrue(true)
            default:
                XCTFail("Expected pathTraversalDetected, got \(err)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Test 20: GeoJSON Export for Overlay Manager
    
    public func testTrailManager_GeoJSONExportForOverlay() async throws {
        let manager = await TrailManager(baseDirectory: tempDirectory, parser: parser, autoScan: false)
        
        let gpxContent = """
        <gpx version="1.1"><trk><name>Overlay Trail</name><trkseg><trkpt lat="37.8" lon="-122.4"/><trkpt lat="37.9" lon="-122.5"/></trkseg></trk></gpx>
        """
        let fileURL = tempDirectory.appendingPathComponent("overlay_trail.gpx")
        try gpxContent.write(to: fileURL, atomically: true, encoding: .utf8)
        
        let scanned = try await manager.scanTrails()
        XCTAssertEqual(scanned.count, 1)
        
        let geoJSONURL = try await manager.exportGeoJSON(for: scanned[0])
        XCTAssertTrue(FileManager.default.fileExists(atPath: geoJSONURL.path))
        XCTAssertEqual(geoJSONURL.pathExtension, "geojson")
        
        let allURLs = await manager.allTrailGeoJSONURLs()
        XCTAssertEqual(allURLs.count, 1)
        XCTAssertEqual(allURLs[0].lastPathComponent, "overlay_trail.geojson")
    }
    
    // MARK: - Test 21: UTF-8 with Byte Order Mark (BOM) Resilience
    
    public func testXMLWithBOM() throws {
        let bomString = "\u{FEFF}<?xml version=\"1.0\" encoding=\"UTF-8\"?><gpx version=\"1.1\"><trk><name>BOM Trail</name><trkseg><trkpt lat=\"37.7\" lon=\"-122.4\"/></trkseg></trk></gpx>"
        let track = try parser.parse(xmlString: bomString)
        XCTAssertEqual(track.name, "BOM Trail")
        XCTAssertEqual(track.points.count, 1)
    }
    
    // MARK: - Test 22: GPX with Standard XML Namespaces
    
    public func testGPXWithXMLNamespaces() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="StravaGPX" xmlns="http://www.topografix.com/GPX/1/1" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.topografix.com/GPX/1/1 http://www.topografix.com/GPX/1/1/gpx.xsd">
            <metadata>
                <time>2026-11-21T05:00:00Z</time>
            </metadata>
            <trk>
                <name>Namespace Trail</name>
                <type>hiking</type>
                <trkseg>
                    <trkpt lat="37.77" lon="-122.42">
                        <ele>150.0</ele>
                    </trkpt>
                </trkseg>
            </trk>
        </gpx>
        """
        let track = try parser.parse(xmlString: xml)
        XCTAssertEqual(track.name, "Namespace Trail")
        XCTAssertEqual(track.points.count, 1)
        XCTAssertEqual(track.points[0].elevation, 150.0)
    }
    
    // MARK: - Test 23: Multiple Distinct Tracks in One GPX File
    
    public func testMultipleTracksCombined() throws {
        let xml = """
        <gpx version="1.1">
            <trk>
                <name>Track One</name>
                <trkseg>
                    <trkpt lat="37.1" lon="-122.1"><ele>100</ele></trkpt>
                    <trkpt lat="37.2" lon="-122.1"><ele>150</ele></trkpt>
                </trkseg>
            </trk>
            <trk>
                <name>Track Two</name>
                <trkseg>
                    <trkpt lat="37.3" lon="-122.1"><ele>200</ele></trkpt>
                </trkseg>
            </trk>
        </gpx>
        """
        // Test distinct tracks extraction
        let tracks = try parser.parseTracks(data: xml.data(using: .utf8)!)
        XCTAssertEqual(tracks.count, 2)
        XCTAssertEqual(tracks[0].name, "Track One")
        XCTAssertEqual(tracks[1].name, "Track Two")
        
        // Test combined track extraction
        let combined = try parser.parse(xmlString: xml)
        XCTAssertEqual(combined.points.count, 3)
        XCTAssertEqual(combined.points[0].coordinate.latitude, 37.1)
        XCTAssertEqual(combined.points[2].coordinate.latitude, 37.3)
        XCTAssertTrue(combined.totalDistance > 0.0)
    }
    
    // MARK: - Test 24: Single Point Track
    
    public func testSinglePointTrack() throws {
        let xml = """
        <gpx version="1.1">
            <trk>
                <name>Single Point Summit</name>
                <trkseg>
                    <trkpt lat="37.75" lon="-122.45"><ele>280.0</ele></trkpt>
                </trkseg>
            </trk>
        </gpx>
        """
        let track = try parser.parse(xmlString: xml)
        XCTAssertEqual(track.points.count, 1)
        XCTAssertEqual(track.totalDistance, 0.0)
        XCTAssertEqual(track.elevationGain, 0.0)
        XCTAssertEqual(track.elevationLoss, 0.0)
        XCTAssertEqual(track.minElevation, 280.0)
        XCTAssertEqual(track.maxElevation, 280.0)
        XCTAssertEqual(track.bounds.minLatitude, 37.75)
        XCTAssertEqual(track.bounds.maxLatitude, 37.75)
        XCTAssertEqual(track.bounds.center.latitude, 37.75)
        XCTAssertEqual(track.bounds.center.longitude, -122.45)
    }
    
    // MARK: - Test 25: XML Entities in Track Name and Description
    
    public func testXMLEntitiesInTrackNameAndDescription() throws {
        let xml = """
        <gpx version="1.1">
            <trk>
                <name>Rock &amp; Trail &lt;High&gt; &quot;Scenic&quot;</name>
                <desc>It&apos;s a beautiful day &amp; ridge</desc>
                <trkseg>
                    <trkpt lat="37.75" lon="-122.45"/>
                </trkseg>
            </trk>
        </gpx>
        """
        let track = try parser.parse(xmlString: xml)
        XCTAssertEqual(track.name, "Rock & Trail <High> \"Scenic\"")
        XCTAssertEqual(track.trackDescription, "It's a beautiful day & ridge")
    }
    
    // MARK: - Test 26: Path Traversal Adversarial Vector Matrix
    
    public func testPathTraversalAdversarialVectors() async {
        let manager = await TrailManager(baseDirectory: tempDirectory, parser: parser, autoScan: false)
        
        let adversarialVectors = [
            "../../../etc/passwd",
            "/private/etc/hosts",
            "trail/../../sensitive.txt",
            "....//....//trail.gpx",
            "trail.gpx\0.txt",
            "..",
            "/",
            "\\",
            "trail/../trail.gpx",
            "%2e%2e%2f",
            "%2e%2e%2fetc%2fpasswd",
            "%2e%2e%5c",
            "%2e%2e%2fescape.gpx",
            "%252e%252e%252f",
            "%2500",
            "%252e%252e%255c",
            "%252e%252e%252fetc%252fpasswd.gpx"
        ]
        
        for vector in adversarialVectors {
            do {
                try await manager.deleteTrail(named: vector)
                XCTFail("Vector '\(vector)' should have been blocked by path traversal protection")
            } catch let err as TrailManagerError {
                switch err {
                case .pathTraversalDetected:
                    XCTAssertTrue(true)
                default:
                    XCTFail("Vector '\(vector)' resulted in unexpected TrailManagerError: \(err)")
                }
            } catch {
                XCTFail("Vector '\(vector)' resulted in unexpected error: \(error)")
            }
        }
    }
    
    // MARK: - Test 27: Reload Lifecycle & Published Property Updates
    
    public func testReloadUpdatesPublishedProperties() async throws {
        let manager = await TrailManager(baseDirectory: tempDirectory, parser: parser, autoScan: false)
        
        // Write a test GPX
        let gpx = "<gpx version=\"1.1\"><trk><name>Reload Test</name><trkseg><trkpt lat=\"37.0\" lon=\"-122.0\"/></trkseg></trk></gpx>"
        try gpx.write(to: tempDirectory.appendingPathComponent("reload.gpx"), atomically: true, encoding: .utf8)
        
        await manager.reload()
        
        let trails = await manager.importedTrails
        let loading = await manager.isLoading
        let err = await manager.errorMessage
        
        XCTAssertEqual(trails.count, 1)
        XCTAssertEqual(trails[0].name, "Reload Test")
        XCTAssertFalse(loading)
        XCTAssertNil(err)
    }
    
    // MARK: - Test 28: Symlink Traversal & External Deletion Defense
    
    public func testSymlinkTraversalAndExternalDeletionDefense() async throws {
        let fm = FileManager.default
        let outsideDir = fm.temporaryDirectory.appendingPathComponent("Outside_\(UUID().uuidString)")
        try fm.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outsideDir) }
        
        let externalTarget = outsideDir.appendingPathComponent("external.gpx")
        let externalGeoJSON = outsideDir.appendingPathComponent("external.geojson")
        try "EXTERNAL TARGET".write(to: externalTarget, atomically: true, encoding: .utf8)
        try "SECRET DATA".write(to: externalGeoJSON, atomically: true, encoding: .utf8)
        
        let symlinkInTrails = tempDirectory.appendingPathComponent("symlink.gpx")
        try fm.createSymbolicLink(at: symlinkInTrails, withDestinationURL: externalTarget)
        
        let manager = await TrailManager(baseDirectory: tempDirectory, parser: parser, autoScan: false)
        
        var threwExpectedError = false
        do {
            try await manager.deleteTrail(at: symlinkInTrails)
            XCTFail("Expected deleteTrail(at:) to throw pathTraversalDetected on external symlink")
        } catch let err as TrailManagerError {
            if case .pathTraversalDetected = err {
                threwExpectedError = true
            } else {
                XCTFail("Unexpected TrailManagerError: \(err)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        
        XCTAssertTrue(threwExpectedError, "Should throw pathTraversalDetected on symlink pointing outside")
        XCTAssertTrue(fm.fileExists(atPath: externalTarget.path), "External GPX target file must survive")
        XCTAssertTrue(fm.fileExists(atPath: externalGeoJSON.path), "External GeoJSON file must survive without being deleted")
    }
    
    // MARK: - Test 29: Percent-Encoded Traversal in File Import
    
    public func testPercentEncodedTraversalImport() async throws {
        let fm = FileManager.default
        let testVectors = [
            "%2e%2e%2fescape.gpx",
            "%252e%252e%252fetc%252fpasswd.gpx",
            "%252e%252e%255c",
            "%2500"
        ]
        let gpx = "<gpx version=\"1.1\"><trk><name>Escape</name><trkseg><trkpt lat=\"37.0\" lon=\"-122.0\"/></trkseg></trk></gpx>"
        let manager = await TrailManager(baseDirectory: tempDirectory, parser: parser, autoScan: false)
        
        for vector in testVectors {
            let evilURL = fm.temporaryDirectory.appendingPathComponent(vector)
            try gpx.write(to: evilURL, atomically: true, encoding: .utf8)
            defer { try? fm.removeItem(at: evilURL) }
            
            var threwExpectedError = false
            do {
                _ = try await manager.importTrail(from: evilURL)
                XCTFail("Expected importTrail(from:) to block percent-encoded traversal URL '\(vector)'")
            } catch let err as TrailManagerError {
                if case .pathTraversalDetected = err {
                    threwExpectedError = true
                } else {
                    XCTFail("Unexpected TrailManagerError for '\(vector)': \(err)")
                }
            } catch {
                XCTFail("Unexpected error for '\(vector)': \(error)")
            }
            
            XCTAssertTrue(threwExpectedError, "importTrail must reject traversal filename: \(vector)")
        }
    }
    
    // MARK: - Test 30: Cleanup Corrupted Destination File on Import Failure
    
    public func testCorruptImportFileCleanup() async throws {
        let fm = FileManager.default
        let corruptSourceURL = fm.temporaryDirectory.appendingPathComponent("corrupt_source_\(UUID().uuidString).gpx")
        try "<not valid xml <gpx>>>".write(to: corruptSourceURL, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: corruptSourceURL) }
        
        let manager = await TrailManager(baseDirectory: tempDirectory, parser: parser, autoScan: false)
        let expectedDestURL = tempDirectory.appendingPathComponent(corruptSourceURL.lastPathComponent)
        
        var threwError = false
        do {
            _ = try await manager.importTrail(from: corruptSourceURL)
            XCTFail("Expected corrupted GPX import to throw error")
        } catch {
            threwError = true
        }
        
        XCTAssertTrue(threwError, "Corrupt GPX should throw an error")
        XCTAssertFalse(fm.fileExists(atPath: expectedDestURL.path), "Orphaned corrupted file must be deleted from trails directory on failure")
    }
    
    // MARK: - Test 31: Interface Contract Aliases (scanDocumentsDirectory & importFile)
    
    public func testInterfaceContractAliases() async throws {
        let fm = FileManager.default
        let sampleURL = fm.temporaryDirectory.appendingPathComponent("alias_test_\(UUID().uuidString).gpx")
        let gpx = """
        <gpx version="1.1">
            <trk>
                <name>Interface Contract Trail</name>
                <trkseg>
                    <trkpt lat="37.75" lon="-122.45"/>
                </trkseg>
            </trk>
        </gpx>
        """
        try gpx.write(to: sampleURL, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: sampleURL) }
        
        let manager = await TrailManager(baseDirectory: tempDirectory, parser: parser, autoScan: false)
        
        // Test synchronous importFile(from:)
        let imported = try await manager.importFile(from: sampleURL)
        XCTAssertEqual(imported.name, "Interface Contract Trail")
        
        // Test synchronous scanDocumentsDirectory()
        let scanned = try await manager.scanDocumentsDirectory()
        XCTAssertEqual(scanned.count, 1)
        XCTAssertEqual(scanned.first?.name, "Interface Contract Trail")
    }
    
    // MARK: - Test 32: Coordinate NaN, Infinity, and Out-of-Range Validation
    
    public func testCoordinateNaNInfAndRangeValidation() throws {
        let xml = """
        <gpx version="1.1">
            <trk>
                <name>Sanitization Track</name>
                <trkseg>
                    <trkpt lat="NaN" lon="-122.0"/>
                    <trkpt lat="37.0" lon="Infinity"/>
                    <trkpt lat="95.0" lon="-122.0"/>
                    <trkpt lat="37.0" lon="-200.0"/>
                    <trkpt lat="37.75" lon="-122.45">
                        <ele>NaN</ele>
                    </trkpt>
                    <trkpt lat="37.76" lon="-122.44">
                        <ele>150.0</ele>
                    </trkpt>
                </trkseg>
            </trk>
        </gpx>
        """
        let track = try parser.parse(xmlString: xml)
        
        // Invalid points (lat=NaN, lon=Inf, lat=95, lon=-200) should be dropped
        XCTAssertEqual(track.points.count, 2)
        XCTAssertEqual(track.points[0].coordinate.latitude, 37.75)
        XCTAssertEqual(track.points[0].coordinate.longitude, -122.45)
        XCTAssertNil(track.points[0].elevation, "NaN elevation must be sanitized to nil")
        
        XCTAssertEqual(track.points[1].coordinate.latitude, 37.76)
        XCTAssertEqual(track.points[1].coordinate.longitude, -122.44)
        XCTAssertEqual(track.points[1].elevation, 150.0)
        
        XCTAssertTrue(track.totalDistance.isFinite)
        XCTAssertTrue(track.elevationGain.isFinite)
        
        // Verify JSON serialization doesn't crash on sanitized track
        let jsonData = try track.toGeoJSONData()
        XCTAssertTrue(jsonData.count > 0)
    }
    
    // MARK: - Test 33: GPXParser Re-Entrancy and Concurrent Parsing Safety
    
    public func testGPXParserReentrancyAndConcurrency() async throws {
        let sharedParser = GPXParser()
        let taskCount = 30
        
        let results = try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for i in 0..<taskCount {
                group.addTask {
                    let xml = """
                    <gpx version="1.1">
                        <trk>
                            <name>Concurrent Track \(i)</name>
                            <trkseg>
                                <trkpt lat="\(37.0 + Double(i) * 0.01)" lon="-122.0">
                                    <ele>\(100.0 + Double(i))</ele>
                                </trkpt>
                            </trkseg>
                        </trk>
                    </gpx>
                    """
                    let track = try sharedParser.parse(xmlString: xml)
                    return (i, track.name)
                }
            }
            
            var collected: [Int: String] = [:]
            for try await (id, name) in group {
                collected[id] = name
            }
            return collected
        }
        
        XCTAssertEqual(results.count, taskCount)
        for i in 0..<taskCount {
            XCTAssertEqual(results[i], "Concurrent Track \(i)")
        }
    }
    
    // MARK: - Test 34: Haversine Precision Clamping on Extremes
    
    public func testHaversinePrecisionClamping() {
        // Antipodal points
        let antipodalDist = GPXParser.haversineDistance(lat1: 0.0, lon1: 0.0, lat2: 0.0, lon2: 180.0)
        XCTAssertTrue(antipodalDist.isFinite, "Antipodal distance must be finite")
        XCTAssertFalse(antipodalDist.isNaN, "Antipodal distance must not be NaN")
        XCTAssertTrue(antipodalDist > 20_000_000.0)
        
        // Identical points
        let zeroDist = GPXParser.haversineDistance(lat1: 37.75, lon1: -122.45, lat2: 37.75, lon2: -122.45)
        XCTAssertEqual(zeroDist, 0.0)
        XCTAssertTrue(zeroDist.isFinite)
        XCTAssertFalse(zeroDist.isNaN)
    }
    
    // MARK: - Test 35: Double-Encoded Path Traversal Vectors (Remediation Iteration 3)
    
    public func testDoubleEncodedPathTraversalAdversarialVectors() async throws {
        let fm = FileManager.default
        let manager = await TrailManager(baseDirectory: tempDirectory, parser: parser, autoScan: false)
        let validGPX = "<gpx version=\"1.1\"><trk><name>Double Encoded</name><trkseg><trkpt lat=\"37.0\" lon=\"-122.0\"/></trkseg></trk></gpx>"
        
        // 1. deleteTrail(named: "%252e%252e%252f") throws pathTraversalDetected
        var delete1ThrewExpected = false
        do {
            try await manager.deleteTrail(named: "%252e%252e%252f")
            XCTFail("deleteTrail(named: '%252e%252e%252f') must not succeed")
        } catch let err as TrailManagerError {
            if case .pathTraversalDetected = err {
                delete1ThrewExpected = true
            } else {
                XCTFail("Unexpected TrailManagerError: \(err)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(delete1ThrewExpected, "deleteTrail(named: '%252e%252e%252f') must throw pathTraversalDetected")
        
        // 2. deleteTrail(named: "%2500") throws pathTraversalDetected
        var delete2ThrewExpected = false
        do {
            try await manager.deleteTrail(named: "%2500")
            XCTFail("deleteTrail(named: '%2500') must not succeed")
        } catch let err as TrailManagerError {
            if case .pathTraversalDetected = err {
                delete2ThrewExpected = true
            } else {
                XCTFail("Unexpected TrailManagerError: \(err)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(delete2ThrewExpected, "deleteTrail(named: '%2500') must throw pathTraversalDetected")
        
        // 3. importFile(from: srcURL) where filename is "%252e%252e%252fetc%252fpasswd.gpx" throws pathTraversalDetected
        let srcURL1 = fm.temporaryDirectory.appendingPathComponent("%252e%252e%252fetc%252fpasswd.gpx")
        try validGPX.write(to: srcURL1, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: srcURL1) }
        
        var import1ThrewExpected = false
        do {
            _ = try await manager.importFile(from: srcURL1)
            XCTFail("importFile(from: '%252e%252e%252fetc%252fpasswd.gpx') must not succeed")
        } catch let err as TrailManagerError {
            if case .pathTraversalDetected = err {
                import1ThrewExpected = true
            } else {
                XCTFail("Unexpected TrailManagerError: \(err)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(import1ThrewExpected, "importFile with '%252e%252e%252fetc%252fpasswd.gpx' must throw pathTraversalDetected")
        
        // 4. importFile(from: srcURL) where filename is "%252e%252e%255c" throws pathTraversalDetected
        let srcURL2 = fm.temporaryDirectory.appendingPathComponent("%252e%252e%255c")
        try validGPX.write(to: srcURL2, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: srcURL2) }
        
        var import2ThrewExpected = false
        do {
            _ = try await manager.importFile(from: srcURL2)
            XCTFail("importFile(from: '%252e%252e%255c') must not succeed")
        } catch let err as TrailManagerError {
            if case .pathTraversalDetected = err {
                import2ThrewExpected = true
            } else {
                XCTFail("Unexpected TrailManagerError: \(err)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(import2ThrewExpected, "importFile with '%252e%252e%255c' must throw pathTraversalDetected")
    }
}
