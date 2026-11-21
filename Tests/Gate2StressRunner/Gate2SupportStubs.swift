// Gate2SupportStubs.swift — Production-fidelity support stubs for Tier 5 Gate 2 stress harness
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

    public var iconName: String { "arrow.up" }

    public func formattedDistance(useMetric: Bool) -> String {
        if useMetric {
            let m = distanceMiles * 1609.34
            return m < 1000 ? "\(Int(m)) m" : String(format: "%.1f km", distanceMiles * 1.60934)
        } else {
            return distanceMiles < 0.1 ? "\(Int(distanceMiles * 5280)) ft" : String(format: "%.1f mi", distanceMiles)
        }
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
        if useMetric {
            return String(format: "%.1f km", totalDistanceMiles * 1.60934)
        } else {
            return String(format: "%.1f mi", totalDistanceMiles)
        }
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
}

public final class SearchService: ObservableObject {
    public init() {}

    public func reverseGeocodeAsync(coordinate: CLLocationCoordinate2D) async -> SearchResult? {
        return SearchResult(id: 1, name: "Mock Place", lat: coordinate.latitude, lon: coordinate.longitude)
    }

    public func searchAsync(query: String, userLocation: CLLocationCoordinate2D?) async -> [SearchResult] {
        return [SearchResult(id: 1, name: query, lat: 64.8436, lon: -147.7215)]
    }

    /// Real implementation from SearchService.swift:348-435
    public func parseCoordinates(query: String) -> CLLocationCoordinate2D? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let pattern = #"([+-]?\d+(?:\.\d+)?)\s*[°º˚]?\s*([NSEWnsew])?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let nsString = trimmed as NSString
        let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: nsString.length))
        guard matches.count == 2 else { return nil }

        let nonCoord = regex.stringByReplacingMatches(
            in: trimmed,
            options: [],
            range: NSRange(location: 0, length: nsString.length),
            withTemplate: ""
        )
        let allowedSeparators = CharacterSet(charactersIn: ",; \t\n°º˚/")
        guard nonCoord.unicodeScalars.allSatisfy({ allowedSeparators.contains($0) }) else { return nil }

        struct CoordComponent {
            let value: Double
            let cardinal: Character?
        }

        var components: [CoordComponent] = []
        for match in matches {
            let valRange = match.range(at: 1)
            guard valRange.location != NSNotFound,
                  let val = Double(nsString.substring(with: valRange)) else { return nil }

            var card: Character? = nil
            let cardRange = match.range(at: 2)
            if cardRange.location != NSNotFound {
                let cardStr = nsString.substring(with: cardRange).uppercased()
                if let first = cardStr.first {
                    card = first
                }
            }
            components.append(CoordComponent(value: val, cardinal: card))
        }

        guard components.count == 2 else { return nil }
        let c0 = components[0]
        let c1 = components[1]
        var lat: Double?
        var lon: Double?

        if let dir0 = c0.cardinal, let dir1 = c1.cardinal {
            if (dir0 == "N" || dir0 == "S") && (dir1 == "E" || dir1 == "W") {
                lat = (dir0 == "S") ? -abs(c0.value) : abs(c0.value)
                lon = (dir1 == "W") ? -abs(c1.value) : abs(c1.value)
            } else if (dir0 == "E" || dir0 == "W") && (dir1 == "N" || dir1 == "S") {
                lon = (dir0 == "W") ? -abs(c0.value) : abs(c0.value)
                lat = (dir1 == "S") ? -abs(c1.value) : abs(c1.value)
            } else {
                return nil
            }
        } else if let dir0 = c0.cardinal {
            if dir0 == "N" || dir0 == "S" {
                lat = (dir0 == "S") ? -abs(c0.value) : abs(c0.value)
                lon = c1.value
            } else {
                lon = (dir0 == "W") ? -abs(c0.value) : abs(c0.value)
                lat = c1.value
            }
        } else if let dir1 = c1.cardinal {
            if dir1 == "N" || dir1 == "S" {
                lat = (dir1 == "S") ? -abs(c1.value) : abs(c1.value)
                lon = c0.value
            } else {
                lon = (dir1 == "W") ? -abs(c1.value) : abs(c1.value)
                lat = c0.value
            }
        } else {
            lat = c0.value
            lon = c1.value
        }

        guard let finalLat = lat, let finalLon = lon,
              finalLat >= -90.0 && finalLat <= 90.0,
              finalLon >= -180.0 && finalLon <= 180.0 else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: finalLat, longitude: finalLon)
    }
}

public final class RoutingService: ObservableObject, @unchecked Sendable {
    public let voiceLock = NSLock()
    private var _isVoiceMuted: Bool = false
    public var isVoiceMuted: Bool {
        get {
            voiceLock.lock()
            defer { voiceLock.unlock() }
            return _isVoiceMuted
        }
        set {
            voiceLock.lock()
            let changedToMuted = newValue && !_isVoiceMuted
            _isVoiceMuted = newValue
            voiceLock.unlock()
            if changedToMuted {
                stopVoice()
            }
        }
    }

    public var spokenInstructions: [(text: String, stepId: Int?, force: Bool)] = []
    public var stopVoiceCallCount: Int = 0
    public var activeSpeechGeneration: Int = 0
    public var utteranceGenerations: [UUID: Int] = [:]
    public var lastSpokenInstruction: String = ""
    public var lastSpokenStepId: Int? = nil
    public var lastSpokenTime: Date = .distantPast

    public init() {}

    public func stopVoice() {
        voiceLock.lock()
        activeSpeechGeneration += 1
        utteranceGenerations.removeAll()
        lastSpokenInstruction = ""
        lastSpokenStepId = nil
        lastSpokenTime = .distantPast
        stopVoiceCallCount += 1
        voiceLock.unlock()
    }

    public func speakTurnInstruction(_ text: String, stepId: Int? = nil, force: Bool = false) {
        voiceLock.lock()
        guard !_isVoiceMuted && !text.isEmpty else {
            voiceLock.unlock()
            return
        }

        let now = Date()
        let isSameText = (text == lastSpokenInstruction)
        let isSameStep = (stepId != nil && lastSpokenStepId != nil) ? (stepId == lastSpokenStepId) : true
        let timeSinceLast = now.timeIntervalSince(lastSpokenTime)

        if !force && isSameText && isSameStep && timeSinceLast < 6.0 {
            voiceLock.unlock()
            return
        }

        lastSpokenInstruction = text
        lastSpokenStepId = stepId
        lastSpokenTime = now
        activeSpeechGeneration += 1
        spokenInstructions.append((text: text, stepId: stepId, force: force))
        voiceLock.unlock()
    }

    public func calculateRoute(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        mode: String = "auto",
        useMetric: Bool = false
    ) -> RouteDetails? {
        if from.latitude < 50.0 || from.latitude > 75.0 { return nil }
        return RouteDetails(
            coordinates: [from, to],
            totalDistanceMiles: 1.0,
            totalDurationSeconds: 60,
            steps: [],
            costing: mode
        )
    }

    public func isUserOffRoute(
        userLocation: CLLocationCoordinate2D,
        routeCoordinates: [CLLocationCoordinate2D],
        thresholdMeters: Double = 35.0,
        activeCoordIndex: Int? = nil
    ) -> Bool {
        guard routeCoordinates.count >= 2 else { return false }

        let startIndex: Int
        let endIndex: Int
        if let current = activeCoordIndex {
            startIndex = max(0, current - 5)
            endIndex = min(routeCoordinates.count - 1, current + 35)
        } else {
            startIndex = 0
            endIndex = routeCoordinates.count - 1
        }

        var minDistance = Double.greatestFiniteMagnitude
        for i in startIndex..<endIndex {
            let dist = distanceToSegmentMeters(p: userLocation, a: routeCoordinates[i], b: routeCoordinates[i + 1])
            if dist < minDistance {
                minDistance = dist
            }
        }

        if minDistance > thresholdMeters && activeCoordIndex != nil {
            for i in 0..<(routeCoordinates.count - 1) {
                let dist = distanceToSegmentMeters(p: userLocation, a: routeCoordinates[i], b: routeCoordinates[i + 1])
                if dist < minDistance {
                    minDistance = dist
                }
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
    private static let offlineAssetExtensions = [".pmtiles", ".tar", ".db", ".json"]

    public static func excludeOfflineAssetsInDocuments(docsURL: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: docsURL, includingPropertiesForKeys: nil) else {
            return
        }
        for fileURL in contents {
            let lower = fileURL.lastPathComponent.lowercased()
            if offlineAssetExtensions.contains(where: { lower.hasSuffix($0) }) {
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = true
                var mutableFileURL = fileURL
                try? mutableFileURL.setResourceValues(resourceValues)
            }
        }
    }

    public static func url(for filename: String) -> URL {
        return FileManager.default.temporaryDirectory.appendingPathComponent(filename)
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
