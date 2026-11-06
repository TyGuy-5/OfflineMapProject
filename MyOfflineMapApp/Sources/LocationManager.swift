import Foundation
import CoreLocation
import UIKit

@MainActor
public final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published public var location: CLLocation?
    @Published public var heading: Double = 0.0
    @Published public var smoothedSpeedMph: Int = 0
    @Published public var smoothedSpeedKmh: Int = 0
    @Published public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published public var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    @Published public var isGpsSignalLow: Bool = false
    @Published public var isStationary: Bool = true

    private var previousSpeedMps: Double = 0.0
    private let speedSmoothingAlpha: Double = 0.35 // EMA smoothing factor
    private var lastValidCourse: Double = 0.0
    nonisolated(unsafe) private var orientationObserver: (any NSObjectProtocol)?

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = true
        authorizationStatus = manager.authorizationStatus
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        updateHeadingOrientation()

        orientationObserver = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.updateHeadingOrientation()
            }
        }

        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
    }

    deinit {
        if let observer = orientationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        Task { @MainActor in
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }

    public func updateHeadingOrientation() {
        switch UIDevice.current.orientation {
        case .landscapeLeft:
            manager.headingOrientation = .landscapeLeft
        case .landscapeRight:
            manager.headingOrientation = .landscapeRight
        case .portraitUpsideDown:
            manager.headingOrientation = .portraitUpsideDown
        default:
            manager.headingOrientation = .portrait
        }
    }

    public func setNavigationActive(_ active: Bool) {
        UIApplication.shared.isIdleTimerDisabled = active
        if let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String], modes.contains("location") {
            self.manager.allowsBackgroundLocationUpdates = active
            self.manager.showsBackgroundLocationIndicator = active
        }
        self.manager.pausesLocationUpdatesAutomatically = !active
    }

    public func requestPreciseLocation() {
        if #available(iOS 14.0, *) {
            manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "NavigationAccuracy") { [weak self] _ in
                Task { @MainActor in
                    guard let self = self else { return }
                    self.accuracyAuthorization = self.manager.accuracyAuthorization
                }
            }
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }

        // Silently discard stale cached fixes (> 15s) without triggering false low-GPS warning
        if abs(latest.timestamp.timeIntervalSinceNow) >= 15.0 {
            return
        }

        // Only flag weak GPS signal for current fixes with poor or negative horizontal accuracy
        if latest.horizontalAccuracy < 0 || latest.horizontalAccuracy >= 65.0 {
            Task { @MainActor in
                self.isGpsSignalLow = true
            }
            return
        }

        Task { @MainActor in
            self.processLocation(latest)
        }
    }

    private func processLocation(_ latest: CLLocation) {
        let signalLow = latest.horizontalAccuracy > 25.0

        // Speed calculation: only update smoothing if speed is valid (>= 0)
        if latest.speed >= 0 {
            var rawSpeed = latest.speed

            // If drifting while stopped at a stoplight or parked (speed < 0.5 m/s with moderate accuracy), clamp to 0
            if rawSpeed < 0.5 && latest.horizontalAccuracy > 12.0 {
                rawSpeed = 0.0
                previousSpeedMps = 0.0
            } else {
                // Apply Exponential Moving Average (EMA) smoothing
                previousSpeedMps = (speedSmoothingAlpha * rawSpeed) + ((1.0 - speedSmoothingAlpha) * previousSpeedMps)
            }
        }

        let stationary = previousSpeedMps < 0.3
        let mph = Int(round(previousSpeedMps * 2.23694))
        let kmh = Int(round(previousSpeedMps * 3.6))

        // If moving faster than 1.2 m/s (~2.7 mph), lock map bearing to GPS course vector
        var courseToPublish: Double? = nil
        if previousSpeedMps >= 1.2 && latest.course >= 0 {
            lastValidCourse = latest.course
            courseToPublish = latest.course
        }

        self.location = latest
        self.isGpsSignalLow = signalLow
        self.isStationary = stationary
        self.smoothedSpeedMph = max(0, mph)
        self.smoothedSpeedKmh = max(0, kmh)
        if let course = courseToPublish {
            self.heading = course
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        let headingVal = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            guard self.isStationary || self.previousSpeedMps < 1.2 else { return }
            self.heading = headingVal
        }
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let auth = manager.authorizationStatus
        let acc = manager.accuracyAuthorization
        Task { @MainActor in
            self.authorizationStatus = auth
            self.accuracyAuthorization = acc
            switch auth {
            case .authorizedWhenInUse, .authorizedAlways:
                self.manager.startUpdatingLocation()
                self.manager.startUpdatingHeading()
            case .denied, .restricted:
                print("LocationManager: Permission denied or restricted.")
            case .notDetermined:
                self.manager.requestWhenInUseAuthorization()
            @unknown default:
                break
            }
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationManager didFailWithError: \(error.localizedDescription)")
        Task { @MainActor in
            self.isGpsSignalLow = true
        }
    }
}
