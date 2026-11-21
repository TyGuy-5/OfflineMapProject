import Foundation
import CoreLocation

/// Utility to build deterministic sequences of CLLocation points for testing trail navigation,
/// cross-track deviation, debounced alerting, hysteresis reset, and GPS signal degradation.
public struct LocationSequenceBuilder: Sendable {
    
    public static let earthRadiusMeters: Double = 6371000.0
    public static let metersPerDegreeLat: Double = 111132.95
    
    /// Computes meters per degree longitude at a given latitude.
    public static func metersPerDegreeLon(atLatitude latitude: Double) -> Double {
        let radians = latitude * .pi / 180.0
        return metersPerDegreeLat * cos(radians)
    }
    
    /// Haversine distance between two coordinates in meters.
    public static func distance(from c1: CLLocationCoordinate2D, to c2: CLLocationCoordinate2D) -> Double {
        let lat1 = c1.latitude * .pi / 180.0
        let lon1 = c1.longitude * .pi / 180.0
        let lat2 = c2.latitude * .pi / 180.0
        let lon2 = c2.longitude * .pi / 180.0
        
        let dlat = lat2 - lat1
        let dlon = lon2 - lon1
        
        let a = sin(dlat / 2.0) * sin(dlat / 2.0) +
                cos(lat1) * cos(lat2) * sin(dlon / 2.0) * sin(dlon / 2.0)
        let c = 2.0 * atan2(sqrt(a), sqrt(1.0 - a))
        return earthRadiusMeters * c
    }
    
    /// Shifts coordinate by north/east meter offsets.
    public static func shift(
        coordinate: CLLocationCoordinate2D,
        northMeters: Double,
        eastMeters: Double
    ) -> CLLocationCoordinate2D {
        let dLat = northMeters / metersPerDegreeLat
        let dLon = eastMeters / metersPerDegreeLon(atLatitude: coordinate.latitude)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + dLat,
            longitude: coordinate.longitude + dLon
        )
    }
    
    /// Offsets coordinate perpendicular to a given bearing in degrees (offset > 0 = right/east, offset < 0 = left/west).
    public static func offsetPerpendicular(
        coordinate: CLLocationCoordinate2D,
        bearingDegrees: Double,
        offsetMeters: Double
    ) -> CLLocationCoordinate2D {
        let perpBearing = (bearingDegrees + 90.0) * .pi / 180.0
        let northMeters = offsetMeters * cos(perpBearing)
        let eastMeters = offsetMeters * sin(perpBearing)
        return shift(coordinate: coordinate, northMeters: northMeters, eastMeters: eastMeters)
    }
    
    // MARK: - Scenario Builders
    
    /// Generates a standard off-trail test scenario:
    /// 1. 5 points on the trail (0m deviation)
    /// 2. 3 points drifted >25m off trail (30-35m deviation, triggering alert)
    /// 3. 2 points returned <18m within trail (10-12m, resetting hysteresis)
    public static func makeOffTrailScenario(
        start: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        stepMeters: Double = 10.0,
        bearingDegrees: Double = 0.0 // Due North
    ) -> (onTrail: [CLLocation], offTrail: [CLLocation], recovered: [CLLocation]) {
        let baseTime = Date()
        
        // 1. On trail (5 steps, 0 to 40 meters North)
        let onTrail = (0..<5).map { i in
            let coord = shift(coordinate: start, northMeters: Double(i) * stepMeters, eastMeters: 0.0)
            return CLLocation(
                coordinate: coord,
                altitude: 100.0 + Double(i) * 2.0,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 5.0,
                timestamp: baseTime.addingTimeInterval(Double(i) * 2.0)
            )
        }
        
        // 2. Off trail: continuing North from 50m to 70m, but offset 32m East (>25m threshold)
        let offTrail = (0..<3).map { i in
            let coord = shift(coordinate: start, northMeters: (50.0 + Double(i) * stepMeters), eastMeters: 32.0)
            return CLLocation(
                coordinate: coord,
                altitude: 110.0,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 5.0,
                timestamp: baseTime.addingTimeInterval(12.0 + Double(i) * 2.0)
            )
        }
        
        // 3. Recovered: at 80m and 90m North, returning to 10m East (<18m hysteresis threshold)
        let recovered = (0..<2).map { i in
            let coord = shift(coordinate: start, northMeters: (80.0 + Double(i) * stepMeters), eastMeters: 10.0)
            return CLLocation(
                coordinate: coord,
                altitude: 114.0 + Double(i) * 2.0,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 5.0,
                timestamp: baseTime.addingTimeInterval(20.0 + Double(i) * 2.0)
            )
        }
        
        return (onTrail, offTrail, recovered)
    }
    
    /// Generates a straight track sequence of arbitrary length and elevation.
    public static func makeStraightTrack(
        start: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 46.8529, longitude: -113.9850),
        stepCount: Int = 10,
        stepMeters: Double = 20.0,
        bearingDegrees: Double = 45.0,
        startAltitude: Double = 900.0,
        totalElevationGain: Double = 200.0
    ) -> [CLLocation] {
        let rad = bearingDegrees * .pi / 180.0
        let baseTime = Date()
        let eleStep = stepCount > 1 ? totalElevationGain / Double(stepCount - 1) : 0.0
        
        return (0..<stepCount).map { i in
            let dist = Double(i) * stepMeters
            let north = dist * cos(rad)
            let east = dist * sin(rad)
            let coord = shift(coordinate: start, northMeters: north, eastMeters: east)
            return CLLocation(
                coordinate: coord,
                altitude: startAltitude + Double(i) * eleStep,
                horizontalAccuracy: 4.0,
                verticalAccuracy: 3.0,
                timestamp: baseTime.addingTimeInterval(Double(i) * 3.0)
            )
        }
    }
    
    /// Generates a track with degraded GPS horizontal accuracy (e.g. ±65m) to test filtering and debouncing.
    public static func makeDegradedAccuracyTrack(
        start: CLLocationCoordinate2D,
        count: Int = 5,
        accuracyMeters: Double = 65.0
    ) -> [CLLocation] {
        let baseTime = Date()
        return (0..<count).map { i in
            let coord = shift(coordinate: start, northMeters: Double(i) * 15.0, eastMeters: 0.0)
            return CLLocation(
                coordinate: coord,
                altitude: 500.0,
                horizontalAccuracy: accuracyMeters,
                verticalAccuracy: accuracyMeters,
                timestamp: baseTime.addingTimeInterval(Double(i) * 2.0)
            )
        }
    }
    
    /// Generates high-altitude alpine trek points with significant elevation change.
    public static func makeAlpineTrek(
        start: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 45.8326, longitude: 6.8652), // Mont Blanc
        pointsCount: Int = 50,
        totalElevationGain: Double = 3200.0
    ) -> [CLLocation] {
        let baseTime = Date()
        let stepElevation = totalElevationGain / Double(pointsCount)
        return (0..<pointsCount).map { i in
            let coord = shift(coordinate: start, northMeters: Double(i) * 50.0, eastMeters: Double(i) * 30.0)
            return CLLocation(
                coordinate: coord,
                altitude: 1000.0 + Double(i) * stepElevation,
                horizontalAccuracy: 3.0,
                verticalAccuracy: 4.0,
                timestamp: baseTime.addingTimeInterval(Double(i) * 10.0)
            )
        }
    }
    
    /// Generates a circular loop track.
    public static func makeLoopTrack(
        center: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        radiusMeters: Double = 500.0,
        stepsCount: Int = 36
    ) -> [CLLocation] {
        let baseTime = Date()
        return (0..<stepsCount).map { i in
            let angle = (Double(i) / Double(stepsCount)) * 2.0 * .pi
            let north = radiusMeters * cos(angle)
            let east = radiusMeters * sin(angle)
            let coord = shift(coordinate: center, northMeters: north, eastMeters: east)
            return CLLocation(
                coordinate: coord,
                altitude: 50.0,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 5.0,
                timestamp: baseTime.addingTimeInterval(Double(i) * 5.0)
            )
        }
    }
}
