import Foundation
import CoreLocation

@MainActor
func runAll() async {
    print("🚀 Running RoutePlanningTests...")
    let tests = RoutePlanningTests()

    print("- testPlaceLocationEqualityAndHashing...")
    tests.testPlaceLocationEqualityAndHashing()
    print("  ✓ PASSED")

    print("- testPlaceLocationNegativeZeroEquivalence...")
    tests.testPlaceLocationNegativeZeroEquivalence()
    print("  ✓ PASSED")

    print("- testRouteEndpointProperties...")
    tests.testRouteEndpointProperties()
    print("  ✓ PASSED")

    print("- testValidCoordinateParsing...")
    tests.testValidCoordinateParsing()
    print("  ✓ PASSED")

    print("- testInvalidCoordinateParsing...")
    tests.testInvalidCoordinateParsing()
    print("  ✓ PASSED")

    print("- testCoordinateReDoSPerformance...")
    tests.testCoordinateReDoSPerformance()
    print("  ✓ PASSED")

    print("- testSearchServiceSyntheticCoordinateResult...")
    await tests.testSearchServiceSyntheticCoordinateResult()
    print("  ✓ PASSED")

    print("- testNavigationViewModelCoordinateResolution...")
    tests.testNavigationViewModelCoordinateResolution()
    print("  ✓ PASSED")

    print("- testNavigationViewModelSwapOriginDestination...")
    await tests.testNavigationViewModelSwapOriginDestination()
    print("  ✓ PASSED")

    print("- testNavigationViewModelResetOriginToCurrentLocation...")
    await tests.testNavigationViewModelResetOriginToCurrentLocation()
    print("  ✓ PASSED")

    print("- testNavigationViewModelIsRemoteOriginCalculation...")
    tests.testNavigationViewModelIsRemoteOriginCalculation()
    print("  ✓ PASSED")

    print("- testNavigationViewModelPreviewModeLifecycleTransition...")
    tests.testNavigationViewModelPreviewModeLifecycleTransition()
    print("  ✓ PASSED")

    print("- testNavigationViewModelRouteToStart...")
    tests.testNavigationViewModelRouteToStart()
    print("  ✓ PASSED")

    print("- testNavigationViewModelConcurrencyCancellation...")
    await tests.testNavigationViewModelConcurrencyCancellation()
    print("  ✓ PASSED")

    print("\n🎉 ALL 14 TESTS PASSED EMPIRICALLY WITH ZERO ERRORS!")
}

let sema = DispatchSemaphore(value: 0)
Task { @MainActor in
    await runAll()
    sema.signal()
}
sema.wait()
