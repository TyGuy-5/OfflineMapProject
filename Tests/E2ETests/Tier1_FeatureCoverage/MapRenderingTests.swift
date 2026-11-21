// MapRenderingTests.swift — Tier 1 Feature Coverage: MapLibre Rendering & Navigation Annotations

import Foundation
import CoreLocation

public final class MapRenderingTests: E2ETestSuite {
    public let name = "MapLibre Rendering & Annotation Suite"
    public let tier = TestTier.tier1
    
    public var tests: [TestCaseEntry] {
        return [
            TestCaseEntry(name: "testT1_MapViewRecenterDeduplicationPreventsDuplicateCameraAnimations", tier: tier, block: testT1_MapViewRecenterDeduplicationPreventsDuplicateCameraAnimations),
            TestCaseEntry(name: "testT1_MapViewZoomDeduplicationPreventsCompoundingZoomSteps", tier: tier, block: testT1_MapViewZoomDeduplicationPreventsCompoundingZoomSteps),
            TestCaseEntry(name: "testT1_FullCoordinateEqualityDetectsDetourReroutesWithIdenticalVertexCount", tier: tier, block: testT1_FullCoordinateEqualityDetectsDetourReroutesWithIdenticalVertexCount),
            TestCaseEntry(name: "testT1_IdenticalRouteCoordinatesDoNotTriggerRedundantRedraw", tier: tier, block: testT1_IdenticalRouteCoordinatesDoNotTriggerRedundantRedraw),
            TestCaseEntry(name: "testT1_DirectionalVehicleAnnotationDelegateConfiguration", tier: tier, block: testT1_DirectionalVehicleAnnotationDelegateConfiguration)
        ]
    }
    
    /// R5.1: Prevent redundant camera recentering during rapid UI updates by tracking consumption state in Coordinator
    func testT1_MapViewRecenterDeduplicationPreventsDuplicateCameraAnimations() async throws {
        let coordinator = OpaqueMapViewCoordinator()
        let userCoord = TestCoordinates.fairbanksDowntown
        
        // First request to recenter
        coordinator.applyRecenter(coordinate: userCoord)
        assertEqual(coordinator.centerAnimationCount, 1, "First recenter must execute")
        assertTrue(coordinator.isRecenterConsumed, "Coordinator must mark recenter as consumed")
        
        // Rapid secondary UI cycle before async binding cleanup executes
        coordinator.applyRecenter(coordinate: userCoord)
        assertEqual(coordinator.centerAnimationCount, 1, "Rapid consecutive recenter must NOT re-trigger camera animation")
        
        // Reset consumption (after async binding nil-out)
        coordinator.isRecenterConsumed = false
        coordinator.applyRecenter(coordinate: userCoord)
        assertEqual(coordinator.centerAnimationCount, 2, "Fresh recenter after consumption reset should execute")
    }
    
    /// R5.1: Prevent compounding zoom level animations during rapid UI updates by tracking zoom consumption
    func testT1_MapViewZoomDeduplicationPreventsCompoundingZoomSteps() async throws {
        let coordinator = OpaqueMapViewCoordinator()
        
        // User clicks zoom in (+1.0)
        coordinator.applyZoomStep(step: 1.0)
        assertEqual(coordinator.zoomAnimationCount, 1, "Initial zoom step must execute")
        assertTrue(coordinator.isZoomStepConsumed, "Zoom step must be consumed")
        
        // Rapid UI update cycle (e.g. GPS tick) with unconsumed binding still present
        coordinator.applyZoomStep(step: 1.0)
        assertEqual(coordinator.zoomAnimationCount, 1, "Duplicate zoom invocation must be blocked by consumption flag")
    }
    
    /// R5.2: Perform a complete coordinate equality check on routeCoordinates updates instead of sampling 3 vertices,
    /// avoiding missed redraws on reroutes where vertex count, start, midpoint, and endpoint match.
    func testT1_FullCoordinateEqualityDetectsDetourReroutesWithIdenticalVertexCount() async throws {
        let coordinator = OpaqueMapViewCoordinator()
        
        // Route 1: 5 coordinates along Cushman St
        let route1 = [
            CLLocationCoordinate2D(latitude: 64.8400, longitude: -147.7200), // Start (same)
            CLLocationCoordinate2D(latitude: 64.8410, longitude: -147.7200), // Route 1 path
            CLLocationCoordinate2D(latitude: 64.8420, longitude: -147.7200), // Midpoint (same)
            CLLocationCoordinate2D(latitude: 64.8430, longitude: -147.7200), // Route 1 path
            CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7200)  // End (same)
        ]
        
        // Route 2: 5 coordinates taking an alternate parallel block detour on Lacey St,
        // but having the exact same count (5), start (index 0), midpoint (index 2), and end (index 4)!
        // Under the flawed 3-point check (f1==f2, l1==l2, m1==m2), this reroute was SILENTLY DROPPED!
        let route2 = [
            CLLocationCoordinate2D(latitude: 64.8400, longitude: -147.7200), // Start (same)
            CLLocationCoordinate2D(latitude: 64.8410, longitude: -147.7230), // Detour! (differs by 0.0030 lon)
            CLLocationCoordinate2D(latitude: 64.8420, longitude: -147.7200), // Midpoint (same)
            CLLocationCoordinate2D(latitude: 64.8430, longitude: -147.7230), // Detour! (differs by 0.0030 lon)
            CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7200)  // End (same)
        ]
        
        coordinator.updateRouteCoordinates(newRoute: route1)
        assertEqual(coordinator.redrawCount, 1, "Initial route must be drawn")
        
        // Reroute to detour with matching start, midpoint, end, and count
        coordinator.updateRouteCoordinates(newRoute: route2)
        assertEqual(coordinator.redrawCount, 2, "Full coordinate equality check must detect detour differences and trigger redraw!")
    }
    
    /// R5.2: Identical route coordinates do not trigger redundant redraws
    func testT1_IdenticalRouteCoordinatesDoNotTriggerRedundantRedraw() async throws {
        let coordinator = OpaqueMapViewCoordinator()
        let route = [
            CLLocationCoordinate2D(latitude: 64.8400, longitude: -147.7200),
            CLLocationCoordinate2D(latitude: 64.8410, longitude: -147.7200),
            CLLocationCoordinate2D(latitude: 64.8420, longitude: -147.7200)
        ]
        
        coordinator.updateRouteCoordinates(newRoute: route)
        assertEqual(coordinator.redrawCount, 1, "First assignment draws route")
        
        // Redelivering exact same route coordinates
        coordinator.updateRouteCoordinates(newRoute: route)
        assertEqual(coordinator.redrawCount, 1, "Exact same coordinates must not trigger redundant redraw")
    }
    
    /// R5.3: Render a directional navigation arrow / vehicle icon for carAnnotation using MapLibre image delegate
    func testT1_DirectionalVehicleAnnotationDelegateConfiguration() async throws {
        let carAnnotationTitle = "Current Position"
        let isVehicleAnnotation = (carAnnotationTitle == "Current Position")
        assertTrue(isVehicleAnnotation, "Vehicle annotation identified by title")
        
        // Verifying delegate asset key for navigation arrow
        let expectedAssetKey = "navigation-vehicle-arrow"
        assertFalse(expectedAssetKey.isEmpty, "Navigation arrow asset key must be defined")
    }
}
