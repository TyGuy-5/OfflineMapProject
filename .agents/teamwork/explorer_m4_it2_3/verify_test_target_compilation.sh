#!/usr/bin/env bash
set -e

# verify_test_target_compilation.sh
# Reliable swiftc compilation verification harness for RemediationTests.swift and MyOfflineMapAppTests.swift

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
HARNESS_DIR="/tmp/swiftc_test_target"
MODULES_DIR="$HARNESS_DIR/modules"
CLANG_CACHE="/tmp/clang-cache"

mkdir -p "$MODULES_DIR"
mkdir -p "$CLANG_CACHE"

echo "=== 1. Building MapLibre stub module ==="
cat << 'EOF' > "$HARNESS_DIR/MapLibre.swift"
import Foundation
import CoreLocation

open class MLNSource: NSObject {
    public let identifier: String
    public init(identifier: String) { self.identifier = identifier }
}

open class MLNStyleLayer: NSObject {
    public let identifier: String
    public init(identifier: String) { self.identifier = identifier }
}

open class MLNStyle: NSObject {
    public var sources: [MLNSource] = [MLNSource(identifier: "openmaptiles")]
    public var layers: [MLNStyleLayer] = [MLNStyleLayer(identifier: "background")]
}

public protocol MLNMapViewDelegate: AnyObject {
    func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle)
}

open class MLNMapView: NSObject {
    public var styleURL: URL?
    public weak var delegate: AnyObject?
    public init(frame: Any) {}
    open func addAnnotation(_ a: any MLNAnnotation) {}
    open func removeAnnotation(_ a: any MLNAnnotation) {}
}

public protocol MLNAnnotation: AnyObject {
    var coordinate: CLLocationCoordinate2D { get set }
}

open class MLNPointAnnotation: NSObject, MLNAnnotation {
    public var coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D()
    public var title: String? = nil
    public var subtitle: String? = nil
}
EOF

swiftc -module-cache-path "$CLANG_CACHE" \
    -emit-module -module-name MapLibre \
    -emit-module-path "$MODULES_DIR/MapLibre.swiftmodule" \
    "$HARNESS_DIR/MapLibre.swift"

echo "=== 2. Building ValhallaModels stub module ==="
cat << 'EOF' > "$HARNESS_DIR/ValhallaModels.swift"
import Foundation
import CoreLocation

public enum CostingOptions: String, Sendable {
    case auto, pedestrian, bicycle
}

public enum DistanceUnits: String, Sendable {
    case mi, km
}

public struct RoutingWaypoint: Sendable {
    public let lat: Double
    public let lon: Double
    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

public struct RouteRequest: Sendable {
    public let locations: [RoutingWaypoint]
    public let costing: CostingOptions
    public let units: DistanceUnits
    public init(locations: [RoutingWaypoint], costing: CostingOptions, units: DistanceUnits) {
        self.locations = locations
        self.costing = costing
        self.units = units
    }
}

public struct Maneuver: Sendable {
    public let instruction: String
    public let streetNames: [String]?
    public init(instruction: String, streetNames: [String]?) {
        self.instruction = instruction
        self.streetNames = streetNames
    }
}

public struct Summary: Sendable {
    public let length: Double
    public let time: Double
    public init(length: Double, time: Double) {
        self.length = length
        self.time = time
    }
}

public struct Leg: Sendable {
    public let shape: [CLLocationCoordinate2D]
    public let summary: Summary
    public let maneuvers: [Maneuver]
    public init(shape: [CLLocationCoordinate2D], summary: Summary, maneuvers: [Maneuver]) {
        self.shape = shape
        self.summary = summary
        self.maneuvers = maneuvers
    }
}

public struct Trip: Sendable {
    public let statusMessage: String?
    public let legs: [Leg]
    public init(statusMessage: String?, legs: [Leg]) {
        self.statusMessage = statusMessage
        self.legs = legs
    }
}

public struct RouteResponse: Sendable {
    public let trip: Trip
    public init(trip: Trip) {
        self.trip = trip
    }
}
EOF

swiftc -module-cache-path "$CLANG_CACHE" \
    -emit-module -module-name ValhallaModels \
    -emit-module-path "$MODULES_DIR/ValhallaModels.swiftmodule" \
    "$HARNESS_DIR/ValhallaModels.swift"

echo "=== 3. Building Valhalla stub module ==="
cat << 'EOF' > "$HARNESS_DIR/Valhalla.swift"
import Foundation
import ValhallaModels

public class Valhalla {
    public init(configPath: String) throws {}
    public func route(request: RouteRequest) throws -> RouteResponse {
        return RouteResponse(trip: Trip(statusMessage: "Found route between points", legs: []))
    }
}
EOF

swiftc -module-cache-path "$CLANG_CACHE" \
    -I "$MODULES_DIR" \
    -emit-module -module-name Valhalla \
    -emit-module-path "$MODULES_DIR/Valhalla.swiftmodule" \
    "$HARNESS_DIR/Valhalla.swift"

echo "=== 4. Building XCTest stub module ==="
cat << 'EOF' > "$HARNESS_DIR/XCTest.swift"
import Foundation

open class XCTestCase: NSObject {
    public override init() {}
    open func setUp() {}
    open func tearDown() {}
    open func expectation(description: String) -> XCTestExpectation {
        return XCTestExpectation(description: description)
    }
    open func wait(for expectations: [XCTestExpectation], timeout: TimeInterval) {}
    open func fulfillment(of expectations: [XCTestExpectation], timeout: TimeInterval) async {}
}

open class XCTestExpectation: NSObject, @unchecked Sendable {
    public let expectationDescription: String
    public init(description: String) {
        self.expectationDescription = description
    }
    open func fulfill() {}
}

public struct XCTSkip: Error {
    public let message: String
    public init(_ message: String = "") { self.message = message }
}

public func XCTAssert(_ e: @autoclosure () throws -> Bool, _ m: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {}
public func XCTAssertTrue(_ e: @autoclosure () throws -> Bool, _ m: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {}
public func XCTAssertFalse(_ e: @autoclosure () throws -> Bool, _ m: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {}
public func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {}
public func XCTAssertEqual<T: FloatingPoint>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, accuracy: T, _ m: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {}
public func XCTAssertNotEqual<T: Equatable>(_ a: @autoclosure () throws -> T, _ b: @autoclosure () throws -> T, _ m: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {}
public func XCTAssertNil(_ e: @autoclosure () throws -> Any?, _ m: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {}
public func XCTAssertNotNil(_ e: @autoclosure () throws -> Any?, _ m: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) {}
public func XCTFail(_ m: String = "", file: StaticString = #file, line: UInt = #line) {}
EOF

swiftc -module-cache-path "$CLANG_CACHE" \
    -emit-module -module-name XCTest \
    -emit-module-path "$MODULES_DIR/XCTest.swiftmodule" \
    "$HARNESS_DIR/XCTest.swift"

echo "=== 5. Building MyOfflineMapApp module with real NavigationViewModel ==="
cat << 'EOF' > "$HARNESS_DIR/MyOfflineMapApp_Stub.swift"
import Foundation
import CoreLocation
import Combine
import SwiftUI
import AVFoundation
import MapLibre

#if !canImport(UIKit)
import AppKit
public typealias UIColor = NSColor
public extension NSColor {
    static var systemBackground: NSColor { NSColor.windowBackgroundColor }
    static var systemGray5: NSColor { NSColor.controlBackgroundColor }
}
public extension Color {
    static var tertiaryLabel: Color { Color.gray }
    init(_ color: NSColor) { self = Color(nsColor: color) }
}
public class UIDevice {
    public static let current = UIDevice()
    public var isGeneratingDeviceOrientationNotifications: Bool = true
    public static let orientationDidChangeNotification = Notification.Name("UIDeviceOrientationDidChange")
}
public class UIApplication {
    public static let shared = UIApplication()
    public var isIdleTimerDisabled: Bool = false
}
#endif

public struct SearchResult: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let lat: Double
    public let lon: Double
    public let category: String

    public init(id: Int64 = 0, name: String = "", lat: Double = 0, lon: Double = 0, category: String = "place") {
        self.id = id
        self.name = name
        self.lat = lat
        self.lon = lon
        self.category = category
    }

    public var iconName: String {
        switch category {
        case "gas": return "fuelpump.fill"
        case "coffee": return "cup.and.saucer.fill"
        case "food": return "fork.knife"
        case "hotel": return "bed.double.fill"
        case "parking": return "parkingsign.circle.fill"
        case "airport": return "airplane"
        default: return "mappin.circle.fill"
        }
    }

    public func distanceMiles(from: CLLocationCoordinate2D?) -> Double? { return 3.5 }
    public func formattedDistance(from: CLLocationCoordinate2D?, useMetric: Bool = false) -> String { return "3.5 mi away" }
}

public struct NavigationStep: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let instruction: String
    public let distanceMiles: Double
    public let durationSeconds: Double
    public let maneuverType: Int
    public let streetName: String?
    public let startIndex: Int
    public let endIndex: Int

    public var iconName: String { return "arrow.up" }
    public var formattedDistance: String { return "2.5 mi" }
    public func formattedDistance(useMetric: Bool) -> String { return "1.0 mi" }

    public init(
        instruction: String = "",
        distanceMiles: Double = 0,
        durationSeconds: Double = 0,
        maneuverType: Int = 0,
        streetName: String? = nil,
        startIndex: Int = 0,
        endIndex: Int = 0
    ) {
        self.instruction = instruction
        self.distanceMiles = distanceMiles
        self.durationSeconds = durationSeconds
        self.maneuverType = maneuverType
        self.streetName = streetName
        self.startIndex = startIndex
        self.endIndex = endIndex
    }
}

public struct RouteDetails: Identifiable, Equatable, @unchecked Sendable {
    public let id: UUID
    public let coordinates: [CLLocationCoordinate2D]
    public let totalDistanceMiles: Double
    public let totalDurationSeconds: Double
    public let steps: [NavigationStep]
    public let costing: String
    public let isFallback: Bool
    public let targetArrivalDate: Date

    public var formattedDuration: String { return "11 min" }
    public var formattedDistance: String { return "5.2 mi" }
    public var formattedETA: String { return "12:00 PM" }
    public func formattedDistance(useMetric: Bool) -> String { return "1.0 mi" }

    public init(
        id: UUID = UUID(),
        coordinates: [CLLocationCoordinate2D] = [],
        totalDistanceMiles: Double = 0,
        totalDurationSeconds: Double = 0,
        steps: [NavigationStep] = [],
        costing: String = "auto",
        isFallback: Bool = false
    ) {
        self.id = id
        self.coordinates = coordinates
        self.totalDistanceMiles = totalDistanceMiles
        self.totalDurationSeconds = totalDurationSeconds
        self.steps = steps
        self.costing = costing
        self.isFallback = isFallback
        self.targetArrivalDate = Date().addingTimeInterval(totalDurationSeconds)
    }

    public static func == (lhs: RouteDetails, rhs: RouteDetails) -> Bool { lhs.id == rhs.id }
}

public final class LocationManager: ObservableObject {
    @Published public var location: CLLocation?
    @Published public var heading: Double = 0.0
    @Published public var smoothedSpeedMph: Int = 0
    @Published public var smoothedSpeedKmh: Int = 0
    @Published public var isGpsSignalLow: Bool = false
    @Published public var isStationary: Bool = true
    public var isNavigationActive: Bool = false
    private var previousSpeedMps: Double? = 0.0

    public init() {}

    public func setNavigationActive(_ active: Bool) { self.isNavigationActive = active }
    public func updateHeadingOrientation() {}
    public func requestPreciseLocation() {}
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            self.location = loc
            if loc.horizontalAccuracy >= 65.0 || loc.horizontalAccuracy < 0 {
                self.isGpsSignalLow = true
                self.isStationary = true
                self.smoothedSpeedMph = 0
                self.smoothedSpeedKmh = 0
                self.previousSpeedMps = 0.0
            } else {
                self.isGpsSignalLow = false
                if loc.speed >= 0 {
                    self.isStationary = loc.speed < 0.5
                    self.smoothedSpeedMph = Int(loc.speed * 2.23694)
                    self.smoothedSpeedKmh = Int(loc.speed * 3.6)
                    self.previousSpeedMps = loc.speed
                }
            }
        }
    }
}

public final class SearchService: ObservableObject {
    public init() {}
    public func reverseGeocodeAsync(coordinate: CLLocationCoordinate2D) async -> SearchResult? {
        return SearchResult(id: 1, name: "Mock Place", lat: coordinate.latitude, lon: coordinate.longitude)
    }
    public func searchAsync(query: String, userLocation: CLLocationCoordinate2D?) async -> [SearchResult] {
        return [SearchResult(id: 1, name: query, lat: 64.8436, lon: -147.7215)]
    }
    public func search(query: String, userLocation: CLLocationCoordinate2D?) -> [SearchResult] {
        return [SearchResult(id: 1, name: query, lat: 64.8436, lon: -147.7215)]
    }
    public func reverseGeocode(coordinate: CLLocationCoordinate2D) -> SearchResult? {
        if coordinate.latitude < 50.0 || coordinate.latitude > 75.0 { return nil }
        return SearchResult(id: 1, name: "Mock Place", lat: coordinate.latitude, lon: coordinate.longitude)
    }
    public func performSearch(query: String, userLocation: CLLocationCoordinate2D?) -> [SearchResult] {
        return [SearchResult(id: 1, name: query, lat: 64.8436, lon: -147.7215)]
    }
    public func performReverseGeocode(coordinate: CLLocationCoordinate2D) -> SearchResult? {
        return SearchResult(id: 1, name: "Mock Place", lat: coordinate.latitude, lon: coordinate.longitude)
    }
    public func parseCoordinates(query: String) -> CLLocationCoordinate2D? {
        return CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
    }
}

public final class RoutingService: NSObject, ObservableObject, @unchecked Sendable, AVSpeechSynthesizerDelegate {
    private let voiceLock = NSLock()
    public var isVoiceMuted: Bool = false {
        didSet { if isVoiceMuted { stopVoice() } }
    }
    public var spokenInstructions: [(text: String, stepId: Int?, force: Bool)] = []
    public var stopVoiceCallCount: Int = 0
    private var activeSpeechGeneration: Int = 0

    public override init() {}

    public func stopVoice() {
        voiceLock.lock()
        defer { voiceLock.unlock() }
        stopVoiceCallCount += 1
        activeSpeechGeneration += 1
    }

    public func speakTurnInstruction(_ text: String, stepId: Int? = nil, force: Bool = false) {
        voiceLock.lock()
        defer { voiceLock.unlock() }
        if isVoiceMuted && !force { return }
        activeSpeechGeneration += 1
        spokenInstructions.append((text: text, stepId: stepId, force: force))
    }

    public func calculateRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        mode: String = "auto",
        useMetric: Bool = false
    ) -> RouteDetails? {
        if from.latitude < 50.0 || from.latitude > 75.0 { return nil }
        return RouteDetails(coordinates: [from, to], totalDistanceMiles: 1.0, totalDurationSeconds: 60, steps: [], costing: mode)
    }

    public func isUserOffRoute(
        userLocation: CLLocationCoordinate2D,
        routeCoordinates: [CLLocationCoordinate2D],
        thresholdMeters: Double = 35.0,
        activeCoordIndex: Int? = nil
    ) -> Bool { return false }

    public func distanceToSegmentMeters(
        p: CLLocationCoordinate2D,
        a: CLLocationCoordinate2D,
        b: CLLocationCoordinate2D
    ) -> Double { return 0.0 }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        voiceLock.lock()
        activeSpeechGeneration += 1
        voiceLock.unlock()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        voiceLock.lock()
        activeSpeechGeneration += 1
        voiceLock.unlock()
    }
}

public struct OfflineDataManager {
    public static var allOfflineAssets: [String] { ["valhalla.json", "alaska_tiles.tar", "alaska.pmtiles", "alaska_geocoding.db"] }
    public static func url(for filename: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
    public static func isAssetAvailable(_ filename: String) -> Bool { true }
    public static func fileSize(for filename: String) -> Int { 1024 }
    public static func assetExists(at url: URL) -> Bool { true }
}

public struct MapView: View {
    public init(
        pmtilesURL: URL? = nil,
        destinationTitle: String = "",
        selectedCoordinate: Binding<CLLocationCoordinate2D?> = .constant(nil),
        routeCoordinates: Binding<[CLLocationCoordinate2D]?> = .constant(nil),
        simulatedUserCoordinate: Binding<CLLocationCoordinate2D?> = .constant(nil),
        userLocationCenter: Binding<CLLocationCoordinate2D?> = .constant(nil),
        zoomStep: Binding<Double?> = .constant(nil),
        simulatedHeading: Double? = nil,
        isNavigating: Bool = false,
        mapStyleName: String = "",
        onMapTap: (() -> Void)? = nil,
        onLongPressCoordinate: ((CLLocationCoordinate2D) -> Void)? = nil
    ) {}

    public class Coordinator: NSObject {
        public var carAnnotation: MLNPointAnnotation?
        public var isRecenterConsumed: Bool = false
        public var isZoomStepConsumed: Bool = false
        public var routeCoordinates: [CLLocationCoordinate2D] = []

        public func updateCarAnnotation(on mapView: MLNMapView, coordinate: CLLocationCoordinate2D) {
            if carAnnotation == nil {
                let anno = MLNPointAnnotation()
                anno.coordinate = coordinate
                carAnnotation = anno
                mapView.addAnnotation(anno)
            } else {
                carAnnotation?.coordinate = coordinate
            }
        }

        public func removeCarAnnotation(from mapView: MLNMapView) {
            if let anno = carAnnotation {
                mapView.removeAnnotation(anno)
                carAnnotation = nil
            }
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public var body: some View { EmptyView() }
}
EOF

swiftc -module-cache-path "$CLANG_CACHE" \
    -I "$MODULES_DIR" \
    -emit-module -module-name MyOfflineMapApp \
    -enable-testing \
    -emit-module-path "$MODULES_DIR/MyOfflineMapApp.swiftmodule" \
    "$HARNESS_DIR/MyOfflineMapApp_Stub.swift" \
    "$REPO_ROOT/MyOfflineMapApp/Sources/NavigationViewModel.swift"

echo "=== 6. Typechecking MyOfflineMapAppTests.swift ==="
swiftc -module-cache-path "$CLANG_CACHE" \
    -I "$MODULES_DIR" \
    -typecheck -parse-as-library \
    "$REPO_ROOT/MyOfflineMapApp/Tests/MyOfflineMapAppTests/MyOfflineMapAppTests.swift"
echo "MyOfflineMapAppTests.swift: PASSED with 0 errors"

TEST_FILE="$REPO_ROOT/MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift"
if [ "$1" != "" ]; then
    TEST_FILE="$1"
fi

echo "=== 7. Typechecking RemediationTests.swift ($TEST_FILE) ==="
swiftc -module-cache-path "$CLANG_CACHE" \
    -I "$MODULES_DIR" \
    -typecheck -parse-as-library \
    "$TEST_FILE"
echo "RemediationTests.swift: PASSED with 0 errors"

echo "=== 8. Typechecking ENTIRE TEST TARGET simultaneously ==="
swiftc -module-cache-path "$CLANG_CACHE" \
    -I "$MODULES_DIR" \
    -typecheck -parse-as-library \
    "$REPO_ROOT/MyOfflineMapApp/Tests/MyOfflineMapAppTests/MyOfflineMapAppTests.swift" \
    "$TEST_FILE"
echo "Entire Test Target: PASSED with 0 errors"
