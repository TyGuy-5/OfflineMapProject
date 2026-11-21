// GPSAccuracyBoundaryTests.swift — Tier 2 Boundary Cases: GPS Signal Degradation & Lifecycle

import Foundation
import CoreLocation

public final class GPSAccuracyBoundaryTests: E2ETestSuite {
    public let name = "GPS Accuracy & Signal Degradation Boundary Suite"
    public let tier = TestTier.tier2
    
    public var tests: [TestCaseEntry] {
        return [
            TestCaseEntry(name: "testT2_ExactBoundaryAccuracySixtyFiveMetersTriggersDegradation", tier: tier, block: testT2_ExactBoundaryAccuracySixtyFiveMetersTriggersDegradation),
            TestCaseEntry(name: "testT2_SubThresholdAccuracySixtyFourPointNineMetersRetainsSpeed", tier: tier, block: testT2_SubThresholdAccuracySixtyFourPointNineMetersRetainsSpeed),
            TestCaseEntry(name: "testT2_NegativeHorizontalAccuracyTreatedAsDegraded", tier: tier, block: testT2_NegativeHorizontalAccuracyTreatedAsDegraded),
            TestCaseEntry(name: "testT2_StaleCachedLaunchFixesDiscardedWithoutFalseLowGPSWarning", tier: tier, block: testT2_StaleCachedLaunchFixesDiscardedWithoutFalseLowGPSWarning),
            TestCaseEntry(name: "testT2_RapidAccuracyOscillationsRecoverSpeedometerSmoothly", tier: tier, block: testT2_RapidAccuracyOscillationsRecoverSpeedometerSmoothly)
        ]
    }
    
    /// Exact threshold accuracy (horizontalAccuracy = 65.0) triggers degraded state
    func testT2_ExactBoundaryAccuracySixtyFiveMetersTriggersDegradation() async throws {
        let observer = OpaqueLocationObserver()
        observer.processLocationFix(horizontalAccuracy: 65.0, rawSpeedMps: 20.0, ageSeconds: 1.0)
        
        assertTrue(observer.isGpsSignalLow, "Accuracy == 65.0 must flag low GPS signal")
        assertEqual(observer.smoothedSpeedMph, 0, "Speedometer must be zeroed at exactly 65.0m accuracy")
        assertTrue(observer.isStationary, "Must be stationary at 65.0m accuracy")
    }
    
    /// Sub-threshold accuracy (horizontalAccuracy = 64.9) retains valid speedometer
    func testT2_SubThresholdAccuracySixtyFourPointNineMetersRetainsSpeed() async throws {
        let observer = OpaqueLocationObserver()
        observer.processLocationFix(horizontalAccuracy: 64.9, rawSpeedMps: 15.0, ageSeconds: 1.0)
        
        assertFalse(observer.isGpsSignalLow, "Accuracy < 65.0 should not flag low GPS")
        assertTrue(observer.smoothedSpeedMph > 30, "Speedometer should report positive speed (~33 mph)")
        assertFalse(observer.isStationary, "Vehicle should not be stationary")
    }
    
    /// Negative horizontal accuracy (-1.0, uncalibrated) triggers degraded state
    func testT2_NegativeHorizontalAccuracyTreatedAsDegraded() async throws {
        let observer = OpaqueLocationObserver()
        observer.processLocationFix(horizontalAccuracy: -1.0, rawSpeedMps: 25.0, ageSeconds: 0.5)
        
        assertTrue(observer.isGpsSignalLow, "Negative accuracy must trigger low GPS flag")
        assertEqual(observer.smoothedSpeedMph, 0, "Negative accuracy must zero speed")
        assertTrue(observer.isStationary, "Must set stationary state on negative accuracy")
    }
    
    /// Stale cached fixes (> 15 seconds old) discarded without false low GPS warning
    func testT2_StaleCachedLaunchFixesDiscardedWithoutFalseLowGPSWarning() async throws {
        let observer = OpaqueLocationObserver()
        // Feed a fix that is 25 seconds old
        observer.processLocationFix(horizontalAccuracy: 5.0, rawSpeedMps: 0.0, ageSeconds: 25.0)
        
        assertFalse(observer.isGpsSignalLow, "Stale fix must be ignored without triggering false low GPS warning")
    }
    
    /// Rapid accuracy oscillations (good -> bad -> good -> bad)
    func testT2_RapidAccuracyOscillationsRecoverSpeedometerSmoothly() async throws {
        let observer = OpaqueLocationObserver()
        
        // 1. Good GPS
        observer.processLocationFix(horizontalAccuracy: 8.0, rawSpeedMps: 20.0, ageSeconds: 1.0)
        assertFalse(observer.isGpsSignalLow)
        assertTrue(observer.smoothedSpeedMph > 40)
        
        // 2. Degraded GPS (entering tunnel)
        observer.processLocationFix(horizontalAccuracy: 95.0, rawSpeedMps: 20.0, ageSeconds: 1.0)
        assertTrue(observer.isGpsSignalLow)
        assertEqual(observer.smoothedSpeedMph, 0)
        
        // 3. Exiting tunnel, regaining good GPS
        observer.processLocationFix(horizontalAccuracy: 6.0, rawSpeedMps: 20.0, ageSeconds: 1.0)
        assertFalse(observer.isGpsSignalLow)
        assertTrue(observer.smoothedSpeedMph > 40, "Speedometer must restore upon signal recovery")
        assertFalse(observer.isStationary)
    }
}
