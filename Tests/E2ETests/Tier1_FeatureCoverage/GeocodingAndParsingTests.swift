// GeocodingAndParsingTests.swift — Tier 1 Feature Coverage: Geocoding Optimization, Input Parsing, Category Queries

import Foundation
import CoreLocation

public final class GeocodingAndParsingTests: E2ETestSuite {
    public let name = "Geocoding Optimization & Input Parsing Suite"
    public let tier = TestTier.tier1
    
    public var tests: [TestCaseEntry] {
        return [
            TestCaseEntry(name: "testT1_ReverseGeocodeScansFullBoundingBoxWithoutPrematureBreak", tier: tier, block: testT1_ReverseGeocodeScansFullBoundingBoxWithoutPrematureBreak),
            TestCaseEntry(name: "testT1_CoordinateParsingWithDegreeSymbols", tier: tier, block: testT1_CoordinateParsingWithDegreeSymbols),
            TestCaseEntry(name: "testT1_CoordinateParsingWithCardinalDirections", tier: tier, block: testT1_CoordinateParsingWithCardinalDirections),
            TestCaseEntry(name: "testT1_CoordinateParsingWithSouthernAndWesternHemispheres", tier: tier, block: testT1_CoordinateParsingWithSouthernAndWesternHemispheres),
            TestCaseEntry(name: "testT1_CategoryClassificationForGroceryBrandsAndTerms", tier: tier, block: testT1_CategoryClassificationForGroceryBrandsAndTerms),
            TestCaseEntry(name: "testT1_CategoryFTS5QueryExpansionForGroceries", tier: tier, block: testT1_CategoryFTS5QueryExpansionForGroceries),
            TestCaseEntry(name: "testT1_ReverseGeocodeSparseAreaReturnsDroppedPinFallback", tier: tier, block: testT1_ReverseGeocodeSparseAreaReturnsDroppedPinFallback)
        ]
    }
    
    /// R4.1: In SearchService.swift, remove the premature < 25.0 meter break in performReverseGeocode
    /// so the search scans the candidate bounding box and selects the true closest POI.
    func testT1_ReverseGeocodeScansFullBoundingBoxWithoutPrematureBreak() async throws {
        // Query coordinate at downtown intersection
        let queryCoord = CLLocationCoordinate2D(latitude: 64.84360, longitude: -147.72150)
        
        // Construct candidates in candidate box:
        // Candidate A: 20 meters away (lat 64.84378)
        // Candidate B: 5 meters away (lat 64.84364)
        // In the flawed implementation with "if minDistanceMeters < 25.0 { break }", Candidate A was evaluated first,
        // so the loop broke immediately, returning Candidate A (20m away) instead of Candidate B (5m away)!
        let candA = OpaqueSearchResult(id: 101, name: "Farther POI (20m)", lat: 64.84378, lon: -147.72150)
        let candB = OpaqueSearchResult(id: 102, name: "Closer True POI (5m)", lat: 64.84364, lon: -147.72150)
        let candC = OpaqueSearchResult(id: 103, name: "Third POI (35m)", lat: 64.84390, lon: -147.72150)
        
        let closest = OpaqueReverseGeocoder.findClosestPOI(queryCoord: queryCoord, candidates: [candA, candB, candC])
        assertNotNil(closest, "Should return a closest candidate")
        assertEqual(closest?.id, 102, "Must return Candidate B (the true closest POI at 5m) rather than breaking prematurely on Candidate A (20m)")
    }
    
    /// R4.2: Update parseCoordinates to accept coordinates with degree symbols (°)
    func testT1_CoordinateParsingWithDegreeSymbols() async throws {
        let query1 = "64.8436°, -147.7215°"
        let coord1 = OpaqueCoordinateParser.parse(query: query1)
        assertNotNil(coord1, "Should parse degree symbols")
        assertInDelta(coord1?.latitude ?? 0, 64.8436, delta: 0.0001, "Latitude mismatch")
        assertInDelta(coord1?.longitude ?? 0, -147.7215, delta: 0.0001, "Longitude mismatch")
        
        let query2 = "61.2181 ° , -149.9003 °"
        let coord2 = OpaqueCoordinateParser.parse(query: query2)
        assertNotNil(coord2, "Should parse spaced degree symbols")
        assertInDelta(coord2?.latitude ?? 0, 61.2181, delta: 0.0001)
        assertInDelta(coord2?.longitude ?? 0, -149.9003, delta: 0.0001)
    }
    
    /// R4.2: Update parseCoordinates to accept cardinal direction suffixes (N, S, E, W)
    func testT1_CoordinateParsingWithCardinalDirections() async throws {
        let query1 = "64.8436° N, 147.7215° W"
        let coord1 = OpaqueCoordinateParser.parse(query: query1)
        assertNotNil(coord1, "Should parse N and W cardinal suffixes")
        assertInDelta(coord1?.latitude ?? 0, 64.8436, delta: 0.0001)
        assertInDelta(coord1?.longitude ?? 0, -147.7215, delta: 0.0001, "W must produce negative longitude")
        
        let query2 = "58.3019 N, 134.4197 W"
        let coord2 = OpaqueCoordinateParser.parse(query: query2)
        assertNotNil(coord2, "Should parse cardinal suffixes without degree signs")
        assertInDelta(coord2?.latitude ?? 0, 58.3019, delta: 0.0001)
        assertInDelta(coord2?.longitude ?? 0, -134.4197, delta: 0.0001)
    }
    
    /// R4.2: Parse negative coordinates and southern/eastern directions
    func testT1_CoordinateParsingWithSouthernAndWesternHemispheres() async throws {
        let query1 = "34.6037° S, 58.3816° W" // Buenos Aires
        let coord1 = OpaqueCoordinateParser.parse(query: query1)
        assertNotNil(coord1, "Should parse Southern hemisphere coordinates")
        assertInDelta(coord1?.latitude ?? 0, -34.6037, delta: 0.0001, "S must convert to negative latitude")
        assertInDelta(coord1?.longitude ?? 0, -58.3816, delta: 0.0001, "W must convert to negative longitude")
        
        let query2 = "35.6762° N, 139.6503° E" // Tokyo
        let coord2 = OpaqueCoordinateParser.parse(query: query2)
        assertNotNil(coord2, "Should parse Eastern hemisphere coordinates")
        assertInDelta(coord2?.latitude ?? 0, 35.6762, delta: 0.0001)
        assertInDelta(coord2?.longitude ?? 0, 139.6503, delta: 0.0001, "E must produce positive longitude")
    }
    
    /// R4.3: Refine category classification and search queries for POI categories such as groceries
    func testT1_CategoryClassificationForGroceryBrandsAndTerms() async throws {
        let storeNames = [
            ("Fred Meyer Superstore", "grocery", "cart.fill"),
            ("Carrs Safeway Quality Foods", "grocery", "cart.fill"),
            ("Costco Wholesale Fairbanks", "grocery", "cart.fill"),
            ("Co-Op Market & Deli", "grocery", "cart.fill"),
            ("Roald's Local Groceries", "grocery", "cart.fill"),
            ("Sunshine Supermarket", "grocery", "cart.fill")
        ]
        
        for (name, expectedCat, expectedIcon) in storeNames {
            let item = OpaqueSearchResult(id: 1, name: name, lat: 64.84, lon: -147.72)
            assertEqual(item.category, expectedCat, "Expected '\(name)' to be classified as \(expectedCat)")
            assertEqual(item.iconName, expectedIcon, "Expected '\(name)' to have icon \(expectedIcon)")
        }
    }
    
    /// R4.3: Validate expanded FTS5 query terms for groceries
    func testT1_CategoryFTS5QueryExpansionForGroceries() async throws {
        let ftsQuery = OpaqueCategoryClassifier.expandedFTS5GroceryQuery()
        assertTrue(ftsQuery.contains("\"grocery\"*"), "Query must contain 'grocery'*")
        assertTrue(ftsQuery.contains("\"supermarket\"*"), "Query must contain 'supermarket'*")
        assertTrue(ftsQuery.contains("\"market\"*"), "Query must contain 'market'*")
        assertTrue(ftsQuery.contains("\"fred\"*"), "Query must contain 'fred'*")
        assertTrue(ftsQuery.contains("\"safeway\"*"), "Query must contain 'safeway'*")
        assertTrue(ftsQuery.contains("\"costco\"*"), "Query must contain 'costco'*")
    }
    
    /// Sparse area reverse geocoding returns Dropped Pin without hanging
    func testT1_ReverseGeocodeSparseAreaReturnsDroppedPinFallback() async throws {
        let oceanCoord = CLLocationCoordinate2D(latitude: 55.0, longitude: -160.0) // Open Gulf of Alaska
        let candidates: [OpaqueSearchResult] = [] // No candidates in ocean bounding box
        
        let result = OpaqueReverseGeocoder.findClosestPOI(queryCoord: oceanCoord, candidates: candidates)
        assertNil(result, "Empty candidate box should return nil from closest POI lookup")
    }
}
