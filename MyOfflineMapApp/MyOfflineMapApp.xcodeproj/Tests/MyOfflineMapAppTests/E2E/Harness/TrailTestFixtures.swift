import Foundation
import CoreLocation

#if canImport(XCTest)
import XCTest
#else
// Standalone XCTest compatibility shim for compilation and execution in environments without Xcode SDK
open class XCTestCase {
    public required init() {}
    open func setUp() async throws {}
    open func tearDown() async throws {}
    open func setUp() {}
    open func tearDown() {}
}

public var globalTestFailuresCount = 0

public func XCTAssert(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    if !condition() {
        globalTestFailuresCount += 1
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
    let v1 = a(), v2 = b()
    if v1 != v2 {
        globalTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): [\(v1)] != [\(v2)] - \(message())")
    }
}
public func XCTAssertNotNil(_ a: @autoclosure () -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    if a() == nil {
        globalTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): Value is nil - \(message())")
    }
}
public func XCTAssertNil(_ a: @autoclosure () -> Any?, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    if a() != nil {
        globalTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): Value is not nil - \(message())")
    }
}
public func XCTAssertGreaterThan(_ a: @autoclosure () -> Double, _ b: @autoclosure () -> Double, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    let v1 = a(), v2 = b()
    if !(v1 > v2) {
        globalTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): [\(v1)] not > [\(v2)] - \(message())")
    }
}
public func XCTAssertGreaterThanOrEqual<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    let v1 = a(), v2 = b()
    if !(v1 >= v2) {
        globalTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): [\(v1)] not >= [\(v2)] - \(message())")
    }
}
public func XCTAssertLessThan(_ a: @autoclosure () -> Double, _ b: @autoclosure () -> Double, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    let v1 = a(), v2 = b()
    if !(v1 < v2) {
        globalTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): [\(v1)] not < [\(v2)] - \(message())")
    }
}
public func XCTAssertLessThanOrEqual<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {
    let v1 = a(), v2 = b()
    if !(v1 <= v2) {
        globalTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): [\(v1)] not <= [\(v2)] - \(message())")
    }
}
public func XCTAssertEqualWithAccuracy(_ a: Double, _ b: Double, accuracy: Double, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    if abs(a - b) > accuracy {
        globalTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): |\(a) - \(b)| > \(accuracy) - \(message)")
    }
}
public func XCTFail(_ message: String, file: StaticString = #file, line: UInt = #line) {
    globalTestFailuresCount += 1
    print("❌ XCTFail at \(file):\(line): \(message)")
}

public struct XCTSkip: Error {
    public let message: String
    public init(_ message: String = "") {
        self.message = message
    }
}

public func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line, _ errorHandler: (Error) -> Void = { _ in }) {
    do {
        _ = try expression()
        globalTestFailuresCount += 1
        print("❌ Assertion Failed at \(file):\(line): Expected error to be thrown - \(message())")
    } catch {
        errorHandler(error)
    }
}
#endif

#if canImport(MyOfflineMapApp)
@testable import MyOfflineMapApp
#endif

// MARK: - M1 Dependency Test Doubles
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
    public var shouldThrowError: Bool = false

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

    public init() {}

    private func recordCall(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, costing: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        _calculateRouteCallCount += 1
        _lastOrigin = origin
        _lastDestination = destination
        _lastCosting = costing
        return shouldThrowError
    }

    public func calculateRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        costing: String
    ) async throws -> RouteResponse {
        let shouldThrow = recordCall(from: origin, to: destination, costing: costing)

        if shouldThrow {
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

// MARK: - Style JSON Loader Helper
public func loadBasemapStyleJSON() throws -> [String: Any] {
    let styleURL: URL
    if FileManager.default.fileExists(atPath: "Resources/style.json") {
        styleURL = URL(fileURLWithPath: "Resources/style.json")
    } else {
        let thisFile = URL(fileURLWithPath: #filePath)
        let projectRoot = thisFile
            .deletingLastPathComponent() // Harness
            .deletingLastPathComponent() // E2E
            .deletingLastPathComponent() // MyOfflineMapAppTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // Project Root
        styleURL = projectRoot.appendingPathComponent("Resources/style.json")
    }
    guard FileManager.default.fileExists(atPath: styleURL.path) else {
        throw XCTSkip("Resources/style.json not found at \(styleURL.path)")
    }
    let data = try Data(contentsOf: styleURL)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw XCTSkip("Resources/style.json is not valid JSON dictionary")
    }
    return json
}

// MARK: - LocationManager Harness Wrapper per PROJECT.md §M4
public final class E2ELocationManager: @unchecked Sendable {
    public static let shared = E2ELocationManager()
    public private(set) var activityType: CLActivityType = .otherNavigation
    public private(set) var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    public let clLocationManager = CLLocationManager()
    
    public init() {
        clLocationManager.desiredAccuracy = kCLLocationAccuracyBest
        clLocationManager.activityType = .otherNavigation
    }
    
    public func setActivityType(_ type: CLActivityType) {
        self.activityType = type
        self.clLocationManager.activityType = type
    }
    
    public func resetToDefaults() {
        self.activityType = .otherNavigation
        self.clLocationManager.activityType = .otherNavigation
        self.desiredAccuracy = kCLLocationAccuracyBest
        self.clLocationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
}

// MARK: - Shared E2E Data Models & Interface Contracts per PROJECT.md


public struct E2EGPXTrackPoint: Equatable, Sendable {
    public let coordinate: CLLocationCoordinate2D
    public let elevation: Double?
    public let time: Date?
    public let cumulativeDistance: Double
    
    public init(coordinate: CLLocationCoordinate2D, elevation: Double? = nil, time: Date? = nil, cumulativeDistance: Double = 0.0) {
        self.coordinate = coordinate
        self.elevation = elevation
        self.time = time
        self.cumulativeDistance = cumulativeDistance
    }
    
    public static func == (lhs: E2EGPXTrackPoint, rhs: E2EGPXTrackPoint) -> Bool {
        return lhs.coordinate.latitude == rhs.coordinate.latitude &&
               lhs.coordinate.longitude == rhs.coordinate.longitude &&
               lhs.elevation == rhs.elevation &&
               lhs.time == rhs.time &&
               lhs.cumulativeDistance == rhs.cumulativeDistance
    }
}

public struct E2EGPXTrack: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let points: [E2EGPXTrackPoint]
    public let totalDistance: Double
    public let elevationGain: Double
    public let elevationLoss: Double
    public let fileURL: URL?
    
    public init(
        id: UUID = UUID(),
        name: String,
        points: [E2EGPXTrackPoint],
        totalDistance: Double,
        elevationGain: Double,
        elevationLoss: Double,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.points = points
        self.totalDistance = totalDistance
        self.elevationGain = elevationGain
        self.elevationLoss = elevationLoss
        self.fileURL = fileURL
    }
    
    public static func == (lhs: E2EGPXTrack, rhs: E2EGPXTrack) -> Bool {
        return lhs.id == rhs.id && lhs.name == rhs.name && lhs.points.count == rhs.points.count
    }
}

// MARK: - Shared E2E GPX Parser per PROJECT.md §M3
public final class E2EGPXParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var points: [E2EGPXTrackPoint] = []
    private var trackName: String = "Untitled Track"
    private var currentElement: String = ""
    private var currentText: String = ""
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle: Double?
    private var currentTime: Date?
    private var cumulativeDistance: Double = 0.0
    private var elevationGain: Double = 0.0
    private var elevationLoss: Double = 0.0
    private var lastCoordinate: CLLocationCoordinate2D?
    private var lastElevation: Double?
    
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private static let isoFallbackFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    
    public func parse(xmlString: String) throws -> E2EGPXTrack {
        guard let data = xmlString.data(using: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }
        return try parse(data: data)
    }
    
    public func parse(data: Data) throws -> E2EGPXTrack {
        points.removeAll()
        trackName = "Untitled Track"
        cumulativeDistance = 0.0
        elevationGain = 0.0
        elevationLoss = 0.0
        lastCoordinate = nil
        lastElevation = nil
        
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() else {
            throw parser.parserError ?? URLError(.cannotParseResponse)
        }
        
        return E2EGPXTrack(
            name: trackName,
            points: points,
            totalDistance: cumulativeDistance,
            elevationGain: elevationGain,
            elevationLoss: elevationLoss
        )
    }
    
    public func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentText = ""
        
        if elementName == "trkpt" {
            if let latStr = attributeDict["lat"], let lat = Double(latStr),
               let lonStr = attributeDict["lon"], let lon = Double(lonStr) {
                currentLat = lat
                currentLon = lon
            }
            currentEle = nil
            currentTime = nil
        }
    }
    
    public func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
    
    public func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if elementName == "name" && trackName == "Untitled Track" && !trimmed.isEmpty {
            trackName = trimmed
        } else if elementName == "ele" {
            currentEle = Double(trimmed)
        } else if elementName == "time" {
            currentTime = Self.isoFormatter.date(from: trimmed) ?? Self.isoFallbackFormatter.date(from: trimmed)
        } else if elementName == "trkpt" {
            if let lat = currentLat, let lon = currentLon {
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                if let lastCoord = lastCoordinate {
                    let d = LocationSequenceBuilder.distance(from: lastCoord, to: coord)
                    cumulativeDistance += d
                }
                lastCoordinate = coord
                
                if let ele = currentEle {
                    if let lastEle = lastElevation {
                        let diff = ele - lastEle
                        if diff > 0 { elevationGain += diff }
                        else { elevationLoss += abs(diff) }
                    }
                    lastElevation = ele
                }
                
                points.append(E2EGPXTrackPoint(
                    coordinate: coord,
                    elevation: currentEle,
                    time: currentTime,
                    cumulativeDistance: cumulativeDistance
                ))
            }
            currentLat = nil
            currentLon = nil
            currentEle = nil
            currentTime = nil
        }
    }
}

// MARK: - Shared E2E Trail Navigator per PROJECT.md §M4
public final class E2ETrailNavigator: @unchecked Sendable {
    public private(set) var activeTrack: E2EGPXTrack?
    public private(set) var userProgressDistance: Double = 0.0
    public private(set) var remainingDistance: Double = 0.0
    public private(set) var currentElevation: Double? = nil
    public private(set) var crossTrackDeviation: Double = 0.0
    public private(set) var isOffTrail: Bool = false
    
    public var offTrailThresholdMeters: Double = 25.0
    public var recoveryThresholdMeters: Double = 18.0
    public var audioAlertSpy: MockAudioAlertSpy?
    
    private var lastAlertTime: Date?
    public var debounceIntervalSeconds: TimeInterval = 10.0
    
    public init(audioAlertSpy: MockAudioAlertSpy? = nil) {
        self.audioAlertSpy = audioAlertSpy
    }
    
    public func startNavigation(track: E2EGPXTrack) {
        self.activeTrack = track
        self.userProgressDistance = 0.0
        self.remainingDistance = track.totalDistance
        self.currentElevation = track.points.first?.elevation
        self.crossTrackDeviation = 0.0
        self.isOffTrail = false
        self.lastAlertTime = nil
    }
    
    public func stopNavigation() {
        self.activeTrack = nil
        self.userProgressDistance = 0.0
        self.remainingDistance = 0.0
        self.currentElevation = nil
        self.crossTrackDeviation = 0.0
        self.isOffTrail = false
    }
    
    @discardableResult
    public func updateLocation(_ location: CLLocation) -> (isOffTrail: Bool, deviation: Double) {
        guard let track = activeTrack, !track.points.isEmpty else {
            return (false, 0.0)
        }
        
        var minDistance = Double.infinity
        var closestIndex = 0
        for (idx, pt) in track.points.enumerated() {
            let dist = LocationSequenceBuilder.distance(from: location.coordinate, to: pt.coordinate)
            if dist < minDistance {
                minDistance = dist
                closestIndex = idx
            }
        }
        
        self.crossTrackDeviation = minDistance
        let closestPoint = track.points[closestIndex]
        self.userProgressDistance = closestPoint.cumulativeDistance
        self.remainingDistance = max(0.0, track.totalDistance - closestPoint.cumulativeDistance)
        self.currentElevation = closestPoint.elevation
        
        if minDistance > offTrailThresholdMeters {
            if !isOffTrail {
                isOffTrail = true
                triggerAlert(deviation: minDistance)
            } else {
                triggerAlertIfNeeded(deviation: minDistance)
            }
        } else if minDistance < recoveryThresholdMeters {
            isOffTrail = false
        }
        
        return (isOffTrail, minDistance)
    }
    
    private func triggerAlert(deviation: Double) {
        lastAlertTime = Date()
        audioAlertSpy?.recordAlert(deviationMeters: deviation, alertType: "offTrail")
    }
    
    private func triggerAlertIfNeeded(deviation: Double) {
        let now = Date()
        if let last = lastAlertTime {
            if now.timeIntervalSince(last) >= debounceIntervalSeconds {
                lastAlertTime = now
                audioAlertSpy?.recordAlert(deviationMeters: deviation, alertType: "offTrailDebounced")
            }
        } else {
            triggerAlert(deviation: deviation)
        }
    }
}

// MARK: - Authoritative Repository of Test Fixtures
public struct TrailTestFixtures: Sendable {
    
    // MARK: - Valid GPX Fixtures
    
    public static let validGPXString: String = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="MyOfflineMapAppTests" xmlns="http://www.topografix.com/GPX/1/1">
      <metadata>
        <name>Mount Sentinel Trail</name>
        <desc>Classic Missoula zig-zag trail to the iconic M.</desc>
        <time>2026-11-21T08:00:00Z</time>
      </metadata>
      <trk>
        <name>Mount Sentinel Trail</name>
        <trkseg>
          <trkpt lat="46.852900" lon="-113.985000">
            <ele>980.5</ele>
            <time>2026-11-21T08:00:00Z</time>
          </trkpt>
          <trkpt lat="46.853500" lon="-113.983500">
            <ele>1015.0</ele>
            <time>2026-11-21T08:05:00Z</time>
          </trkpt>
          <trkpt lat="46.854200" lon="-113.981800">
            <ele>1058.2</ele>
            <time>2026-11-21T08:10:00Z</time>
          </trkpt>
          <trkpt lat="46.854900" lon="-113.980200">
            <ele>1102.7</ele>
            <time>2026-11-21T08:16:00Z</time>
          </trkpt>
          <trkpt lat="46.855800" lon="-113.978500">
            <ele>1158.0</ele>
            <time>2026-11-21T08:24:00Z</time>
          </trkpt>
        </trkseg>
      </trk>
    </gpx>
    """
    
    public static let multiSegmentGPXString: String = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="MyOfflineMapAppTests">
      <trk>
        <name>Two-Part Ridge Trek</name>
        <trkseg>
          <trkpt lat="37.7749" lon="-122.4194"><ele>10.0</ele></trkpt>
          <trkpt lat="37.7755" lon="-122.4190"><ele>25.0</ele></trkpt>
        </trkseg>
        <trkseg>
          <trkpt lat="37.7760" lon="-122.4185"><ele>40.0</ele></trkpt>
          <trkpt lat="37.7765" lon="-122.4180"><ele>55.0</ele></trkpt>
        </trkseg>
      </trk>
    </gpx>
    """
    
    public static let alpineTrekGPXString: String = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="MyOfflineMapAppTests">
      <trk>
        <name>Chamonix to Aiguille du Midi</name>
        <trkseg>
          <trkpt lat="45.9237" lon="6.8694"><ele>1035.0</ele></trkpt>
          <trkpt lat="45.9080" lon="6.8770"><ele>1800.0</ele></trkpt>
          <trkpt lat="45.8920" lon="6.8820"><ele>2700.0</ele></trkpt>
          <trkpt lat="45.8778" lon="6.8872"><ele>3842.0</ele></trkpt>
        </trkseg>
      </trk>
    </gpx>
    """

    // MARK: - Adversarial & Edge GPX Fixtures
    
    public static let corruptGPXString: String = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1"><trk><name>Unclosed Tag<trkseg><trkpt lat="46.85" lon="-113.98">
    """
    
    public static let emptyGPXString: String = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="MyOfflineMapAppTests">
      <trk>
        <name>Zero Points Trail</name>
        <trkseg>
        </trkseg>
      </trk>
    </gpx>
    """
    
    public static let singlePointGPXString: String = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1" creator="MyOfflineMapAppTests">
      <trk>
        <name>Single Landmark Point</name>
        <trkseg>
          <trkpt lat="37.7749" lon="-122.4194"><ele>15.0</ele></trkpt>
        </trkseg>
      </trk>
    </gpx>
    """
    
    public static let missingElevationGPXString: String = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1">
      <trk>
        <name>Flat 2D Trail</name>
        <trkseg>
          <trkpt lat="37.7700" lon="-122.4100"></trkpt>
          <trkpt lat="37.7710" lon="-122.4110"></trkpt>
        </trkseg>
      </trk>
    </gpx>
    """
    
    public static let extremeCoordinatesGPXString: String = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gpx version="1.1">
      <trk>
        <name>Polar and Antimeridian Expedition</name>
        <trkseg>
          <trkpt lat="89.9999" lon="0.0000"><ele>0.0</ele></trkpt>
          <trkpt lat="0.0000" lon="179.9999"><ele>0.0</ele></trkpt>
          <trkpt lat="0.0000" lon="-179.9999"><ele>0.0</ele></trkpt>
          <trkpt lat="-89.9999" lon="0.0000"><ele>2800.0</ele></trkpt>
        </trkseg>
      </trk>
    </gpx>
    """

    // MARK: - Overpass API JSON Fixtures
    
    public static let overpassJSONSample: String = """
    {
      "version": 0.6,
      "generator": "Overpass API 0.7.62",
      "osm3s": {
        "timestamp_osm_base": "2026-11-21T00:00:00Z"
      },
      "elements": [
        {
          "type": "way",
          "id": 1001,
          "tags": {
            "highway": "path",
            "name": "Sentinel Ridge Trail",
            "surface": "dirt",
            "sac_scale": "hiking"
          },
          "geometry": [
            {"lat": 46.8529, "lon": -113.9850},
            {"lat": 46.8535, "lon": -113.9835},
            {"lat": 46.8542, "lon": -113.9818}
          ]
        },
        {
          "type": "way",
          "id": 1002,
          "tags": {
            "highway": "track",
            "name": "Fire Road 3",
            "tracktype": "grade2"
          },
          "geometry": [
            {"lat": 46.8542, "lon": -113.9818},
            {"lat": 46.8550, "lon": -113.9800},
            {"lat": 46.8560, "lon": -113.9780}
          ]
        }
      ]
    }
    """
    
    public static let overpassJSONEmpty: String = """
    {
      "version": 0.6,
      "generator": "Overpass API",
      "elements": []
    }
    """
    
    public static let overpassJSONCorrupt: String = """
    {"version": 0.6, "elements": [{"type": "way", "id": 1234
    """

    public static let overpassJSONDegraded: String = """
    {
      "version": 0.6,
      "generator": "Overpass API",
      "elements": [
        {
          "type": "way",
          "id": 5001,
          "tags": null,
          "geometry": [
            {"lat": 37.77, "lon": -122.42},
            {"lat": 37.78, "lon": -122.43}
          ]
        },
        {
          "type": "way",
          "id": 5002,
          "tags": {"highway": "path"},
          "geometry": null
        },
        {
          "type": "way",
          "id": 5003,
          "tags": {"highway": "path"},
          "geometry": [
            {"lat": 37.79, "lon": -122.44}
          ]
        }
      ]
    }
    """

    // MARK: - Coordinate Search Fixtures
    
    public struct CoordinateSearchCase: Sendable {
        public let input: String
        public let isValid: Bool
        public let expectedLat: Double?
        public let expectedLon: Double?
    }
    
    public static let coordinateSearchCases: [CoordinateSearchCase] = [
        CoordinateSearchCase(input: "37.7749, -122.4194", isValid: true, expectedLat: 37.7749, expectedLon: -122.4194),
        CoordinateSearchCase(input: " -46.8529 ,  113.9850 ", isValid: true, expectedLat: -46.8529, expectedLon: 113.9850),
        CoordinateSearchCase(input: "0,0", isValid: true, expectedLat: 0.0, expectedLon: 0.0),
        CoordinateSearchCase(input: "90.0, 180.0", isValid: true, expectedLat: 90.0, expectedLon: 180.0),
        CoordinateSearchCase(input: "-90.0, -180.0", isValid: true, expectedLat: -90.0, expectedLon: -180.0),
        CoordinateSearchCase(input: "not a coordinate", isValid: false, expectedLat: nil, expectedLon: nil),
        CoordinateSearchCase(input: "91.0, 10.0", isValid: false, expectedLat: nil, expectedLon: nil),
        CoordinateSearchCase(input: "10.0, 181.0", isValid: false, expectedLat: nil, expectedLon: nil),
        CoordinateSearchCase(input: "37.7749", isValid: false, expectedLat: nil, expectedLon: nil),
        CoordinateSearchCase(input: "37.7749, -122.4194, 100", isValid: false, expectedLat: nil, expectedLon: nil)
    ]
}
