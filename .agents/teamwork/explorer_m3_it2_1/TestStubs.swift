import Foundation
import CoreLocation
import Combine

public struct SearchResult: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let lat: Double
    public let lon: Double
    public let category: String

    public init(id: Int64 = 0, name: String = "", lat: Double = 0, lon: Double = 0, category: String = "") {
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
    public func formattedDistance(from: CLLocationCoordinate2D?, useMetric: Bool = false) -> String { "" }
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

    public var iconName: String { "arrow.up" }
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
        self.targetArrivalDate = Date()
    }

    public static func == (lhs: RouteDetails, rhs: RouteDetails) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
public final class LocationManager: ObservableObject {
    @Published public var location: CLLocation?
    @Published public var smoothedSpeedMph: Int = 0
    @Published public var smoothedSpeedKmh: Int = 0
    @Published public var isStationary: Bool = false
    public var heading: Double = 0.0
    public init() {}
    public func setNavigationActive(_ active: Bool) {}
}

public final class SearchService: @unchecked Sendable {
    public init(databasePath: String? = nil) {}
    public func performSearch(query: String, userLocation: CLLocationCoordinate2D?) -> [SearchResult] { [] }
    public func searchPlaces(query: String, userLocation: CLLocationCoordinate2D?, completion: @escaping ([SearchResult]) -> Void) {
        completion([])
    }
    public func performReverseGeocode(coordinate: CLLocationCoordinate2D) -> SearchResult? { nil }
    public func parseCoordinates(query: String) -> CLLocationCoordinate2D? { nil }
    public func reverseGeocodeAsync(coordinate: CLLocationCoordinate2D) async -> SearchResult? { nil }
    public func searchAsync(query: String, userLocation: CLLocationCoordinate2D?) async -> [SearchResult] { [] }
}

public final class RoutingService: @unchecked Sendable {
    public var isVoiceMuted: Bool = false
    public init() {}
    public func stopVoice() {}
    public func speakTurnInstruction(_ text: String, stepId: Int? = nil, force: Bool = false) {}
    public func calculateRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, mode: String = "auto", useMetric: Bool = false) -> RouteDetails? { nil }
    public func isUserOffRoute(userLocation: CLLocationCoordinate2D, routeCoordinates: [CLLocationCoordinate2D], thresholdMeters: Double = 35.0, activeCoordIndex: Int? = nil) -> Bool { false }
    public func distanceToSegmentMeters(p: CLLocationCoordinate2D, a: CLLocationCoordinate2D, b: CLLocationCoordinate2D) -> Double { 0.0 }
}

public enum OfflineDataManager {
    public static func url(for filename: String) -> URL { URL(fileURLWithPath: "/tmp/map.pmtiles") }
}
