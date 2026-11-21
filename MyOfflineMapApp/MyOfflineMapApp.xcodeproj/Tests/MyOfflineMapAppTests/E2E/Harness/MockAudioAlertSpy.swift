import Foundation

/// A spy class tracking audio alert invocations during trail navigation.
/// Captures invocation counts, precise timestamps, alert types, and allows
/// verification of debounce intervals and hysteresis suppression.
public final class MockAudioAlertSpy: @unchecked Sendable {
    
    public struct AlertRecord: Sendable, Equatable {
        public let timestamp: Date
        public let deviationMeters: Double
        public let alertType: String
        
        public init(timestamp: Date = Date(), deviationMeters: Double, alertType: String = "offTrail") {
            self.timestamp = timestamp
            self.deviationMeters = deviationMeters
            self.alertType = alertType
        }
    }
    
    private let lock = NSLock()
    private var _records: [AlertRecord] = []
    private var _isMuted: Bool = false
    
    public init() {}
    
    /// Total number of audio alerts triggered.
    public var alertPlayCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _records.count
    }
    
    /// Most recent alert timestamp.
    public var lastAlertTimestamp: Date? {
        lock.lock()
        defer { lock.unlock() }
        return _records.last?.timestamp
    }
    
    /// All alert records in chronological order.
    public var records: [AlertRecord] {
        lock.lock()
        defer { lock.unlock() }
        return _records
    }
    
    /// Whether audio output is currently muted.
    public var isMuted: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isMuted
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _isMuted = newValue
        }
    }
    
    /// Records an alert event.
    public func recordAlert(deviationMeters: Double = 25.0, alertType: String = "offTrail") {
        lock.lock()
        defer { lock.unlock() }
        guard !_isMuted else { return }
        _records.append(AlertRecord(timestamp: Date(), deviationMeters: deviationMeters, alertType: alertType))
    }
    
    /// Resets all recorded state.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _records.removeAll()
        _isMuted = false
    }
    
    /// Asserts whether all consecutive alerts respected a minimum debounce interval.
    public func verifyDebounceInterval(minIntervalSeconds: TimeInterval) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard _records.count > 1 else { return true }
        for i in 1..<_records.count {
            let diff = _records[i].timestamp.timeIntervalSince(_records[i - 1].timestamp)
            if diff < minIntervalSeconds {
                return false
            }
        }
        return true
    }
}
