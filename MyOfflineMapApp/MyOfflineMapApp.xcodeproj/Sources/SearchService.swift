import Foundation
import CoreLocation

/// Represents a search result item from POI database or coordinate parser.
public struct SearchResult: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let coordinate: CLLocationCoordinate2D

    public init(
        id: String = UUID().uuidString,
        title: String,
        subtitle: String? = nil,
        coordinate: CLLocationCoordinate2D
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.coordinate = coordinate
    }

    public static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        return lhs.id == rhs.id &&
               lhs.title == rhs.title &&
               lhs.subtitle == rhs.subtitle &&
               lhs.coordinate.latitude == rhs.coordinate.latitude &&
               lhs.coordinate.longitude == rhs.coordinate.longitude
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(subtitle)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
    }
}

/// Offline search service providing POI queries and coordinate parsing.
public class SearchService {
    public init() {}

    /// Parses an input string matching "lat, lon" or "lat,lon" with optional signs and spaces.
    /// Supports optional leading '+' or '-' signs: e.g. "+37.7749, -122.4194", "45.5152, +122.6784".
    /// Rejects strings containing newlines, invalid coordinate ranges, or malformed characters.
    public static func parseCoordinateString(_ query: String) -> CLLocationCoordinate2D? {
        // Disallow newlines/carriage returns
        if query.contains("\n") || query.contains("\r") {
            return nil
        }

        let pattern = #"^\s*([+-]?\d{1,2}(?:\.\d+)?)\s*,\s*([+-]?\d{1,3}(?:\.\d+)?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(query.startIndex..<query.endIndex, in: query)
        guard let match = regex.firstMatch(in: query, options: [], range: range),
              match.numberOfRanges == 3,
              let latRange = Range(match.range(at: 1), in: query),
              let lonRange = Range(match.range(at: 2), in: query),
              let lat = Double(query[latRange]),
              let lon = Double(query[lonRange]) else {
            return nil
        }

        // Validate coordinate bounds [-90, 90] and [-180, 180]
        guard lat >= -90.0 && lat <= 90.0 && lon >= -180.0 && lon <= 180.0 else {
            return nil
        }

        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Performs search for places matching query, returning a synthetic coordinate result if coordinates are recognized.
    public func search(query: String) async -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var results: [SearchResult] = []

        // If query parses as a coordinate string, prepend a synthetic SearchResult
        if let coord = SearchService.parseCoordinateString(query) {
            let latStr = String(format: "%.4f", coord.latitude)
            let lonStr = String(format: "%.4f", coord.longitude)
            let synthetic = SearchResult(
                id: "coord_\(latStr)_\(lonStr)",
                title: "Coordinates",
                subtitle: "\(latStr), \(lonStr)",
                coordinate: coord
            )
            results.append(synthetic)
        }

        return results
    }
}
