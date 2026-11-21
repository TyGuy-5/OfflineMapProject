# Milestone 3 Challenger Handoff Report: ViewModel State Machine, Persistence, and Forwarding Contracts

**Agent**: `challenger_m3_2` (teamwork_challenger: critic, specialist)  
**Parent**: `353a2eeb-3a48-4ff7-be7e-6c7ece6b589d`  
**Date**: 2026-11-07T07:45:00Z  
**Milestone**: Milestone 3 — Navigation ViewModel Architecture & Telemetry  
**Status**: REVIEW COMPLETE — REQUEST_CHANGES  
**Stress Report**: `.agents/teamwork/challenger_m3_2/challenge_report.md`  
**Handoff Report**: `.agents/teamwork/challenger_m3_2/handoff.md`  

---

## 1. Observation

1. **State Machine & Telemetry Empirical Test Results**:
   - Developed and compiled a comprehensive 79-assertion Swift test harness (`/tmp/stress_runner`) exercising `NavigationViewModel.swift` state transitions across all `MapAppMode` values (`.explore`, `.searchList`, `.placeDetail`, `.routePreview`, `.navigation`).
   - All state transitions executed flawlessly:
     - Explore -> SearchList via `handleQueryChange("Fairbanks")` (`appMode == .searchList`, `isSearching == true`).
     - SearchList -> Explore via `handleQueryChange("F")` and `dismissSearch()` (`appMode == .explore`).
     - Explore -> PlaceDetail via `selectPlace(place)` (`appMode == .placeDetail`).
     - PlaceDetail -> RoutePreview via `calculateRouteTo(place)` (`appMode == .routePreview`).
     - RoutePreview -> Navigation via `startNavigation()` and `startSimulatedDrive()`.
     - EndNavigation / ResetToExplore transitions: `endNavigation()` returns to `.routePreview` if route exists; `resetToExplore()` unconditionally resets all state to `.explore`.
     - Dual-point arrival detection (R2.5): Successfully triggers arrival at setback destination coordinate within 25.0m.
     - Switchback search clamping (R2.1): Forward search index clamped to `currentStepEnd + 2` slack, preventing jump across hairpin turns.
     - Monotonic telemetry countdown (R2.2): Step distance monotonically decreases and strictly evaluates to `0.0` at and past `stepEnd`.
     - Multi-speed simulation loop (R2.3): `while` loop successfully advances and announces all intermediate maneuvers during 5x multi-vertex jumps.
     - Hardware GPS start fix (R2.4): Valid live GPS fixes preserve live coordinate and course; stale (> 15s) and degraded (>= 65m) fixes fall back to route start.

2. **Preference Persistence (`@AppStorage`)**:
   - `"useMetric"` and `"isVoiceMuted"` correctly write to and read from `UserDefaults.standard`.
   - Modifying `isVoiceMuted` synchronizes `routingService.isVoiceMuted` and calls `routingService.stopVoice()`.
   - Initializing `NavigationViewModel` synchronizes persisted `isVoiceMuted` to `RoutingService`.

3. **Source String Inspection Contracts (`RemediationTests.swift`)**:
   - Verified verbatim presence of all 10 source string inspection contracts in `MyOfflineMapApp/Sources/ContentView.swift`:
     1. `func dismissSearch()`: count = 1 (PASS)
     2. `func clearSearch()`: count = 1 (PASS)
     3. `func resetToExplore()`: count = 1 (PASS)
     4. `searchTask?.cancel()`: count = 4 (PASS, >= 4)
     5. `isProgrammaticTextChange = true`: count = 1 (PASS)
     6. `if isProgrammaticTextChange`: count = 1 (PASS)
     7. `guard isWithinSupportedRegion(location.coordinate) else { return }`: present (PASS)
     8. `if !isNavigating && !isSimulating`: present (PASS)
     9. `testAdversarial03` string 1 (`if destinationText != category {\n            isProgrammaticTextChange = true\n            destinationText = category\n        }`): present (PASS)
     10. `testAdversarial03` string 2 (`if isProgrammaticTextChange {\n                            isProgrammaticTextChange = false\n                            return\n                        }`): present (PASS)

4. **Full E2E Test Suite Execution**:
   - Ran `./Tests/E2ETests/run_e2e_tests.sh`:
     - Duration: 0.116s.
     - Result: 69/69 PASS (Tiers 1–4, 100% green).

5. **Direct Swift Compiler Verification of `ContentView.swift` (Critical Defect)**:
   - When compiling `MyOfflineMapApp/Sources/ContentView.swift` with Swift, the compiler emitted 10 fatal errors:
     ```
     MyOfflineMapApp/Sources/ContentView.swift:209:13: error: cannot assign to property: 'self' is immutable
      208 |         if destinationText != category {
      209 |             isProgrammaticTextChange = true
          |             `- error: cannot assign to property: 'self' is immutable
      210 |             destinationText = category
     
     MyOfflineMapApp/Sources/ContentView.swift:210:13: error: cannot assign to property: 'self' is immutable
      209 |             isProgrammaticTextChange = true
      210 |             destinationText = category
          |             `- error: cannot assign to property: 'self' is immutable
     
     MyOfflineMapApp/Sources/ContentView.swift:388:29: error: cannot assign to property: 'self' is immutable
      386 |                     .onChange(of: destinationText) { _, newValue in
      387 |                         if isProgrammaticTextChange {
      388 |                             isProgrammaticTextChange = false
          |                             `- error: cannot assign to property: 'self' is immutable
     
     MyOfflineMapApp/Sources/ContentView.swift:875:21: error: cannot assign to property: 'self' is immutable
      874 |                 Button(action: {
      875 |                     isHudMode = true
          |                     `- error: cannot assign to property: 'self' is immutable
     
     MyOfflineMapApp/Sources/ContentView.swift:993:38: error: cannot assign to property: 'self' is immutable
      993 |                 Button(action: { isHudMode = false }) {
          |                                  `- error: cannot assign to property: 'self' is immutable
     ```
   - In `MyOfflineMapApp/Sources/ContentView.swift` (lines 20–168), 37 forwarding properties are declared with bare `set { viewModel.<prop> = newValue }`.
   - Because `ContentView` is a `struct`, bare `set` defines a `mutating` setter.
   - Non-mutating methods (`func searchCategory(_:)`) and closures (`.onChange`, `Button(action:)`) cannot call mutating setters on an immutable `self`.
   - Testing with `nonmutating set { viewModel.<prop> = newValue }` in `/tmp/ContentView_nonmutating.swift` resulted in **0 immutability errors**.

---

## 2. Logic Chain

1. From Observation 1, `NavigationViewModel.swift` successfully implements all state transitions, dual-point arrival, switchback clamping, monotonic distance calculation, simulation catch-up loops, and GPS lifecycle logic.
2. From Observation 2, user preferences correctly persist in `UserDefaults.standard` and synchronize with `RoutingService`.
3. From Observation 3 and 4, all 10 source string inspection contracts and all 69 E2E tests pass.
4. However, from Observation 5:
   - `run_e2e_tests.sh` only tests mock domain models in `Tests/E2ETests/Support/TestHarness.swift` and does not compile `ContentView.swift`.
   - The worker only verified `ContentView.swift` using Python string matching without executing a Swift compiler check on `ContentView.swift`.
   - In Swift, a struct computed property with `set { ... }` defaults to `mutating set`.
   - Because `searchCategory` is non-mutating and closures in SwiftUI `body` capture `self` as a value, calling mutating setters causes the compiler to reject the file with 10 `cannot assign to property: 'self' is immutable` errors.
   - Declaring the setters as `nonmutating set { viewModel.<prop> = newValue }` cleanly resolves the issue because `viewModel` is a reference type (`@StateObject` / `@MainActor class`).
5. Therefore, despite excellent business logic in `NavigationViewModel.swift`, Milestone 3 cannot be approved until `ContentView.swift` is fixed to use `nonmutating set` on its forwarding properties so that production code compiles cleanly.

---

## 3. Caveats

- As required by the challenger role, challenger did not edit production files (`ContentView.swift` or `NavigationViewModel.swift`). The proposed fix was empirically tested and verified in `/tmp/ContentView_nonmutating.swift`.
- No other regressions or functional bugs were found across requirements R1.1, R1.2, R1.3, and R2.1–R2.5.

---

## 4. Conclusion

**Verdict**: **REQUEST_CHANGES**

`NavigationViewModel.swift` satisfies all functional, architectural, and adversarial requirements. However, `ContentView.swift` has a fatal Swift compilation defect due to 37 mutating computed property setters on a struct.

**Required Action from Worker**:
In `MyOfflineMapApp/Sources/ContentView.swift`:
Replace `set {` with `nonmutating set {` on all forwarding properties in lines 20–168 (e.g. `appMode`, `isHudMode`, `destinationText`, `isProgrammaticTextChange`, etc.).

---

## 5. Verification Method

To verify the defect and the resolution independently:

1. **Demonstrate Compiler Defect**:
   ```bash
   python3 -c '
   import subprocess
   cmd = [
       "swiftc", "-module-cache-path", "/tmp/clang-cache",
       "-c", "-parse-as-library",
       "/tmp/TestStubs.swift", "/tmp/MapViewStub.swift",
       "MyOfflineMapApp/Sources/NavigationViewModel.swift",
       "MyOfflineMapApp/Sources/ContentView.swift"
   ]
   res = subprocess.run(cmd, capture_output=True, text=True, env={"TMPDIR": "/tmp"})
   errors = [l for l in res.stderr.splitlines() if "cannot assign to property: '\''self'\'' is immutable" in l]
   print(f"Found {len(errors)} immutability errors in ContentView.swift")
   for err in errors:
       print(" ", err)
   '
   ```
   **Result**: 10 fatal `cannot assign to property: 'self' is immutable` errors found.

2. **Verify That `nonmutating set` Eliminates All Errors**:
   ```bash
   python3 -c '
   import subprocess
   cmd = [
       "swiftc", "-module-cache-path", "/tmp/clang-cache",
       "-c", "-parse-as-library",
       "/tmp/TestStubs.swift", "/tmp/MapViewStub.swift",
       "MyOfflineMapApp/Sources/NavigationViewModel.swift",
       "/tmp/ContentView_nonmutating.swift"
   ]
   res = subprocess.run(cmd, capture_output=True, text=True, env={"TMPDIR": "/tmp"})
   errors = [l for l in res.stderr.splitlines() if "cannot assign to property: '\''self'\'' is immutable" in l]
   print(f"Found {len(errors)} immutability errors in ContentView_nonmutating.swift")
   '
   ```
   **Result**: 0 errors found.

3. **Verify All 10 Source Inspection Contracts**:
   ```bash
   python3 -c '\''
   content = open("MyOfflineMapApp/Sources/ContentView.swift").read()
   checks = [
       ("func dismissSearch()", content.count("func dismissSearch()") == 1),
       ("func clearSearch()", content.count("func clearSearch()") == 1),
       ("func resetToExplore()", content.count("func resetToExplore()") == 1),
       ("searchTask?.cancel() >= 4", content.count("searchTask?.cancel()") >= 4),
       ("isProgrammaticTextChange = true", content.count("isProgrammaticTextChange = true") >= 1),
       ("if isProgrammaticTextChange", content.count("if isProgrammaticTextChange") >= 1),
       ("guard isWithinSupportedRegion", "guard isWithinSupportedRegion(location.coordinate) else { return }" in content),
       ("if !isNavigating && !isSimulating", "if !isNavigating && !isSimulating" in content),
       ("testAdversarial03 string 1", "if destinationText != category {\n            isProgrammaticTextChange = true\n            destinationText = category\n        }" in content),
       ("testAdversarial03 string 2", "if isProgrammaticTextChange {\n                            isProgrammaticTextChange = false\n                            return\n                        }" in content),
   ]
   for name, ok in checks:
       assert ok, f"Failed: {name}"
   print("ALL 10 SOURCE CONTRACT CHECKS PASSED")
   '\''
   ```

4. **Run E2E Tests**:
   ```bash
   ./Tests/E2ETests/run_e2e_tests.sh
   ```
   **Result**: 69/69 PASS (100%).
