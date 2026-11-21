// TestData.swift — Geographic coordinates, route polylines, and POI test fixtures

import Foundation
import CoreLocation

public struct TestCoordinates {
    // Alaska In-Region Benchmarks
    public static let fairbanksDowntown = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
    public static let fairbanksAirport = CLLocationCoordinate2D(latitude: 64.8153, longitude: -147.8564)
    public static let uafCampus = CLLocationCoordinate2D(latitude: 64.8569, longitude: -147.8028)
    public static let coopMarketFairbanks = CLLocationCoordinate2D(latitude: 64.8465, longitude: -147.7120)
    public static let fredMeyerFairbanks = CLLocationCoordinate2D(latitude: 64.8480, longitude: -147.7340)
    public static let costcoFairbanks = CLLocationCoordinate2D(latitude: 64.8490, longitude: -147.7010)
    public static let anchorageDowntown = CLLocationCoordinate2D(latitude: 61.2181, longitude: -149.9003)
    public static let juneauDowntown = CLLocationCoordinate2D(latitude: 58.3019, longitude: -134.4197)
    public static let barrowUtqiagvik = CLLocationCoordinate2D(latitude: 71.2906, longitude: -156.7887)
    
    // Alaska Bounding Box Limits: [51.0, 72.0] x [-179.0, -129.0]
    public static let southwestBoundary = CLLocationCoordinate2D(latitude: 51.0, longitude: -179.0)
    public static let northeastBoundary = CLLocationCoordinate2D(latitude: 72.0, longitude: -129.0)
    
    // Out-of-Region Coordinates
    public static let seattleDowntown = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
    public static let sanFrancisco = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
    public static let newYorkCity = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
    public static let honolulu = CLLocationCoordinate2D(latitude: 21.3069, longitude: -157.8583)
    public static let london = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
    public static let tokyo = CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503)
    public static let nullIsland = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
}

public struct TestGeometries {
    /// Generates a synthetic switchback / hairpin turn route.
    /// Leg 1: coordinates 0...10 heading North along longitude -147.7200
    /// Hairpin curve: coordinates 10...14 turning East and South
    /// Leg 2: coordinates 14...24 heading South along longitude -147.7198 (approx 10-15 meters East of Leg 1!)
    public static func makeSwitchbackRoute() -> (coordinates: [CLLocationCoordinate2D], steps: [OpaqueNavigationStep]) {
        var coords: [CLLocationCoordinate2D] = []
        let baseLat = 64.8400
        
        // Leg 1: Step 0 (Northward, indices 0..10)
        for i in 0...10 {
            coords.append(CLLocationCoordinate2D(latitude: baseLat + Double(i) * 0.0005, longitude: -147.7200))
        }
        // Hairpin turn: Step 1 (Curve, indices 10..14)
        coords.append(CLLocationCoordinate2D(latitude: baseLat + 0.0052, longitude: -147.7199))
        coords.append(CLLocationCoordinate2D(latitude: baseLat + 0.0053, longitude: -147.7198))
        coords.append(CLLocationCoordinate2D(latitude: baseLat + 0.0052, longitude: -147.7197))
        coords.append(CLLocationCoordinate2D(latitude: baseLat + 0.0050, longitude: -147.7197))
        
        // Leg 2: Step 2 (Southward, parallel proximate road segment, indices 14..24)
        for i in 1...10 {
            coords.append(CLLocationCoordinate2D(latitude: baseLat + 0.0050 - Double(i) * 0.0005, longitude: -147.7197))
        }
        
        let step0 = OpaqueNavigationStep(
            instruction: "Head north on Ester Dome Road",
            distanceMiles: 0.35,
            durationSeconds: 40.0,
            maneuverType: 1,
            streetName: "Ester Dome Road",
            startIndex: 0,
            endIndex: 10
        )
        let step1 = OpaqueNavigationStep(
            instruction: "Make a sharp right on Switchback Cutoff",
            distanceMiles: 0.05,
            durationSeconds: 15.0,
            maneuverType: 13,
            streetName: "Switchback Cutoff",
            startIndex: 10,
            endIndex: 14
        )
        let step2 = OpaqueNavigationStep(
            instruction: "Continue south toward Sheep Creek Road",
            distanceMiles: 0.35,
            durationSeconds: 40.0,
            maneuverType: 1,
            streetName: "Sheep Creek Road",
            startIndex: 14,
            endIndex: 24
        )
        
        return (coords, [step0, step1, step2])
    }
    
    /// Generates a route where the final destination pin is set back 35 meters from the road centerline.
    public static func makeSetbackDestinationScenario() -> (
        coordinates: [CLLocationCoordinate2D],
        steps: [OpaqueNavigationStep],
        roadEndCoordinate: CLLocationCoordinate2D,
        destinationPinCoordinate: CLLocationCoordinate2D,
        userArrivedCoordinate: CLLocationCoordinate2D
    ) {
        let roadStart = CLLocationCoordinate2D(latitude: 64.8430, longitude: -147.7200)
        let roadMid = CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7200)
        let roadEnd = CLLocationCoordinate2D(latitude: 64.8450, longitude: -147.7200) // End of drivable street
        
        // Destination pin is set back into a parking lot 35m West (approx 0.00075 lon at 64.8N)
        let destPin = CLLocationCoordinate2D(latitude: 64.8450, longitude: -147.72075)
        
        // User approaches within 10 meters of destination pin (which is still 30m away from roadEnd!)
        let userArrival = CLLocationCoordinate2D(latitude: 64.8450, longitude: -147.7206)
        
        let step = OpaqueNavigationStep(
            instruction: "Drive north on Cushman Street to destination parking lot",
            distanceMiles: 0.15,
            durationSeconds: 25.0,
            maneuverType: 1,
            streetName: "Cushman Street",
            startIndex: 0,
            endIndex: 2
        )
        
        return ([roadStart, roadMid, roadEnd], [step], roadEnd, destPin, userArrival)
    }
}
