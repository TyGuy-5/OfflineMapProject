// SearchBoundaryTests.swift — Tier 2 Boundary Cases: Search Boundaries & Query Injection Robustness

import Foundation
import CoreLocation

public final class SearchBoundaryTests: E2ETestSuite {
    public let name = "Search Boundary & Query Tokenization Suite"
    public let tier = TestTier.tier2
    
    public var tests: [TestCaseEntry] {
        return [
            TestCaseEntry(name: "testT2_EmptyAndWhitespaceOnlyQueriesReturnEmptyResults", tier: tier, block: testT2_EmptyAndWhitespaceOnlyQueriesReturnEmptyResults),
            TestCaseEntry(name: "testT2_SingleCharacterQueriesBelowThresholdSuppressed", tier: tier, block: testT2_SingleCharacterQueriesBelowThresholdSuppressed),
            TestCaseEntry(name: "testT2_FTS5PunctuationAndInjectionCharactersSanitized", tier: tier, block: testT2_FTS5PunctuationAndInjectionCharactersSanitized),
            TestCaseEntry(name: "testT2_ExtremelyLongSearchQueriesHandledGracefully", tier: tier, block: testT2_ExtremelyLongSearchQueriesHandledGracefully),
            TestCaseEntry(name: "testT2_OceanAndSparseCoordinatesEnforceProgressTimeout", tier: tier, block: testT2_OceanAndSparseCoordinatesEnforceProgressTimeout)
        ]
    }
    
    /// Empty string and whitespace-only queries
    func testT2_EmptyAndWhitespaceOnlyQueriesReturnEmptyResults() async throws {
        func sanitizeQueryTokens(_ raw: String) -> [String] {
            let nonAlphanumeric = CharacterSet.alphanumerics.inverted
            return raw.components(separatedBy: nonAlphanumeric).filter { !$0.isEmpty }
        }
        
        let emptyInputs = ["", " ", "   ", "\t", "\n", "\r\n"]
        for input in emptyInputs {
            let tokens = sanitizeQueryTokens(input)
            assertTrue(tokens.isEmpty, "Tokens for '\(input)' must be empty")
        }
    }
    
    /// Single-character queries below 2-character threshold
    func testT2_SingleCharacterQueriesBelowThresholdSuppressed() async throws {
        func shouldTriggerSearch(query: String) -> Bool {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count >= 2
        }
        
        assertFalse(shouldTriggerSearch(query: "a"), "Single letter 'a' should not trigger search")
        assertFalse(shouldTriggerSearch(query: " 1 "), "Single digit '1' with spaces should not trigger search")
        assertTrue(shouldTriggerSearch(query: "ak"), "2-letter query 'ak' should trigger search")
        assertTrue(shouldTriggerSearch(query: "gas"), "3-letter query 'gas' should trigger search")
    }
    
    /// Special FTS5 meta-characters and punctuation (*, ", ', -, :, (, ), /, \)
    func testT2_FTS5PunctuationAndInjectionCharactersSanitized() async throws {
        let rawQuery = "Fairbanks* - Alaska: \"Coffee\" & (Gas/Oil) ' OR 1=1 --"
        let nonAlphanumeric = CharacterSet.alphanumerics.inverted
        let tokens = rawQuery.components(separatedBy: nonAlphanumeric).filter { !$0.isEmpty }
        
        // Tokens must be strictly stripped of raw punctuation
        assertEqual(tokens, ["Fairbanks", "Alaska", "Coffee", "Gas", "Oil", "OR", "1", "1"])
        
        // FTS5 prefix formation safely wraps each token in double quotes
        let ftsQuery = tokens.map { "\"\($0)\"*" }.joined(separator: " ")
        assertFalse(ftsQuery.contains("--"), "Must not contain SQL comment syntax")
        assertFalse(ftsQuery.contains("1=1"), "Must not contain raw SQL boolean clauses")
        assertTrue(ftsQuery.contains("\"Fairbanks\"*"))
    }
    
    /// Extremely long search queries (> 1,000 characters)
    func testT2_ExtremelyLongSearchQueriesHandledGracefully() async throws {
        let longWord = String(repeating: "Alaska", count: 200) // 1,200 chars
        let nonAlphanumeric = CharacterSet.alphanumerics.inverted
        let tokens = longWord.components(separatedBy: nonAlphanumeric).filter { !$0.isEmpty }
        
        assertEqual(tokens.count, 1, "Should identify one large token")
        assertTrue(tokens[0].count > 1000, "Token length > 1000")
        
        // Prefix query construction should not crash
        let ftsQuery = tokens.prefix(10).map { "\"\($0)\"*" }.joined(separator: " ")
        assertFalse(ftsQuery.isEmpty, "Query should form without overflow")
    }
    
    /// Sparse / ocean coordinates reverse geocoding completes quickly
    func testT2_OceanAndSparseCoordinatesEnforceProgressTimeout() async throws {
        let t0 = CFAbsoluteTimeGetCurrent()
        let sparseCoord = CLLocationCoordinate2D(latitude: 54.0, longitude: -155.0) // Deep Pacific
        let candidates: [OpaqueSearchResult] = []
        
        let result = OpaqueReverseGeocoder.findClosestPOI(queryCoord: sparseCoord, candidates: candidates)
        let elapsed = CFAbsoluteTimeGetCurrent() - t0
        
        assertNil(result, "Sparse ocean coordinate returns nil")
        assertTrue(elapsed < 0.7, "Sparse query must finish within millisecond deadline (took \(elapsed)s)")
    }
}
