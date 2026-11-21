import Foundation
import CoreLocation
import Combine

/// Protocol for querying user's current GPS location.
public protocol LocationManagerProtocol: AnyObject, Sendable {
    var currentLocation: CLLocation? { get }
}

/// Fallback / default location manager wrapper conforming to LocationManagerProtocol.
public final class StandardLocationManager: NSObject, LocationManagerProtocol, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private let lock = NSLock()
    private var _currentLocation: CLLocation?

    public var currentLocation: CLLocation? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _currentLocation
        }
        set {
            lock.lock()
            _currentLocation = newValue
            lock.unlock()
        }
    }

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let last = locations.last {
            currentLocation = last
        }
    }
}

/// Central ViewModel coordinating origin/destination endpoints, route calculation,
/// remote origin preview mode, off-route suppression, and turn-by-turn navigation state.
@MainActor
public class NavigationViewModel: ObservableObject {
    @Published public var originEndpoint: RouteEndpoint = .currentLocation
    @Published public var destinationEndpoint: RouteEndpoint? = nil
    @Published public var isRoutePreviewMode: Bool = false
    @Published public var currentRoute: RouteResponse? = nil
    @Published public var isOffRoute: Bool = false
    @Published public var rerouteCount: Int = 0
    @Published public var originText: String = ""
    @Published public var destinationText: String = ""
    @Published public var selectedCosting: String = "auto"

    public var remoteThresholdMeters: Double = 200.0
    public var offRouteThresholdMeters: Double = 50.0

    public let locationManager: LocationManagerProtocol
    public let routingService: RoutingServiceProtocol

    private var routingTask: Task<Void, Never>? = nil

    public init(
        locationManager: LocationManagerProtocol = StandardLocationManager(),
        routingService: RoutingServiceProtocol = RoutingService()
    ) {
        self.locationManager = locationManager
        self.routingService = routingService
    }

    deinit {
        routingTask?.cancel()
    }

    // MARK: - Endpoint Resolution

    /// Resolves a RouteEndpoint to concrete GPS coordinates.
    public func resolveCoordinate(for endpoint: RouteEndpoint) -> CLLocationCoordinate2D? {
        switch endpoint {
        case .currentLocation:
            return locationManager.currentLocation?.coordinate
        case .custom(let place):
            return place.coordinate
        }
    }

    /// Determines whether the custom origin is remote (> thresholdMeters from device GPS).
    public func isRemoteOrigin(thresholdMeters: Double = 200.0, currentLocation: CLLocation? = nil) -> Bool {
        guard case .custom(let place) = originEndpoint else {
            return false
        }
        let userLoc = currentLocation ?? locationManager.currentLocation
        guard let userLoc = userLoc else {
            return true // Remote by default if device location is unavailable
        }
        let originLoc = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        return userLoc.distance(from: originLoc) > thresholdMeters
    }

    // MARK: - Actions

    /// Swaps origin and destination endpoints and UI text bindings, then triggers route recalculation.
    public func swapOriginDestination() {
        guard let currentDest = destinationEndpoint else { return }
        let oldOrigin = originEndpoint
        originEndpoint = currentDest
        destinationEndpoint = oldOrigin

        // Synchronize UI search string bindings
        let tempText = originText
        originText = destinationText
        destinationText = tempText

        // Cancel previous routing task and recalculate
        routingTask?.cancel()
        routingTask = Task { [weak self] in
            await self?.calculateRoute()
        }
    }

    /// Resets origin back to Current Location, clears preview mode immediately, and triggers recalculation.
    public func resetOriginToCurrentLocation() {
        originEndpoint = .currentLocation
        originText = ""
        isRoutePreviewMode = false

        routingTask?.cancel()
        routingTask = Task { [weak self] in
            await self?.calculateRoute()
        }
    }

    /// Action for RoutePreviewHUD: calculates a route from current GPS location to the custom origin.
    public func routeToStart() {
        guard case .custom(let place) = originEndpoint else { return }
        destinationEndpoint = .custom(place: place)
        destinationText = place.name
        resetOriginToCurrentLocation()
    }

    /// Parameterized route calculation using resolved origin and destination endpoints.
    public func calculateRoute() async {
        guard !Task.isCancelled else { return }

        guard let originCoord = resolveCoordinate(for: originEndpoint),
              let destEndpoint = destinationEndpoint,
              let destCoord = resolveCoordinate(for: destEndpoint) else {
            self.currentRoute = nil
            return
        }

        // Update preview mode status based on proximity
        if originEndpoint.isCurrentLocation {
            isRoutePreviewMode = false
        } else {
            isRoutePreviewMode = isRemoteOrigin(thresholdMeters: remoteThresholdMeters)
        }

        do {
            let route = try await routingService.calculateRoute(
                from: originCoord,
                to: destCoord,
                costing: selectedCosting
            )

            guard !Task.isCancelled else { return }
            self.currentRoute = route
            self.isOffRoute = false
        } catch {
            guard !Task.isCancelled else { return }
            print("Failed to calculate route: \(error.localizedDescription)")
            self.currentRoute = nil
        }
    }

    /// Handles streaming GPS location updates:
    /// In preview mode, evaluates distance to origin and transitions to live tracking once <= 200m.
    /// In live tracking mode, evaluates off-route deviation.
    public func handleLocationUpdate(_ location: CLLocation) {
        if isRoutePreviewMode {
            if !isRemoteOrigin(thresholdMeters: remoteThresholdMeters, currentLocation: location) {
                // User has arrived within remoteThresholdMeters of custom origin
                isRoutePreviewMode = false
            } else {
                // Suppress off-route recalculation while origin is remote
                return
            }
        }

        // Standard live tracking and off-route detection
        checkOffRouteAndReroute(currentLocation: location)
    }

    /// Checks if user position has deviated off active route and triggers recalculation if necessary.
    public func checkOffRouteAndReroute(currentLocation: CLLocation) {
        guard let route = currentRoute, !route.coordinates.isEmpty else { return }

        // Find minimum distance from user to route coordinates
        var minDistance = Double.greatestFiniteMagnitude
        for coord in route.coordinates {
            let loc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            let dist = currentLocation.distance(from: loc)
            if dist < minDistance {
                minDistance = dist
            }
        }

        if minDistance > offRouteThresholdMeters {
            isOffRoute = true
            rerouteCount += 1
            // Recalculate route from user position
            routingTask?.cancel()
            routingTask = Task { [weak self] in
                guard let self = self, let dest = self.destinationEndpoint,
                      let destCoord = self.resolveCoordinate(for: dest) else { return }
                do {
                    let newRoute = try await self.routingService.calculateRoute(
                        from: currentLocation.coordinate,
                        to: destCoord,
                        costing: self.selectedCosting
                    )
                    guard !Task.isCancelled else { return }
                    self.currentRoute = newRoute
                    self.isOffRoute = false
                } catch {
                    print("Reroute failed: \(error)")
                }
            }
        } else {
            isOffRoute = false
        }
    }
}
