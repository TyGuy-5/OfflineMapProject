import Foundation
import CoreLocation

#if canImport(MapLibre)
import MapLibre
#endif

/// A single coordinate point along a GPX track or route.
public struct GPXTrackPoint: Equatable, Hashable, Sendable {
    public let coordinate: CLLocationCoordinate2D
    public let elevation: Double?      // Elevation in meters
    public let time: Date?             // Timestamp of point
    public let cumulativeDistance: Double // Cumulative distance from start of track in meters
    
    public init(
        coordinate: CLLocationCoordinate2D,
        elevation: Double? = nil,
        time: Date? = nil,
        cumulativeDistance: Double = 0.0
    ) {
        self.coordinate = coordinate
        self.elevation = elevation
        self.time = time
        self.cumulativeDistance = cumulativeDistance
    }
    
    public static func == (lhs: GPXTrackPoint, rhs: GPXTrackPoint) -> Bool {
        return lhs.coordinate.latitude == rhs.coordinate.latitude &&
               lhs.coordinate.longitude == rhs.coordinate.longitude &&
               lhs.elevation == rhs.elevation &&
               lhs.time == rhs.time &&
               abs(lhs.cumulativeDistance - rhs.cumulativeDistance) < 0.0001
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        hasher.combine(elevation)
        hasher.combine(time)
        hasher.combine(cumulativeDistance)
    }
}

/// Bounding box representation for a GPX track or route.
public struct GPXBounds: Equatable, Hashable, Sendable {
    public let minLatitude: Double
    public let maxLatitude: Double
    public let minLongitude: Double
    public let maxLongitude: Double
    
    public static let zero = GPXBounds(minLatitude: 0, maxLatitude: 0, minLongitude: 0, maxLongitude: 0)
    
    public init(minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
    }
    
    public var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (minLatitude + maxLatitude) / 2.0,
            longitude: (minLongitude + maxLongitude) / 2.0
        )
    }
    
    public var latitudeSpan: Double {
        return maxLatitude - minLatitude
    }
    
    public var longitudeSpan: Double {
        return maxLongitude - minLongitude
    }
    
    public var sw: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: minLatitude, longitude: minLongitude)
    }
    
    public var ne: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: maxLatitude, longitude: maxLongitude)
    }
    
    public func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        return coordinate.latitude >= minLatitude &&
               coordinate.latitude <= maxLatitude &&
               coordinate.longitude >= minLongitude &&
               coordinate.longitude <= maxLongitude
    }
    
    public func toCoordinateBounds() -> MLNCoordinateBounds {
        return MLNCoordinateBounds(sw: sw, ne: ne)
    }
}

/// An imported GPX track or route consisting of ordered points, statistics, and bounds.
public struct GPXTrack: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let trackDescription: String?
    public let points: [GPXTrackPoint]
    public let totalDistance: Double    // In meters
    public let elevationGain: Double     // Cumulative ascent in meters
    public let elevationLoss: Double     // Cumulative descent in meters
    public let minElevation: Double?     // Lowest elevation in meters
    public let maxElevation: Double?     // Highest elevation in meters
    public let bounds: GPXBounds
    public let fileURL: URL?
    public let date: Date?
    
    public init(
        id: UUID = UUID(),
        name: String,
        trackDescription: String? = nil,
        points: [GPXTrackPoint] = [],
        totalDistance: Double = 0.0,
        elevationGain: Double = 0.0,
        elevationLoss: Double = 0.0,
        minElevation: Double? = nil,
        maxElevation: Double? = nil,
        bounds: GPXBounds = .zero,
        fileURL: URL? = nil,
        date: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.trackDescription = trackDescription
        self.points = points
        self.totalDistance = totalDistance
        self.elevationGain = elevationGain
        self.elevationLoss = elevationLoss
        self.minElevation = minElevation
        self.maxElevation = maxElevation
        self.bounds = bounds
        self.fileURL = fileURL
        self.date = date ?? points.first?.time
    }
    
    public static func == (lhs: GPXTrack, rhs: GPXTrack) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.trackDescription == rhs.trackDescription &&
               lhs.points == rhs.points &&
               abs(lhs.totalDistance - rhs.totalDistance) < 0.001 &&
               abs(lhs.elevationGain - rhs.elevationGain) < 0.001 &&
               abs(lhs.elevationLoss - rhs.elevationLoss) < 0.001 &&
               lhs.minElevation == rhs.minElevation &&
               lhs.maxElevation == rhs.maxElevation &&
               lhs.bounds == rhs.bounds &&
               lhs.fileURL == rhs.fileURL &&
               lhs.date == rhs.date
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(trackDescription)
        hasher.combine(points)
        hasher.combine(totalDistance)
        hasher.combine(elevationGain)
        hasher.combine(elevationLoss)
        hasher.combine(minElevation)
        hasher.combine(maxElevation)
        hasher.combine(bounds)
        hasher.combine(fileURL)
        hasher.combine(date)
    }
}

// MARK: - GeoJSON Conversion for Map Overlay Integration
extension GPXTrack {
    /// Converts the track into an RFC 7946 GeoJSON Feature with [longitude, latitude] coordinates.
    public func toGeoJSONFeature() -> GeoJSONFeature {
        let coordinates: [[Double]] = points.map { pt in
            [pt.coordinate.longitude, pt.coordinate.latitude]
        }
        
        var props: [String: String] = [
            "name": name,
            "total_distance": String(format: "%.1f", totalDistance),
            "elevation_gain": String(format: "%.1f", elevationGain),
            "elevation_loss": String(format: "%.1f", elevationLoss),
            "points_count": "\(points.count)"
        ]
        if let desc = trackDescription {
            props["desc"] = desc
        }
        if let fileURL = fileURL {
            props["file_name"] = fileURL.lastPathComponent
        }
        
        return GeoJSONFeature(
            id: Int64(abs(id.hashValue)),
            geometry: GeoJSONGeometry(type: "LineString", coordinates: coordinates),
            properties: props
        )
    }
    
    /// Converts the track into an RFC 7946 GeoJSON FeatureCollection.
    public func toGeoJSONFeatureCollection() -> GeoJSONFeatureCollection {
        return GeoJSONFeatureCollection(features: [toGeoJSONFeature()])
    }
    
    /// Serializes the track into RFC 7946 GeoJSON Data.
    public func toGeoJSONData() throws -> Data {
        let collection = toGeoJSONFeatureCollection()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(collection)
    }
}
