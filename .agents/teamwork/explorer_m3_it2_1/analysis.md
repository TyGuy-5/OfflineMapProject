# Milestone 3 Iteration 2: Investigation & Analysis of ContentView.swift Mutability Fix

**Agent**: `explorer_m3_it2_1` (teamwork_explorer: investigation, synthesis)  
**Parent**: `353a2eeb-3a48-4ff7-be7e-6c7ece6b589d`  
**Date**: 2026-11-07T07:54:00Z  
**Target Codebase**: `MyOfflineMapApp/Sources/ContentView.swift`  
**Scope**: Resolution of Challenger M3 REQUEST_CHANGES (`cannot assign to property: 'self' is immutable`)

---

## Executive Summary

Challenger `challenger_m3_2` reported that `ContentView` (a Swift `struct`) defines 37 computed forwarding properties in lines 20–168 using bare `set { viewModel.<prop> = newValue }`. In Swift, struct computed property setters default to `mutating set`. When methods (such as `searchCategory(_:)`) or closures within SwiftUI views (such as `.onChange(of: destinationText)` or `Button(action:)`) attempt to assign to these properties on `self`, the Swift compiler rejects the code with 10 fatal `cannot assign to property: 'self' is immutable` errors.

This investigation confirmed:
1. Every single one of the 37 forwarding properties forwards to `viewModel.<prop> = newValue`.
2. Because `viewModel` is an `@StateObject` (an instance of `@MainActor public final class NavigationViewModel`), assigning to `viewModel.<prop>` mutates a property of a reference-type class, not the value-type `ContentView` struct.
3. Marking all 37 setters as `nonmutating set` is 100% syntactically and semantically valid in Swift, completely eliminates all 10 compiler errors, preserves all 10 source string inspection contracts required by `RemediationTests.swift`, and passes all 69 E2E tests.

---

## 1. Root Cause Analysis

### Swift Struct Mutability Rules
In Swift:
- Computed properties defined on a `struct` have an implicitly `mutating` setter by default (`mutating set`).
- Methods on a struct are non-mutating unless explicitly marked `mutating func`.
- SwiftUI view closures (e.g., `Button(action: { ... })`, `.onChange(...) { ... }`) capture the view instance (`self`) by value as an immutable constant (`let self`).
- A `mutating set` cannot be called on an immutable instance of `self` or inside non-mutating methods.

### The Triggering Assignments in `ContentView.swift`
When `ContentView.swift` is compiled, the compiler encounters assignments to forwarding properties in non-mutating contexts:
1. **Method Context (`searchCategory`)**:
   - `searchCategory(_:)` (lines 207–213) assigns:
     - Line 209: `isProgrammaticTextChange = true`
     - Line 210: `destinationText = category`
   - Because `searchCategory` is non-mutating, calling mutating setters causes compiler errors.
2. **Closure Contexts**:
   - Line 388: `isProgrammaticTextChange = false` in `.onChange(of: destinationText)`
   - Line 875: `isHudMode = true` in Windshield HUD toggle `Button(action:)`
   - Line 993: `isHudMode = false` in HUD dismiss `Button(action:)`
   - Additional button actions (e.g. lines 649, 655 `zoomStep = ±1.0`, line 824 `showStepsSheet = true`, lines 955, 958, 961 `simulationSpeedMultiplier = 1.0/2.0/5.0`).

### The Solution: `nonmutating set`
Because the backing storage is `viewModel` (a class reference held by `@StateObject`), updating `viewModel.<prop>` does not modify any stored fields of the `ContentView` struct. Swift explicitly provides `nonmutating set` for this exact scenario:
```swift
var destinationText: String {
    get { viewModel.destinationText }
    nonmutating set { viewModel.destinationText = newValue }
}
```
With `nonmutating set`, `self` remains immutable, allowing non-mutating methods, SwiftUI closures, and external callers holding `let view = ContentView()` to mutate view model state through the forwarding properties.

---

## 2. Enumeration of All 37 Forwarding Property Setters

The table below enumerates all 37 computed forwarding properties in `MyOfflineMapApp/Sources/ContentView.swift` (lines 20–168). Every property has been verified to correctly forward both its getter (`get { viewModel.<prop> }`) and its setter (`viewModel.<prop> = newValue`).

| # | Property Name | Type | Lines | Backing Target in `NavigationViewModel` | Setter Status |
|---|---------------|------|-------|-----------------------------------------|---------------|
| 1 | `appMode` | `MapAppMode` | 20–23 | `viewModel.appMode` | Needs `nonmutating set` |
| 2 | `selectedPlace` | `SearchResult?` | 24–27 | `viewModel.selectedPlace` | Needs `nonmutating set` |
| 3 | `routeDetails` | `RouteDetails?` | 28–31 | `viewModel.routeDetails` | Needs `nonmutating set` |
| 4 | `selectedTravelMode` | `String` | 32–35 | `viewModel.selectedTravelMode` | Needs `nonmutating set` |
| 5 | `showStepsSheet` | `Bool` | 36–39 | `viewModel.showStepsSheet` | Needs `nonmutating set` |
| 6 | `isHudMode` | `Bool` | 40–43 | `viewModel.isHudMode` | Needs `nonmutating set` |
| 7 | `useMetric` | `Bool` | 44–47 | `viewModel.useMetric` | Needs `nonmutating set` |
| 8 | `isVoiceMuted` | `Bool` | 48–51 | `viewModel.isVoiceMuted` | Needs `nonmutating set` |
| 9 | `destinationText` | `String` | 52–55 | `viewModel.destinationText` | Needs `nonmutating set` |
| 10 | `searchResults` | `[SearchResult]` | 56–59 | `viewModel.searchResults` | Needs `nonmutating set` |
| 11 | `isSearching` | `Bool` | 60–63 | `viewModel.isSearching` | Needs `nonmutating set` |
| 12 | `searchTask` | `Task<Void, Never>?` | 64–67 | `viewModel.searchTask` | Needs `nonmutating set` |
| 13 | `isProgrammaticTextChange` | `Bool` | 68–71 | `viewModel.isProgrammaticTextChange` | Needs `nonmutating set` |
| 14 | `selectedCoordinate` | `CLLocationCoordinate2D?` | 72–75 | `viewModel.selectedCoordinate` | Needs `nonmutating set` |
| 15 | `routeCoordinates` | `[CLLocationCoordinate2D]?` | 76–79 | `viewModel.routeCoordinates` | Needs `nonmutating set` |
| 16 | `simulatedUserCoordinate` | `CLLocationCoordinate2D?` | 80–83 | `viewModel.simulatedUserCoordinate` | Needs `nonmutating set` |
| 17 | `userLocationCenter` | `CLLocationCoordinate2D?` | 84–87 | `viewModel.userLocationCenter` | Needs `nonmutating set` |
| 18 | `simulatedHeading` | `Double?` | 88–91 | `viewModel.simulatedHeading` | Needs `nonmutating set` |
| 19 | `zoomStep` | `Double?` | 92–95 | `viewModel.zoomStep` | Needs `nonmutating set` |
| 20 | `isNavigating` | `Bool` | 96–99 | `viewModel.isNavigating` | Needs `nonmutating set` |
| 21 | `isSimulating` | `Bool` | 100–103 | `viewModel.isSimulating` | Needs `nonmutating set` |
| 22 | `currentStepIndex` | `Int` | 104–107 | `viewModel.currentStepIndex` | Needs `nonmutating set` |
| 23 | `currentCoordIndex` | `Int` | 108–111 | `viewModel.currentCoordIndex` | Needs `nonmutating set` |
| 24 | `simulatedSpeedMph` | `Int` | 112–115 | `viewModel.simulatedSpeedMph` | Needs `nonmutating set` |
| 25 | `simulationSpeedMultiplier` | `Double` | 116–119 | `viewModel.simulationSpeedMultiplier` | Needs `nonmutating set` |
| 26 | `isRecalculating` | `Bool` | 120–123 | `viewModel.isRecalculating` | Needs `nonmutating set` |
| 27 | `consecutiveRerouteFailures` | `Int` | 124–127 | `viewModel.consecutiveRerouteFailures` | Needs `nonmutating set` |
| 28 | `lastRerouteTime` | `Date` | 128–131 | `viewModel.lastRerouteTime` | Needs `nonmutating set` |
| 29 | `activeRouteRequestId` | `UUID?` | 132–135 | `viewModel.activeRouteRequestId` | Needs `nonmutating set` |
| 30 | `remainingStepDistanceMiles` | `Double` | 136–139 | `viewModel.remainingStepDistanceMiles` | Needs `nonmutating set` |
| 31 | `remainingRouteDistanceMiles` | `Double` | 140–143 | `viewModel.remainingRouteDistanceMiles` | Needs `nonmutating set` |
| 32 | `remainingRouteDurationSeconds` | `Double` | 144–147 | `viewModel.remainingRouteDurationSeconds` | Needs `nonmutating set` |
| 33 | `dynamicArrivalDate` | `Date` | 148–151 | `viewModel.dynamicArrivalDate` | Needs `nonmutating set` |
| 34 | `hasAnnouncedAdvanceTurn` | `Bool` | 152–155 | `viewModel.hasAnnouncedAdvanceTurn` | Needs `nonmutating set` |
| 35 | `errorMessage` | `String?` | 156–159 | `viewModel.errorMessage` | Needs `nonmutating set` |
| 36 | `showErrorAlert` | `Bool` | 160–163 | `viewModel.showErrorAlert` | Needs `nonmutating set` |
| 37 | `isMapDataMissing` | `Bool` | 164–167 | `viewModel.isMapDataMissing` | Needs `nonmutating set` |

### Read-Only Computed Properties (Lines 169–178)
For completeness, lines 169–178 contain 8 instance read-only computed properties and 1 static property:
- `displaySpeed: Int { viewModel.displaySpeed }`
- `speedUnit: String { viewModel.speedUnit }`
- `altitudeValue: Int { viewModel.altitudeValue }`
- `altitudeUnit: String { viewModel.altitudeUnit }`
- `effectiveUserCoordinate: CLLocationCoordinate2D { viewModel.effectiveUserCoordinate }`
- `formattedRemainingDuration: String { viewModel.formattedRemainingDuration }`
- `formattedRemainingETA: String { viewModel.formattedRemainingETA }`
- `currentNavigationStep: NavigationStep { viewModel.currentNavigationStep }`
- `static var defaultAlaskaCoordinate: CLLocationCoordinate2D { NavigationViewModel.defaultAlaskaCoordinate }`

These properties do not define setters and require no changes.

---

## 3. Empirical Verification Results

1. **Reproduction of Compiler Failure**:
   - Compiling the current `ContentView.swift` with `swiftc` emitted 10 `cannot assign to property: 'self' is immutable` errors.
2. **Verification of Proposed `nonmutating set` Fix**:
   - Applying `nonmutating set` to all 37 properties reduced `cannot assign to property` errors from **10 to 0**.
3. **Verification of Immutable Instance Assignment**:
   - Compiled a test harness instantiating `let view = ContentView(viewModel: vm)` and performing mutations across all 37 properties.
   - All 37 assignments compiled with **0 errors**.
4. **Verification of Source Text Inspection Contracts (`RemediationTests.swift`)**:
   - All 10 contracts verified passing:
     - `func dismissSearch()` count == 1 (PASS)
     - `func clearSearch()` count == 1 (PASS)
     - `func resetToExplore()` count == 1 (PASS)
     - `searchTask?.cancel()` count >= 4 (PASS, count = 4)
     - `isProgrammaticTextChange = true` count >= 1 (PASS)
     - `if isProgrammaticTextChange` count >= 1 (PASS)
     - `guard isWithinSupportedRegion(location.coordinate) else { return }` present (PASS)
     - `if !isNavigating && !isSimulating` present (PASS)
     - `testAdversarial03` string 1 present (PASS)
     - `testAdversarial03` string 2 present (PASS)
5. **E2E Test Suite Execution**:
   - Ran `./Tests/E2ETests/run_e2e_tests.sh`:
   - 69/69 tests passed across Tiers 1–4 (0.117s).

---

## 4. Recommended Replacement Block for `ContentView.swift`

### Target File
`MyOfflineMapApp/Sources/ContentView.swift`, Lines 20–168.

### Replacement Code Snippet
```swift
    var appMode: MapAppMode {
        get { viewModel.appMode }
        nonmutating set { viewModel.appMode = newValue }
    }
    var selectedPlace: SearchResult? {
        get { viewModel.selectedPlace }
        nonmutating set { viewModel.selectedPlace = newValue }
    }
    var routeDetails: RouteDetails? {
        get { viewModel.routeDetails }
        nonmutating set { viewModel.routeDetails = newValue }
    }
    var selectedTravelMode: String {
        get { viewModel.selectedTravelMode }
        nonmutating set { viewModel.selectedTravelMode = newValue }
    }
    var showStepsSheet: Bool {
        get { viewModel.showStepsSheet }
        nonmutating set { viewModel.showStepsSheet = newValue }
    }
    var isHudMode: Bool {
        get { viewModel.isHudMode }
        nonmutating set { viewModel.isHudMode = newValue }
    }
    var useMetric: Bool {
        get { viewModel.useMetric }
        nonmutating set { viewModel.useMetric = newValue }
    }
    var isVoiceMuted: Bool {
        get { viewModel.isVoiceMuted }
        nonmutating set { viewModel.isVoiceMuted = newValue }
    }
    var destinationText: String {
        get { viewModel.destinationText }
        nonmutating set { viewModel.destinationText = newValue }
    }
    var searchResults: [SearchResult] {
        get { viewModel.searchResults }
        nonmutating set { viewModel.searchResults = newValue }
    }
    var isSearching: Bool {
        get { viewModel.isSearching }
        nonmutating set { viewModel.isSearching = newValue }
    }
    var searchTask: Task<Void, Never>? {
        get { viewModel.searchTask }
        nonmutating set { viewModel.searchTask = newValue }
    }
    var isProgrammaticTextChange: Bool {
        get { viewModel.isProgrammaticTextChange }
        nonmutating set { viewModel.isProgrammaticTextChange = newValue }
    }
    var selectedCoordinate: CLLocationCoordinate2D? {
        get { viewModel.selectedCoordinate }
        nonmutating set { viewModel.selectedCoordinate = newValue }
    }
    var routeCoordinates: [CLLocationCoordinate2D]? {
        get { viewModel.routeCoordinates }
        nonmutating set { viewModel.routeCoordinates = newValue }
    }
    var simulatedUserCoordinate: CLLocationCoordinate2D? {
        get { viewModel.simulatedUserCoordinate }
        nonmutating set { viewModel.simulatedUserCoordinate = newValue }
    }
    var userLocationCenter: CLLocationCoordinate2D? {
        get { viewModel.userLocationCenter }
        nonmutating set { viewModel.userLocationCenter = newValue }
    }
    var simulatedHeading: Double? {
        get { viewModel.simulatedHeading }
        nonmutating set { viewModel.simulatedHeading = newValue }
    }
    var zoomStep: Double? {
        get { viewModel.zoomStep }
        nonmutating set { viewModel.zoomStep = newValue }
    }
    var isNavigating: Bool {
        get { viewModel.isNavigating }
        nonmutating set { viewModel.isNavigating = newValue }
    }
    var isSimulating: Bool {
        get { viewModel.isSimulating }
        nonmutating set { viewModel.isSimulating = newValue }
    }
    var currentStepIndex: Int {
        get { viewModel.currentStepIndex }
        nonmutating set { viewModel.currentStepIndex = newValue }
    }
    var currentCoordIndex: Int {
        get { viewModel.currentCoordIndex }
        nonmutating set { viewModel.currentCoordIndex = newValue }
    }
    var simulatedSpeedMph: Int {
        get { viewModel.simulatedSpeedMph }
        nonmutating set { viewModel.simulatedSpeedMph = newValue }
    }
    var simulationSpeedMultiplier: Double {
        get { viewModel.simulationSpeedMultiplier }
        nonmutating set { viewModel.simulationSpeedMultiplier = newValue }
    }
    var isRecalculating: Bool {
        get { viewModel.isRecalculating }
        nonmutating set { viewModel.isRecalculating = newValue }
    }
    var consecutiveRerouteFailures: Int {
        get { viewModel.consecutiveRerouteFailures }
        nonmutating set { viewModel.consecutiveRerouteFailures = newValue }
    }
    var lastRerouteTime: Date {
        get { viewModel.lastRerouteTime }
        nonmutating set { viewModel.lastRerouteTime = newValue }
    }
    var activeRouteRequestId: UUID? {
        get { viewModel.activeRouteRequestId }
        nonmutating set { viewModel.activeRouteRequestId = newValue }
    }
    var remainingStepDistanceMiles: Double {
        get { viewModel.remainingStepDistanceMiles }
        nonmutating set { viewModel.remainingStepDistanceMiles = newValue }
    }
    var remainingRouteDistanceMiles: Double {
        get { viewModel.remainingRouteDistanceMiles }
        nonmutating set { viewModel.remainingRouteDistanceMiles = newValue }
    }
    var remainingRouteDurationSeconds: Double {
        get { viewModel.remainingRouteDurationSeconds }
        nonmutating set { viewModel.remainingRouteDurationSeconds = newValue }
    }
    var dynamicArrivalDate: Date {
        get { viewModel.dynamicArrivalDate }
        nonmutating set { viewModel.dynamicArrivalDate = newValue }
    }
    var hasAnnouncedAdvanceTurn: Bool {
        get { viewModel.hasAnnouncedAdvanceTurn }
        nonmutating set { viewModel.hasAnnouncedAdvanceTurn = newValue }
    }
    var errorMessage: String? {
        get { viewModel.errorMessage }
        nonmutating set { viewModel.errorMessage = newValue }
    }
    var showErrorAlert: Bool {
        get { viewModel.showErrorAlert }
        nonmutating set { viewModel.showErrorAlert = newValue }
    }
    var isMapDataMissing: Bool {
        get { viewModel.isMapDataMissing }
        nonmutating set { viewModel.isMapDataMissing = newValue }
    }
```

### Generated Artifacts
- Patch file: `.agents/teamwork/explorer_m3_it2_1/contentview_nonmutating_fix.patch`
- Fully modified replacement source: `.agents/teamwork/explorer_m3_it2_1/ContentView_proposed.swift`
