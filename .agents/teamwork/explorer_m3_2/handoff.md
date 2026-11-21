# Handoff Report: Navigation Telemetry, Step Progression, and Simulation Loop (R2.1, R2.2, R2.3)

**Agent**: `explorer_m3_2` (Teamwork Explorer)  
**Parent**: `353a2eeb-3a48-4ff7-be7e-6c7ece6b589d`  
**Milestone**: M3  
**Status**: COMPLETE (Hard Handoff)

---

## 1. Observation

1. **Unclamped Forward Search in `ContentView.swift` (lines 984–985)**:
   ```swift
   let searchStart = max(0, currentCoordIndex - 5)
   let searchEnd = min(coords.count - 1, currentCoordIndex + 50)
   ```
   Direct observation: In `MyOfflineMapApp/Sources/ContentView.swift:985`, `searchEnd` unconditionally projects 50 coordinates forward along the polyline regardless of the current maneuver's extent. In `TestGeometries.makeSwitchbackRoute()`, Step 0 (indices 0..10) runs parallel to Step 2 (indices 14..24) separated by 14.3 meters. At vertex 3 in Step 0, searching up to index 53 scans segment 21 in Step 2. GPS noise or proximity selects index 21 (`minSegDist < 40.0`), setting `currentCoordIndex = 21`. Because line 1006 tests `currentCoordIndex >= currentStep.endIndex` (21 >= 10), `currentStepIndex` immediately jumps prematurely.

2. **Distance Reversal Fallback in `ContentView.swift` (lines 1042–1045)**:
   ```swift
   } else if stepEnd < coords.count {
       stepDistMeters = segmentDistanceMeters(p1: userCoord, p2: coords[stepEnd])
   }
   self.remainingStepDistanceMiles = max(0.0, stepDistMeters * 0.000621371)
   ```
   Direct observation: In `MyOfflineMapApp/Sources/ContentView.swift:1042`, when `clampedIndex >= stepEnd`, execution falls into `else if stepEnd < coords.count` and calculates Euclidean distance from `userCoord` back to `coords[stepEnd]`. As the vehicle drives past `stepEnd`, this distance increases from 0m to 50m+, reversing the countdown. Furthermore, line 1060 (`else if let last = coords.last { routeDistMeters = segmentDistanceMeters(p1: userCoord, p2: last) }`) causes `remainingRouteDistanceMiles` to reopen and count upward when the user drives past the destination.

3. **Single `if` Step Advance in `ContentView.swift` (lines 1315–1321)**:
   ```swift
   if !details.steps.isEmpty && currentStepIndex < details.steps.count - 1 {
       let nextStep = details.steps[currentStepIndex + 1]
       if currentCoordIndex >= nextStep.startIndex {
           currentStepIndex += 1
           hasAnnouncedAdvanceTurn = false
           routingService.speakTurnInstruction(nextStep.instruction, stepId: currentStepIndex * 10 + 2)
       } ...
   }
   ```
   Direct observation: In `MyOfflineMapApp/Sources/ContentView.swift:1315`, a single `if` statement executes per simulation tick. At 5x speed (`stepJump = 5`, lines 1297–1298), jumping from vertex 0 to 5 leaps over two maneuvers (Step 0: 0..2, Step 1: 2..4, Step 2: 4..8). The single `if` increments `currentStepIndex` to only 1, completely skipping Step 2's turn instruction and leaving `currentStepIndex` desynchronized from the car's actual coordinate at vertex 5.

4. **Reference Implementation & Passing Tests in E2E Suite**:
   Direct observation: Running `./Tests/E2ETests/run_e2e_tests.sh` executes 69 tests across Tiers 1–4, passing 100% (0.118s). Specifically:
   - `testT1_SwitchbackSearchClampingEliminatesPrematureStepAdvance` passes.
   - `testT1_MonotonicTelemetryCountdownDecreasesToZeroWithoutReversal` passes.
   - `testT1_MultiSpeedSimulationLoopAdvancesIntermediateManeuversAt5x` passes.
   - `testT2_ExactSwitchbackBoundaryClampingAtEndIndexPlusTwo` passes.
   - `testT2_UserPositionFarBeyondDestinationDoesNotReopenStepDistance` passes.

---

## 2. Logic Chain

1. **R2.1 Switchback Search Clamping**:
   - Observation 1 demonstrates that searching 50 coordinates forward spans multiple maneuvers across switchback tiers separated by only ~14 meters.
   - Restricting the search forward bound to the active step's `endIndex` eliminates scanning vertices that belong to future return tiers.
   - Adding a slack of `+ 2` vertices (`currentStepEnd + 2`) ensures that vehicles turning through the intersection corner do not get clipped by premature search truncation.
   - Clamping `searchEnd = min(coords.count - 1, max(currentCoordIndex + 1, currentStepEnd + 2))` guarantees that `searchEnd > searchStart` and prevents polyline index out-of-bounds errors.
   - Therefore, switchback jumping is eliminated while preserving smooth corner tracking.

2. **R2.2 Monotonic Telemetry Distance**:
   - Observation 2 demonstrates that computing `segmentDistanceMeters(userCoord, coords[stepEnd])` when `clampedIndex >= stepEnd` measures Euclidean distance backwards to the maneuver vertex, which grows as the vehicle moves forward.
   - When `clampedIndex >= stepEnd`, the vehicle has already reached or passed the maneuver point. The remaining distance for this maneuver is physically and logically 0.0.
   - Replacing the fallback branch with `stepDistMeters = 0.0` when `clampedIndex >= stepEnd` guarantees that `remainingStepDistanceMiles` decreases monotonically towards zero and never reverses.
   - Similarly, setting `routeDistMeters = 0.0` when `clampedIndex >= coords.count - 1` ensures destination arrival does not reopen route distance.

3. **R2.3 Multi-Speed Simulation Progression**:
   - Observation 3 shows that multi-vertex jumps (2x and 5x speeds) can leap across multiple short steps in a single 120ms tick, but a single `if` can only advance `currentStepIndex` by at most 1.
   - Replacing the single `if` with a `while !details.steps.isEmpty && currentStepIndex < details.steps.count - 1` loop allows `currentStepIndex` to catch up to the true coordinate index across all traversed steps.
   - Inside each iteration, calling `speakTurnInstruction(nextStep.instruction, stepId: currentStepIndex * 10 + 2)` guarantees that all intermediate maneuvers are announced.
   - Because `currentStepIndex` strictly increases each iteration towards `details.steps.count - 1`, the loop is guaranteed to terminate in $O(\text{steps.count})$ steps.

---

## 3. Caveats

1. **State Relocation to `NavigationViewModel`**:
   - As explored in parallel by `explorer_m3_1`, these three functions (`updateCurrentStepForLiveLocation`, `updateNavigationTelemetry`, `advanceSimulationStep`) belong in `NavigationViewModel.swift`.
   - `ContentView.swift` must retain forwarding wrappers so that existing tests in `RemediationTests.swift` that call `view.updateNavigationTelemetry(...)` and `view.advanceSimulationStep()` continue to compile and pass until Milestone 4.
2. **Audio Prompt Queuing**:
   - In 5x simulation speed, traversing multiple steps in a single tick triggers rapid consecutive calls to `speakTurnInstruction`. `RoutingService`'s deduplication and speech generation lock handle this cleanly, but high-speed simulation will speak the final traversed instruction if audio synthesis takes longer than the tick interval.
3. **Dual-Point Arrival Integration**:
   - Arrival detection in `updateCurrentStepForLiveLocation` integrates dual-point checks (`coords.last` and `selectedCoordinate`) as explored by `explorer_m3_3`. The code snippet in Section 5 includes this dual check for complete coherence.

---

## 4. Conclusion

1. **R2.1**: Implement clamped coordinate search in `updateCurrentStepForLiveLocation`:
   `let currentStepEnd = (!details.steps.isEmpty && currentStepIndex < details.steps.count) ? details.steps[currentStepIndex].endIndex : coords.count - 1`
   `let searchEnd = min(coords.count - 1, max(currentCoordIndex + 1, currentStepEnd + 2))`
2. **R2.2**: Implement monotonic distance calculation in `updateNavigationTelemetry`:
   When `clampedIndex >= stepEnd`, evaluate `stepDistMeters = 0.0`.
   When `clampedIndex >= coords.count - 1`, evaluate `routeDistMeters = 0.0`.
3. **R2.3**: Replace single `if` with `while` loop in `advanceSimulationStep()`:
   `while !details.steps.isEmpty && currentStepIndex < details.steps.count - 1 { ... currentStepIndex += 1 ... }`
4. The full code implementation is documented in `.agents/teamwork/explorer_m3_2/analysis.md` and ready for integration by `worker_m3`.

---

## 5. Verification Method

1. **Run Full E2E Test Suite**:
   ```bash
   ./Tests/E2ETests/run_e2e_tests.sh
   ```
   Expected: 69 / 69 passing (0 failing).
   Specifically verifies:
   - `NavigationTelemetryTests.testT1_SwitchbackSearchClampingEliminatesPrematureStepAdvance`
   - `NavigationTelemetryTests.testT1_MonotonicTelemetryCountdownDecreasesToZeroWithoutReversal`
   - `NavigationTelemetryTests.testT1_MultiSpeedSimulationLoopAdvancesIntermediateManeuversAt5x`
   - `TelemetryBoundaryTests.testT2_ExactSwitchbackBoundaryClampingAtEndIndexPlusTwo`
   - `TelemetryBoundaryTests.testT2_UserPositionFarBeyondDestinationDoesNotReopenStepDistance`
   - `SimulationBoundaryTests.testT2_SimulationAtTwoXLandingExactlyOnStepBoundary`
   - `SimulationBoundaryTests.testT2_SimulationAtFiveXExceedingPolylineLengthCompletesArrival`

2. **Code Inspection**:
   - Inspect `MyOfflineMapApp/Sources/NavigationViewModel.swift` to ensure forward search upper bound is clamped to `currentStepEnd + 2`.
   - Inspect `updateNavigationTelemetry` to ensure `stepDistMeters = 0.0` when `clampedIndex >= stepEnd` and no fallback to `segmentDistanceMeters(p1: userCoord, p2: coords[stepEnd])`.
   - Inspect `advanceSimulationStep` to ensure `while` loop is used for maneuver progression.

3. **Invalidation Conditions**:
   - If `remainingStepDistanceMiles` increases after reaching `stepEnd`, the monotonic countdown fix has regressed.
   - If 5x simulation skips intermediate turn instructions, the `while` loop has regressed to a single `if`.
   - If switchback navigation advances step index before reaching the hairpin apex, the clamping bounds have regressed.
