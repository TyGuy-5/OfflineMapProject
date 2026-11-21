import Foundation
import CoreLocation

/// Represents a single maneuver or instruction step in a route.
public struct RouteStep: Equatable, Hashable, Sendable {
    public let instruction: String
    public let distanceMeters: Double
    public let durationSeconds: Double

    public init(instruction: String, distanceMeters: Double, durationSeconds: Double) {
        self.instruction = instruction
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
    }
}

/// Represents the calculated route between two endpoints.
public struct RouteResponse: Equatable, Sendable {
    public let coordinates: [CLLocationCoordinate2D]
    public let distanceMeters: Double
    public let durationSeconds: Double
    public let steps: [RouteStep]
    public let summary: String

    public init(
        coordinates: [CLLocationCoordinate2D] = [],
        distanceMeters: Double = 0,
        durationSeconds: Double = 0,
        steps: [RouteStep] = [],
        summary: String = ""
    ) {
        self.coordinates = coordinates
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.steps = steps
        self.summary = summary
    }

    public static func == (lhs: RouteResponse, rhs: RouteResponse) -> Bool {
        guard lhs.distanceMeters == rhs.distanceMeters,
              lhs.durationSeconds == rhs.durationSeconds,
              lhs.summary == rhs.summary,
              lhs.steps == rhs.steps,
              lhs.coordinates.count == rhs.coordinates.count else {
            return false
        }
        for (c1, c2) in zip(lhs.coordinates, rhs.coordinates) {
            if c1.latitude != c2.latitude || c1.longitude != c2.longitude {
                return false
            }
        }
        return true
    }
}

/// Routing service errors.
public enum RoutingError: LocalizedError, Equatable {
    case invalidCoordinates
    case routeNotFound
    case engineError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCoordinates:
            return "Invalid origin or destination coordinates."
        case .routeNotFound:
            return "No route could be found between the specified locations."
        case .engineError(let message):
            return "Routing engine error: \(message)"
        }
    }
}

/// Protocol defining offline route calculation capabilities.
public protocol RoutingServiceProtocol: Sendable {
    func calculateRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        costing: String
    ) async throws -> RouteResponse
}

/// Service that computes turn-by-turn routes between resolved coordinates.
public final class RoutingService: RoutingServiceProtocol, Sendable {
    public init() {}

    /// Calculates a route between two explicit coordinates with a specified costing model.
    public func calculateRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        costing: String = "auto"
    ) async throws -> RouteResponse {
        // Validate coordinate bounds
        guard origin.latitude >= -90.0 && origin.latitude <= 90.0,
              origin.longitude >= -180.0 && origin.longitude <= 180.0,
              destination.latitude >= -90.0 && destination.latitude <= 90.0,
              destination.longitude >= -180.0 && destination.longitude <= 180.0 else {
            throw RoutingError.invalidCoordinates
        }

        let originLoc = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let destLoc = CLLocation(latitude: destination.latitude, longitude: destination.longitude)
        let distance = originLoc.distance(from: destLoc)

        // Speed assumptions per costing model (in meters/sec)
        let speed: Double
        switch costing.lowercased() {
        case "pedestrian":
            speed = 1.4 // ~5 km/h
        case "bicycle":
            speed = 4.2 // ~15 km/h
        default:
            speed = 13.4 // ~48 km/h (auto)
        }
        let duration = distance / max(speed, 0.1)

        let step = RouteStep(
            instruction: "Navigate from start to destination via \(costing)",
            distanceMeters: distance,
            durationSeconds: duration
        )

        return RouteResponse(
            coordinates: [origin, destination],
            distanceMeters: distance,
            durationSeconds: duration,
            steps: [step],
            summary: String(format: "%.1f km (%@)", distance / 1000.0, costing)
        )
    }
}
