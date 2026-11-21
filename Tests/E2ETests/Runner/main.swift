// main.swift — Entry point for standalone E2E CLI Test Runner

import Foundation

// Register Tier 1 Suites
E2ETestRegistry.shared.register(suite: NavigationTelemetryTests())
E2ETestRegistry.shared.register(suite: RouteRestartAudioTests())
E2ETestRegistry.shared.register(suite: GeocodingAndParsingTests())
E2ETestRegistry.shared.register(suite: MapRenderingTests())
E2ETestRegistry.shared.register(suite: SettingsPersistenceTests())

// Register Tier 2 Suites
E2ETestRegistry.shared.register(suite: CoordinateBoundaryTests())
E2ETestRegistry.shared.register(suite: SearchBoundaryTests())
E2ETestRegistry.shared.register(suite: TelemetryBoundaryTests())
E2ETestRegistry.shared.register(suite: SimulationBoundaryTests())
E2ETestRegistry.shared.register(suite: GPSAccuracyBoundaryTests())

// Register Tier 3 Suites
E2ETestRegistry.shared.register(suite: AudioSimulationCombinationsTests())
E2ETestRegistry.shared.register(suite: GeocodingNavigationCombinationsTests())
E2ETestRegistry.shared.register(suite: TelemetryUnitCombinationsTests())

// Register Tier 4 Suites
E2ETestRegistry.shared.register(suite: FairbanksGroceryScenarioTests())
E2ETestRegistry.shared.register(suite: SetbackParkingScenarioTests())
E2ETestRegistry.shared.register(suite: UrbanReverseGeocodeScenarioTests())
E2ETestRegistry.shared.register(suite: GPSDegradationScenarioTests())

Task {
    let (allPassed, total, _, failed) = await E2ETestRunner.runAll()
    if allPassed {
        print("🎉 ALL \(total) TESTS PASSED SUCCESSFULLY across Tiers 1-4!")
        exit(0)
    } else {
        print("💥 TEST RUN COMPLETED WITH \(failed) FAILURES out of \(total) tests.")
        exit(1)
    }
}

dispatchMain()
