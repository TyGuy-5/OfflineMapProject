
import Foundation
import CoreLocation
import SwiftUI
import AVFoundation

#if !canImport(UIKit)
import AppKit
public typealias UIColor = NSColor
public typealias UIImage = NSImage

public class UIDevice {
    public static let current = UIDevice()
    public var isGeneratingDeviceOrientationNotifications = true
    public static let orientationDidChangeNotification = Notification.Name("UIDeviceOrientationDidChangeNotification")
}

public class UIApplication {
    public static let shared = UIApplication()
    public var isIdleTimerDisabled = false
}
#endif

// MARK: - XCTest Stubs
public struct XCTSkip: Error {
    public init(_ message: String = "") {}
}

open class XCTestExpectation: NSObject, @unchecked Sendable {
    open func fulfill() {}
}

open class XCTestCase: NSObject {
    public override init() { super.init() }
    open func expectation(description: String) -> XCTestExpectation { XCTestExpectation() }
    open func fulfillment(of expectations: [XCTestExpectation], timeout: TimeInterval) async {}
    open func wait(for expectations: [XCTestExpectation], timeout: TimeInterval) {}
}

public func XCTAssert(_ condition: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertTrue(_ condition: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertFalse(_ condition: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTFail(_ message: String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertEqual<T: FloatingPoint>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, accuracy: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertNotEqual<T: Equatable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertNil(_ a: @autoclosure () -> Any?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertNotNil(_ a: @autoclosure () -> Any?, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertGreaterThan<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertLessThan<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertGreaterThanOrEqual<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {}
public func XCTAssertLessThanOrEqual<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {}

// MARK: - MapLibre Stubs
public protocol MLNAnnotation: AnyObject {}
open class MLNPointAnnotation: NSObject, MLNAnnotation {
    public dynamic var coordinate: CLLocationCoordinate2D = CLLocationCoordinate2D()
    public var title: String?
    public var subtitle: String?
    public override init() { super.init() }
}
open class MLNMapView: NSObject {
    public init(frame: CGRect) { super.init() }
    open func addAnnotation(_ annotation: any MLNAnnotation) {}
    open func removeAnnotation(_ annotation: any MLNAnnotation) {}
    public var annotations: [any MLNAnnotation]? { [] }
}

// MARK: - Models
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

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    public var iconName: String { "mappin" }
    public func distanceMiles(from coord: CLLocationCoordinate2D?) -> Double? { 1.0 }
    public func formattedDistance(from: CLLocationCoordinate2D?, useMetric: Bool = false) -> String { "" }
}

public struct NavigationStep: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let instruction: String
    public let distanceMiles: Double
    public let durationSeconds: Double
    public let maneuverType: Int
    public let streetName: String?
    public let startIndex: Int
    public let endIndex: Int

    public var iconName: String { "arrow.up" }
    public func formattedDistance(useMetric: Bool) -> String { "1.0 mi" }

    public init(
        instruction: String,
        distanceMiles: Double,
        durationSeconds: Double,
        maneuverType: Int,
        streetName: String? = nil,
        startIndex: Int,
        endIndex: Int
    ) {
        self.id = UUID()
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

    public var formattedDuration: String { "10 min" }
    public func formattedDistance(useMetric: Bool) -> String { "1.0 mi" }

    public init(
        id: UUID = UUID(),
        coordinates: [CLLocationCoordinate2D],
        totalDistanceMiles: Double,
        totalDurationSeconds: Double,
        steps: [NavigationStep],
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

    public static func == (lhs: RouteDetails, rhs: RouteDetails) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Services
public final class RoutingService: NSObject, @unchecked Sendable, AVSpeechSynthesizerDelegate, ObservableObject {
    private let voiceLock = NSLock()
    public var isVoiceMuted: Bool = false
    public var spokenInstructions: [(text: String, stepId: Int?, force: Bool)] = []
    public var stopVoiceCallCount: Int = 0
    public var isEngineReady: Bool = true
    private var activeSpeechGeneration: Int = 0

    public override init() { super.init() }

    public func stopVoice() {
        voiceLock.lock()
        stopVoiceCallCount += 1
        voiceLock.unlock()
    }

    public func speakTurnInstruction(_ text: String, stepId: Int? = nil, force: Bool = false) {
        voiceLock.lock()
        activeSpeechGeneration += 1
        spokenInstructions.append((text: text, stepId: stepId, force: force))
        voiceLock.unlock()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        voiceLock.lock()
        voiceLock.unlock()
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        voiceLock.lock()
        voiceLock.unlock()
    }

    public func calculateRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        mode: String = "auto",
        useMetric: Bool = false
    ) -> RouteDetails? {
        return nil
    }

    public func isUserOffRoute(
        userLocation: CLLocationCoordinate2D,
        routeCoordinates: [CLLocationCoordinate2D],
        thresholdMeters: Double = 35.0,
        activeCoordIndex: Int? = nil
    ) -> Bool {
        return false
    }

    public func distanceToSegmentMeters(
        p: CLLocationCoordinate2D,
        a: CLLocationCoordinate2D,
        b: CLLocationCoordinate2D
    ) -> Double {
        return 0.0
    }
}

public final class SearchService: ObservableObject {
    public init() {}

    public func performReverseGeocode(coordinate: CLLocationCoordinate2D) -> SearchResult? {
        return SearchResult(id: 1, name: "Mock Place", lat: coordinate.latitude, lon: coordinate.longitude)
    }

    public func reverseGeocode(coordinate: CLLocationCoordinate2D) -> SearchResult? {
        return performReverseGeocode(coordinate: coordinate)
    }

    public func performSearch(query: String, userLocation: CLLocationCoordinate2D? = nil) -> [SearchResult] {
        return [SearchResult(id: 1, name: query, lat: 64.8436, lon: -147.7215)]
    }

    public func search(query: String, userLocation: CLLocationCoordinate2D? = nil) -> [SearchResult] {
        return performSearch(query: query, userLocation: userLocation)
    }

    public func searchAsync(query: String, userLocation: CLLocationCoordinate2D? = nil) async -> [SearchResult] {
        return search(query: query, userLocation: userLocation)
    }

    public func reverseGeocodeAsync(coordinate: CLLocationCoordinate2D) async -> SearchResult? {
        return reverseGeocode(coordinate: coordinate)
    }

    public func parseCoordinates(query: String) -> CLLocationCoordinate2D? {
        return CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
    }
}

public final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published public var location: CLLocation?
    @Published public var heading: Double = 0.0
    @Published public var smoothedSpeedMph: Int = 0
    @Published public var smoothedSpeedKmh: Int = 0
    @Published public var isGpsSignalLow: Bool = false
    @Published public var isStationary: Bool = true
    public var isNavigationActive: Bool = false

    public override init() { super.init() }

    public func setNavigationActive(_ active: Bool) {
        self.isNavigationActive = active
    }

    public func setMockLocation(_ loc: CLLocation?) {
        self.location = loc
    }

    public func updateHeadingOrientation() {}

    public func requestPreciseLocation() {}

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.location = locations.last
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        self.heading = newHeading.trueHeading
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

public struct OfflineDataManager {
    public static func url(for filename: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
    public static var hasOfflineMap: Bool { true }
    public static func assetExists(at url: URL) -> Bool { true }
}

public struct MapView: View {
    public init(
        pmtilesURL: URL? = nil,
        destinationTitle: String? = nil,
        selectedCoordinate: Binding<CLLocationCoordinate2D?> = .constant(nil),
        routeCoordinates: Binding<[CLLocationCoordinate2D]?> = .constant(nil),
        simulatedUserCoordinate: Binding<CLLocationCoordinate2D?> = .constant(nil),
        userLocationCenter: Binding<CLLocationCoordinate2D?> = .constant(nil),
        zoomStep: Binding<Double?> = .constant(nil),
        simulatedHeading: Double? = nil,
        isNavigating: Bool = false,
        mapStyleName: String = "standard",
        onMapTap: (() -> Void)? = nil,
        onLongPressCoordinate: ((CLLocationCoordinate2D) -> Void)? = nil
    ) {}

    public var body: some View { EmptyView() }

    public class Coordinator: NSObject {
        public var carAnnotation: MLNPointAnnotation? = nil
        public func loadMapStyle(on mapView: MLNMapView, pmtilesURL: URL) {}
        public func updateDestinationAnnotation(on mapView: MLNMapView, coordinate: CLLocationCoordinate2D, title: String?) {}
        public func updateCarAnnotation(on mapView: MLNMapView, coordinate: CLLocationCoordinate2D) {}
        public func removeCarAnnotation(from mapView: MLNMapView) {}
        public func drawRoute(on mapView: MLNMapView, coordinates: [CLLocationCoordinate2D]) {}
    }
    public func makeCoordinator() -> Coordinator { Coordinator() }
}
