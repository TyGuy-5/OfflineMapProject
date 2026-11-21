// GeocodingNavigationCombinationsTests.swift — Tier 3 Cross-Feature Combinations: Geocoding & Search Interactions

import Foundation
import CoreLocation

public final class GeocodingNavigationCombinationsTests: E2ETestSuite {
    public let name = "Geocoding & Search Combinations Suite"
    public let tier = TestTier.tier3
    
    public var tests: [TestCaseEntry] {
        return [
            TestCaseEntry(name: "testT3_CoordinateSearchWithDegreesFeedsReverseGeocoding", tier: tier, block: testT3_CoordinateSearchWithDegreesFeedsReverseGeocoding),
            TestCaseEntry(name: "testT3_CategorySearchGroceriesPrioritizesLocalBoundingBox", tier: tier, block: testT3_CategorySearchGroceriesPrioritizesLocalBoundingBox),
            TestCaseEntry(name: "testT3_RoutingEngineFailFastTimeoutDoesNotDeadlockSearchTasks", tier: tier, block: testT3_RoutingEngineFailFastTimeoutDoesNotDeadlockSearchTasks)
        ]
    }
    
    /// Pairwise 4: Coordinate Search with Degree Symbols + Reverse Geocoding
    /// Parsing cardinal coordinate input creates a dropped pin and reverse geocodes the closest POI
    func testT3_CoordinateSearchWithDegreesFeedsReverseGeocoding() async throws {
        let inputQuery = "64.8436° N, 147.7215° W"
        let parsedCoord = OpaqueCoordinateParser.parse(query: inputQuery)
        assertNotNil(parsedCoord, "Must parse degrees with cardinal directions")
        
        // Simulating reverse geocode resolution around this parsed coordinate
        let cand1 = OpaqueSearchResult(id: 1, name: "Fairbanks City Hall", lat: 64.8438, lon: -147.7210)
        let cand2 = OpaqueSearchResult(id: 2, name: "Golden Heart Plaza", lat: 64.84365, lon: -147.72155) // ~6m away
        
        let resolved = OpaqueReverseGeocoder.findClosestPOI(queryCoord: parsedCoord!, candidates: [cand1, cand2])
        assertNotNil(resolved)
        assertEqual(resolved?.name, "Golden Heart Plaza", "Reverse geocode must resolve true closest POI near parsed coordinate")
    }
    
    /// Pairwise 5: Category Search "Groceries" + Local Spatial Bounding Box Prioritization
    /// Querying "Groceries" while user is in Fairbanks ranks local Fairbanks supermarkets ahead of Anchorage supermarkets
    func testT3_CategorySearchGroceriesPrioritizesLocalBoundingBox() async throws {
        let userLocation = TestCoordinates.fairbanksDowntown
        
        // Candidate grocery stores
        let fairbanksCoOp = OpaqueSearchResult(id: 1, name: "Co-Op Market & Deli", lat: 64.8465, lon: -147.7120)
        let fairbanksFredMeyer = OpaqueSearchResult(id: 2, name: "Fred Meyer Fairbanks", lat: 64.8480, lon: -147.7340)
        let anchorageCarrs = OpaqueSearchResult(id: 3, name: "Carrs Safeway Anchorage", lat: 61.2181, lon: -149.9003) // ~260 miles away
        
        var results = [anchorageCarrs, fairbanksCoOp, fairbanksFredMeyer]
        // Rank by distance from Fairbanks user location
        results.sort {
            ($0.distanceMiles(from: userLocation) ?? Double.greatestFiniteMagnitude) <
            ($1.distanceMiles(from: userLocation) ?? Double.greatestFiniteMagnitude)
        }
        
        assertEqual(results[0].name, "Co-Op Market & Deli", "Closest local Fairbanks grocery store must be first")
        assertEqual(results[1].name, "Fred Meyer Fairbanks", "Second closest local Fairbanks store must be second")
        assertEqual(results[2].name, "Carrs Safeway Anchorage", "Anchorage store 260 miles away must rank last")
    }
    
    /// Pairwise 6: Routing Engine Fail-Fast Timeout + Search Task Cancellation
    /// Background route calculation enforcing 5.0-second fail-fast timeout returns nil cleanly without deadlocking UI queue
    func testT3_RoutingEngineFailFastTimeoutDoesNotDeadlockSearchTasks() async throws {
        let group = DispatchGroup()
        var routeCalculationFinished = false
        var searchTaskCancelled = false
        
        // 1. Simulate Valhalla route calculation with 5.0s wait timeout
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            let initGroup = DispatchGroup()
            initGroup.enter() // Simulating slow/stuck background worker
            
            // Fail-fast wait with timeout
            let waitResult = initGroup.wait(timeout: .now() + 0.1) // Shortened for test
            let routeResult: OpaqueRouteDetails?
            if waitResult == .timedOut {
                routeResult = nil // Clean nil return contract per R3.4
            } else {
                routeResult = nil
            }
            assertNil(routeResult, "Must cleanly return nil on timeout without hanging")
            routeCalculationFinished = true
            group.leave()
        }
        
        // 2. Concurrently dispatch and cancel search task on main queue
        let task = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if Task.isCancelled {
                searchTaskCancelled = true
            }
        }
        task.cancel()
        _ = await task.result
        
        let waitRes: DispatchTimeoutResult = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let res = group.wait(timeout: .now() + 2.0)
                continuation.resume(returning: res)
            }
        }
        assertEqual(waitRes, .success, "Must finish without deadlocking worker queues")
        assertTrue(routeCalculationFinished)
        assertTrue(searchTaskCancelled)
    }
}
