// main.swift — Standalone Empirical Stress Test Runner for NavigationViewModel

import Foundation
import CoreLocation
import Combine
import SwiftUI

@main
struct StressRunner {
    static let RED = "\u{001B}[31m"
    static let GREEN = "\u{001B}[32m"
    static let YELLOW = "\u{001B}[33m"
    static let BLUE = "\u{001B}[34m"
    static let CYAN = "\u{001B}[36m"
    static let BOLD = "\u{001B}[1m"
    static let RESET = "\u{001B}[0m"

    static var testsRun = 0
    static var testsPassed = 0
    static var testsFailed = 0

    static func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        if !condition() {
            print("  \(RED)❌ FAIL [line \(line)]: \(message)\(RESET)")
            testsFailed += 1
            fatalError("Assertion failed: \(message) at line \(line)")
        }
    }

    static func assertFalse(_ condition: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        assertTrue(!condition(), message, file: file, line: line)
    }

    static func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        assertTrue(a == b, "\(message) — Expected [\(b)], got [\(a)]", file: file, line: line)
    }

    static func assertNil<T>(_ a: T?, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        assertTrue(a == nil, "\(message) — Expected nil, got [\(String(describing: a))]", file: file, line: line)
    }

    static func assertNotNil<T>(_ a: T?, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        assertTrue(a != nil, "\(message) — Expected non-nil", file: file, line: line)
    }

    static func runTest(_ name: String, _ block: () throws -> Void) {
        testsRun += 1
        do {
            try block()
            testsPassed += 1
            print("  \(GREEN)✅ PASS: \(name)\(RESET)")
        } catch {
            testsFailed += 1
            print("  \(RED)❌ FAIL: \(name) with error: \(error)\(RESET)")
        }
    }

    static func runAsyncTest(_ name: String, _ block: () async throws -> Void) async {
        testsRun += 1
        do {
            try await block()
            testsPassed += 1
            print("  \(GREEN)✅ PASS: \(name)\(RESET)")
        } catch {
            testsFailed += 1
            print("  \(RED)❌ FAIL: \(name) with error: \(error)\(RESET)")
        }
    }

    @MainActor
    static func main() async {
        print("\(BOLD)\(CYAN)========================================================\(RESET)")
        print("\(BOLD)\(CYAN)🚀 EMPIRICAL STRESS TEST RUNNER: NavigationViewModel (R6.1/R6.2)\(RESET)")
        print("\(BOLD)\(CYAN)========================================================\(RESET)")

        // ====================================================
        // Suite 1: Direct RemediationTests Refactored Suites
        // ====================================================
        print("\n\(BOLD)📦 Suite 1: Direct RemediationTests.swift Refactored Unit Tests\(RESET)")

        runTest("test01_OutOfRegionGPSHandling") {
            let vm = NavigationViewModel()
            let validAlaskaCoordinates = [
                CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215), // Fairbanks
                CLLocationCoordinate2D(latitude: 61.2181, longitude: -149.9003), // Anchorage
                CLLocationCoordinate2D(latitude: 58.3019, longitude: -134.4197), // Juneau
                CLLocationCoordinate2D(latitude: 71.2906, longitude: -156.7887), // Utqiagvik
                CLLocationCoordinate2D(latitude: 51.0, longitude: -179.0),       // SW
                CLLocationCoordinate2D(latitude: 72.0, longitude: -129.0)        // NE
            ]
            for coord in validAlaskaCoordinates {
                assertTrue(vm.isWithinSupportedRegion(coord))
            }
            let outOfRegionCoordinates = [
                CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321),
                CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
                CLLocationCoordinate2D(latitude: 21.3069, longitude: -157.8583),
                CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278),
                CLLocationCoordinate2D(latitude: 35.6762, longitude: 139.6503),
                CLLocationCoordinate2D(latitude: 50.999, longitude: -147.0),
                CLLocationCoordinate2D(latitude: 72.001, longitude: -147.0),
                CLLocationCoordinate2D(latitude: 64.0, longitude: -179.001),
                CLLocationCoordinate2D(latitude: 64.0, longitude: -128.999)
            ]
            for coord in outOfRegionCoordinates {
                assertFalse(vm.isWithinSupportedRegion(coord))
            }
            assertEqual(NavigationViewModel.defaultAlaskaCoordinate.latitude, 64.8436)
            assertEqual(NavigationViewModel.defaultAlaskaCoordinate.longitude, -147.7215)
            assertEqual(vm.effectiveUserCoordinate.latitude, NavigationViewModel.defaultAlaskaCoordinate.latitude)
            assertEqual(vm.effectiveUserCoordinate.longitude, NavigationViewModel.defaultAlaskaCoordinate.longitude)

            let simCoord = CLLocationCoordinate2D(latitude: 61.2181, longitude: -149.9003)
            vm.simulatedUserCoordinate = simCoord
            assertEqual(vm.effectiveUserCoordinate.latitude, simCoord.latitude)
            assertEqual(vm.effectiveUserCoordinate.longitude, simCoord.longitude)
            vm.simulatedUserCoordinate = nil
        }

        await runAsyncTest("test02_InFlightSearchTaskCancellation") {
            let vm = NavigationViewModel()
            vm.handleQueryChange("Fairbanks")
            assertTrue(vm.isSearching)
            assertNotNil(vm.searchTask)
            assertEqual(vm.appMode, .searchList)
            let task1 = vm.searchTask
            vm.dismissSearch()
            assertTrue(task1?.isCancelled ?? false)
            assertNil(vm.searchTask)
            assertFalse(vm.isSearching)
            assertEqual(vm.appMode, .explore)

            vm.handleQueryChange("Anchorage")
            assertTrue(vm.isSearching)
            let task2 = vm.searchTask
            vm.clearSearch()
            assertTrue(task2?.isCancelled ?? false)
            assertNil(vm.searchTask)
            assertEqual(vm.destinationText, "")
            assertTrue(vm.searchResults.isEmpty)
            assertEqual(vm.appMode, .explore)

            vm.handleQueryChange("Juneau")
            assertTrue(vm.isSearching)
            let task3 = vm.searchTask
            vm.resetToExplore()
            assertTrue(task3?.isCancelled ?? false)
            assertNil(vm.searchTask)
            assertEqual(vm.appMode, .explore)

            vm.handleQueryChange("Fair")
            let priorTask = vm.searchTask
            vm.handleQueryChange("Fairbanks")
            assertTrue(priorTask?.isCancelled ?? false)
            vm.dismissSearch()
        }

        runTest("test03_CategorySearchSingleInvocation") {
            let vm = NavigationViewModel()
            assertFalse(vm.isProgrammaticTextChange)

            vm.searchCategory("Gas")
            assertEqual(vm.destinationText, "Gas")
            assertTrue(vm.isProgrammaticTextChange)

            vm.isProgrammaticTextChange = false
            vm.searchCategory("Gas")
            assertFalse(vm.isProgrammaticTextChange)

            vm.searchCategory("Coffee")
            assertEqual(vm.destinationText, "Coffee")
            assertTrue(vm.isProgrammaticTextChange)

            vm.isProgrammaticTextChange = false
            let place = SearchResult(id: 10, name: "Mocha Dan's", lat: 64.85, lon: -147.8)
            vm.selectPlace(place)
            assertEqual(vm.destinationText, "Mocha Dan's")
            assertTrue(vm.isProgrammaticTextChange)
            assertEqual(vm.appMode, .placeDetail)
            vm.dismissSearch()
        }

        runTest("test04_RouteTelemetryCalculationZeroStepsSafety") {
            let vm = NavigationViewModel()
            let coord1 = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
            let coord2 = CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7210)
            let coord3 = CLLocationCoordinate2D(latitude: 64.8445, longitude: -147.7205)

            let detailsWithZeroSteps = RouteDetails(
                coordinates: [coord1, coord2, coord3],
                totalDistanceMiles: 0.15,
                totalDurationSeconds: 45,
                steps: [],
                costing: "auto"
            )
            vm.routeDetails = detailsWithZeroSteps
            vm.updateNavigationTelemetry(at: coord1, coordIndex: 0, in: detailsWithZeroSteps)
            assertEqual(vm.remainingStepDistanceMiles, 0.0)

            let step = NavigationStep(
                instruction: "Drive north",
                distanceMiles: 0.15,
                durationSeconds: 45,
                maneuverType: 1,
                streetName: "Cushman St",
                startIndex: 0,
                endIndex: 2
            )
            let detailsWithSteps = RouteDetails(
                coordinates: [coord1, coord2, coord3],
                totalDistanceMiles: 0.15,
                totalDurationSeconds: 45,
                steps: [step],
                costing: "auto"
            )
            vm.routeDetails = detailsWithSteps
            vm.updateNavigationTelemetry(at: coord1, coordIndex: 0, in: detailsWithSteps)
            assertTrue(vm.remainingStepDistanceMiles > 0.0)
        }

        runTest("test05_DistanceUnitTogglingPreservesSimulationProgress") {
            let vm = NavigationViewModel()
            vm.useMetric = false
            assertEqual(vm.speedUnit, "mph")
            assertEqual(vm.altitudeUnit, "ft")

            let p1 = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
            let p2 = CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7210)
            let p3 = CLLocationCoordinate2D(latitude: 64.8445, longitude: -147.7205)
            let step1 = NavigationStep(instruction: "Go north", distanceMiles: 0.1, durationSeconds: 30, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 1)
            let step2 = NavigationStep(instruction: "Turn right", distanceMiles: 0.1, durationSeconds: 30, maneuverType: 2, streetName: nil, startIndex: 1, endIndex: 2)
            let route = RouteDetails(coordinates: [p1, p2, p3], totalDistanceMiles: 0.2, totalDurationSeconds: 60, steps: [step1, step2], costing: "auto")

            vm.routeDetails = route
            vm.routeCoordinates = [p1, p2, p3]
            vm.isNavigating = true
            vm.isSimulating = true
            vm.currentCoordIndex = 1
            vm.currentStepIndex = 1
            vm.simulatedSpeedMph = 45

            vm.useMetric = true
            assertTrue(vm.isNavigating)
            assertTrue(vm.isSimulating)
            assertEqual(vm.currentCoordIndex, 1)
            assertEqual(vm.currentStepIndex, 1)
            assertEqual(vm.speedUnit, "km/h")
            assertEqual(vm.altitudeUnit, "m")
            assertEqual(vm.displaySpeed, 72)
            vm.endNavigation()
        }

        runTest("test18_SimulationStepProgressionBoundsSafety") {
            let vm = NavigationViewModel()
            let coord1 = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
            let coord2 = CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7210)
            let coord3 = CLLocationCoordinate2D(latitude: 64.8445, longitude: -147.7205)

            let zeroStepsRoute = RouteDetails(coordinates: [coord1, coord2, coord3], totalDistanceMiles: 0.15, totalDurationSeconds: 45, steps: [], costing: "auto")
            vm.routeDetails = zeroStepsRoute
            vm.isNavigating = true
            vm.isSimulating = true
            vm.currentCoordIndex = 0
            vm.currentStepIndex = 0

            vm.advanceSimulationStep()
            assertEqual(vm.currentStepIndex, 0)

            let malformedStep1 = NavigationStep(instruction: "Drive north", distanceMiles: 0.1, durationSeconds: 20, maneuverType: 1, streetName: "Cushman", startIndex: -5, endIndex: 1)
            let malformedStep2 = NavigationStep(instruction: "Turn right", distanceMiles: 0.05, durationSeconds: 25, maneuverType: 2, streetName: "1st Ave", startIndex: -2, endIndex: 2)
            let malformedRoute = RouteDetails(coordinates: [coord1, coord2, coord3], totalDistanceMiles: 0.15, totalDurationSeconds: 45, steps: [malformedStep1, malformedStep2], costing: "auto")
            vm.routeDetails = malformedRoute
            vm.currentCoordIndex = 0
            vm.currentStepIndex = 0

            vm.advanceSimulationStep()
            assertTrue(vm.currentCoordIndex >= 0)
            vm.endNavigation()
        }

        runTest("test19_TelemetryOutOfBoundsEdgeCases") {
            let vm = NavigationViewModel()
            let coord1 = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
            let coord2 = CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7210)
            let coord3 = CLLocationCoordinate2D(latitude: 64.8445, longitude: -147.7205)

            let negativeEndStep = NavigationStep(instruction: "Proceed", distanceMiles: 0.1, durationSeconds: 20, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: -5)
            let routeWithNegativeEnd = RouteDetails(coordinates: [coord1, coord2, coord3], totalDistanceMiles: 0.15, totalDurationSeconds: 45, steps: [negativeEndStep], costing: "auto")
            vm.routeDetails = routeWithNegativeEnd

            vm.updateNavigationTelemetry(at: coord1, coordIndex: 0, in: routeWithNegativeEnd)
            assertEqual(vm.remainingStepDistanceMiles, 0.0)

            let oversizedEndStep = NavigationStep(instruction: "Proceed", distanceMiles: 0.1, durationSeconds: 20, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 9999)
            let routeWithOversizedEnd = RouteDetails(coordinates: [coord1, coord2, coord3], totalDistanceMiles: 0.15, totalDurationSeconds: 45, steps: [oversizedEndStep], costing: "auto")
            vm.routeDetails = routeWithOversizedEnd
            vm.updateNavigationTelemetry(at: coord1, coordIndex: 1, in: routeWithOversizedEnd)
            assertTrue(vm.remainingStepDistanceMiles >= 0.0)
        }

        // ====================================================
        // Suite 2: R2.1–R2.5 Behavioral Implementation Tests
        // ====================================================
        print("\n\(BOLD)📦 Suite 2: R2.1–R2.5 Telemetry and Progression Tests (test22-test27)\(RESET)")

        runTest("test22_NavigationViewModelStartNavigationHardwareGPSRetention") {
            let lm = LocationManager()
            let vm = NavigationViewModel(locationManager: lm)
            let coords = [
                CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215),
                CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7210)
            ]
            let details = RouteDetails(
                coordinates: coords,
                totalDistanceMiles: 0.1,
                totalDurationSeconds: 30,
                steps: [NavigationStep(instruction: "Go", distanceMiles: 0.1, durationSeconds: 30, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 1)],
                costing: "auto"
            )
            vm.routeDetails = details
            vm.routeCoordinates = coords

            // 1. Fresh, accurate, in-region hardware fix:
            let hardwareFix = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 64.8438, longitude: -147.7212),
                altitude: 100,
                horizontalAccuracy: 10.0,
                verticalAccuracy: 5.0,
                course: 45.0,
                speed: 5.0,
                timestamp: Date()
            )
            lm.setMockLocation(hardwareFix)
            vm.startNavigation()
            assertEqual(vm.simulatedUserCoordinate?.latitude ?? 0, 64.8438)
            vm.endNavigation()

            // 2. Degraded fix (accuracy >= 65m):
            let degradedFix = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 64.8438, longitude: -147.7212),
                altitude: 100,
                horizontalAccuracy: 75.0,
                verticalAccuracy: 5.0,
                course: 45.0,
                speed: 5.0,
                timestamp: Date()
            )
            lm.setMockLocation(degradedFix)
            vm.routeDetails = details
            vm.routeCoordinates = coords
            vm.startNavigation()
            assertEqual(vm.simulatedUserCoordinate?.latitude ?? 0, coords.first!.latitude)
            vm.endNavigation()
        }

        runTest("test23_NavigationViewModelAdvanceSimulationStepMultiSpeedLoop") {
            let vm = NavigationViewModel()
            var coords: [CLLocationCoordinate2D] = []
            for i in 0..<20 {
                coords.append(CLLocationCoordinate2D(latitude: 64.84 + Double(i) * 0.001, longitude: -147.72))
            }
            let step0 = NavigationStep(instruction: "Step 0", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 2)
            let step1 = NavigationStep(instruction: "Step 1", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 1, streetName: nil, startIndex: 2, endIndex: 4)
            let step2 = NavigationStep(instruction: "Step 2", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 1, streetName: nil, startIndex: 4, endIndex: 6)
            let step3 = NavigationStep(instruction: "Step 3", distanceMiles: 0.5, durationSeconds: 50, maneuverType: 1, streetName: nil, startIndex: 6, endIndex: 19)

            let details = RouteDetails(coordinates: coords, totalDistanceMiles: 0.8, totalDurationSeconds: 80, steps: [step0, step1, step2, step3], costing: "auto")
            vm.routeDetails = details
            vm.routeCoordinates = coords
            vm.isNavigating = true
            vm.isSimulating = true
            vm.currentCoordIndex = 0
            vm.currentStepIndex = 0
            vm.simulationSpeedMultiplier = 5.0

            vm.advanceSimulationStep()
            assertEqual(vm.currentCoordIndex, 5)
            assertEqual(vm.currentStepIndex, 2)
            vm.endNavigation()
        }

        runTest("test24_NavigationViewModelSwitchbackSearchClamping") {
            let vm = NavigationViewModel()
            var coords: [CLLocationCoordinate2D] = []
            for i in 0...3 {
                coords.append(CLLocationCoordinate2D(latitude: 64.84 + Double(i) * 0.001, longitude: -147.7200))
            }
            for i in 4...7 {
                coords.append(CLLocationCoordinate2D(latitude: 64.843 - Double(i - 4) * 0.001, longitude: -147.7198))
            }
            let step1 = NavigationStep(instruction: "Go north", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 1, streetName: "North Way", startIndex: 0, endIndex: 3)
            let step2 = NavigationStep(instruction: "Hairpin turn south", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 2, streetName: "South Way", startIndex: 3, endIndex: 7)

            let details = RouteDetails(coordinates: coords, totalDistanceMiles: 0.4, totalDurationSeconds: 40, steps: [step1, step2], costing: "auto")
            vm.routeDetails = details
            vm.routeCoordinates = coords
            vm.isNavigating = true
            vm.currentStepIndex = 0
            vm.currentCoordIndex = 1

            let userPos = CLLocationCoordinate2D(latitude: 64.8410, longitude: -147.7200)
            vm.updateCurrentStepForLiveLocation(userPos, in: details)

            assertEqual(vm.currentStepIndex, 0)
            assertTrue(vm.currentCoordIndex <= 5)
            vm.endNavigation()
        }

        runTest("test25_NavigationViewModelMonotonicTelemetryCountdownAndZeroing") {
            let vm = NavigationViewModel()
            let p0 = CLLocationCoordinate2D(latitude: 64.8400, longitude: -147.7200)
            let p1 = CLLocationCoordinate2D(latitude: 64.8410, longitude: -147.7200)
            let p2 = CLLocationCoordinate2D(latitude: 64.8420, longitude: -147.7200)
            let p3 = CLLocationCoordinate2D(latitude: 64.8430, longitude: -147.7200)
            let coords = [p0, p1, p2, p3]

            let step = NavigationStep(instruction: "Straight", distanceMiles: 0.3, durationSeconds: 30, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 2)
            let details = RouteDetails(coordinates: coords, totalDistanceMiles: 0.3, totalDurationSeconds: 30, steps: [step], costing: "auto")

            vm.routeDetails = details
            vm.currentStepIndex = 0

            vm.updateNavigationTelemetry(at: p0, coordIndex: 0, in: details)
            let dist0 = vm.remainingStepDistanceMiles
            assertTrue(dist0 > 0.0)

            vm.updateNavigationTelemetry(at: p1, coordIndex: 1, in: details)
            let dist1 = vm.remainingStepDistanceMiles
            assertTrue(dist1 < dist0)

            vm.updateNavigationTelemetry(at: p2, coordIndex: 2, in: details)
            assertEqual(vm.remainingStepDistanceMiles, 0.0)

            vm.updateNavigationTelemetry(at: p3, coordIndex: 3, in: details)
            assertEqual(vm.remainingStepDistanceMiles, 0.0)
        }

        runTest("test26_NavigationViewModelDualPointArrivalDetection") {
            let vm = NavigationViewModel()
            let roadStart = CLLocationCoordinate2D(latitude: 64.8400, longitude: -147.7200)
            let roadEnd = CLLocationCoordinate2D(latitude: 64.8430, longitude: -147.7200)
            let coords = [roadStart, roadEnd]

            let setbackPin = CLLocationCoordinate2D(latitude: 64.8430, longitude: -147.7194)
            let step = NavigationStep(instruction: "Arrive", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 1)
            let details = RouteDetails(coordinates: coords, totalDistanceMiles: 0.2, totalDurationSeconds: 20, steps: [step], costing: "auto")

            vm.routeDetails = details
            vm.routeCoordinates = coords
            vm.selectedCoordinate = setbackPin
            vm.isNavigating = true
            vm.currentStepIndex = 0
            vm.currentCoordIndex = 1

            let userInParkingLot = CLLocationCoordinate2D(latitude: 64.8430, longitude: -147.7196)
            vm.updateCurrentStepForLiveLocation(userInParkingLot, in: details)

            assertFalse(vm.isNavigating)
            assertNil(vm.routeDetails)
        }

        runTest("test27_NavigationViewModelResetAndEndNavigationCleanliness") {
            let vm = NavigationViewModel()
            let coord = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
            let place = SearchResult(id: 42, name: "Moose's Tooth", lat: 64.84, lon: -147.72)

            vm.selectPlace(place)
            vm.routeCoordinates = [coord]
            vm.routeDetails = RouteDetails(coordinates: [coord, coord], totalDistanceMiles: 1.0, totalDurationSeconds: 60, steps: [], costing: "auto")
            vm.isNavigating = true
            vm.isSimulating = true
            vm.simulatedUserCoordinate = coord
            vm.simulatedHeading = 90.0

            vm.resetToExplore()

            assertEqual(vm.appMode, .explore)
            assertFalse(vm.isNavigating)
            assertFalse(vm.isSimulating)
            assertNil(vm.routeDetails)
            assertNil(vm.routeCoordinates)
            assertNil(vm.selectedPlace)
            assertNil(vm.selectedCoordinate)
            assertNil(vm.simulatedUserCoordinate)
            assertNil(vm.simulatedHeading)
            assertEqual(vm.destinationText, "")
            assertTrue(vm.searchResults.isEmpty)
            assertNil(vm.searchTask)
        }

        // ====================================================
        // Suite 3: Adversarial Tests (testAdversarial01-05)
        // ====================================================
        print("\n\(BOLD)📦 Suite 3: Adversarial Challenge Suites (testAdversarial01-05)\(RESET)")

        runTest("testAdversarial01_OutOfRegionGPSHandling_BoundaryOnly") {
            let vm = NavigationViewModel()
            let equatorCoords = [
                CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),
                CLLocationCoordinate2D(latitude: 0.0, longitude: -147.0),
                CLLocationCoordinate2D(latitude: 0.0, longitude: 180.0),
                CLLocationCoordinate2D(latitude: 0.0, longitude: -180.0),
                CLLocationCoordinate2D(latitude: 0.0, longitude: -129.0)
            ]
            for coord in equatorCoords {
                assertFalse(vm.isWithinSupportedRegion(coord))
            }
            let polarCoords = [
                CLLocationCoordinate2D(latitude: 90.0, longitude: 0.0),
                CLLocationCoordinate2D(latitude: -90.0, longitude: 0.0)
            ]
            for coord in polarCoords {
                assertFalse(vm.isWithinSupportedRegion(coord))
            }
        }

        await runAsyncTest("testAdversarial02_SearchTaskLifecycle") {
            let vm = NavigationViewModel()
            for i in 0..<50 {
                let query = (i % 2 == 0) ? "Fairbanks" : "Anchorage Airport"
                vm.searchCategory(query)
                if i % 3 == 0 {
                    vm.clearSearch()
                    assertNil(vm.searchTask)
                } else if i % 3 == 1 {
                    vm.dismissSearch()
                    assertNil(vm.searchTask)
                } else {
                    vm.resetToExplore()
                    assertNil(vm.searchTask)
                }
            }
        }

        runTest("testAdversarial03_CategorySearchDeduplication") {
            let vm = NavigationViewModel()
            let categories = ["Gas", "Coffee", "Restaurant", "Market", "Parking", "Hotel", "Hospital"]
            for cat in categories {
                vm.searchCategory(cat)
            }
            vm.isProgrammaticTextChange = false
            vm.destinationText = ""
            vm.searchCategory("Hospital")
            assertEqual(vm.destinationText, "Hospital")
            assertTrue(vm.isProgrammaticTextChange)

            vm.isProgrammaticTextChange = false
            vm.searchCategory("Hospital")
            assertFalse(vm.isProgrammaticTextChange)

            vm.searchCategory("Coffee")
            assertEqual(vm.destinationText, "Coffee")
            assertTrue(vm.isProgrammaticTextChange)

            vm.clearSearch()
            assertNil(vm.searchTask)
            assertEqual(vm.destinationText, "")
        }

        runTest("testAdversarial04_RouteTelemetryZeroOneAndLargeStepArrays") {
            let vm = NavigationViewModel()
            let coordA = CLLocationCoordinate2D(latitude: 64.84, longitude: -147.72)
            let coordB = CLLocationCoordinate2D(latitude: 64.85, longitude: -147.71)
            let zeroStepsRoute = RouteDetails(coordinates: [coordA, coordB], totalDistanceMiles: 1.0, totalDurationSeconds: 120, steps: [], costing: "auto")
            vm.routeDetails = zeroStepsRoute

            for idx in [-5, 0, 1, 10] {
                vm.updateNavigationTelemetry(at: coordA, coordIndex: idx, in: zeroStepsRoute)
                assertFalse(vm.formattedRemainingDuration.isEmpty)
                assertFalse(vm.formattedRemainingETA.isEmpty)
            }

            let singleStep = NavigationStep(instruction: "Head north", distanceMiles: 2.5, durationSeconds: 180, maneuverType: 1, streetName: "Airport Way", startIndex: 0, endIndex: 2)
            let coordC = CLLocationCoordinate2D(latitude: 64.86, longitude: -147.70)
            let oneStepRoute = RouteDetails(coordinates: [coordA, coordB, coordC], totalDistanceMiles: 2.5, totalDurationSeconds: 180, steps: [singleStep], costing: "auto")
            vm.routeDetails = oneStepRoute
            vm.updateNavigationTelemetry(at: coordA, coordIndex: 0, in: oneStepRoute)
            assertFalse(vm.formattedRemainingDuration.isEmpty)

            var largeCoords: [CLLocationCoordinate2D] = []
            var largeSteps: [NavigationStep] = []
            for i in 0..<5000 {
                largeCoords.append(CLLocationCoordinate2D(latitude: 64.0 + Double(i) * 0.0001, longitude: -147.0 - Double(i) * 0.0001))
            }
            for s in 0..<500 {
                let start = s * 10
                let end = min(start + 10, 4999)
                largeSteps.append(NavigationStep(instruction: "Continue step \(s)", distanceMiles: 0.5, durationSeconds: 30, maneuverType: 1, streetName: "Route \(s)", startIndex: start, endIndex: end))
            }
            let largeRoute = RouteDetails(coordinates: largeCoords, totalDistanceMiles: 250.0, totalDurationSeconds: 15000, steps: largeSteps, costing: "auto")
            vm.routeDetails = largeRoute

            let testIndices = [-10, 0, 1, 2500, 4998, 4999, 5050]
            for idx in testIndices {
                vm.updateNavigationTelemetry(at: largeCoords[min(max(0, idx), 4999)], coordIndex: idx, in: largeRoute)
                assertFalse(vm.formattedRemainingDuration.isEmpty)
                assertFalse(vm.formattedRemainingETA.isEmpty)
            }

            let zeroLengthRoute = RouteDetails(coordinates: [coordA, coordB], totalDistanceMiles: 0.0, totalDurationSeconds: 0.0, steps: [], costing: "auto")
            vm.updateNavigationTelemetry(at: coordA, coordIndex: 0, in: zeroLengthRoute)
            assertFalse(vm.formattedRemainingDuration.isEmpty)

            assertEqual(vm.formatCountdownDistance(0.0, useMetric: false), "0 ft")
            assertEqual(vm.formatCountdownDistance(0.05, useMetric: false), "264 ft")
            assertEqual(vm.formatCountdownDistance(0.099, useMetric: false), "522 ft")
            assertEqual(vm.formatCountdownDistance(0.10, useMetric: false), "0.1 mi")
            assertEqual(vm.formatCountdownDistance(0.5, useMetric: false), "0.5 mi")
            assertEqual(vm.formatCountdownDistance(5.0, useMetric: false), "5.0 mi")

            assertEqual(vm.formatCountdownDistance(0.0, useMetric: true), "0 m")
            assertEqual(vm.formatCountdownDistance(0.05, useMetric: true), "80 m")
            assertEqual(vm.formatCountdownDistance(0.5, useMetric: true), "804 m")
            assertEqual(vm.formatCountdownDistance(5.0, useMetric: true), "8.0 km")
        }

        runTest("testAdversarial05_SimulationMetricTogglingProgressPreservation") {
            let vm = NavigationViewModel()
            vm.useMetric = false
            assertEqual(vm.speedUnit, "mph")
            assertEqual(vm.altitudeUnit, "ft")

            let p1 = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
            let p2 = CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7210)
            let p3 = CLLocationCoordinate2D(latitude: 64.8445, longitude: -147.7205)
            let step = NavigationStep(instruction: "Go north", distanceMiles: 0.1, durationSeconds: 30, maneuverType: 1, streetName: nil, startIndex: 0, endIndex: 2)
            let route = RouteDetails(coordinates: [p1, p2, p3], totalDistanceMiles: 0.1, totalDurationSeconds: 30, steps: [step], costing: "auto")
            vm.routeDetails = route
            vm.routeCoordinates = [p1, p2, p3]
            vm.startNavigation()
            vm.startSimulatedDrive()
            vm.advanceSimulationStep()

            let savedCoordIndex = vm.currentCoordIndex
            let savedStepIndex = vm.currentStepIndex
            assertTrue(vm.isNavigating)
            assertTrue(vm.isSimulating)

            vm.useMetric.toggle()
            assertTrue(vm.isNavigating)
            assertTrue(vm.isSimulating)
            assertEqual(vm.currentCoordIndex, savedCoordIndex)
            assertEqual(vm.currentStepIndex, savedStepIndex)
            assertEqual(vm.speedUnit, "km/h")
            assertEqual(vm.altitudeUnit, "m")

            let imperialShort = vm.formatCountdownDistance(0.05, useMetric: false)
            let metricShort = vm.formatCountdownDistance(0.05, useMetric: true)
            assertTrue(imperialShort.contains("ft"))
            assertTrue(metricShort.contains("m"))
            vm.endNavigation()
        }

        // ====================================================
        // Suite 4: Empirical Challenger Bug Investigation
        // ====================================================
        print("\n\(BOLD)📦 Suite 4: Empirical Challenger Bug Analysis (RemediationTests:645-683)\(RESET)")

        runTest("challengeInvestigation_RemediationTests682_AccidentalArrivalBug") {
            // Replicate lines 645-683 of RemediationTests.swift EXACTLY
            let vm = NavigationViewModel()
            let coords = [
                CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215),
                CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7210)
            ]
            let route = RouteDetails(
                coordinates: coords,
                totalDistanceMiles: 0.1,
                totalDurationSeconds: 30,
                steps: [],
                costing: "auto"
            )
            vm.routeDetails = route
            vm.routeCoordinates = coords
            vm.isNavigating = true
            vm.isSimulating = false
            let initialPuck = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
            vm.simulatedUserCoordinate = initialPuck

            // 1. Deliver out-of-region location fix (San Francisco)
            let outOfRegionFix = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                altitude: 10,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 5.0,
                timestamp: Date()
            )
            vm.handleLocationUpdate(outOfRegionFix)
            assertEqual(vm.simulatedUserCoordinate?.latitude, initialPuck.latitude, "Out-of-region fix must be silently dropped without modifying user coordinate")

            // 2. Deliver valid in-region location fix (Fairbanks downtown)
            let inRegionFix = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 64.8438, longitude: -147.7212),
                altitude: 10,
                horizontalAccuracy: 5.0,
                verticalAccuracy: 5.0,
                timestamp: Date()
            )

            // Calculate distance to route endpoint
            let distToRoadEnd = vm.segmentDistanceMeters(p1: inRegionFix.coordinate, p2: coords.last!)
            print("    [Info] Distance from inRegionFix to route end: \(distToRoadEnd) meters (< 25m threshold!)")
            assertTrue(distToRoadEnd < 25.0, "Physical distance is 24.048m, which is strictly less than 25m arrival threshold")

            vm.handleLocationUpdate(inRegionFix)

            // In RemediationTests.swift:682:
            // XCTAssertEqual(vm.simulatedUserCoordinate?.latitude ?? 0, 64.8438, accuracy: 0.0001)
            // But because distToRoadEnd < 25.0, arrival detection triggers, endNavigation() is called,
            // and simulatedUserCoordinate is cleared to nil!
            let actualLat = vm.simulatedUserCoordinate?.latitude ?? 0
            print("    [Info] After handleLocationUpdate: vm.simulatedUserCoordinate is \(String(describing: vm.simulatedUserCoordinate)) (actualLat = \(actualLat))")
            assertEqual(actualLat, 0.0, "Empirical verification proves simulatedUserCoordinate was cleared to nil due to arrival!")
            assertFalse(vm.isNavigating, "Navigation ended due to arrival at destination!")
            assertNil(vm.routeDetails, "Route was cleared due to arrival!")

            // Now demonstrate that with route endpoint > 40m away, handleLocationUpdate updates coordinate without ending navigation:
            let farCoords = [
                CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215),
                CLLocationCoordinate2D(latitude: 64.8500, longitude: -147.7210) // ~685m away
            ]
            let farRoute = RouteDetails(coordinates: farCoords, totalDistanceMiles: 0.5, totalDurationSeconds: 120, steps: [], costing: "auto")
            vm.routeDetails = farRoute
            vm.routeCoordinates = farCoords
            vm.isNavigating = true
            vm.isSimulating = false
            vm.simulatedUserCoordinate = initialPuck

            vm.handleLocationUpdate(inRegionFix)
            assertEqual(vm.simulatedUserCoordinate?.latitude ?? 0, 64.8438, "When route endpoint is far (>40m), in-region fix updates simulatedUserCoordinate correctly without premature arrival")
            assertTrue(vm.isNavigating, "Navigation remains active when not arrived")
            vm.endNavigation()
        }

        print("\n\(BOLD)\(CYAN)========================================================\(RESET)")
        print("\(BOLD)📊 EMPIRICAL STRESS TEST EXECUTION SUMMARY\(RESET)")
        print("\(BOLD)\(CYAN)========================================================\(RESET)")
        print("Total Tests:  \(testsRun)")
        print("Passed:       \(GREEN)\(testsPassed) ✅\(RESET)")
        print("Failed:       \(testsFailed == 0 ? "\(GREEN)0" : "\(RED)\(testsFailed)")\(RESET)")
        print("\(BOLD)\(CYAN)========================================================\(RESET)")

        if testsFailed == 0 {
            print("\n\(BOLD)\(GREEN)🎉 ALL \(testsRun) STRESS TESTS EXECUTED AND EMPIRICALLY CONFIRMED!\(RESET)\n")
        } else {
            print("\n\(BOLD)\(RED)❌ \(testsFailed) TESTS FAILED!\(RESET)\n")
            exit(1)
        }
    }
}
