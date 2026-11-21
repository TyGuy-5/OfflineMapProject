import Foundation
import CoreLocation
import Combine

/// Central location manager managing device GPS positioning, desired accuracy,
/// and activity type switching for route planning vs. fitness trail navigation.
@MainActor
public class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    public static let shared = LocationManager()
    
    public let clLocationManager: CLLocationManager
    
    @Published public private(set) var activeActivityType: CLActivityType
    @Published public private(set) var currentLocation: CLLocation?
    
    /// Backward-compatible computed property for activityType.
    public var activityType: CLActivityType {
        get { activeActivityType }
        set { setActivityType(newValue) }
    }
    
    /// Desired location accuracy forwarding to underlying CLLocationManager.
    public var desiredAccuracy: CLLocationAccuracy {
        get { clLocationManager.desiredAccuracy }
        set { clLocationManager.desiredAccuracy = newValue }
    }
    
    private var previousActivityType: CLActivityType = .automotiveNavigation
    private var isTrailNavigationActive: Bool = false
    
    public init(clLocationManager: CLLocationManager = CLLocationManager()) {
        self.clLocationManager = clLocationManager
        self.activeActivityType = .automotiveNavigation
        self.previousActivityType = .automotiveNavigation
        super.init()
        self.clLocationManager.delegate = self
        self.clLocationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.clLocationManager.activityType = .automotiveNavigation
    }
    
    /// Sets the active activity type on both the underlying CLLocationManager and published property.
    public func setActivityType(_ type: CLActivityType) {
        clLocationManager.activityType = type
        activeActivityType = type
    }
    
    /// Activates or deactivates trail navigation fitness mode.
    /// When active is true: records the current activityType and switches to `.fitness` to suppress road-snapping.
    /// When active is false: restores the previous activityType (e.g. `.automotiveNavigation`).
    public func setTrailNavigationActive(_ active: Bool) {
        if active {
            if !isTrailNavigationActive {
                previousActivityType = clLocationManager.activityType
                isTrailNavigationActive = true
            }
            setActivityType(.fitness)
        } else {
            if isTrailNavigationActive {
                isTrailNavigationActive = false
                setActivityType(previousActivityType)
            }
        }
    }
    
    /// Resets configuration to default navigation mode.
    public func resetToDefaults() {
        isTrailNavigationActive = false
        previousActivityType = .automotiveNavigation
        setActivityType(.automotiveNavigation)
        desiredAccuracy = kCLLocationAccuracyBest
    }
    
    // MARK: - CLLocationManagerDelegate
    
    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = last
        }
    }
}
