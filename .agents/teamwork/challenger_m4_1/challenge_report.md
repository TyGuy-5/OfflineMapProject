# Challenge Report — Milestone 4: Test Suite Modernization & Build Config

**Agent**: `challenger_m4_1` (Role: critic, specialist)  
**Parent Agent**: `353a2eeb-3a48-4ff7-be7e-6c7ece6b589d`  
**Date**: 2026-11-07T10:40:00Z  
**Verdict**: **REQUEST_CHANGES**  

---

## 1. Executive Summary

Milestone 4 aimed to modernize `RemediationTests.swift` and `MyOfflineMapAppTests.swift` by refactoring tests to directly exercise `NavigationViewModel`, removing fragile `#filePath` ASCII inspections, removing undeclared `import ValhallaConfigModels`, and sanitizing documentation files.

While structural audits show:
- `#filePath` in `RemediationTests.swift` is **0** (PASS)
- `ContentView()` in `RemediationTests.swift` is **0** (PASS)
- `ValhallaConfigModels` in `MyOfflineMapAppTests.swift` is **0** (PASS)
- Hardcoded host volume paths in `DOCUMENTATION.md` & `AUDIT_REPORT.md` is **0** (PASS)
- `./Tests/E2ETests/run_e2e_tests.sh` passes **69/69** (PASS)
- Standalone compile via `swiftc` succeeds with **0 errors** (PASS)

**CRITICAL FINDING**: An empirical stress harness executing the exact logic in `RemediationTests.swift` revealed a runtime assertion failure in `testAdversarial01_OutOfRegionGPSHandling()` (lines 645–684). The test author configured a 2-coordinate test route ending at `(64.8440, -147.7210)` and then delivered an in-region GPS fix at `(64.8438, -147.7212)`. Because the Euclidean distance between these coordinates is **24.04857 meters** (< the 25.0m arrival threshold in `updateCurrentStepForLiveLocation`), the arrival detector triggers, calls `endNavigation()`, and resets `simulatedUserCoordinate` to `nil`. As a result, line 682 (`XCTAssertEqual(vm.simulatedUserCoordinate?.latitude ?? 0, 64.8438, accuracy: 0.0001)`) evaluates `0.0 == 64.8438` and **fails at runtime**.

---

## 2. Empirical Verification Matrix

| Area | Contract / Requirement | Empirical Challenge Result | Status |
|---|---|---|---|
| **R6.1 Text Removal** | Zero `#filePath` occurrences in `RemediationTests.swift` | Grep count = 0 | ✅ PASS |
| **R6.1 View Struct Removal** | Zero unmounted `ContentView()` mutations in `RemediationTests.swift` | Grep count = 0 | ✅ PASS |
| **R6.2 Dependency Cleanliness** | Zero `ValhallaConfigModels` in `MyOfflineMapAppTests.swift` | Grep count = 0 | ✅ PASS |
| **R6.4 Path Portability** | Zero `/Volumes/Extended Hard Drive...` or machine simulator UDIDs in docs | Regex audit across all lines = 0 | ✅ PASS |
| **OfflineDataManager** | Exactly 1 `#filePath` preserved for simulator fallback | Grep count = 1 | ✅ PASS |
| **E2E Test Runner** | 69 tests across Tiers 1–4 pass via `run_e2e_tests.sh` | 69/69 pass in 0.107s | ✅ PASS |
| **R1.1 / R6.1 Search Task** | Search cancellation across `dismissSearch`, `clearSearch`, `resetToExplore` | Verified in standalone runner (100 rapid queries) | ✅ PASS |
| **R1.1 / R6.1 Category Dedup** | Programmatic text change flag asserted once, deduplicated on repeat tap | Verified in standalone runner across 7 categories | ✅ PASS |
| **R1.3 / R6.1 Unit Toggling** | Unit toggle (`useMetric`) preserves active simulation progress & converts units | Verified in standalone runner (100x toggle stress, 45 mph -> 72 km/h) | ✅ PASS |
| **R2.1 Clamping** | Coordinate search clamped to `currentStep.endIndex + 2` on switchbacks | Verified in standalone runner (`currentStepIndex` retained at 0) | ✅ PASS |
| **R2.2 Monotonic Telemetry** | Monotonic countdown to 0.0 at `stepEnd`, stays 0.0 past `stepEnd` | Verified in standalone runner | ✅ PASS |
| **R2.3 Multi-Speed Loop** | `advanceSimulationStep()` advances multiple maneuvers at 5x via `while` loop | Verified in standalone runner (`currentCoordIndex`: 0->5->10, `currentStepIndex`: 0->2->3) | ✅ PASS |
| **R2.4 GPS Start Fix** | Hardware GPS retained at start when accurate (<65m); fallback when degraded | Verified in standalone runner | ✅ PASS |
| **R2.5 Dual-Point Arrival** | Setback destination pin arrival detection within 25m/40m | Verified in standalone runner | ✅ PASS |
| **R6.1 Test Execution** | `testAdversarial01_OutOfRegionGPSHandling()` in `RemediationTests.swift` | **FAILS at line 682**: `simulatedUserCoordinate` is `nil` (0.0 != 64.8438) due to accidental arrival | ❌ **FAIL** |

---

## 3. Detailed Failure Analysis: Accidental Arrival in `testAdversarial01`

### 3.1 Observation
In `MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift` lines 643–684:
```swift
// 6. Behavioral verification: handleLocationUpdate drops out-of-region fixes without corrupting state
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

// Deliver out-of-region location fix (San Francisco)
let outOfRegionFix = CLLocation(...)
vm.handleLocationUpdate(outOfRegionFix)
XCTAssertEqual(vm.simulatedUserCoordinate?.latitude, initialPuck.latitude, ...)

// Deliver valid in-region location fix (Fairbanks downtown)
let inRegionFix = CLLocation(
    coordinate: CLLocationCoordinate2D(latitude: 64.8438, longitude: -147.7212),
    altitude: 10,
    horizontalAccuracy: 5.0,
    verticalAccuracy: 5.0,
    timestamp: Date()
)
vm.handleLocationUpdate(inRegionFix)
XCTAssertEqual(vm.simulatedUserCoordinate?.latitude ?? 0, 64.8438, accuracy: 0.0001, "Valid in-region fix must update simulatedUserCoordinate")
vm.endNavigation()
```

### 3.2 Root Cause & Mathematical Proof
1. `vm.handleLocationUpdate(inRegionFix)` executes line 238 of `NavigationViewModel.swift`:
   ```swift
   simulatedUserCoordinate = location.coordinate // 64.8438, -147.7212
   ```
2. Line 246 executes:
   ```swift
   updateCurrentStepForLiveLocation(location.coordinate, in: details)
   ```
3. In `updateCurrentStepForLiveLocation`:
   ```swift
   if coords.count >= 2 {
       let distToRoadEnd = segmentDistanceMeters(p1: userCoord, p2: coords.last!)
       ...
       if distToRoadEnd < 25.0 || distToPin < 25.0 || (isNearEnd && (distToRoadEnd < 40.0 || distToPin < 40.0)) {
           routingService.speakTurnInstruction("You have arrived at your destination.", force: true)
           routeDetails = nil
           routeCoordinates = nil
           endNavigation()
           return
       }
   }
   ```
4. Computing Euclidean distance between `userCoord` `(64.8438, -147.7212)` and `coords.last!` `(64.8440, -147.7210)`:
   - `dy = (64.8440 - 64.8438) * 110540.0 = 22.108 m`
   - `dx = (-147.7210 - (-147.7212)) * 111320.0 * cos(64.8438 * pi / 180) = 9.464 m`
   - `distToRoadEnd = sqrt(22.108^2 + 9.464^2) = 24.04857 m`
5. Since `24.04857 < 25.0`, the arrival condition evaluates to `true`.
6. `endNavigation()` is called, which executes:
   ```swift
   isNavigating = false
   simulatedUserCoordinate = nil
   ```
7. When the test asserts:
   ```swift
   XCTAssertEqual(vm.simulatedUserCoordinate?.latitude ?? 0, 64.8438, accuracy: 0.0001)
   ```
   `vm.simulatedUserCoordinate` is `nil`, so `vm.simulatedUserCoordinate?.latitude ?? 0` is `0.0`.
   The assertion fails: `0.0 != 64.8438`.

### 3.3 Mitigation & Fix for `worker_m4`
In `MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift` line 646:
Change `coords` to a route whose destination coordinate is sufficiently distant (e.g. > 40m) so that the live in-region GPS fix does not trigger arrival:
```swift
// Replace line 646:
        let coords = [
            CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215),
            CLLocationCoordinate2D(latitude: 64.8500, longitude: -147.7210) // ~685m away, avoiding premature arrival
        ]
```
With `64.8500`, `distToRoadEnd = 685.3m`, arrival is not triggered, `simulatedUserCoordinate` remains `64.8438`, and the test passes cleanly.

---

## 4. Final Verdict

**REQUEST_CHANGES**

Worker `worker_m4` must apply the 1-line coordinate fix in `RemediationTests.swift:646` so that `testAdversarial01_OutOfRegionGPSHandling()` passes at runtime during live test execution.
