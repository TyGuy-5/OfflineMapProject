import Foundation
import CoreLocation
import Combine

/// Real-time snapshot of the user's progress along an active GPX trail.
public struct TrailProgress: Equatable, Sendable {
    public let distanceTraversed: Double
    public let remainingDistance: Double
    public let progressRatio: Double        // 0.0 ... 1.0
    public let currentElevation: Double?
    public let crossTrackDeviation: Double  // In meters
    public let isOffTrail: Bool
    public let closestCoordinate: CLLocationCoordinate2D
    public let segmentIndex: Int
    
    public init(
        distanceTraversed: Double,
        remainingDistance: Double,
        progressRatio: Double,
        currentElevation: Double?,
        crossTrackDeviation: Double,
        isOffTrail: Bool,
        closestCoordinate: CLLocationCoordinate2D,
        segmentIndex: Int
    ) {
        self.distanceTraversed = distanceTraversed
        self.remainingDistance = remainingDistance
        self.progressRatio = progressRatio
        self.currentElevation = currentElevation
        self.crossTrackDeviation = crossTrackDeviation
        self.isOffTrail = isOffTrail
        self.closestCoordinate = closestCoordinate
        self.segmentIndex = segmentIndex
    }
    
    public static func == (lhs: TrailProgress, rhs: TrailProgress) -> Bool {
        return abs(lhs.distanceTraversed - rhs.distanceTraversed) < 0.001 &&
               abs(lhs.remainingDistance - rhs.remainingDistance) < 0.001 &&
               abs(lhs.progressRatio - rhs.progressRatio) < 0.0001 &&
               lhs.currentElevation == rhs.currentElevation &&
               abs(lhs.crossTrackDeviation - rhs.crossTrackDeviation) < 0.001 &&
               lhs.isOffTrail == rhs.isOffTrail &&
               abs(lhs.closestCoordinate.latitude - rhs.closestCoordinate.latitude) < 1e-7 &&
               abs(lhs.closestCoordinate.longitude - rhs.closestCoordinate.longitude) < 1e-7 &&
               lhs.segmentIndex == rhs.segmentIndex
    }
}

/// Central navigation engine performing cross-track projection, progress calculation,
/// elevation interpolation, and debounced off-trail alerting for GPX tracks.
@MainActor
public class TrailNavigator: ObservableObject {
    @Published public private(set) var activeTrack: GPXTrack?
    @Published public private(set) var userProgressDistance: Double = 0.0
    @Published public private(set) var remainingDistance: Double = 0.0
    @Published public private(set) var currentElevation: Double? = nil
    @Published public private(set) var crossTrackDeviation: Double = 0.0
    @Published public private(set) var isOffTrail: Bool = false
    @Published public private(set) var currentProgress: TrailProgress? = nil
    
    public let audioAlertService: TrailAudioAlertService?
    public let locationManager: LocationManager?
    
    public var offTrailThresholdMeters: Double = 25.0
    public var recoveryThresholdMeters: Double = 18.0
    public var maxGPSAccuracyMeters: Double = 30.0
    public var debounceFixCount: Int = 3
    public var debounceDurationSeconds: TimeInterval = 4.0
    
    private var consecutiveOffTrailCount: Int = 0
    private var offTrailStartTime: Date? = nil
    
    public init(
        audioAlertService: TrailAudioAlertService? = nil,
        locationManager: LocationManager? = nil
    ) {
        self.audioAlertService = audioAlertService
        self.locationManager = locationManager
    }
    
    /// Starts active navigation along the specified GPX track.
    /// Sets LocationManager to `.fitness` mode to eliminate road-snapping.
    public func startNavigation(track: GPXTrack) {
        self.activeTrack = track
        self.userProgressDistance = 0.0
        self.remainingDistance = track.totalDistance
        self.currentElevation = track.points.first?.elevation
        self.crossTrackDeviation = 0.0
        self.isOffTrail = false
        self.currentProgress = nil
        self.consecutiveOffTrailCount = 0
        self.offTrailStartTime = nil
        
        locationManager?.setTrailNavigationActive(true)
        audioAlertService?.resetCooldown()
    }
    
    /// Stops active navigation and restores previous location tracking mode.
    public func stopNavigation() {
        self.activeTrack = nil
        self.userProgressDistance = 0.0
        self.remainingDistance = 0.0
        self.currentElevation = nil
        self.crossTrackDeviation = 0.0
        self.isOffTrail = false
        self.currentProgress = nil
        self.consecutiveOffTrailCount = 0
        self.offTrailStartTime = nil
        
        locationManager?.setTrailNavigationActive(false)
    }
    
    /// Ingests a new GPS fix, projects it onto the closest trail segment,
    /// updates distance/elevation, and assesses off-trail deviation.
    @discardableResult
    public func updateLocation(_ location: CLLocation) -> TrailProgress? {
        guard CLLocationCoordinate2DIsValid(location.coordinate) else { return nil }
        guard abs(location.coordinate.latitude) <= 90.0,
              abs(location.coordinate.longitude) <= 180.0,
              !location.coordinate.latitude.isNaN,
              !location.coordinate.longitude.isNaN,
              !location.horizontalAccuracy.isNaN else {
            return nil
        }
        guard let track = activeTrack, !track.points.isEmpty else {
            return nil
        }
        
        // Single-point track handling
        if track.points.count == 1 {
            let pt = track.points[0]
            let dist = location.distance(from: CLLocation(latitude: pt.coordinate.latitude, longitude: pt.coordinate.longitude))
            
            self.crossTrackDeviation = dist
            self.userProgressDistance = 0.0
            self.remainingDistance = 0.0
            self.currentElevation = pt.elevation
            
            evaluateOffTrailState(deviation: dist, location: location)
            
            let progress = TrailProgress(
                distanceTraversed: 0.0,
                remainingDistance: 0.0,
                progressRatio: 1.0,
                currentElevation: pt.elevation,
                crossTrackDeviation: dist,
                isOffTrail: self.isOffTrail,
                closestCoordinate: pt.coordinate,
                segmentIndex: 0
            )
            self.currentProgress = progress
            return progress
        }
        
        // Multi-segment equirectangular cross-track projection
        var minDeviation = Double.infinity
        var bestSegmentIndex = 0
        var bestT = 0.0
        var bestClosestCoord = track.points[0].coordinate
        
        let R = 6_371_000.0
        let deg2rad = Double.pi / 180.0
        
        for i in 0..<(track.points.count - 1) {
            let p1 = track.points[i]
            let p2 = track.points[i + 1]
            
            let phi0 = p1.coordinate.latitude * deg2rad
            let cosPhi0 = cos(phi0)
            
            var dLon = p2.coordinate.longitude - p1.coordinate.longitude
            while dLon > 180.0 { dLon -= 360.0 }
            while dLon < -180.0 { dLon += 360.0 }
            
            let dx = dLon * deg2rad * R * cosPhi0
            let dy = (p2.coordinate.latitude - p1.coordinate.latitude) * deg2rad * R
            let lenSq = dx * dx + dy * dy
            
            let t: Double
            let closestLat: Double
            var closestLon: Double
            
            if lenSq < 1e-12 {
                t = 0.0
                closestLat = p1.coordinate.latitude
                closestLon = p1.coordinate.longitude
            } else {
                var uLon = location.coordinate.longitude - p1.coordinate.longitude
                while uLon > 180.0 { uLon -= 360.0 }
                while uLon < -180.0 { uLon += 360.0 }
                
                let ux = uLon * deg2rad * R * cosPhi0
                let uy = (location.coordinate.latitude - p1.coordinate.latitude) * deg2rad * R
                let rawT = (ux * dx + uy * dy) / lenSq
                t = min(1.0, max(0.0, rawT))
                closestLat = p1.coordinate.latitude + t * (p2.coordinate.latitude - p1.coordinate.latitude)
                closestLon = p1.coordinate.longitude + t * dLon
                while closestLon > 180.0 { closestLon -= 360.0 }
                while closestLon < -180.0 { closestLon += 360.0 }
            }
            
            let closestCoord = CLLocationCoordinate2D(latitude: closestLat, longitude: closestLon)
            let dev = location.distance(from: CLLocation(latitude: closestLat, longitude: closestLon))
            
            if dev < minDeviation {
                minDeviation = dev
                bestSegmentIndex = i
                bestT = t
                bestClosestCoord = closestCoord
            }
        }
        
        let pK = track.points[bestSegmentIndex]
        let pK1 = track.points[bestSegmentIndex + 1]
        let segmentDistance = pK1.cumulativeDistance - pK.cumulativeDistance
        let userDist = pK.cumulativeDistance + bestT * segmentDistance
        let remainingDist = max(0.0, track.totalDistance - userDist)
        let progressRatio = track.totalDistance > 0 ? min(1.0, max(0.0, userDist / track.totalDistance)) : 1.0
        
        let interpElevation: Double?
        if let e1 = pK.elevation, let e2 = pK1.elevation {
            interpElevation = e1 + bestT * (e2 - e1)
        } else {
            interpElevation = pK.elevation ?? pK1.elevation
        }
        
        evaluateOffTrailState(deviation: minDeviation, location: location)
        
        self.crossTrackDeviation = minDeviation
        self.userProgressDistance = userDist
        self.remainingDistance = remainingDist
        self.currentElevation = interpElevation
        
        let progress = TrailProgress(
            distanceTraversed: userDist,
            remainingDistance: remainingDist,
            progressRatio: progressRatio,
            currentElevation: interpElevation,
            crossTrackDeviation: minDeviation,
            isOffTrail: self.isOffTrail,
            closestCoordinate: bestClosestCoord,
            segmentIndex: bestSegmentIndex
        )
        self.currentProgress = progress
        return progress
    }
    
    // MARK: - Off-Trail State Machine
    
    private func evaluateOffTrailState(deviation: Double, location: CLLocation) {
        // Degraded GPS Accuracy Protection:
        // If accuracy > 30.0m or < 0.0 (invalid) or isNaN, do not transition to off-trail
        let isGPSDegraded = location.horizontalAccuracy > maxGPSAccuracyMeters || location.horizontalAccuracy < 0.0 || location.horizontalAccuracy.isNaN
        
        if isOffTrail {
            // Hysteresis recovery: User remains in off-trail state until deviation drops below 18.0m
            if deviation < recoveryThresholdMeters {
                isOffTrail = false
                consecutiveOffTrailCount = 0
                offTrailStartTime = nil
            } else {
                // Continued off-trail state: trigger alert periodically subject to cooldown
                if !isGPSDegraded && deviation >= offTrailThresholdMeters {
                    audioAlertService?.triggerOffTrailAlert(deviation: deviation, timestamp: location.timestamp)
                }
            }
        } else {
            // Currently on trail: evaluate deviation and debounce criteria
            if isGPSDegraded {
                // Suppress off-trail trigger on unreliable fix
                consecutiveOffTrailCount = 0
                offTrailStartTime = nil
            } else if deviation >= offTrailThresholdMeters {
                consecutiveOffTrailCount += 1
                if offTrailStartTime == nil {
                    offTrailStartTime = location.timestamp
                }
                let sustainedDuration = location.timestamp.timeIntervalSince(offTrailStartTime ?? location.timestamp)
                
                // Debounce: minimum 3 consecutive fixes OR sustained duration >= 4.0 seconds
                if consecutiveOffTrailCount >= debounceFixCount || sustainedDuration >= debounceDurationSeconds {
                    isOffTrail = true
                    audioAlertService?.triggerOffTrailAlert(deviation: deviation, timestamp: location.timestamp)
                }
            } else {
                consecutiveOffTrailCount = 0
                offTrailStartTime = nil
            }
        }
    }
}
