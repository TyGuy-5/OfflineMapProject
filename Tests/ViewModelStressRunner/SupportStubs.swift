// SupportStubs.swift — Standalone stub models for NavigationViewModel empirical verification

import Foundation
import CoreLocation
import Combine
import SwiftUI

#if !canImport(UIKit)
import AppKit

public typealias UIColor = NSColor

public extension NSColor {
    static var systemBackground: NSColor { NSColor.windowBackgroundColor }
    static var systemGray5: NSColor { NSColor.controlBackgroundColor }
}

public extension Color {
    static var tertiaryLabel: Color { Color.gray }
    init(_ color: NSColor) {
        self = Color(nsColor: color)
    }
}
#endif

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

    public var iconName: String {
        return "arrow.up"
    }

    public func formattedDistance(useMetric: Bool) -> String {
        return "1.0 mi"
    }

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

    public var formattedDuration: String {
        let minutes = Int(totalDurationSeconds / 60)
        return "\(max(1, minutes)) min"
    }

    public func formattedDistance(useMetric: Bool) -> String {
        return "1.0 mi"
    }

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

public struct OfflineDataManager {
    public static func url(for filename: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(filename)
    }
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

    public var body: some View {
        EmptyView()
    }
}
