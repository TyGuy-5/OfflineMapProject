import Foundation
import CoreLocation

extension CLLocationCoordinate2D: @retroactive @unchecked Sendable {}

/// Represents a place or location used as a route endpoint.
public struct PlaceLocation: Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let subtitle: String?
    public let coordinate: CLLocationCoordinate2D

    public init(id: String = UUID().uuidString, name: String, subtitle: String? = nil, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.coordinate = coordinate
    }

    public static func == (lhs: PlaceLocation, rhs: PlaceLocation) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.subtitle == rhs.subtitle &&
               lhs.coordinate.latitude == rhs.coordinate.latitude &&
               lhs.coordinate.longitude == rhs.coordinate.longitude
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(subtitle)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
    }
}

/// Represents either the user's current GPS location or a user-selected custom location.
public enum RouteEndpoint: Equatable, Hashable, Sendable {
    case currentLocation
    case custom(place: PlaceLocation)

    public var displayName: String {
        switch self {
        case .currentLocation:
            return "Current Location"
        case .custom(let place):
            return place.name
        }
    }

    public var isCurrentLocation: Bool {
        switch self {
        case .currentLocation:
            return true
        case .custom:
            return false
        }
    }
}
