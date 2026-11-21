// CoordinateBoundaryTests.swift — Tier 2 Boundary Cases: Coordinate Extremes & Format Anomalies

import Foundation
import CoreLocation

public final class CoordinateBoundaryTests: E2ETestSuite {
    public let name = "Coordinate Boundary & Parsing Extremes Suite"
    public let tier = TestTier.tier2
    
    public var tests: [TestCaseEntry] {
        return [
            TestCaseEntry(name: "testT2_PolesAndInternationalDateLineBoundaries", tier: tier, block: testT2_PolesAndInternationalDateLineBoundaries),
            TestCaseEntry(name: "testT2_OutOfRangeCoordinatesRejected", tier: tier, block: testT2_OutOfRangeCoordinatesRejected),
            TestCaseEntry(name: "testT2_ExtremeWhitespaceAndDelimiterVariations", tier: tier, block: testT2_ExtremeWhitespaceAndDelimiterVariations),
            TestCaseEntry(name: "testT2_MalformedAndIncompleteCoordinateStrings", tier: tier, block: testT2_MalformedAndIncompleteCoordinateStrings),
            TestCaseEntry(name: "testT2_NullIslandAndEquatorPrimeMeridianBoundary", tier: tier, block: testT2_NullIslandAndEquatorPrimeMeridianBoundary)
        ]
    }
    
    /// Exact poles and date line limits (±90.0 latitude, ±180.0 longitude)
    func testT2_PolesAndInternationalDateLineBoundaries() async throws {
        // North Pole
        let np = OpaqueCoordinateParser.parse(query: "90.0° N, 0.0° E")
        assertNotNil(np, "North Pole should parse")
        assertEqual(np?.latitude ?? 0, 90.0)
        
        // South Pole
        let sp = OpaqueCoordinateParser.parse(query: "90.0° S, 0.0° W")
        assertNotNil(sp, "South Pole should parse")
        assertEqual(sp?.latitude ?? 0, -90.0)
        
        // Date Line West
        let dlw = OpaqueCoordinateParser.parse(query: "0.0, -180.0")
        assertNotNil(dlw, "Date line -180 should parse")
        assertEqual(dlw?.longitude ?? 0, -180.0)
        
        // Date Line East
        let dle = OpaqueCoordinateParser.parse(query: "0.0, 180.0")
        assertNotNil(dle, "Date line +180 should parse")
        assertEqual(dle?.longitude ?? 0, 180.0)
    }
    
    /// Out-of-range coordinates must safely return nil without crashing
    func testT2_OutOfRangeCoordinatesRejected() async throws {
        let invalidQueries = [
            "90.0001, -147.7215",
            "-90.0001, -147.7215",
            "64.8436, 180.0001",
            "64.8436, -180.0001",
            "91.0° N, 147.0° W",
            "64.8436° N, 181.0° W",
            "999.0, 999.0"
        ]
        for query in invalidQueries {
            let res = OpaqueCoordinateParser.parse(query: query)
            assertNil(res, "Query '\(query)' should return nil as out-of-range")
        }
    }
    
    /// Extreme whitespace, tab delimiters, and semicolon separators
    func testT2_ExtremeWhitespaceAndDelimiterVariations() async throws {
        let spacedQueries = [
            "  64.8436  ,   -147.7215   ",
            "64.8436; -147.7215",
            "64.8436°   N   ;   147.7215°   W",
            "  64.8436°N  ,  147.7215°W  "
        ]
        for query in spacedQueries {
            let res = OpaqueCoordinateParser.parse(query: query)
            assertNotNil(res, "Query '\(query)' should be parsed successfully")
            assertInDelta(res?.latitude ?? 0, 64.8436, delta: 0.0001)
            assertInDelta(res?.longitude ?? 0, -147.7215, delta: 0.0001)
        }
    }
    
    /// Malformed strings, non-numeric tokens, and incomplete inputs
    func testT2_MalformedAndIncompleteCoordinateStrings() async throws {
        let malformed = [
            "",
            "   ",
            "64.8436",
            "64.8436,",
            ", -147.7215",
            "Fairbanks, Alaska",
            "latitude, longitude",
            "64.84.36, -147.72.15",
            "NaN, NaN",
            "Infinity, -147.7215"
        ]
        for query in malformed {
            let res = OpaqueCoordinateParser.parse(query: query)
            assertNil(res, "Malformed query '\(query)' must return nil")
        }
    }
    
    /// Null Island (0.0, 0.0) boundary
    func testT2_NullIslandAndEquatorPrimeMeridianBoundary() async throws {
        let query = "0.0000, 0.0000"
        let res = OpaqueCoordinateParser.parse(query: query)
        assertNotNil(res, "Null Island (0,0) should parse successfully")
        assertEqual(res?.latitude ?? 1.0, 0.0)
        assertEqual(res?.longitude ?? 1.0, 0.0)
    }
}
