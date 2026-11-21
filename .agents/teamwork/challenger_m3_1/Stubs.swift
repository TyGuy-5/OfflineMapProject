import Foundation
import CoreLocation
import Combine

public struct SearchResult: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let lat: Double
    public let lon: Double
    public let category: String

    public init(id: Int64, name: String, lat: Double, lon: Double, category: String = "place") {
        self.id = id
        self.name = name
        self.lat = lat
        self.lon = lon
        self.category = category
    }
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
        instruction: String,
        distanceMiles: Double,
        durationSeconds: Double,
        maneuverType: Int,
        streetName: String?,
        startIndex: Int,
        endIndex: Int
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

public final class LocationManager: ObservableObject {
    @Published public var location: CLLocation?
    @Published public var heading: Double = 0.0
    @Published public var smoothedSpeedMph: Int = 0
    @Published public var smoothedSpeedKmh: Int = 0
    @Published public var isGpsSignalLow: Bool = false
    @Published public var isStationary: Bool = true
    public var isNavigationActive: Bool = false

    public init() {}

    public func setNavigationActive(_ active: Bool) {
        self.isNavigationActive = active
    }

    public func setMockLocation(_ loc: CLLocation?) {
        self.location = loc
        if let loc = loc {
            if loc.speed >= 0 {
                self.smoothedSpeedMph = Int(loc.speed * 2.23694)
                self.smoothedSpeedKmh = Int(loc.speed * 3.6)
                self.isStationary = loc.speed < 0.5
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
}

public final class RoutingService: ObservableObject, @unchecked Sendable {
    private let voiceLock = NSLock()
    public var isVoiceMuted: Bool = false
    public var spokenInstructions: [(text: String, stepId: Int?, force: Bool)] = []
    public var stopVoiceCallCount: Int = 0

    public init() {}

    public func stopVoice() {
        voiceLock.lock()
        defer { voiceLock.unlock() }
        stopVoiceCallCount += 1
    }

    public func speakTurnInstruction(_ text: String, stepId: Int? = nil, force: Bool = false) {
        voiceLock.lock()
        defer { voiceLock.unlock() }
        spokenInstructions.append((text: text, stepId: stepId, force: force))
    }

    public func calculateRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        mode: String,
        useMetric: Bool
    ) -> RouteDetails? {
        return nil
    }

    public func isUserOffRoute(
        userLocation: CLLocationCoordinate2D,
        routeCoordinates: [CLLocationCoordinate2D],
        thresholdMeters: Double = 35.0,
        activeCoordIndex: Int? = nil
    ) -> Bool {
        guard routeCoordinates.count >= 2 else { return false }
        let startIndex = max(0, (activeCoordIndex ?? 0) - 5)
        let endIndex = min(routeCoordinates.count - 1, (activeCoordIndex ?? 0) + 35)

        var minDistance = Double.greatestFiniteMagnitude
        for i in startIndex..<endIndex {
            let dist = distanceToSegmentMeters(p: userLocation, a: routeCoordinates[i], b: routeCoordinates[i + 1])
            if dist < minDistance {
                minDistance = dist
            }
        }
        return minDistance > thresholdMeters
    }

    public func distanceToSegmentMeters(
        p: CLLocationCoordinate2D,
        a: CLLocationCoordinate2D,
        b: CLLocationCoordinate2D
    ) -> Double {
        let latRad = a.latitude * .pi / 180.0
        let cosLat = cos(latRad)
        let metersPerDegLon = 111320.0 * cosLat
        let metersPerDegLat = 110540.0

        let dx = (b.longitude - a.longitude) * metersPerDegLon
        let dy = (b.latitude - a.latitude) * metersPerDegLat
        let segLenSq = dx * dx + dy * dy

        let px = (p.longitude - a.longitude) * metersPerDegLon
        let py = (p.latitude - a.latitude) * metersPerDegLat

        if segLenSq < 1.0 {
            return sqrt(px * px + py * py)
        }

        let dot = px * dx + py * dy
        let t = max(0.0, min(1.0, dot / segLenSq))

        let nearestX = t * dx
        let nearestY = t * dy

        let diffX = px - nearestX
        let diffY = py - nearestY
        return sqrt(diffX * diffX + diffY * diffY)
    }
}

public struct OfflineDataManager {
    public static func url(for filename: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
}
