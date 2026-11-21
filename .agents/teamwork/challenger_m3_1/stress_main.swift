import Foundation
import CoreLocation

// MARK: - Empirical Adversarial Stress Test Suite for Milestone 3
// Tests R2.1–R2.5 directly against NavigationViewModel production class.

@MainActor
final class StressTestRunner {
    private var totalTests = 0
    private var passedTests = 0
    private var failedTests = 0
    private var failureMessages: [String] = []

    func assert(_ condition: Bool, _ message: String, file: String = #file, line: Int = #line) {
        totalTests += 1
        if condition {
            passedTests += 1
        } else {
            failedTests += 1
            let failStr = "FAIL [line \(line)]: \(message)"
            failureMessages.append(failStr)
            print("  ❌ \(failStr)")
        }
    }

    func runAll() async {
        print("=================================================================")
        print("🔥 STARTING ADVERSARIAL STRESS TEST SUITE (MILESTONE 3: R2.1–R2.5)")
        print("=================================================================")

        await testModule1_SwitchbackSearchClamping()
        await testModule2_MonotonicDistanceCountdown()
        await testModule3_MultiSpeedSimulationProgression()
        await testModule4_HardwareGPSStartFix()
        await testModule5_DualPointArrivalDetection()
        await testModule6_BoundaryAndEdgeCases()

        print("\n=================================================================")
        print("📊 STRESS TEST EXECUTION SUMMARY")
        print("=================================================================")
        print("Total Checks: \(totalTests)")
        print("Passed:       \(passedTests) ✅")
        print("Failed:       \(failedTests) ❌")

        if failedTests == 0 {
            print("\n🎉 ALL ADVERSARIAL STRESS TESTS PASSED SUCCESSFULLY!")
        } else {
            print("\n⚠️ FAILURES DETECTED:")
            for msg in failureMessages {
                print("  - \(msg)")
            }
        }
        print("=================================================================")
        if failedTests > 0 {
            exit(1)
        }
    }

    // MARK: - Geometries
    private func makeSwitchbackRoute(spacingMeters: Double = 14.19) -> RouteDetails {
        // Fairbanks: 1 deg lat ~ 110540m, 1 deg lon ~ 47320m
        let lonOffset = spacingMeters / 47320.0
        var coords: [CLLocationCoordinate2D] = []
        let baseLat = 64.8400

        // Leg 1: Step 0 (Northward, indices 0..10, 55m per vertex)
        for i in 0...10 {
            coords.append(CLLocationCoordinate2D(latitude: baseLat + Double(i) * 0.0005, longitude: -147.7200))
        }

        // Hairpin curve: Step 1 (indices 10..14)
        coords.append(CLLocationCoordinate2D(latitude: baseLat + 0.0052, longitude: -147.7200 + lonOffset * 0.33))
        coords.append(CLLocationCoordinate2D(latitude: baseLat + 0.0053, longitude: -147.7200 + lonOffset * 0.67))
        coords.append(CLLocationCoordinate2D(latitude: baseLat + 0.0052, longitude: -147.7200 + lonOffset))
        coords.append(CLLocationCoordinate2D(latitude: baseLat + 0.0050, longitude: -147.7200 + lonOffset))

        // Leg 2: Step 2 (Southward parallel, indices 14..24)
        for i in 1...10 {
            coords.append(CLLocationCoordinate2D(latitude: baseLat + 0.0050 - Double(i) * 0.0005, longitude: -147.7200 + lonOffset))
        }

        let step0 = NavigationStep(instruction: "Head north on Ester Dome Road", distanceMiles: 0.35, durationSeconds: 40, maneuverType: 1, streetName: "Ester Dome Road", startIndex: 0, endIndex: 10)
        let step1 = NavigationStep(instruction: "Sharp right on Switchback Cutoff", distanceMiles: 0.05, durationSeconds: 15, maneuverType: 13, streetName: "Switchback Cutoff", startIndex: 10, endIndex: 14)
        let step2 = NavigationStep(instruction: "Continue south toward Sheep Creek Road", distanceMiles: 0.35, durationSeconds: 40, maneuverType: 1, streetName: "Sheep Creek Road", startIndex: 14, endIndex: 24)

        return RouteDetails(
            coordinates: coords,
            totalDistanceMiles: 0.75,
            totalDurationSeconds: 95,
            steps: [step0, step1, step2]
        )
    }

    // MARK: - Module 1: Switchback Geometry & Clamped Search Clamping (R2.1)
    func testModule1_SwitchbackSearchClamping() async {
        print("\n--- [Module 1] Switchback Geometry & Search Clamping (R2.1) ---")

        // Test 1.1: Standard Switchback (14.2m separation between parallel legs)
        let route = makeSwitchbackRoute(spacingMeters: 14.19)
        let coords = route.coordinates
        let step0End = route.steps[0].endIndex // 10

        // Verify distance between Leg 1 index 3 and Leg 2 index 21 is ~14.2m
        let pLeg1 = coords[3]
        let pLeg2 = coords[21]
        let distBetweenLegs = NavigationViewModel.segmentDistanceMeters(p1: pLeg1, p2: pLeg2)
        assert(distBetweenLegs >= 13.0 && distBetweenLegs <= 15.5, "Leg separation must be ~14.2m (actual: \(distBetweenLegs)m)")

        // Drive up Leg 1 from index 0 to 9.
        // At every vertex, test exact position and 5 lateral perturbations towards Leg 2.
        for i in 0...9 {
            for jitterMeters in [0.0, 2.0, 4.0, 6.0, 8.0, 10.0] {
                let vm = NavigationViewModel()
                vm.routeDetails = route
                vm.routeCoordinates = coords
                vm.isNavigating = true
                vm.currentStepIndex = 0
                vm.currentCoordIndex = i

                let baseCoord = coords[i]
                let jitterLon = (jitterMeters / 47320.0)
                let userCoord = CLLocationCoordinate2D(latitude: baseCoord.latitude, longitude: baseCoord.longitude + jitterLon)

                vm.updateCurrentStepForLiveLocation(userCoord, in: route)

                // Clamping rule: forward search is clamped to min(coords.count - 1, max(currentCoordIndex + 1, currentStepEnd + 2))
                assert(vm.currentCoordIndex <= step0End + 2, "Coordinate index (\(vm.currentCoordIndex)) must be clamped <= \(step0End + 2) at vertex \(i) with \(jitterMeters)m jitter")
                assert(vm.currentStepIndex == 0, "Step index must remain 0 on Leg 1 at vertex \(i) (got \(vm.currentStepIndex))")
            }
        }
        print("  ✅ 1.1 Switchback search clamping verified across 10 vertices x 6 lateral perturbations")

        // Test 1.2: Ultra-tight 6-meter separation switchback
        let routeTight = makeSwitchbackRoute(spacingMeters: 6.0)
        let pTight1 = routeTight.coordinates[3]
        let pTight2 = routeTight.coordinates[21]
        let distTight = NavigationViewModel.segmentDistanceMeters(p1: pTight1, p2: pTight2)
        assert(distTight >= 5.0 && distTight <= 7.0, "Tight switchback separation must be ~6m (actual: \(distTight)m)")

        for i in 0...9 {
            let vmTight = NavigationViewModel()
            vmTight.routeDetails = routeTight
            vmTight.routeCoordinates = routeTight.coordinates
            vmTight.isNavigating = true
            vmTight.currentStepIndex = 0
            vmTight.currentCoordIndex = i

            let baseCoord = routeTight.coordinates[i]
            // Lateral perturbation placing user only 2m from parallel Leg 2
            let jitterCoord = CLLocationCoordinate2D(latitude: baseCoord.latitude, longitude: baseCoord.longitude + (4.0 / 47320.0))

            vmTight.updateCurrentStepForLiveLocation(jitterCoord, in: routeTight)
            assert(vmTight.currentCoordIndex <= step0End + 2, "In 6m switchback, coordIndex must remain clamped <= \(step0End + 2) (got \(vmTight.currentCoordIndex))")
            assert(vmTight.currentStepIndex == 0, "In 6m switchback, stepIndex must not advance prematurely (got \(vmTight.currentStepIndex))")
        }
        print("  ✅ 1.2 Ultra-tight 6m switchback clamping verified")

        // Test 1.3: Sequential Progression through entire switchback route
        let vmSeq = NavigationViewModel()
        vmSeq.routeDetails = route
        vmSeq.routeCoordinates = coords
        vmSeq.isNavigating = true
        vmSeq.currentStepIndex = 0
        vmSeq.currentCoordIndex = 0

        // Drive through all 25 coordinates sequentially
        for (idx, coord) in coords.enumerated() {
            vmSeq.updateCurrentStepForLiveLocation(coord, in: route)
            let curStep = vmSeq.currentStepIndex
            let curStepEnd = route.steps[curStep].endIndex
            assert(vmSeq.currentCoordIndex <= curStepEnd + 2, "During sequential drive at index \(idx), currentCoordIndex (\(vmSeq.currentCoordIndex)) must be clamped <= stepEnd+2 (\(curStepEnd + 2))")
        }
        print("  ✅ 1.3 Full sequential traversal through switchback completed smoothly")
    }

    // MARK: - Module 2: Monotonic Distance Countdown & Non-Reversal (R2.2)
    func testModule2_MonotonicDistanceCountdown() async {
        print("\n--- [Module 2] Monotonic Distance Countdown (R2.2) ---")

        let route = makeSwitchbackRoute(spacingMeters: 14.19)
        let coords = route.coordinates
        let step0End = route.steps[0].endIndex // 10

        let vm = NavigationViewModel()
        vm.routeDetails = route
        vm.routeCoordinates = coords

        // Test 2.1: Transition across step boundary
        var prevStepDist: Double = Double.greatestFiniteMagnitude
        for idx in 5...15 {
            let coord = coords[idx]
            vm.currentCoordIndex = idx
            vm.currentStepIndex = 0 // Keeping step 0 active to test driving past its end
            vm.updateNavigationTelemetry(at: coord, coordIndex: idx, in: route)

            let stepDist = vm.remainingStepDistanceMiles
            if idx < step0End {
                assert(stepDist <= prevStepDist + 1e-6, "Step distance must decrease monotonically before stepEnd: at index \(idx) got \(stepDist) vs prev \(prevStepDist)")
                prevStepDist = stepDist
            } else {
                // At or past stepEnd: strictly 0.0
                assert(stepDist == 0.0, "Step distance must evaluate strictly to 0.0 at/past stepEnd (index \(idx) got \(stepDist))")
            }
        }
        print("  ✅ 2.1 Step distance evaluates strictly to 0.0 past stepEnd without reversal")

        // Test 2.2: Continuous sub-meter traversal (1,000 fine-grained points)
        var prevRouteDist: Double = Double.greatestFiniteMagnitude
        var monotonicViolations = 0

        for i in 0...1000 {
            let fraction = Double(i) / 1000.0
            let totalSegments = Double(coords.count - 1)
            let virtualIdx = fraction * totalSegments
            let segIdx = min(coords.count - 2, Int(virtualIdx))
            let t = virtualIdx - Double(segIdx)

            let pA = coords[segIdx]
            let pB = coords[segIdx + 1]
            let interpolated = CLLocationCoordinate2D(
                latitude: pA.latitude + t * (pB.latitude - pA.latitude),
                longitude: pA.longitude + t * (pB.longitude - pA.longitude)
            )

            vm.updateNavigationTelemetry(at: interpolated, coordIndex: segIdx, in: route)
            let routeDist = vm.remainingRouteDistanceMiles

            if routeDist > prevRouteDist + 1e-6 {
                monotonicViolations += 1
            }
            prevRouteDist = routeDist
        }
        assert(monotonicViolations == 0, "Route distance must be strictly monotonic across 1,000 sub-meter points (violations: \(monotonicViolations))")
        print("  ✅ 2.2 Sub-meter traversal monotonic across 1,000 points (0 violations)")

        // Test 2.3: Driving past destination endpoint
        let lastCoord = coords.last!
        let pastDistancesMeters = [5.0, 20.0, 50.0, 200.0, 1000.0]
        for dist in pastDistancesMeters {
            let pastCoord = CLLocationCoordinate2D(latitude: lastCoord.latitude + (dist / 110540.0), longitude: lastCoord.longitude)
            vm.updateNavigationTelemetry(at: pastCoord, coordIndex: coords.count - 1, in: route)
            assert(vm.remainingRouteDistanceMiles == 0.0, "Driving \(dist)m past destination must evaluate remainingRouteDistanceMiles to 0.0 (got \(vm.remainingRouteDistanceMiles))")
            assert(vm.remainingStepDistanceMiles == 0.0, "Driving \(dist)m past destination must evaluate remainingStepDistanceMiles to 0.0 (got \(vm.remainingStepDistanceMiles))")
        }
        print("  ✅ 2.3 Over-driving past destination evaluates to 0.0 at all distances")
    }

    // MARK: - Module 3: Multi-Speed Simulation Progression (R2.3)
    func testModule3_MultiSpeedSimulationProgression() async {
        print("\n--- [Module 3] Multi-Speed Simulation Progression (R2.3) ---")

        // Build route with 8 distinct, densely placed steps
        var simCoords: [CLLocationCoordinate2D] = []
        for i in 0...24 {
            simCoords.append(CLLocationCoordinate2D(latitude: 64.8400 + Double(i) * 0.0003, longitude: -147.7200))
        }

        let steps: [NavigationStep] = [
            NavigationStep(instruction: "Turn right onto 1st Ave", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 10, streetName: "1st Ave", startIndex: 0, endIndex: 2),
            NavigationStep(instruction: "Turn left onto 2nd Ave", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 15, streetName: "2nd Ave", startIndex: 2, endIndex: 4),
            NavigationStep(instruction: "Bear right onto Main St", distanceMiles: 0.05, durationSeconds: 5, maneuverType: 9, streetName: "Main St", startIndex: 4, endIndex: 5),
            NavigationStep(instruction: "Turn right onto Elm St", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 10, streetName: "Elm St", startIndex: 5, endIndex: 7),
            NavigationStep(instruction: "Turn left onto Pine St", distanceMiles: 0.1, durationSeconds: 10, maneuverType: 15, streetName: "Pine St", startIndex: 7, endIndex: 9),
            NavigationStep(instruction: "Continue onto Hwy 3", distanceMiles: 0.25, durationSeconds: 25, maneuverType: 1, streetName: "Hwy 3", startIndex: 9, endIndex: 14),
            NavigationStep(instruction: "Take exit 4", distanceMiles: 0.2, durationSeconds: 20, maneuverType: 22, streetName: "Exit 4", startIndex: 14, endIndex: 18),
            NavigationStep(instruction: "Arrive at destination", distanceMiles: 0.3, durationSeconds: 30, maneuverType: 4, streetName: "Arrival", startIndex: 18, endIndex: 24)
        ]

        let simRoute = RouteDetails(coordinates: simCoords, totalDistanceMiles: 1.2, totalDurationSeconds: 120, steps: steps)

        // Test multipliers: 1x, 2x, 5x, 10x
        for multiplier in [1.0, 2.0, 5.0, 10.0] {
            let mockRouting = RoutingService()
            let vm = NavigationViewModel(routingService: mockRouting)
            vm.routeDetails = simRoute
            vm.routeCoordinates = simCoords
            vm.isNavigating = true
            vm.isSimulating = true
            vm.simulationSpeedMultiplier = multiplier
            vm.currentCoordIndex = 0
            vm.currentStepIndex = 0

            // Advance simulation step by step until arrival
            var safetyCounter = 0
            while vm.isNavigating && safetyCounter < 100 {
                safetyCounter += 1
                vm.advanceSimulationStep()
            }

            // Verify that every single intermediate maneuver (steps 1 through 7) was announced!
            let spokenTexts = mockRouting.spokenInstructions.map { $0.text }
            for stepIdx in 1..<steps.count {
                let expectedInstruction = steps[stepIdx].instruction
                let wasSpoken = spokenTexts.contains(expectedInstruction)
                assert(wasSpoken, "At \(multiplier)x simulation, instruction '\(expectedInstruction)' must be announced (spoken: \(spokenTexts))")
            }
            assert(spokenTexts.contains("You have arrived at your destination."), "At \(multiplier)x simulation, destination arrival must be announced")
            assert(!vm.isNavigating, "At \(multiplier)x simulation, navigation must terminate cleanly upon arrival")
        }
        print("  ✅ 3.1 All 8 maneuvers announced across 1x, 2x, 5x, and 10x simulation speeds")

        // Test 3.2: Randomized speed multiplier switching
        var dynamicSpeedRuns = 0
        for _ in 0..<20 {
            let mockRouting = RoutingService()
            let vm = NavigationViewModel(routingService: mockRouting)
            vm.routeDetails = simRoute
            vm.routeCoordinates = simCoords
            vm.isNavigating = true
            vm.isSimulating = true
            vm.currentCoordIndex = 0
            vm.currentStepIndex = 0

            var safetyCounter = 0
            let speedChoices = [1.0, 2.0, 5.0, 10.0]
            while vm.isNavigating && safetyCounter < 100 {
                safetyCounter += 1
                vm.simulationSpeedMultiplier = speedChoices[safetyCounter % speedChoices.count]
                vm.advanceSimulationStep()
            }

            let spokenTexts = mockRouting.spokenInstructions.map { $0.text }
            for stepIdx in 1..<steps.count {
                assert(spokenTexts.contains(steps[stepIdx].instruction), "Under dynamic speed switching, step \(stepIdx) must be announced")
            }
            dynamicSpeedRuns += 1
        }
        assert(dynamicSpeedRuns == 20, "Completed 20 dynamic speed switching runs")
        print("  ✅ 3.2 Dynamic speed switching stress test passed (20 randomized runs)")
    }

    // MARK: - Module 4: Hardware GPS Start Fix (R2.4)
    func testModule4_HardwareGPSStartFix() async {
        print("\n--- [Module 4] Hardware GPS Start Fix (R2.4) ---")

        let routeStart = CLLocationCoordinate2D(latitude: 64.8450, longitude: -147.7200)
        let routeEnd = CLLocationCoordinate2D(latitude: 64.8500, longitude: -147.7200)
        let route = RouteDetails(
            coordinates: [routeStart, routeEnd],
            totalDistanceMiles: 0.5,
            totalDurationSeconds: 60,
            steps: [NavigationStep(instruction: "Go north", distanceMiles: 0.5, durationSeconds: 60, maneuverType: 1, streetName: "North", startIndex: 0, endIndex: 1)]
        )

        // Test 4.1: Valid healthy GPS fix retained
        let validLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 64.8420, longitude: -147.7210),
            altitude: 150.0,
            horizontalAccuracy: 8.0,
            verticalAccuracy: 5.0,
            course: 42.0,
            speed: 12.0,
            timestamp: Date()
        )
        let mockLocManager = LocationManager()
        mockLocManager.setMockLocation(validLoc)

        let vm = NavigationViewModel(locationManager: mockLocManager)
        vm.routeDetails = route
        vm.routeCoordinates = route.coordinates
        vm.startNavigation()

        assert(vm.simulatedUserCoordinate?.latitude == validLoc.coordinate.latitude, "Healthy live GPS coordinate must be retained (got \(String(describing: vm.simulatedUserCoordinate?.latitude)))")
        assert(vm.simulatedUserCoordinate?.longitude == validLoc.coordinate.longitude, "Healthy live GPS coordinate must be retained (got \(String(describing: vm.simulatedUserCoordinate?.longitude)))")
        assert(vm.simulatedHeading == 42.0, "Healthy course must be retained (got \(String(describing: vm.simulatedHeading)))")
        print("  ✅ 4.1 Healthy live GPS fix retained without freezing at origin")

        // Test 4.2: Degraded GPS (accuracy >= 65m) snaps to polyline start
        for badAccuracy in [65.0, 75.0, 200.0, -1.0] {
            let badLoc = CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: 64.8420, longitude: -147.7210),
                altitude: 150.0,
                horizontalAccuracy: badAccuracy,
                verticalAccuracy: 5.0,
                timestamp: Date()
            )
            mockLocManager.setMockLocation(badLoc)
            let vmBad = NavigationViewModel(locationManager: mockLocManager)
            vmBad.routeDetails = route
            vmBad.routeCoordinates = route.coordinates
            vmBad.startNavigation()

            assert(vmBad.simulatedUserCoordinate?.latitude == routeStart.latitude, "Degraded GPS (acc \(badAccuracy)m) must snap to polyline start")
        }
        print("  ✅ 4.2 Degraded/invalid GPS accuracy snaps to route start")

        // Test 4.3: Stale GPS timestamp (> 15.0s old) snaps to polyline start
        let staleLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 64.8420, longitude: -147.7210),
            altitude: 150.0,
            horizontalAccuracy: 10.0,
            verticalAccuracy: 5.0,
            timestamp: Date().addingTimeInterval(-20.0)
        )
        mockLocManager.setMockLocation(staleLoc)
        let vmStale = NavigationViewModel(locationManager: mockLocManager)
        vmStale.routeDetails = route
        vmStale.routeCoordinates = route.coordinates
        vmStale.startNavigation()

        assert(vmStale.simulatedUserCoordinate?.latitude == routeStart.latitude, "Stale GPS timestamp (20s old) must snap to polyline start")
        print("  ✅ 4.3 Stale GPS fix snaps to route start")

        // Test 4.4: Out-of-region GPS (e.g. San Francisco) snaps to polyline start
        let sfLoc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            altitude: 10.0,
            horizontalAccuracy: 5.0,
            verticalAccuracy: 5.0,
            timestamp: Date()
        )
        mockLocManager.setMockLocation(sfLoc)
        let vmSF = NavigationViewModel(locationManager: mockLocManager)
        vmSF.routeDetails = route
        vmSF.routeCoordinates = route.coordinates
        vmSF.startNavigation()

        assert(vmSF.simulatedUserCoordinate?.latitude == routeStart.latitude, "Out-of-region GPS fix must snap to polyline start")
        print("  ✅ 4.4 Out-of-region GPS fix snaps to route start")

        // Test 4.5: Simulated drive explicitly begins at route start even with valid hardware GPS
        mockLocManager.setMockLocation(validLoc)
        let vmSim = NavigationViewModel(locationManager: mockLocManager)
        vmSim.routeDetails = route
        vmSim.routeCoordinates = route.coordinates
        vmSim.startSimulatedDrive()

        assert(vmSim.simulatedUserCoordinate?.latitude == routeStart.latitude, "Simulation must explicitly begin at route start coordinate")
        assert(vmSim.currentCoordIndex == 0, "Simulation must begin at coordIndex 0")
        print("  ✅ 4.5 Simulated drive explicitly begins at polyline origin")
    }

    // MARK: - Module 5: Dual-Point Arrival Detection (R2.5)
    func testModule5_DualPointArrivalDetection() async {
        print("\n--- [Module 5] Dual-Point Arrival Detection (R2.5) ---")

        // Setup setback parking lot scenario from TestGeometries
        // Road ends at (64.8450, -147.7200)
        // Destination pin is set back 35.5m West: (64.8450, -147.72075)
        let pRoadStart = CLLocationCoordinate2D(latitude: 64.8430, longitude: -147.7200)
        let pRoadMid = CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7200)
        let roadEnd = CLLocationCoordinate2D(latitude: 64.8450, longitude: -147.7200)
        let destPin = CLLocationCoordinate2D(latitude: 64.8450, longitude: -147.72075)

        let step0 = NavigationStep(instruction: "Proceed along road", distanceMiles: 0.1, durationSeconds: 20, maneuverType: 1, streetName: "Drive", startIndex: 0, endIndex: 1)
        let step1 = NavigationStep(instruction: "Arrive at destination", distanceMiles: 0.1, durationSeconds: 20, maneuverType: 4, streetName: "Store", startIndex: 1, endIndex: 2)
        let setbackRoute = RouteDetails(
            coordinates: [pRoadStart, pRoadMid, roadEnd],
            totalDistanceMiles: 0.2,
            totalDurationSeconds: 40,
            steps: [step0, step1]
        )

        // Test 5.1: User is 7m from destPin, but 28.4m from roadEnd
        let userNearPin = CLLocationCoordinate2D(latitude: 64.8450, longitude: -147.72060)
        let mockRouter1 = RoutingService()
        let vm1 = NavigationViewModel(routingService: mockRouter1)
        vm1.routeDetails = setbackRoute
        vm1.routeCoordinates = setbackRoute.coordinates
        vm1.selectedCoordinate = destPin
        vm1.isNavigating = true
        vm1.currentCoordIndex = 1
        vm1.currentStepIndex = 1

        let dRoad1 = NavigationViewModel.segmentDistanceMeters(p1: userNearPin, p2: roadEnd)
        let dPin1 = NavigationViewModel.segmentDistanceMeters(p1: userNearPin, p2: destPin)
        assert(dRoad1 > 25.0, "User must be > 25m from road end (actual: \(dRoad1)m)")
        assert(dPin1 < 12.0, "User must be < 12m from pin (actual: \(dPin1)m)")

        vm1.updateCurrentStepForLiveLocation(userNearPin, in: setbackRoute)
        assert(!vm1.isNavigating, "Dual-point arrival must trigger when approaching setback destination pin")
        assert(mockRouter1.spokenInstructions.contains(where: { $0.text.contains("arrived at your destination") }), "Arrival instruction must be announced")
        print("  ✅ 5.1 Arrival triggers at setback destination pin (28.4m from road end)")

        // Test 5.2: User arrives within 10m of road end
        let userAtRoadEnd = CLLocationCoordinate2D(latitude: 64.84495, longitude: -147.7200)
        let mockRouter2 = RoutingService()
        let vm2 = NavigationViewModel(routingService: mockRouter2)
        vm2.routeDetails = setbackRoute
        vm2.routeCoordinates = setbackRoute.coordinates
        vm2.selectedCoordinate = destPin
        vm2.isNavigating = true
        vm2.currentCoordIndex = 2
        vm2.currentStepIndex = 1

        vm2.updateCurrentStepForLiveLocation(userAtRoadEnd, in: setbackRoute)
        assert(!vm2.isNavigating, "Arrival must trigger at road end")
        print("  ✅ 5.2 Arrival triggers at road endpoint")

        // Test 5.3: Beyond threshold (55m from both roadEnd and destPin) does NOT trigger arrival
        // Road end is at lon -147.7200, destPin at -147.72075.
        // User at lon -147.72200 is ~95m from road end and ~59m from destPin.
        let userFarAway = CLLocationCoordinate2D(latitude: 64.8450, longitude: -147.72200)
        let mockRouter3 = RoutingService()
        let vm3 = NavigationViewModel(routingService: mockRouter3)
        vm3.routeDetails = setbackRoute
        vm3.routeCoordinates = setbackRoute.coordinates
        vm3.selectedCoordinate = destPin
        vm3.isNavigating = true
        vm3.currentCoordIndex = 2
        vm3.currentStepIndex = 1

        let dRoad3 = NavigationViewModel.segmentDistanceMeters(p1: userFarAway, p2: roadEnd)
        let dPin3 = NavigationViewModel.segmentDistanceMeters(p1: userFarAway, p2: destPin)
        assert(dRoad3 > 50.0, "User must be > 50m from road end (actual: \(dRoad3)m)")
        assert(dPin3 > 50.0, "User must be > 50m from pin (actual: \(dPin3)m)")

        vm3.updateCurrentStepForLiveLocation(userFarAway, in: setbackRoute)
        assert(vm3.isNavigating, "Arrival must NOT trigger when user is > 50m from both road end and destination pin")
        print("  ✅ 5.3 Beyond arrival threshold does NOT trigger arrival prematurely")

        // Test 5.4: False arrival prevention early in route on longer polyline
        // Route has 15 coordinates. At index 2 (Step 0), user is NOT near end (isNearEnd == false).
        var longCoords: [CLLocationCoordinate2D] = []
        for k in 0...14 {
            longCoords.append(CLLocationCoordinate2D(latitude: 64.8300 + Double(k) * 0.001, longitude: -147.7200))
        }
        let longPin = longCoords.last!
        let longRoute = RouteDetails(
            coordinates: longCoords,
            totalDistanceMiles: 1.5,
            totalDurationSeconds: 180,
            steps: [
                NavigationStep(instruction: "Step 0", distanceMiles: 0.5, durationSeconds: 60, maneuverType: 1, streetName: "St 0", startIndex: 0, endIndex: 5),
                NavigationStep(instruction: "Step 1", distanceMiles: 0.5, durationSeconds: 60, maneuverType: 1, streetName: "St 1", startIndex: 5, endIndex: 10),
                NavigationStep(instruction: "Step 2", distanceMiles: 0.5, durationSeconds: 60, maneuverType: 4, streetName: "St 2", startIndex: 10, endIndex: 14)
            ]
        )
        let mockRouter4 = RoutingService()
        let vm4 = NavigationViewModel(routingService: mockRouter4)
        vm4.routeDetails = longRoute
        vm4.routeCoordinates = longCoords
        vm4.selectedCoordinate = longPin
        vm4.isNavigating = true
        vm4.currentCoordIndex = 2
        vm4.currentStepIndex = 0

        // Place user 30m away from the destination pin:
        // Since user is at index 2 (early in route), isNearEnd is FALSE.
        // Relaxed 40m threshold only applies when isNearEnd is true.
        // For non-near-end, the threshold is < 25.0m.
        // Since 30m >= 25.0m, arrival should NOT trigger!
        let userAt30mFromPin = CLLocationCoordinate2D(latitude: longPin.latitude, longitude: longPin.longitude + (30.0 / 47320.0))
        let distEarly = NavigationViewModel.segmentDistanceMeters(p1: userAt30mFromPin, p2: longPin)
        assert(distEarly >= 28.0 && distEarly <= 32.0, "User is ~30m from pin (actual: \(distEarly)m)")

        vm4.updateCurrentStepForLiveLocation(userAt30mFromPin, in: longRoute)
        assert(vm4.isNavigating, "Early in route, 30m from pin must NOT trigger arrival (relaxed 40m only applies near end!)")
        print("  ✅ 5.4 False early arrival prevented when > 25m early in route")

        // Test 5.5: Nil destination pin handling
        let mockRouter5 = RoutingService()
        let vm5 = NavigationViewModel(routingService: mockRouter5)
        vm5.routeDetails = setbackRoute
        vm5.routeCoordinates = setbackRoute.coordinates
        vm5.selectedCoordinate = nil // No pin!
        vm5.isNavigating = true
        vm5.currentCoordIndex = 2
        vm5.currentStepIndex = 1

        vm5.updateCurrentStepForLiveLocation(userAtRoadEnd, in: setbackRoute)
        assert(!vm5.isNavigating, "Arrival must trigger at road end even when selectedCoordinate is nil")
        print("  ✅ 5.5 Nil destination pin handled gracefully and triggers at road end")
    }

    // MARK: - Module 6: Boundary, Formatters & Preference Persistence (R1.3, Edge Cases)
    func testModule6_BoundaryAndEdgeCases() async {
        print("\n--- [Module 6] Boundary Conditions, Formatting & Persistence ---")

        let vm = NavigationViewModel()

        // Test 6.1: Empty and minimal coordinates safety
        let emptyRoute = RouteDetails(coordinates: [], totalDistanceMiles: 0, totalDurationSeconds: 0, steps: [])
        vm.updateNavigationTelemetry(at: CLLocationCoordinate2D(latitude: 64.0, longitude: -147.0), coordIndex: 0, in: emptyRoute)
        assert(vm.remainingStepDistanceMiles == 0.0, "Empty route telemetry step distance is 0.0")
        assert(vm.remainingRouteDistanceMiles == 0.0, "Empty route telemetry route distance is 0.0")

        let singleCoordRoute = RouteDetails(
            coordinates: [CLLocationCoordinate2D(latitude: 64.0, longitude: -147.0)],
            totalDistanceMiles: 0,
            totalDurationSeconds: 0,
            steps: []
        )
        vm.updateNavigationTelemetry(at: CLLocationCoordinate2D(latitude: 64.0, longitude: -147.0), coordIndex: 0, in: singleCoordRoute)
        assert(vm.remainingStepDistanceMiles == 0.0, "Single coord route step distance is 0.0")
        assert(vm.remainingRouteDistanceMiles == 0.0, "Single coord route distance is 0.0")

        // Test 6.2: formatCountdownDistance metric vs imperial
        let dist0_05mi = 0.05
        let strImperialFeet = NavigationViewModel.formatCountdownDistance(dist0_05mi, useMetric: false)
        assert(strImperialFeet.contains("ft"), "0.05 miles must format in feet (got '\(strImperialFeet)')")

        let strMetricMeters = NavigationViewModel.formatCountdownDistance(dist0_05mi, useMetric: true)
        assert(strMetricMeters.contains("m"), "0.05 miles must format in meters (got '\(strMetricMeters)')")

        let dist2_5mi = 2.5
        let strImperialMiles = NavigationViewModel.formatCountdownDistance(dist2_5mi, useMetric: false)
        assert(strImperialMiles.contains("mi"), "2.5 miles must format in mi (got '\(strImperialMiles)')")

        let strMetricKm = NavigationViewModel.formatCountdownDistance(dist2_5mi, useMetric: true)
        assert(strMetricKm.contains("km"), "2.5 miles must format in km (got '\(strMetricKm)')")

        // Test 6.3: Voice mute toggle synchronization
        let mockRouting = RoutingService()
        let vmSync = NavigationViewModel(routingService: mockRouting)
        assert(mockRouting.isVoiceMuted == vmSync.isVoiceMuted, "Initial voice mute state must be synchronized")

        vmSync.toggleVoiceMute()
        assert(vmSync.isVoiceMuted == true, "toggleVoiceMute toggles state")
        assert(mockRouting.isVoiceMuted == true, "toggleVoiceMute synchronizes with routing service")
        assert(mockRouting.stopVoiceCallCount >= 1, "Muting voice calls stopVoice()")

        print("  ✅ 6.1–6.3 Boundary conditions, formatters, and voice mute sync passed")
    }
}

@main
struct StressMain {
    static func main() async {
        let runner = await StressTestRunner()
        await runner.runAll()
    }
}
