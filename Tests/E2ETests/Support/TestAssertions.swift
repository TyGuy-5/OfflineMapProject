// TestAssertions.swift — Opaque-box test assertion engine

import Foundation

public struct TestFailure: Sendable {
    public let message: String
    public let file: String
    public let line: Int
}

public final class TestExecutionContext: @unchecked Sendable {
    public static let shared = TestExecutionContext()
    private let lock = NSLock()
    private var failures: [TestFailure] = []
    
    public func recordFailure(_ message: String, file: String, line: Int) {
        lock.lock()
        defer { lock.unlock() }
        failures.append(TestFailure(message: message, file: file, line: line))
    }
    
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        failures.removeAll()
    }
    
    public func getFailures() -> [TestFailure] {
        lock.lock()
        defer { lock.unlock() }
        return failures
    }
}

public func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #filePath, line: Int = #line) {
    if actual != expected {
        let msg = message.isEmpty ? "Expected '\(expected)' but got '\(actual)'" : "\(message) (Expected '\(expected)', got '\(actual)')"
        TestExecutionContext.shared.recordFailure(msg, file: file, line: line)
    }
}

public func assertNotEqual<T: Equatable>(_ actual: T, _ unexpected: T, _ message: String = "", file: String = #filePath, line: Int = #line) {
    if actual == unexpected {
        let msg = message.isEmpty ? "Did not expect '\(unexpected)'" : "\(message) (Did not expect '\(unexpected)')"
        TestExecutionContext.shared.recordFailure(msg, file: file, line: line)
    }
}

public func assertTrue(_ condition: Bool, _ message: String = "Expected condition to be true", file: String = #filePath, line: Int = #line) {
    if !condition {
        TestExecutionContext.shared.recordFailure(message, file: file, line: line)
    }
}

public func assertFalse(_ condition: Bool, _ message: String = "Expected condition to be false", file: String = #filePath, line: Int = #line) {
    if condition {
        TestExecutionContext.shared.recordFailure(message, file: file, line: line)
    }
}

public func assertNil(_ value: Any?, _ message: String = "Expected value to be nil", file: String = #filePath, line: Int = #line) {
    if value != nil {
        TestExecutionContext.shared.recordFailure("\(message) (got \(String(describing: value)))", file: file, line: line)
    }
}

public func assertNotNil(_ value: Any?, _ message: String = "Expected value to not be nil", file: String = #filePath, line: Int = #line) {
    if value == nil {
        TestExecutionContext.shared.recordFailure(message, file: file, line: line)
    }
}

public func assertInDelta(_ actual: Double, _ expected: Double, delta: Double, _ message: String = "", file: String = #filePath, line: Int = #line) {
    let diff = abs(actual - expected)
    if diff > delta {
        let msg = message.isEmpty ? "Value \(actual) is not within \(delta) of \(expected) (diff: \(diff))" : "\(message) (\(actual) vs \(expected), diff: \(diff) > \(delta))"
        TestExecutionContext.shared.recordFailure(msg, file: file, line: line)
    }
}

public func assertGreaterThan(_ actual: Double, _ threshold: Double, _ message: String = "", file: String = #filePath, line: Int = #line) {
    if actual <= threshold {
        let msg = message.isEmpty ? "Expected \(actual) > \(threshold)" : "\(message) (\(actual) <= \(threshold))"
        TestExecutionContext.shared.recordFailure(msg, file: file, line: line)
    }
}

public func assertLessThan(_ actual: Double, _ threshold: Double, _ message: String = "", file: String = #filePath, line: Int = #line) {
    if actual >= threshold {
        let msg = message.isEmpty ? "Expected \(actual) < \(threshold)" : "\(message) (\(actual) >= \(threshold))"
        TestExecutionContext.shared.recordFailure(msg, file: file, line: line)
    }
}

public func fail(_ message: String, file: String = #filePath, line: Int = #line) {
    TestExecutionContext.shared.recordFailure(message, file: file, line: line)
}
