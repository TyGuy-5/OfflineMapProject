// TestRunner.swift — E2E Test Suite Runner and Diagnostic Reporter

import Foundation

public enum TestTier: String, CaseIterable, Sendable {
    case tier1 = "Tier 1: Feature Coverage"
    case tier2 = "Tier 2: Boundary & Corner Cases"
    case tier3 = "Tier 3: Pairwise Combinations"
    case tier4 = "Tier 4: Real-World Application Scenarios"
}

public struct TestCaseResult: Sendable {
    public let name: String
    public let tier: TestTier
    public let passed: Bool
    public let durationSeconds: Double
    public let failures: [TestFailure]
}

public typealias TestBlock = () async throws -> Void

public struct TestCaseEntry {
    public let name: String
    public let tier: TestTier
    public let block: TestBlock
    
    public init(name: String, tier: TestTier, block: @escaping TestBlock) {
        self.name = name
        self.tier = tier
        self.block = block
    }
}

public protocol E2ETestSuite {
    var name: String { get }
    var tier: TestTier { get }
    var tests: [TestCaseEntry] { get }
}

public final class E2ETestRegistry: @unchecked Sendable {
    public static let shared = E2ETestRegistry()
    private var suites: [E2ETestSuite] = []
    
    public func register(suite: E2ETestSuite) {
        suites.append(suite)
    }
    
    public func getAllSuites() -> [E2ETestSuite] {
        return suites
    }
}

public final class E2ETestRunner {
    public static func runAll() async -> (allPassed: Bool, totalCount: Int, passedCount: Int, failedCount: Int) {
        print("\n========================================================")
        print("🚀 RUNNING OPALUE-BOX E2E TEST SUITE (TIERS 1 - 4)")
        print("========================================================\n")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        var results: [TestCaseResult] = []
        let suites = E2ETestRegistry.shared.getAllSuites()
        
        for suite in suites {
            print("\n📦 Suite: \(suite.name) [\(suite.tier.rawValue)]")
            for entry in suite.tests {
                TestExecutionContext.shared.reset()
                let t0 = CFAbsoluteTimeGetCurrent()
                var thrownError: Error? = nil
                
                do {
                    try await entry.block()
                } catch {
                    thrownError = error
                }
                
                let t1 = CFAbsoluteTimeGetCurrent()
                var failures = TestExecutionContext.shared.getFailures()
                if let err = thrownError {
                    failures.append(TestFailure(message: "Unhandled error: \(err)", file: #filePath, line: #line))
                }
                
                let passed = failures.isEmpty
                let res = TestCaseResult(name: entry.name, tier: entry.tier, passed: passed, durationSeconds: t1 - t0, failures: failures)
                results.append(res)
                
                if passed {
                    print("  ✅ PASS: \(entry.name) (\(String(format: "%.3f", res.durationSeconds))s)")
                } else {
                    print("  ❌ FAIL: \(entry.name) (\(String(format: "%.3f", res.durationSeconds))s)")
                    for f in failures {
                        print("     ↳ \(f.message) [\(f.file):\(f.line)]")
                    }
                }
            }
        }
        
        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        let totalCount = results.count
        let passedCount = results.filter { $0.passed }.count
        let failedCount = results.filter { !$0.passed }.count
        let allPassed = (failedCount == 0 && totalCount > 0)
        
        print("\n========================================================")
        print("📊 E2E TEST EXECUTION SUMMARY")
        print("========================================================")
        print("Total Duration: \(String(format: "%.3f", totalTime)) seconds")
        print("Total Tests:    \(totalCount)")
        print("Passed:         \(passedCount) ✅")
        print("Failed:         \(failedCount) \(failedCount > 0 ? "❌" : "")")
        
        print("\n--- Breakdown by Tier ---")
        for tier in TestTier.allCases {
            let tierResults = results.filter { $0.tier == tier }
            let tierPassed = tierResults.filter { $0.passed }.count
            let tierFailed = tierResults.filter { !$0.passed }.count
            print("\(tier.rawValue): \(tierPassed)/\(tierResults.count) passed \(tierFailed > 0 ? "(❌ \(tierFailed) failed)" : "✅")")
        }
        print("========================================================\n")
        
        return (allPassed, totalCount, passedCount, failedCount)
    }
}
