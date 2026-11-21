# Milestone 4 Explorer Report: RemediationTests Modernization (R6.1)

**Agent**: `explorer_m4_1` (teamwork_explorer: investigation, synthesis)  
**Parent Agent**: `353a2eeb-3a48-4ff7-be7e-6c7ece6b589d`  
**Date**: 2026-11-07T10:16:00Z  
**Target File**: `MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift`  
**Working Directory**: `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m4_1`  
**Handoff Type**: Hard (Task Complete)  

---

## 1. Observation

### 1.1 Existing Structure of `RemediationTests.swift`
`MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift` is a 2096-line test file containing three test suites and 44 test methods:
1. `final class RemediationTests: XCTestCase` (lines 10–1495): 21 numbered tests (`test01`–`test21`) + 12 adversarial tests (`testAdversarial01`–`testAdversarial12`) = 33 test methods.
2. `final class ConcurrencyAudioStressTests: XCTestCase` (lines 1498–1799): 7 concurrency & audio safety test methods.
3. `final class LocationManagerAdversarialStressTests: XCTestCase` (lines 1802–2090): 4 location manager adversarial stress test methods.

### 1.2 Inventory of Unmounted `ContentView()` Instantiations
`RemediationTests.swift` instantiates `ContentView()` on unmounted View structs at 12 distinct locations:
- Line 15 (`test01_OutOfRegionGPSHandling`): `let view = ContentView()`
- Line 59 (`test02_InFlightSearchTaskCancellation`): `var view = ContentView()`
- Line 111 (`test03_CategorySearchSingleInvocation`): `var view = ContentView()`
- Line 137 (`test04_RouteTelemetryCalculationZeroStepsSafety`): `var view = ContentView()`
- Line 183 (`test05_DistanceUnitTogglingPreservesSimulationProgress`): `let view = ContentView()`
- Line 585 (`testAdversarial01_OutOfRegionGPSHandling`): `let view = ContentView()`
- Line 670 (`testAdversarial02_SearchTaskLifecycle`): `var view = ContentView()`
- Line 715 (`testAdversarial03_CategorySearchDeduplication`): `var view = ContentView()`
- Line 750 (`testAdversarial04_RouteTelemetryZeroOneAndLargeStepArrays`): `var view = ContentView()`
- Line 862 (`testAdversarial05_SimulationMetricTogglingProgressPreservation`): `let view = ContentView()`
- Line 1289 (`test18_SimulationStepProgressionBoundsSafety`): `var view = ContentView()`
- Line 1349 (`test19_TelemetryOutOfBoundsEdgeCases`): `var view = ContentView()`

**Flaw**: In SwiftUI, mutating state on an unmounted struct (`var view = ContentView()`, `view.currentCoordIndex = 0`, etc.) bypasses view rendering cycles, breaks `@StateObject` lifecycle assumptions, and requires 37 `nonmutating set` forwarding stubs in `ContentView.swift` purely to satisfy tests.

### 1.3 Inventory of `#filePath` and Source Code File String Inspection
`RemediationTests.swift` uses `#filePath` to inspect source files on disk at 10 distinct locations:
1. Line 81 (`test02_InFlightSearchTaskCancellation`):
   ```swift
   let contentViewURL = URL(fileURLWithPath: #filePath)
       .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
       .appendingPathComponent("Sources/ContentView.swift")
   let content = try String(contentsOf: contentViewURL, encoding: .utf8)
   XCTAssertTrue(content.contains("func dismissSearch()"))
   XCTAssertTrue(content.contains("func clearSearch()"))
   XCTAssertTrue(content.contains("func resetToExplore()"))
   let occurrences = content.components(separatedBy: "searchTask?.cancel()").count - 1
   XCTAssertTrue(occurrences >= 4)
   ```
2. Line 118 (`test03_CategorySearchSingleInvocation`):
   ```swift
   let contentViewURL = URL(fileURLWithPath: #filePath)...appendingPathComponent("Sources/ContentView.swift")
   let content = try String(contentsOf: contentViewURL, encoding: .utf8)
   XCTAssertTrue(content.contains("isProgrammaticTextChange = true"))
   XCTAssertTrue(content.contains("if isProgrammaticTextChange"))
   ```
3. Line 191 (`test05_DistanceUnitTogglingPreservesSimulationProgress`):
   ```swift
   let contentViewURL = URL(fileURLWithPath: #filePath)...appendingPathComponent("Sources/ContentView.swift")
   let content = try String(contentsOf: contentViewURL, encoding: .utf8)
   XCTAssertTrue(content.contains("if !isNavigating && !isSimulating") || content.contains("if !isSimulating && !isNavigating"))
   ```
4. Line 315 (`test09_ProjectConfigurationAndDependencies`):
   ```swift
   let projectYmlURL = URL(fileURLWithPath: #filePath)...appendingPathComponent("project.yml")
   let projectYmlContent = try String(contentsOf: projectYmlURL, encoding: .utf8)
   XCTAssertTrue(projectYmlContent.contains("INFOPLIST_KEY_NSLocationTemporaryUsageDescriptionDictionary"))
   XCTAssertTrue(projectYmlContent.contains("NavigationAccuracy"))
   XCTAssertFalse(projectYmlContent.contains("product: ValhallaConfigModels"))
   ```
5. Line 333 (`test09_ProjectConfigurationAndDependencies`):
   ```swift
   let infoPlistURL = URL(fileURLWithPath: #filePath)...appendingPathComponent("Resources/Info.plist")
   let infoPlistData = try Data(contentsOf: infoPlistURL)
   ```
6. Line 439 (`test12_PhysicalDeviceHostPathProbing`):
   ```swift
   let sourceURL = URL(fileURLWithPath: #filePath)...appendingPathComponent("Sources/OfflineDataManager.swift")
   let source = try String(contentsOf: sourceURL, encoding: .utf8)
   XCTAssertTrue(source.contains("targetEnvironment(simulator)") || source.contains("os(macOS)"))
   XCTAssertFalse(source.contains("#if DEBUG || targetEnvironment(simulator)"))
   ```
7. Line 655 (`testAdversarial01_OutOfRegionGPSHandling`):
   ```swift
   let contentViewURL = URL(fileURLWithPath: #filePath)...appendingPathComponent("Sources/ContentView.swift")
   let content = try String(contentsOf: contentViewURL, encoding: .utf8)
   XCTAssertTrue(content.contains("guard isWithinSupportedRegion(location.coordinate) else { return }"))
   ```
8. Line 731 (`testAdversarial03_CategorySearchDeduplication`):
   ```swift
   let contentViewURL = URL(fileURLWithPath: #filePath)...appendingPathComponent("Sources/ContentView.swift")
   let content = try String(contentsOf: contentViewURL, encoding: .utf8)
   XCTAssertTrue(content.contains("if destinationText != category {\n            isProgrammaticTextChange = true\n            destinationText = category\n        }"))
   XCTAssertTrue(content.contains("if isProgrammaticTextChange {\n                            isProgrammaticTextChange = false\n                            return\n                        }"))
   ```
9. Line 865 (`testAdversarial05_SimulationMetricTogglingProgressPreservation`):
   ```swift
   let contentViewURL = URL(fileURLWithPath: #filePath)...appendingPathComponent("Sources/ContentView.swift")
   let content = try String(contentsOf: contentViewURL, encoding: .utf8)
   XCTAssertTrue(content.contains("if !isNavigating && !isSimulating") || content.contains("if !isSimulating && !isNavigating"))
   ```
10. Line 1122 (`testAdversarial09_PhysicalDeviceHostPathGuardElision`):
    ```swift
    let sourceURL = URL(fileURLWithPath: #filePath)...appendingPathComponent("Sources/OfflineDataManager.swift")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let filePathMatches = source.components(separatedBy: "#filePath").count - 1
    XCTAssertEqual(filePathMatches, 1)
    ```
11. Line 1243 (`testAdversarial11_AudioSessionDeactivationConcurrencyStress`):
    ```swift
    let sourceURL = URL(fileURLWithPath: #filePath)...appendingPathComponent("Sources/RoutingService.swift")
    if let source = try? String(contentsOf: sourceURL, encoding: .utf8) {
        XCTAssertTrue(source.contains("guard generation == currentGen else { return }"))
        XCTAssertTrue(source.contains("guard !self.speechSynthesizer.isSpeaking else { return }"))
    }
    ```

**Flaw**:
- Source-code file string matching does not test executable logic — it tests ASCII formatting. A trivial variable rename or indentation change breaks tests while the runtime behavior remains completely correct.
- `#filePath` resolves to developer host filesystem paths, which fail when executed on physical iOS devices or remote CI where the source checkout differs from the build-host compilation path.

---

## 2. Logic Chain

### 2.1 Why Direct `NavigationViewModel` Testing Is Superior
1. `NavigationViewModel` (`@MainActor public final class NavigationViewModel: ObservableObject`) was extracted in Milestone 3 specifically to encapsulate all state machine transitions, telemetry calculations, search cancellations, and simulation progressions into a dedicated, testable reference type.
2. In unit tests, `NavigationViewModel` can be instantiated directly: `let vm = NavigationViewModel()`. Because it is a class, modifying `@Published` properties, calling action methods, and inspecting internal state transitions is idiomatic and clean.
3. Every single contract previously checked by `#filePath` string inspection is directly observable via public properties or runtime behavioral assertions on `NavigationViewModel`:
   - `searchTask?.cancel()`: Calling `vm.dismissSearch()`, `vm.clearSearch()`, `vm.resetToExplore()` directly cancels `vm.searchTask` (`task.isCancelled == true`), nils `vm.searchTask`, sets `vm.isSearching = false`, and resets `vm.appMode = .explore`.
   - `isProgrammaticTextChange`: Calling `vm.searchCategory("Gas")` when `destinationText != "Gas"` sets `vm.isProgrammaticTextChange = true`. Re-invoking with `"Gas"` leaves `vm.isProgrammaticTextChange = false`.
   - `guard isWithinSupportedRegion(location.coordinate)`: Delivering an out-of-region `CLLocation` (e.g. San Francisco) to `vm.handleLocationUpdate(_:)` does not modify `vm.simulatedUserCoordinate` or advance maneuvers, whereas delivering an in-region `CLLocation` (Fairbanks) updates `vm.simulatedUserCoordinate`.
   - `if !isNavigating && !isSimulating`: Mutating `vm.useMetric = true` during active simulation preserves `vm.isNavigating`, `vm.isSimulating`, `vm.currentCoordIndex`, and `vm.currentStepIndex`, while updating `vm.displaySpeed`, `vm.speedUnit`, and `vm.altitudeUnit`.
   - Telemetry edge cases (0 steps, 1 step, 5000 coordinates, negative start/end indices): Direct execution of `vm.updateNavigationTelemetry(at:coordIndex:in:)` tests real arithmetic without crashing or force-unwrapping.

### 2.2 Complete Test Mapping Table (All 33 Tests in `RemediationTests`)

| Test Method | Current Implementation | Target `NavigationViewModel` API / Behavioral Refactoring | Elimination of `#filePath` & Unmounted View |
|---|---|---|---|
| `test01_OutOfRegionGPSHandling` | `let view = ContentView()`, `view.isWithinSupportedRegion`, `ContentView.defaultAlaskaCoordinate` | `let vm = NavigationViewModel()`, `vm.isWithinSupportedRegion`, `NavigationViewModel.defaultAlaskaCoordinate`, `vm.effectiveUserCoordinate` fallback and override | Replaces `ContentView` with `NavigationViewModel`. No `#filePath` used. |
| `test02_InFlightSearchTaskCancellation` | `var view = ContentView()`, reads `ContentView.swift` via `#filePath` for `searchTask?.cancel()` count | `let vm = NavigationViewModel()`. Start search with `vm.handleQueryChange("Fairbanks")`. Verify `vm.searchTask != nil`, capture task handle. Call `vm.dismissSearch()`. Verify `task.isCancelled == true`, `vm.searchTask == nil`, `vm.isSearching == false`. Repeat for `clearSearch()` and `resetToExplore()`. Test rapid re-query cancellation. | Replaces `ContentView` with `NavigationViewModel`. **Eliminates `#filePath` completely.** |
| `test03_CategorySearchSingleInvocation` | `var view = ContentView()`, reads `ContentView.swift` via `#filePath` for `isProgrammaticTextChange = true` | `let vm = NavigationViewModel()`. Initial `vm.isProgrammaticTextChange == false`. Call `vm.searchCategory("Gas")` -> asserts `destinationText == "Gas"`, `isProgrammaticTextChange == true`. Consume flag (`vm.isProgrammaticTextChange = false`). Call `vm.searchCategory("Gas")` again -> asserts `isProgrammaticTextChange == false` (deduplication!). Call `vm.searchCategory("Coffee")` -> asserts `isProgrammaticTextChange == true`. | Replaces `ContentView` with `NavigationViewModel`. **Eliminates `#filePath` completely.** |
| `test04_RouteTelemetryCalculationZeroStepsSafety` | `var view = ContentView()`, `view.updateNavigationTelemetry` with 0 steps | `let vm = NavigationViewModel()`. Construct 0-step `RouteDetails`, call `vm.updateNavigationTelemetry(at:coordIndex:in:)`. Assert `remainingStepDistanceMiles == 0.0`, `remainingRouteDistanceMiles == 0.0`. Test with valid steps. | Replaces `ContentView` with `NavigationViewModel`. No `#filePath` used. |
| `test05_DistanceUnitTogglingPreservesSimulationProgress` | `let view = ContentView()`, reads `ContentView.swift` via `#filePath` for `if !isNavigating && !isSimulating` | `let vm = NavigationViewModel()`. Test unit strings. Set up active simulation (`vm.isNavigating = true`, `vm.isSimulating = true`, `currentCoordIndex = 2`, `currentStepIndex = 1`). Toggle `vm.useMetric = true`. Assert `isNavigating == true`, `isSimulating == true`, `currentCoordIndex == 2`, `currentStepIndex == 1`, `displaySpeed` converts correctly. | Replaces `ContentView` with `NavigationViewModel`. **Eliminates `#filePath` completely.** |
| `test06_FallbackRoutingContractConsistency` | Direct `RoutingService` test | Retained as-is (clean `RoutingService` contract verification). | No `#filePath`, no `ContentView`. |
| `test07_LocationManagerOrientationObservationAndMainActor` | Direct `LocationManager` test | Retained as-is (clean `LocationManager` lifecycle verification). | No `#filePath`, no `ContentView`. |
| `test08_CachedLocationFixFiltering` | Direct `LocationManager` test | Retained as-is (clean timestamp/accuracy filtering). | No `#filePath`, no `ContentView`. |
| `test09_ProjectConfigurationAndDependencies` | Reads `project.yml` and `Resources/Info.plist` via `#filePath` | Inspect `Bundle.main.infoDictionary` for `NSLocationTemporaryUsageDescriptionDictionary` with key `NavigationAccuracy`. Verify `LocationManager` precision APIs. | **Eliminates `#filePath` completely.** |
| `test10_CarAnnotationCoordinateUpdatesInPlace` | Direct `MapView.Coordinator` test | Retained as-is (MLNMapView spy tests in-place KVO update). | No `#filePath`, no `ContentView`. |
| `test11_LocalSpritePathResolution` | Direct `OfflineDataManager` test | Retained as-is (Application Support sprite priority). | No `#filePath`, no `ContentView`. |
| `test12_PhysicalDeviceHostPathProbing` | Reads `OfflineDataManager.swift` via `#filePath` | Call `OfflineDataManager.url(for: "non_existent_probe.bin")`. On non-macOS/non-simulator builds, verify path does not contain `/Volumes/` or `/Users/`. Test valid asset lookup. | **Eliminates `#filePath` completely.** |
| `test13_ReverseGeocodingQueriesAcrossDataset` | Direct `SearchService` test | Retained as-is. | No `#filePath`, no `ContentView`. |
| `test14_AudioSessionDeactivationRacePrevention` | Direct `RoutingService` test | Retained as-is. | No `#filePath`, no `ContentView`. |
| `test15_AsyncWrappersNonBlockingDispatch` | Direct `SearchService` async test | Retained as-is. | No `#filePath`, no `ContentView`. |
| `test16_StrictConcurrencyAndSendableCompliance` | Direct Model Sendable test | Retained as-is. | No `#filePath`, no `ContentView`. |
| `test17_PreExistingTestSuiteCompatibility` | Direct `SearchResult` model test | Retained as-is. | No `#filePath`, no `ContentView`. |
| `testAdversarial01_OutOfRegionGPSHandling` | `let view = ContentView()`, boundary coords, reads `ContentView.swift` via `#filePath` | `let vm = NavigationViewModel()`. Test boundary coordinates via `vm.isWithinSupportedRegion`. Test `vm.handleLocationUpdate(_:)` dropping out-of-region fixes (SF / Honolulu) without updating `simulatedUserCoordinate`, and accepting in-region fixes. | Replaces `ContentView` with `NavigationViewModel`. **Eliminates `#filePath` completely.** |
| `testAdversarial02_SearchTaskLifecycle` | `var view = ContentView()`, 50-iteration loop calling clear/dismiss/reset | `let vm = NavigationViewModel()`. Loop 50 iterations on `vm.searchCategory`, `vm.clearSearch`, `vm.dismissSearch`, `vm.resetToExplore`. Verify `vm.searchTask == nil`, `vm.isSearching == false` after each call. Keep async task group test. | Replaces `ContentView` with `NavigationViewModel`. No `#filePath` used. |
| `testAdversarial03_CategorySearchDeduplication` | `var view = ContentView()`, reads `ContentView.swift` via `#filePath` for verbatim `isProgrammaticTextChange` code | `let vm = NavigationViewModel()`. Sequential category search assertions: tap "Gas", assert `isProgrammaticTextChange == true`; consume; tap "Gas", assert `isProgrammaticTextChange == false`; tap "Coffee", assert `isProgrammaticTextChange == true`. Burst 5 categories. | Replaces `ContentView` with `NavigationViewModel`. **Eliminates `#filePath` completely.** |
| `testAdversarial04_RouteTelemetryZeroOneAndLargeStepArrays` | `var view = ContentView()`, 0, 1, 5000 coord routes, countdown format | `let vm = NavigationViewModel()`. Test Cases A–E directly on `vm.updateNavigationTelemetry(at:coordIndex:in:)` and `vm.formatCountdownDistance`. Assert no force-unwraps, monotonic reduction, correct formatting. | Replaces `ContentView` with `NavigationViewModel`. No `#filePath` used. |
| `testAdversarial05_SimulationMetricTogglingProgressPreservation` | `let view = ContentView()`, reads `ContentView.swift` via `#filePath` | `let vm = NavigationViewModel()`. Set up active multi-step route simulation. Call `vm.advanceSimulationStep()`. Record state. Toggle `vm.useMetric.toggle()`. Assert `isNavigating == true`, `isSimulating == true`, coordinates/steps preserved, speed/altitude units updated, countdown format switched. | Replaces `ContentView` with `NavigationViewModel`. **Eliminates `#filePath` completely.** |
| `testAdversarial06_LocationManagerStaleGPSFixesBoundaryBehavior` | Direct `LocationManager` test | Retained as-is. | No `#filePath`, no `ContentView`. |
| `testAdversarial07_CarAnnotationRapid60HzUpdatesAndKVOInPlace` | Direct `MapView.Coordinator` test | Retained as-is. | No `#filePath`, no `ContentView`. |
| `testAdversarial08_LocalSpriteResolutionPrecedenceAndAllExtensions` | Direct `OfflineDataManager` test | Retained as-is. | No `#filePath`, no `ContentView`. |
| `testAdversarial09_PhysicalDeviceHostPathGuardElision` | Reads `OfflineDataManager.swift` via `#filePath` | Behavioral tests on `OfflineDataManager.url(for:)` and `OfflineDataManager.assetExists(at:)`. Verify safe fallback to bundle without host leaks. | **Eliminates `#filePath` completely.** |
| `testAdversarial10_ReverseGeocodingStressDeepBoundarySparseOcean` | Direct `SearchService` test | Retained as-is. | No `#filePath`, no `ContentView`. |
| `testAdversarial11_AudioSessionDeactivationConcurrencyStress` | Direct `RoutingService` concurrent test, reads `RoutingService.swift` via `#filePath` | Retain full 40-thread concurrent prompt and delegate test. Inspect `activeSpeechGeneration` progression via Mirror instead of reading source text. | **Eliminates `#filePath` completely.** |
| `testAdversarial12_AsyncWrappersHighConcurrencyBurstStress` | Direct `SearchService` async test | Retained as-is. | No `#filePath`, no `ContentView`. |
| `test18_SimulationStepProgressionBoundsSafety` | `var view = ContentView()`, `advanceSimulationStep` with 0 steps & negative indices | `let vm = NavigationViewModel()`. Set 0-step and malformed-step `RouteDetails` on `vm`, call `vm.advanceSimulationStep()`. Assert `currentStepIndex == 0`, `currentCoordIndex >= 0`. Clean up with `vm.endNavigation()`. | Replaces `ContentView` with `NavigationViewModel`. No `#filePath` used. |
| `test19_TelemetryOutOfBoundsEdgeCases` | `var view = ContentView()`, `updateNavigationTelemetry` with -5 and 9999 endIndex | `let vm = NavigationViewModel()`. Call `vm.updateNavigationTelemetry(at:coordIndex:in:)` with negative endIndex (-5), oversized endIndex (9999), and extreme coord indices (-100, 100). Assert `remainingStepDistanceMiles == 0.0` at negative end, valid telemetry at positive end. | Replaces `ContentView` with `NavigationViewModel`. No `#filePath` used. |
| `test20_SendableConformanceIntegrity` | Direct Model Sendability test | Retained as-is. | No `#filePath`, no `ContentView`. |
| `test21_ValhallaMetricDistanceConversionConsistency` | Direct Model formatting test | Retained as-is. | No `#filePath`, no `ContentView`. |

### 2.3 Additional Dedicated `NavigationViewModel` Lifecycle & Telemetry Tests
To ensure 100% direct testing of the core state transitions implemented in Milestone 3 (R2.1–R2.5), the refactored test file should add direct test methods:
- `test22_NavigationViewModelStartNavigationHardwareGPSRetention`: Tests that starting navigation with a valid, fresh in-region hardware GPS fix sets `simulatedUserCoordinate` to the hardware fix, while stale / degraded / out-of-region fixes fall back to polyline start (R2.4).
- `test23_NavigationViewModelAdvanceSimulationStepMultiSpeedLoop`: Tests that `advanceSimulationStep()` with `simulationSpeedMultiplier = 5.0` leaps multiple coordinates and advances `currentStepIndex` via `while` loop, announcing all intermediate maneuvers (R2.3).
- `test24_NavigationViewModelSwitchbackSearchClamping`: Tests that `updateCurrentStepForLiveLocation` clamps forward coordinate search to `currentStepEnd + 2`, preventing premature step advancement on switchbacks (R2.1).
- `test25_NavigationViewModelMonotonicTelemetryCountdownAndZeroing`: Tests that `updateNavigationTelemetry` decreases monotonically and evaluates strictly to `0.0` when `clampedIndex >= stepEnd` without distance reversal (R2.2).
- `test26_NavigationViewModelDualPointArrivalDetection`: Tests that `updateCurrentStepForLiveLocation` checks distance against both the road-snapped endpoint (`coords.last`) and the destination pin (`selectedCoordinate`), triggering destination arrival when within 25m of either point or within 40m in near-end zone (R2.5).
- `test27_NavigationViewModelResetAndEndNavigationCleanliness`: Tests `endNavigation()` and `resetToExplore()`, verifying complete teardown of timers, search tasks, routes, and coordinates.

---

## 3. Concrete Code Replacement Strategy

### Example 1: Refactoring `test02_InFlightSearchTaskCancellation`
```swift
// BEFORE (Brittle string inspection and unmounted view):
func test02_InFlightSearchTaskCancellation() async throws {
    var view = ContentView()
    view.dismissSearch()
    view.clearSearch()
    view.resetToExplore()

    let exp = expectation(description: "Search task cancellation probe")
    let task = Task.detached(priority: .userInitiated) { ... }
    task.cancel()
    XCTAssertTrue(task.isCancelled)
    await fulfillment(of: [exp], timeout: 1.0)

    let contentViewURL = URL(fileURLWithPath: #filePath)...
    let content = try String(contentsOf: contentViewURL, encoding: .utf8)
    XCTAssertTrue(content.contains("func dismissSearch()"))
    let occurrences = content.components(separatedBy: "searchTask?.cancel()").count - 1
    XCTAssertTrue(occurrences >= 4)
}

// AFTER (Direct NavigationViewModel behavioral testing, 0 #filePath):
func test02_InFlightSearchTaskCancellation() async throws {
    let vm = NavigationViewModel()

    // 1. dismissSearch cancels in-flight search task and resets search state
    vm.handleQueryChange("Fairbanks")
    XCTAssertTrue(vm.isSearching)
    XCTAssertNotNil(vm.searchTask)
    XCTAssertEqual(vm.appMode, .searchList)
    let task1 = vm.searchTask
    vm.dismissSearch()
    XCTAssertTrue(task1?.isCancelled ?? false, "dismissSearch must cancel active searchTask")
    XCTAssertNil(vm.searchTask, "searchTask must be nil after dismissSearch")
    XCTAssertFalse(vm.isSearching, "isSearching must be false after dismissSearch")
    XCTAssertEqual(vm.appMode, .explore, "appMode must return to .explore after dismissSearch")

    // 2. clearSearch cancels in-flight task and clears query text
    vm.handleQueryChange("Anchorage")
    XCTAssertTrue(vm.isSearching)
    let task2 = vm.searchTask
    vm.clearSearch()
    XCTAssertTrue(task2?.isCancelled ?? false, "clearSearch must cancel active searchTask")
    XCTAssertNil(vm.searchTask)
    XCTAssertEqual(vm.destinationText, "", "clearSearch must empty destinationText")
    XCTAssertTrue(vm.searchResults.isEmpty)
    XCTAssertEqual(vm.appMode, .explore)

    // 3. resetToExplore cancels in-flight task and resets all state
    vm.handleQueryChange("Juneau")
    XCTAssertTrue(vm.isSearching)
    let task3 = vm.searchTask
    vm.resetToExplore()
    XCTAssertTrue(task3?.isCancelled ?? false, "resetToExplore must cancel active searchTask")
    XCTAssertNil(vm.searchTask)
    XCTAssertEqual(vm.appMode, .explore)

    // 4. Consecutive query changes cancel prior task automatically
    vm.handleQueryChange("Fair")
    let priorTask = vm.searchTask
    vm.handleQueryChange("Fairbanks")
    XCTAssertTrue(priorTask?.isCancelled ?? false, "Rapid new query must cancel prior searchTask")
    vm.dismissSearch()
}
```

### Example 2: Refactoring `test03_CategorySearchSingleInvocation`
```swift
// BEFORE (Brittle string inspection):
func test03_CategorySearchSingleInvocation() throws {
    var view = ContentView()
    view.searchCategory("Gas")
    let contentViewURL = URL(fileURLWithPath: #filePath)...
    let content = try String(contentsOf: contentViewURL, encoding: .utf8)
    XCTAssertTrue(content.contains("isProgrammaticTextChange = true"))
    XCTAssertTrue(content.contains("if isProgrammaticTextChange"))
}

// AFTER (Direct NavigationViewModel state transition testing):
func test03_CategorySearchSingleInvocation() {
    let vm = NavigationViewModel()
    XCTAssertFalse(vm.isProgrammaticTextChange, "Initial isProgrammaticTextChange must be false")

    // 1. Tapping category chip updates destinationText and flags programmatic change
    vm.searchCategory("Gas")
    XCTAssertEqual(vm.destinationText, "Gas")
    XCTAssertTrue(vm.isProgrammaticTextChange, "searchCategory must set isProgrammaticTextChange = true when modifying destinationText")

    // 2. Simulate view layer consuming the programmatic change flag
    vm.isProgrammaticTextChange = false

    // 3. Repeated tap on the same category does NOT re-trigger programmatic change flag
    vm.searchCategory("Gas")
    XCTAssertFalse(vm.isProgrammaticTextChange, "Tapping same category must not re-assert isProgrammaticTextChange")

    // 4. Tapping distinct category flags programmatic change again
    vm.searchCategory("Coffee")
    XCTAssertEqual(vm.destinationText, "Coffee")
    XCTAssertTrue(vm.isProgrammaticTextChange)

    // 5. Selecting a place sets isProgrammaticTextChange
    vm.isProgrammaticTextChange = false
    let place = SearchResult(id: 10, name: "Mocha Dan's", lat: 64.85, lon: -147.8)
    vm.selectPlace(place)
    XCTAssertEqual(vm.destinationText, "Mocha Dan's")
    XCTAssertTrue(vm.isProgrammaticTextChange)
    XCTAssertEqual(vm.appMode, .placeDetail)
}
```

### Example 3: Refactoring `testAdversarial01_OutOfRegionGPSHandling`
```swift
// BEFORE:
// Lines 654-666: reading ContentView.swift to find guard isWithinSupportedRegion

// AFTER (Direct behavioral drop test on NavigationViewModel):
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
let outOfRegionFix = CLLocation(
    coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
    altitude: 10,
    horizontalAccuracy: 5.0,
    verticalAccuracy: 5.0,
    timestamp: Date()
)
vm.handleLocationUpdate(outOfRegionFix)
XCTAssertEqual(vm.simulatedUserCoordinate?.latitude, initialPuck.latitude, "Out-of-region fix must be silently dropped without modifying user coordinate")

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

---

## 4. Caveats

1. **Test Class Organization**: `RemediationTests.swift` contains three separate `XCTestCase` subclasses (`RemediationTests`, `ConcurrencyAudioStressTests`, `LocationManagerAdversarialStressTests`). The refactoring of `ContentView` and `#filePath` primarily affects `RemediationTests`, while `ConcurrencyAudioStressTests` and `LocationManagerAdversarialStressTests` already test `RoutingService` and `LocationManager` directly. They should be preserved in full to maintain 100% regression defense.
2. **`@MainActor` Isolation**: `NavigationViewModel` is declared `@MainActor`. All test methods interacting with `NavigationViewModel` must be declared on `@MainActor final class RemediationTests: XCTestCase` (which it already is at line 10) or dispatched via `await MainActor.run`.
3. **Backward Compatibility**: `ContentView.swift` maintains 37 forwarding properties (`viewModel.<prop>`) from Milestone 3. The refactoring of `RemediationTests.swift` shifts tests to target `NavigationViewModel` directly, but the forwarding properties in `ContentView.swift` may remain in place for any existing view consumers or external bindings.
4. **Scope Boundaries**: This report covers requirement R6.1. Requirement R6.2 (removing `import ValhallaConfigModels` in `MyOfflineMapAppTests.swift`) is handled by Explorer M4.2, and R6.4 (sanitizing machine paths in documentation) is handled by Explorer M4.3.

---

## 5. Conclusion

1. **Refactoring Feasibility**: 100% of unmounted `ContentView()` mutations and 100% of `#filePath` source-code string matches in `RemediationTests.swift` can be cleanly eliminated and replaced with direct, high-fidelity behavioral tests on `NavigationViewModel`.
2. **Quality & Maintainability Gain**:
   - Zero `#filePath` invocations in `RemediationTests.swift`.
   - Zero fragile source code string matching.
   - Comprehensive direct coverage of R2.1–R2.5 telemetry and progression logic on `NavigationViewModel`.
   - Complete immunity to source file layout, line numbering, or comment formatting changes.
3. **Recommended Implementation Action**:
   The worker for Milestone 4 can rewrite `RemediationTests.swift` according to the mapping table in Section 2.2 and the code patterns in Section 3, resulting in a modern, production-grade unit test suite.

---

## 6. Verification Method

To independently verify the refactored `RemediationTests.swift`:

1. **Verify Complete Elimination of `#filePath`**:
   ```bash
   grep -rn "#filePath" "MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift"
   ```
   **Expected Result**: Output is empty (0 matches).

2. **Verify Elimination of Unmounted `ContentView()`**:
   ```bash
   grep -rn "ContentView()" "MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift"
   ```
   **Expected Result**: Output is empty (0 matches).

3. **Verify Swift Compilation & Typecheck**:
   ```bash
   swiftc -module-cache-path /tmp/clang-cache -typecheck -parse-as-library \
       .agents/teamwork/explorer_m3_it2_3/Stubs.swift \
       MyOfflineMapApp/Sources/NavigationViewModel.swift \
       MyOfflineMapApp/Sources/ContentView.swift
   ```
   **Expected Result**: Exit code 0, 0 compiler errors.

4. **Verify E2E Suite Passes 100%**:
   ```bash
   ./Tests/E2ETests/run_e2e_tests.sh
   ```
   **Expected Result**: 69/69 tests PASS across Tiers 1–4.
