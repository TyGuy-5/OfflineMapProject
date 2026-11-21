# Adversarial Stress Test Report: Milestone 3 (Navigation ViewModel Architecture & Telemetry)

**Agent**: `challenger_m3_2` (teamwork_challenger: critic, specialist)  
**Parent**: `353a2eeb-3a48-4ff7-be7e-6c7ece6b589d`  
**Date**: 2026-11-07T07:44:00Z  
**Target Codebase**: `MyOfflineMapApp/Sources/NavigationViewModel.swift`, `MyOfflineMapApp/Sources/ContentView.swift`  
**Scope**: Requirements R1.1, R1.2, R1.3, R2.1–R2.5  

---

## Challenge Summary

**Overall risk assessment**: HIGH (Build Blocker Detected in `ContentView.swift`)

While the standalone `NavigationViewModel.swift` state machine, telemetry countdown, polyline clamping, simulation loop, dual-point arrival, and AppStorage persistence logic are robust and passed all 79 empirical stress tests, a **critical compilation flaw was identified in `ContentView.swift`**: all 37 forwarding property setters were declared as bare `set { viewModel.<prop> = newValue }` on a SwiftUI `struct`, causing Swift to infer `mutating set`. This triggers 10 `cannot assign to property: 'self' is immutable` compilation errors whenever `searchCategory(_:)`, `.onChange(of: destinationText)`, or HUD button action closures assign to forwarding properties on `self`.

---

## Challenges & Findings

### [Critical] Challenge 1: Mutating Forwarding Property Setters on `ContentView` Struct Break Swift Compilation

- **Assumption challenged**: The worker assumed that declaring forwarding properties on `ContentView` as `var prop: Type { get { viewModel.prop } set { viewModel.prop = newValue } }` would preserve backward compatibility and allow `ContentView` methods and closures to mutate forwarding properties.
- **Attack scenario & Empirical Finding**:
  In Swift, computed property setters on a `struct` default to `mutating set`.
  Because `ContentView` is a `struct`:
  1. Non-mutating methods like `func searchCategory(_ category: String)` cannot assign to `self.isProgrammaticTextChange = true` (line 209) or `self.destinationText = category` (line 210).
  2. Closures in `body` (e.g. `.onChange(of: destinationText)` at line 388, HUD toggle `Button(action: { isHudMode = true })` at line 875, and HUD dismiss `Button(action: { isHudMode = false })` at line 993) capture `self` as an immutable value, so calling a `mutating set` fails with:
     ```
     MyOfflineMapApp/Sources/ContentView.swift:209:13: error: cannot assign to property: 'self' is immutable
     MyOfflineMapApp/Sources/ContentView.swift:210:13: error: cannot assign to property: 'self' is immutable
     MyOfflineMapApp/Sources/ContentView.swift:388:29: error: cannot assign to property: 'self' is immutable
     MyOfflineMapApp/Sources/ContentView.swift:875:21: error: cannot assign to property: 'self' is immutable
     MyOfflineMapApp/Sources/ContentView.swift:993:38: error: cannot assign to property: 'self' is immutable
     ```
  3. External callers holding a `let view = ContentView()` cannot mutate forwarding properties.
- **Blast radius**:
  `ContentView.swift` fails compilation in Swift whenever compiled directly. The E2E test runner passed only because it runs opaque-box mocks against `Tests/E2ETests/Support/TestHarness.swift` rather than compiling `ContentView.swift`. In Milestone 4, compiling the project target and test bundle will immediately fail with 10 compiler errors.
- **Mitigation**:
  Declare all 37 forwarding property setters in `ContentView.swift` with `nonmutating set { viewModel.<prop> = newValue }`. Because `viewModel` is a reference type (`@StateObject var viewModel: NavigationViewModel`), mutating its properties does not mutate the `ContentView` struct instance, satisfying Swift's immutability rules. Tested empirically in `/tmp/ContentView_nonmutating.swift`: completely eliminates all 10 immutability errors while preserving exact source text contracts.

---

### [Low] Challenge 2: Triple `objectWillChange` Publication on `@AppStorage` Mutations

- **Assumption challenged**: Modifying `@AppStorage("useMetric")` or `@AppStorage("isVoiceMuted")` emits exactly one `objectWillChange` event.
- **Attack scenario & Empirical Finding**:
  When `useMetric` or `isVoiceMuted` is mutated, 3 `objectWillChange` events fire:
  1. Event #1: Fired manually by `willSet { objectWillChange.send() }`.
  2. Event #2: Fired automatically by the `@AppStorage` property wrapper on the `ObservableObject`.
  3. Event #3: Fired by `UserDefaults` notification observed by `@AppStorage`.
- **Blast radius**:
  While SwiftUI view rendering automatically coalesces multiple `objectWillChange` events within a single transaction, Combine subscribers or unit tests asserting single-emission counts will observe multiple triggers.
- **Mitigation**:
  `willSet { objectWillChange.send() }` can safely be omitted if targeting Swift/SwiftUI versions where `@AppStorage` synthesizes `ObservableObjectPublisher` triggers, or documented as intentional for backwards compatibility.

---

## Stress Test Results Matrix

| Test Suite / Area | Tested Scenario | Expected Behavior | Actual Behavior | Result |
|---|---|---|---|---|
| **State Machine** | Explore -> SearchList via `handleQueryChange` | `appMode == .searchList`, `isSearching == true` | Transited correctly | PASS |
| **State Machine** | SearchList -> Explore via short query `< 2` chars | `appMode == .explore`, `isSearching == false` | Transited correctly | PASS |
| **State Machine** | SearchList -> Explore via `dismissSearch()` | `appMode == .explore`, `searchTask == nil` | Transited correctly | PASS |
| **State Machine** | Explore -> PlaceDetail via `selectPlace` | `appMode == .placeDetail`, place & coords set | Transited correctly | PASS |
| **State Machine** | PlaceDetail -> RoutePreview via `calculateRouteTo` | `appMode == .routePreview`, async route set | Transited correctly | PASS |
| **State Machine** | RoutePreview -> Navigation via `startNavigation` | `appMode == .navigation`, `isNavigating == true` | Transited correctly | PASS |
| **State Machine** | Navigation -> RoutePreview via `endNavigation` | `appMode == .routePreview`, `isNavigating == false` | Transited correctly | PASS |
| **State Machine** | RoutePreview -> Navigation (Simulated) | `appMode == .navigation`, `isSimulating == true` | Transited correctly | PASS |
| **State Machine** | Navigation -> Explore via `resetToExplore` | `appMode == .explore`, all state reset to nil | Transited correctly | PASS |
| **State Machine** | Route calculation failure fallback | Reverts to `.placeDetail` (if place non-nil) with alert | Reverted correctly | PASS |
| **State Machine** | `startNavigation()` with nil route | Safe no-op, does not enter navigation | Safe no-op | PASS |
| **State Machine** | Arrival detection during live navigation | Polyline cleared, `endNavigation()`, `.explore` | Arrived & cleared | PASS |
| **AppStorage** | Preference persistence in `UserDefaults.standard` | `"useMetric"` and `"isVoiceMuted"` persist | Read & write pass | PASS |
| **AppStorage** | Voice mute synchronization to `RoutingService` | `isVoiceMuted = true` syncs & calls `stopVoice` | Synced & stopped | PASS |
| **AppStorage** | Preference reload on ViewModel re-init | New VM instance loads persisted preferences | Persisted state loaded | PASS |
| **AppStorage** | Rapid 1,000 toggle stress test | ViewModel and routing service stay consistent | 100% consistent | PASS |
| **Telemetry (R2.1)** | Switchback clamping forward bound | Clamped to `currentStepEnd + 2` slack | Clamped, no jump | PASS |
| **Telemetry (R2.2)** | Monotonic countdown without distance reversal | Strictly `0.0` at and past `stepEnd` | 0.0 at stepEnd & beyond | PASS |
| **Simulation (R2.3)**| Multi-speed simulation 5x multi-vertex leap | `while` loop advances step and speaks intermediate turns | Caught up & announced | PASS |
| **Lifecycle (R2.4)** | Live hardware GPS fix start fix | Retains live GPS coord and heading, no origin snap | Live fix retained | PASS |
| **Lifecycle (R2.4)** | Degraded / stale GPS fix fallback | Snaps to route start when GPS accuracy >= 65m or > 15s | Snapped to start | PASS |
| **Arrival (R2.5)** | Dual-point arrival at setback destination | Triggers arrival at setback parking lot (< 25m) | Arrival triggered | PASS |
| **RemediationContracts** | 10 source string inspection contracts | All 10 contracts match verbatim in `ContentView.swift` | 10/10 matched | PASS |
| **E2E Suite** | Full opaque-box E2E test suite (Tiers 1-4) | 69/69 tests pass | 69/69 passed (0.116s) | PASS |
| **Compilation** | Swift struct forwarding property mutability | Computed properties mutable on immutable struct | **10 compilation errors** | **FAIL** |

---

## Actionable Remediation Required

In `MyOfflineMapApp/Sources/ContentView.swift`:
Replace `set {` with `nonmutating set {` across all 37 forwarding properties (lines 20–168).
For example:
```swift
    var destinationText: String {
        get { viewModel.destinationText }
        nonmutating set { viewModel.destinationText = newValue }
    }

    var isProgrammaticTextChange: Bool {
        get { viewModel.isProgrammaticTextChange }
        nonmutating set { viewModel.isProgrammaticTextChange = newValue }
    }

    var isHudMode: Bool {
        get { viewModel.isHudMode }
        nonmutating set { viewModel.isHudMode = newValue }
    }
```
This preserves identical external syntax and string matching while resolving all Swift struct immutability errors.

---

## Binary Verdict

**REQUEST_CHANGES** (Actionable fix: update forwarding property setters in `ContentView.swift` to `nonmutating set`).
