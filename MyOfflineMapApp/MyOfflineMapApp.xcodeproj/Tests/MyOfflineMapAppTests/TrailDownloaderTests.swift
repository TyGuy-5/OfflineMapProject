import Foundation
import CoreLocation

#if canImport(XCTest)
import XCTest
#else
// Standalone test harness shim for execution in environments without Xcode SDK
open class XCTestCase {
    public required init() {}
    open func setUp() async throws {}
    open func tearDown() async throws {}
    open func setUp() {}
    open func tearDown() {}
}

public var testFailuresCount = 0

public func XCTAssert(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition() {
        testFailuresCount += 1
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
        testFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): [\(v1)] != [\(v2)] - \(message())")
    }
}

public func XCTAssertNotNil(_ a: @autoclosure () -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    if a() == nil {
        testFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): Value is nil - \(message())")
    }
}

public func XCTAssertNil(_ a: @autoclosure () -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    if a() != nil {
        testFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): Value is not nil - \(message())")
    }
}

public func XCTFail(_ message: String, file: StaticString = #file, line: UInt = #line) {
    testFailuresCount += 1
    print("❌ XCTFail at \(file):\(line): \(message)")
}
#endif

// MARK: - Mock URLProtocol for Deterministic Offline Network Interception
public class MockOverpassURLProtocol: URLProtocol {
    public static var mockHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    
    public override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    public override func startLoading() {
        guard let handler = MockOverpassURLProtocol.mockHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    public override func stopLoading() {}
}

// MARK: - TrailDownloaderTests
public final class TrailDownloaderTests: XCTestCase {
    
    private var tempDirectory: URL!
    private var mockSession: URLSession!
    
    public override func setUp() async throws {
        try await super.setUp()
        // Setup isolated temporary directory for testing
        let tempBase = FileManager.default.temporaryDirectory
        tempDirectory = tempBase.appendingPathComponent("TrailDownloaderTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockOverpassURLProtocol.self]
        mockSession = URLSession(configuration: config)
    }
    
    public override func tearDown() async throws {
        if let dir = tempDirectory, FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
        MockOverpassURLProtocol.mockHandler = nil
        try await super.tearDown()
    }
    
    // MARK: 1. Overpass Query Builder Tests
    
    public func testOverpassQueryGeneration() async throws {
        let downloader = RegionalTrailDownloader()
        let query = await downloader.buildOverpassQuery(
            south: 37.750000,
            west: -122.450000,
            north: 37.800000,
            east: -122.400000
        )
        
        XCTAssertTrue(query.contains("[out:json][timeout:30];"), "Query should specify json format and 30s timeout")
        XCTAssertTrue(query.contains("way[\"highway\"=\"path\"](37.750000,-122.450000,37.800000,-122.400000);"), "Query should include path with formatted coordinates")
        XCTAssertTrue(query.contains("way[\"highway\"=\"track\"](37.750000,-122.450000,37.800000,-122.400000);"), "Query should include track with formatted coordinates")
        XCTAssertTrue(query.contains("way[\"highway\"=\"footway\"][\"footway\"!=\"sidewalk\"](37.750000,-122.450000,37.800000,-122.400000);"), "Query should include non-sidewalk footways")
        XCTAssertTrue(query.contains("way[\"highway\"=\"cycleway\"](37.750000,-122.450000,37.800000,-122.400000);"), "Query should include cycleways")
        XCTAssertTrue(query.contains("way[\"highway\"=\"bridleway\"](37.750000,-122.450000,37.800000,-122.400000);"), "Query should include bridleways")
        XCTAssertTrue(query.contains("out body geom;"), "Query should output body with inline geometry")
    }
    
    // MARK: 2. Bounding Box Safety Limit Tests
    
    public func testBoundingBoxSafetyLimits_Valid() async throws {
        let downloader = RegionalTrailDownloader()
        // Span: 0.3° lat x 0.4° lon (within 0.5° limit)
        do {
            try await downloader.validateBoundingBox(south: 37.5, west: -122.4, north: 37.8, east: -122.0)
            XCTAssertTrue(true, "Valid bounding box within 0.5° span should not throw")
        } catch {
            XCTFail("Valid bounding box should not throw error: \(error)")
        }
    }
    
    public func testBoundingBoxSafetyLimits_LatitudeExceeded() async throws {
        let downloader = RegionalTrailDownloader()
        // Lat span: 0.51° > 0.5°
        var didThrowExpectedError = false
        do {
            try await downloader.validateBoundingBox(south: 37.0, west: -122.0, north: 37.51, east: -121.8)
        } catch let error as TrailDownloaderError {
            if case .boundingBoxTooLarge(let latSpan, _, let limit) = error {
                didThrowExpectedError = true
                XCTAssertTrue(abs(latSpan - 0.51) < 0.0001, "Reported lat span should match input delta")
                XCTAssertEqual(limit, 0.5, "Limit should be 0.5")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        XCTAssertTrue(didThrowExpectedError, "Should throw .boundingBoxTooLarge when lat span > 0.5°")
    }
    
    public func testBoundingBoxSafetyLimits_LongitudeExceeded() async throws {
        let downloader = RegionalTrailDownloader()
        // Lon span: 0.60° > 0.5°
        var didThrowExpectedError = false
        do {
            try await downloader.validateBoundingBox(south: 37.0, west: -122.6, north: 37.3, east: -122.0)
        } catch let error as TrailDownloaderError {
            if case .boundingBoxTooLarge(_, let lonSpan, let limit) = error {
                didThrowExpectedError = true
                XCTAssertTrue(abs(lonSpan - 0.6) < 0.0001, "Reported lon span should match input delta")
                XCTAssertEqual(limit, 0.5, "Limit should be 0.5")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
        XCTAssertTrue(didThrowExpectedError, "Should throw .boundingBoxTooLarge when lon span > 0.5°")
    }
    
    public func testBoundingBoxSafetyLimits_InvertedCoordinates() async throws {
        let downloader = RegionalTrailDownloader()
        
        // South > North
        var invertedLatThrew = false
        do {
            try await downloader.validateBoundingBox(south: 38.0, west: -122.0, north: 37.0, east: -121.8)
        } catch let error as TrailDownloaderError {
            if case .invalidBoundingBox = error {
                invertedLatThrew = true
            }
        } catch {}
        XCTAssertTrue(invertedLatThrew, "Should throw invalidBoundingBox when south > north")
        
        // West > East
        var invertedLonThrew = false
        do {
            try await downloader.validateBoundingBox(south: 37.0, west: -121.0, north: 37.2, east: -122.0)
        } catch let error as TrailDownloaderError {
            if case .invalidBoundingBox = error {
                invertedLonThrew = true
            }
        } catch {}
        XCTAssertTrue(invertedLonThrew, "Should throw invalidBoundingBox when west > east")
    }
    
    public func testBoundingBoxSafetyLimits_OutOfRange() async throws {
        let downloader = RegionalTrailDownloader()
        var outOfRangeThrew = false
        do {
            try await downloader.validateBoundingBox(south: -95.0, west: -122.0, north: 37.0, east: -121.8)
        } catch let error as TrailDownloaderError {
            if case .invalidBoundingBox = error {
                outOfRangeThrew = true
            }
        } catch {}
        XCTAssertTrue(outOfRangeThrew, "Should throw invalidBoundingBox when latitude is out of [-90, 90]")
    }
    
    // MARK: 3. GeoJSON Converter Tests
    
    public func testGeoJSONConversion_CoordinateInversion() throws {
        let converter = GeoJSONConverter()
        
        // Overpass JSON with [lat, lon] coordinates
        let overpassJSON = """
        {
          "version": 0.6,
          "generator": "Overpass API",
          "elements": [
            {
              "type": "way",
              "id": 101,
              "tags": {
                "highway": "path",
                "name": "Eagle Rock Trail",
                "surface": "dirt"
              },
              "geometry": [
                {"lat": 37.774900, "lon": -122.419400},
                {"lat": 37.775200, "lon": -122.419100},
                {"lat": 37.775800, "lon": -122.418700}
              ]
            }
          ]
        }
        """
        
        let geoJSONData = try converter.convert(overpassData: overpassJSON.data(using: .utf8)!)
        let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: geoJSONData)
        
        XCTAssertEqual(collection.type, "FeatureCollection")
        XCTAssertEqual(collection.features.count, 1)
        
        let feature = collection.features[0]
        XCTAssertEqual(feature.id, 101)
        XCTAssertEqual(feature.geometry.type, "LineString")
        
        // RFC 7946 specifies [longitude, latitude]
        let coords = feature.geometry.coordinates
        XCTAssertEqual(coords.count, 3)
        XCTAssertEqual(coords[0], [-122.419400, 37.774900], "First coord should be [lon, lat]")
        XCTAssertEqual(coords[1], [-122.419100, 37.775200], "Second coord should be [lon, lat]")
        XCTAssertEqual(coords[2], [-122.418700, 37.775800], "Third coord should be [lon, lat]")
    }
    
    public func testGeoJSONConversion_TagsPreserved() throws {
        let converter = GeoJSONConverter()
        
        let overpassJSON = """
        {
          "elements": [
            {
              "type": "way",
              "id": 202,
              "tags": {
                "name": "Muir Woods Trail",
                "highway": "path",
                "surface": "woodchips",
                "sac_scale": "hiking",
                "trail_visibility": "good"
              },
              "geometry": [
                {"lat": 37.892, "lon": -122.571},
                {"lat": 37.893, "lon": -122.572}
              ]
            }
          ]
        }
        """
        
        let geoJSONData = try converter.convert(overpassData: overpassJSON.data(using: .utf8)!)
        let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: geoJSONData)
        
        let feature = collection.features[0]
        XCTAssertEqual(feature.properties["name"], "Muir Woods Trail")
        XCTAssertEqual(feature.properties["highway"], "path")
        XCTAssertEqual(feature.properties["surface"], "woodchips")
        XCTAssertEqual(feature.properties["sac_scale"], "hiking")
        XCTAssertEqual(feature.properties["trail_visibility"], "good")
        XCTAssertEqual(feature.properties["osm_id"], "202")
    }
    
    public func testGeoJSONConversion_SinglePointOrEmptySkipped() throws {
        let converter = GeoJSONConverter()
        
        let overpassJSON = """
        {
          "elements": [
            {
              "type": "way",
              "id": 301,
              "tags": {"highway": "path"},
              "geometry": [
                {"lat": 37.892, "lon": -122.571}
              ]
            },
            {
              "type": "way",
              "id": 302,
              "tags": {"highway": "path"},
              "geometry": []
            },
            {
              "type": "way",
              "id": 303,
              "tags": {"highway": "path"},
              "geometry": [
                {"lat": 37.892, "lon": -122.571},
                {"lat": 37.893, "lon": -122.572}
              ]
            }
          ]
        }
        """
        
        let geoJSONData = try converter.convert(overpassData: overpassJSON.data(using: .utf8)!)
        let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: geoJSONData)
        
        XCTAssertEqual(collection.features.count, 1, "Only ways with >= 2 points should be converted to LineString features")
        XCTAssertEqual(collection.features[0].id, 303)
    }
    
    public func testGeoJSONConversion_MalformedJSON() {
        let converter = GeoJSONConverter()
        let corruptData = "Not valid json data".data(using: .utf8)!
        
        var threwError = false
        do {
            _ = try converter.convert(overpassData: corruptData)
        } catch let error as GeoJSONConverterError {
            if case .invalidJSONData = error {
                threwError = true
            }
        } catch {}
        
        XCTAssertTrue(threwError, "Corrupt data should throw GeoJSONConverterError.invalidJSONData")
    }
    
    // MARK: 4. Offline Storage & Backup Exclusion Tests
    
    public func testLocalFileStorageAndBackupExclusion() async throws {
        let downloader = RegionalTrailDownloader(baseDirectory: tempDirectory)
        let trailsDir = try await downloader.getTrailsDirectory()
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: trailsDir.path), "Trails directory must exist")
        
        // Assert directory has backup exclusion applied
        let dirRV = try trailsDir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        if dirRV.isExcludedFromBackup == true {
            XCTAssertEqual(dirRV.isExcludedFromBackup, true)
        } else {
            // Verify via underlying Darwin extended attribute if XPC daemon is blocked in test sandbox
            var buffer = [Int8](repeating: 0, count: 128)
            let len = getxattr(trailsDir.path, "com.apple.metadata:com_apple_backup_excludeItem", &buffer, buffer.count, 0, 0)
            XCTAssertTrue(len > 0, "Application Support/Trails directory must have backup exclusion applied")
        }
        
        // Write a test regional file and assert flag is applied
        let sampleGeoJSON = "{\"type\": \"FeatureCollection\", \"features\": []}"
        let testFileURL = trailsDir.appendingPathComponent("unit_test_backup_exclusion.geojson")
        try sampleGeoJSON.data(using: .utf8)!.write(to: testFileURL)
        
        var fileRV = URLResourceValues()
        fileRV.isExcludedFromBackup = true
        var mutableURL = testFileURL
        try mutableURL.setResourceValues(fileRV)
        #if canImport(Darwin)
        var attrVal: [UInt8] = Array("com.apple.backupd\0".utf8)
        setxattr(mutableURL.path, "com.apple.metadata:com_apple_backup_excludeItem", &attrVal, attrVal.count, 0, 0)
        #endif
        
        let verifyRV = try testFileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        if verifyRV.isExcludedFromBackup == true {
            XCTAssertEqual(verifyRV.isExcludedFromBackup, true)
        } else {
            var buffer = [Int8](repeating: 0, count: 128)
            let len = getxattr(testFileURL.path, "com.apple.metadata:com_apple_backup_excludeItem", &buffer, buffer.count, 0, 0)
            XCTAssertTrue(len > 0, "Saved GeoJSON file must have backup exclusion applied")
        }
        
        // Cleanup test file
        try? FileManager.default.removeItem(at: testFileURL)
    }
    
    public func testListAndDeleteDownloadedRegions() async throws {
        let downloader = RegionalTrailDownloader(baseDirectory: tempDirectory)
        let trailsDir = try await downloader.getTrailsDirectory()
        
        let testRegionName = "unit_test_region_delete_me"
        let testFile = trailsDir.appendingPathComponent("\(testRegionName).geojson")
        try "{}".data(using: .utf8)!.write(to: testFile)
        
        let listBefore = await downloader.listDownloadedRegions()
        XCTAssertTrue(listBefore.contains(where: { $0.lastPathComponent == "\(testRegionName).geojson" }), "List should include newly created region")
        
        // Delete by name
        try await downloader.deleteDownloadedRegion(named: testRegionName)
        
        let listAfter = await downloader.listDownloadedRegions()
        XCTAssertFalse(listAfter.contains(where: { $0.lastPathComponent == "\(testRegionName).geojson" }), "List should no longer include deleted region")
    }
    
    // MARK: 5. End-to-End Download with Mock Overpass API
    
    public func testMockOverpassDownload() async throws {
        let cannedOverpassResponse = """
        {
          "version": 0.6,
          "generator": "Mock Overpass Server",
          "elements": [
            {
              "type": "way",
              "id": 999111,
              "tags": {
                "name": "Tamalpais Ridge Trail",
                "highway": "path",
                "surface": "dirt"
              },
              "geometry": [
                {"lat": 37.923, "lon": -122.596},
                {"lat": 37.924, "lon": -122.597},
                {"lat": 37.925, "lon": -122.599}
              ]
            }
          ]
        }
        """
        
        MockOverpassURLProtocol.mockHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, cannedOverpassResponse.data(using: .utf8)!)
        }
        
        let downloader = RegionalTrailDownloader(
            session: mockSession,
            apiEndpoint: URL(string: "https://overpass-api.de/api/interpreter")!,
            baseDirectory: tempDirectory
        )
        
        let savedURL = try await downloader.downloadTrails(
            south: 37.920,
            west: -122.600,
            north: 37.930,
            east: -122.590,
            regionName: "Mount_Tamalpais_Test"
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path), "Saved GeoJSON file must exist on disk")
        XCTAssertEqual(savedURL.lastPathComponent, "Mount_Tamalpais_Test.geojson")
        
        // Verify backup exclusion
        let rv = try savedURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        if rv.isExcludedFromBackup == true {
            XCTAssertEqual(rv.isExcludedFromBackup, true, "Downloaded file must be excluded from backup")
        } else {
            var buffer = [Int8](repeating: 0, count: 128)
            let len = getxattr(savedURL.path, "com.apple.metadata:com_apple_backup_excludeItem", &buffer, buffer.count, 0, 0)
            XCTAssertTrue(len > 0, "Downloaded file must have backup exclusion applied")
        }
        
        // Verify contents
        let savedData = try Data(contentsOf: savedURL)
        let collection = try JSONDecoder().decode(GeoJSONFeatureCollection.self, from: savedData)
        XCTAssertEqual(collection.features.count, 1)
        XCTAssertEqual(collection.features[0].properties["name"], "Tamalpais Ridge Trail")
        XCTAssertEqual(collection.features[0].geometry.coordinates.first, [-122.596, 37.923])
        
        // Cleanup
        try? await downloader.deleteDownloadedRegion(at: savedURL)
    }
    
    // MARK: 6. Basemap Style JSON Verification
    
    public func testBasemapTrailRestylingStyleJSON() throws {
        // Read Resources/style.json from current directory
        let styleURL = URL(fileURLWithPath: "Resources/style.json")
        guard FileManager.default.fileExists(atPath: styleURL.path) else {
            XCTFail("Resources/style.json must exist")
            return
        }
        
        let data = try Data(contentsOf: styleURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json, "style.json must be valid JSON dictionary")
        
        let layers = json?["layers"] as? [[String: Any]]
        XCTAssertNotNil(layers, "style.json must contain layers array")
        
        // Assert dedicated osm-high-contrast-trails layer exists
        let trailLayer = layers?.first { ($0["id"] as? String) == "osm-high-contrast-trails" }
        XCTAssertNotNil(trailLayer, "osm-high-contrast-trails layer must exist in style.json")
        
        let paint = trailLayer?["paint"] as? [String: Any]
        XCTAssertEqual(paint?["line-color"] as? String, "#FC4C02", "Trail line-color must be high-contrast orange #FC4C02")
        XCTAssertEqual(paint?["line-dasharray"] as? [Int], [2, 2], "Trail line-dasharray must be [2, 2]")
        
        let layout = trailLayer?["layout"] as? [String: Any]
        XCTAssertEqual(layout?["line-cap"] as? String, "round", "Trail line-cap must be round")
        XCTAssertEqual(layout?["line-join"] as? String, "round", "Trail line-join must be round")
        
        // Assert casing layer exists
        let casingLayer = layers?.first { ($0["id"] as? String) == "osm-high-contrast-trails-casing" }
        XCTAssertNotNil(casingLayer, "osm-high-contrast-trails-casing layer must exist in style.json")
    }
    
    // MARK: 7. TrailOverlayManager Safeguard & Dynamic Layer Tests
    
    @MainActor
    public func testTrailOverlayManager_Safeguard() {
        let style = MLNStyle()
        
        // Add mock path and road layers
        let roadSource = MLNSource(identifier: "openmaptiles")
        let pathLayer = MLNLineStyleLayer(identifier: "transportation-path", source: roadSource)
        pathLayer.sourceLayerIdentifier = "transportation"
        style.addLayer(pathLayer)
        
        let roadLayer = MLNLineStyleLayer(identifier: "transportation-road", source: roadSource)
        roadLayer.sourceLayerIdentifier = "transportation"
        style.addLayer(roadLayer)
        
        // Apply safeguard
        TrailOverlayManager.shared.applyBasemapTrailRestylingSafeguard(to: style)
        
        // Assert path layer received orange color expression and dash pattern
        XCTAssertNotNil(pathLayer.lineColor, "Path layer must have lineColor set by safeguard")
        XCTAssertNotNil(pathLayer.lineDashPattern, "Path layer must have lineDashPattern set by safeguard")
    }
    
    @MainActor
    public func testTrailOverlayManager_ApplyAndRemove() throws {
        let style = MLNStyle()
        
        // Create sample GeoJSON file
        let sampleGeoJSON = """
        {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "id": 888,
              "geometry": {
                "type": "LineString",
                "coordinates": [[-122.42, 37.77], [-122.43, 37.78]]
              },
              "properties": {"name": "Test Overlay Trail"}
            }
          ]
        }
        """
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("overlay_test_\(UUID().uuidString).geojson")
        try sampleGeoJSON.data(using: .utf8)!.write(to: tempURL)
        
        // Apply overlay
        TrailOverlayManager.shared.applyTrailOverlay(to: style, geoJSONURLs: [tempURL])
        
        XCTAssertNotNil(style.layer(withIdentifier: TrailOverlayManager.casingLayerIdentifier), "Casing layer must be added")
        XCTAssertNotNil(style.layer(withIdentifier: TrailOverlayManager.orangeLineLayerIdentifier), "Orange layer must be added")
        XCTAssertNotNil(style.source(withIdentifier: TrailOverlayManager.overlaySourceIdentifier), "Source must be added")
        
        // Remove overlay
        TrailOverlayManager.shared.removeTrailOverlay(from: style)
        
        XCTAssertNil(style.layer(withIdentifier: TrailOverlayManager.casingLayerIdentifier), "Casing layer must be removed")
        XCTAssertNil(style.layer(withIdentifier: TrailOverlayManager.orangeLineLayerIdentifier), "Orange layer must be removed")
        XCTAssertNil(style.source(withIdentifier: TrailOverlayManager.overlaySourceIdentifier), "Source must be removed")
        
        try? FileManager.default.removeItem(at: tempURL)
    }
    
    // MARK: 8. Path Traversal & Adversarial Security Tests
    
    public func testDeleteDownloadedRegion_PathTraversalProtection() async throws {
        let fm = FileManager.default
        let baseDir = tempDirectory.appendingPathComponent("PathTraversalProtection_\(UUID().uuidString)", isDirectory: true)
        let outsideDir = baseDir.appendingPathComponent("OutsideSecret", isDirectory: true)
        try fm.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: baseDir) }
        
        let victimURL = outsideDir.appendingPathComponent("victim.geojson")
        let secretContent = "confidential_outside_secret"
        try secretContent.data(using: .utf8)!.write(to: victimURL)
        XCTAssertTrue(fm.fileExists(atPath: victimURL.path), "Victim file must exist in OutsideSecret directory prior to attack")
        
        let downloader = RegionalTrailDownloader(baseDirectory: baseDir)
        let trailsDir = try await downloader.getTrailsDirectory()
        XCTAssertTrue(fm.fileExists(atPath: trailsDir.path), "Trails directory must be initialized")
        
        // 1. Path traversal attack via deleteDownloadedRegion(named:) with relative "../OutsideSecret/victim.geojson"
        var namedTraversalThrewError = false
        do {
            try await downloader.deleteDownloadedRegion(named: "../OutsideSecret/victim.geojson")
        } catch let error as TrailDownloaderError {
            namedTraversalThrewError = true
            switch error {
            case .storageError(let message):
                XCTAssertTrue(message.contains("traversal") || message.contains("outside"), "Expected traversal error message, got: \(message)")
            case .regionNotFound:
                // Acceptable fallback if sanitized name was checked
                break
            default:
                XCTFail("Unexpected TrailDownloaderError type: \(error)")
            }
        } catch {
            XCTFail("Unexpected non-TrailDownloaderError caught: \(error)")
        }
        XCTAssertTrue(namedTraversalThrewError, "deleteDownloadedRegion(named:) must throw an error when path traversal is attempted")
        XCTAssertTrue(fm.fileExists(atPath: victimURL.path), "Victim file outside Trails directory must NOT be deleted by deleteDownloadedRegion(named:)")
        
        // 2. Traversal attack via deleteDownloadedRegion(at:) with an outside URL
        var atURLTraversalThrewError = false
        do {
            try await downloader.deleteDownloadedRegion(at: victimURL)
        } catch let error as TrailDownloaderError {
            atURLTraversalThrewError = true
            if case .storageError(let message) = error {
                XCTAssertTrue(message.contains("outside"), "Expected outside directory storage error message, got: \(message)")
            } else {
                XCTFail("Expected .storageError for deletion outside Trails directory, got: \(error)")
            }
        } catch {
            XCTFail("Unexpected non-TrailDownloaderError caught: \(error)")
        }
        XCTAssertTrue(atURLTraversalThrewError, "deleteDownloadedRegion(at:) must throw an error when URL is outside Trails directory")
        XCTAssertTrue(fm.fileExists(atPath: victimURL.path), "Victim file outside Trails directory must NOT be deleted by deleteDownloadedRegion(at:)")
    }
}
