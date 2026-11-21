// UrbanReverseGeocodeScenarioTests.swift — Tier 4 Real-World Application Scenario: Dense Urban Reverse Geocoding

import Foundation
import CoreLocation

public final class UrbanReverseGeocodeScenarioTests: E2ETestSuite {
    public let name = "Real-World Scenario 3: Dense Urban Reverse Geocode"
    public let tier = TestTier.tier4
    
    public var tests: [TestCaseEntry] {
        return [
            TestCaseEntry(name: "testT4_DenseUrbanReverseGeocodeSelectsTrueClosestCandidate", tier: tier, block: testT4_DenseUrbanReverseGeocodeSelectsTrueClosestCandidate)
        ]
    }
    
    /// Scenario 3: Long-press at dense urban intersection with multiple POIs within 25 meters.
    /// Eliminating the premature < 25.0m break ensures the candidate with the true minimum Euclidean distance is selected.
    func testT4_DenseUrbanReverseGeocodeSelectsTrueClosestCandidate() async throws {
        // Query coordinate at corner of 2nd Ave & Cushman St
        let queryCoord = CLLocationCoordinate2D(latitude: 64.84360, longitude: -147.72150)
        
        // Simulating the 10 POIs returned by the bounding box query:
        // Candidate 1: Coffee stand at 23.5 meters
        // Candidate 2: Bakery at 18.2 meters
        // Candidate 3: Souvenir shop at 24.1 meters
        // Candidate 4: Boutique hotel at 3.4 meters (TRUE CLOSEST!)
        // Candidate 5: Bookstore at 12.0 meters
        let candidates = [
            OpaqueSearchResult(id: 1, name: "Moose Mountain Coffee", lat: 64.84381, lon: -147.72150), // 23.5m
            OpaqueSearchResult(id: 2, name: "Midnight Sun Bakery", lat: 64.84376, lon: -147.72150),  // 18.2m
            OpaqueSearchResult(id: 3, name: "Aurora Souvenirs", lat: 64.84382, lon: -147.72150),     // 24.1m
            OpaqueSearchResult(id: 4, name: "Golden Heart Hotel & Suites", lat: 64.84363, lon: -147.72150), // 3.4m!
            OpaqueSearchResult(id: 5, name: "Northern Lights Books", lat: 64.84371, lon: -147.72150) // 12.0m
        ]
        
        let closest = OpaqueReverseGeocoder.findClosestPOI(queryCoord: queryCoord, candidates: candidates)
        assertNotNil(closest, "Must resolve a POI")
        assertEqual(closest?.id, 4, "Must select Golden Heart Hotel & Suites (3.4m away), not premature <25m candidate 1 or 2")
        assertEqual(closest?.category, "hotel")
        assertEqual(closest?.iconName, "bed.double.fill")
    }
}
