import Foundation

/// Models representing raw Overpass API JSON elements.
public struct OverpassResponse: Codable, Sendable {
    public let version: Double?
    public let generator: String?
    public let elements: [OverpassElement]
    
    public init(version: Double? = nil, generator: String? = nil, elements: [OverpassElement] = []) {
        self.version = version
        self.generator = generator
        self.elements = elements
    }
}

public struct OverpassElement: Codable, Sendable {
    public let type: String
    public let id: Int64
    public let tags: [String: String]?
    public let geometry: [OverpassCoordinate]?
    public let nodes: [Int64]?
    
    public init(
        type: String,
        id: Int64,
        tags: [String: String]? = nil,
        geometry: [OverpassCoordinate]? = nil,
        nodes: [Int64]? = nil
    ) {
        self.type = type
        self.id = id
        self.tags = tags
        self.geometry = geometry
        self.nodes = nodes
    }
}

public struct OverpassCoordinate: Codable, Sendable, Equatable {
    public let lat: Double
    public let lon: Double
    
    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

/// Standard RFC 7946 GeoJSON models.
public struct GeoJSONFeatureCollection: Codable, Sendable, Equatable {
    public let type: String
    public let features: [GeoJSONFeature]
    
    public init(features: [GeoJSONFeature]) {
        self.type = "FeatureCollection"
        self.features = features
    }
}

public struct GeoJSONFeature: Codable, Sendable, Equatable {
    public let type: String
    public let id: Int64?
    public let geometry: GeoJSONGeometry
    public let properties: [String: String]
    
    public init(id: Int64?, geometry: GeoJSONGeometry, properties: [String: String]) {
        self.type = "Feature"
        self.id = id
        self.geometry = geometry
        self.properties = properties
    }
}

public struct GeoJSONGeometry: Codable, Sendable, Equatable {
    public let type: String
    /// Coordinates in [longitude, latitude] format per RFC 7946.
    public let coordinates: [[Double]]
    
    public init(type: String = "LineString", coordinates: [[Double]]) {
        self.type = type
        self.coordinates = coordinates
    }
}

public enum GeoJSONConverterError: LocalizedError, Equatable {
    case invalidJSONData(String)
    case serializationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidJSONData(let message):
            return "Failed to parse Overpass JSON: \(message)"
        case .serializationFailed(let message):
            return "Failed to serialize GeoJSON: \(message)"
        }
    }
}

/// Converts Overpass API JSON responses to valid RFC 7946 GeoJSON FeatureCollections.
public struct GeoJSONConverter: Sendable {
    public init() {}
    
    /// Converts raw Overpass JSON Data into RFC 7946 GeoJSON Data.
    public func convert(overpassData: Data) throws -> Data {
        let decoder = JSONDecoder()
        let response: OverpassResponse
        do {
            response = try decoder.decode(OverpassResponse.self, from: overpassData)
        } catch {
            throw GeoJSONConverterError.invalidJSONData(error.localizedDescription)
        }
        
        let featureCollection = convert(response: response)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(featureCollection)
        } catch {
            throw GeoJSONConverterError.serializationFailed(error.localizedDescription)
        }
    }
    
    /// Converts an OverpassResponse object into a GeoJSONFeatureCollection.
    public func convert(response: OverpassResponse) -> GeoJSONFeatureCollection {
        return convert(elements: response.elements)
    }
    
    /// Converts a list of OverpassElements into a GeoJSONFeatureCollection.
    /// Inverts [lat, lon] into [lon, lat] coordinate pairs and preserves all tags in properties.
    public func convert(elements: [OverpassElement]) -> GeoJSONFeatureCollection {
        var features: [GeoJSONFeature] = []
        
        for element in elements {
            // Overpass ways contain inline geometry when queried with `out body geom;`
            guard let geometry = element.geometry, geometry.count >= 2 else {
                continue
            }
            
            // RFC 7946 requires [longitude, latitude] coordinate pairs
            let coordinates: [[Double]] = geometry.map { coord in
                [coord.lon, coord.lat]
            }
            
            // Retain tags and attach osm_id
            var properties: [String: String] = element.tags ?? [:]
            properties["osm_id"] = String(element.id)
            if let type = element.tags?["highway"] {
                properties["highway"] = type
            }
            
            let feature = GeoJSONFeature(
                id: element.id,
                geometry: GeoJSONGeometry(type: "LineString", coordinates: coordinates),
                properties: properties
            )
            features.append(feature)
        }
        
        return GeoJSONFeatureCollection(features: features)
    }
    
    /// Helper to convert JSON string to GeoJSON string
    public func convert(overpassJSONString: String) throws -> String {
        guard let data = overpassJSONString.data(using: .utf8) else {
            throw GeoJSONConverterError.invalidJSONData("String is not valid UTF-8")
        }
        let geoJSONData = try convert(overpassData: data)
        guard let resultString = String(data: geoJSONData, encoding: .utf8) else {
            throw GeoJSONConverterError.serializationFailed("Could not decode UTF-8 string from GeoJSON data")
        }
        return resultString
    }
}
