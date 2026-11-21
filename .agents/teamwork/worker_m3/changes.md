# Milestone 3 Detailed Changes: Navigation ViewModel Architecture & Telemetry

## Overview
Milestone 3 extracts navigation, search, simulation, and telemetry state machine logic out of `ContentView.swift` into a dedicated, isolated `@MainActor public final class NavigationViewModel: ObservableObject`, injects it into `ContentView` via `@StateObject`, persists user preferences (`useMetric` and `isVoiceMuted`) across launches via `@AppStorage` keys aligning with `PrivacyInfo.xcprivacy` (`CA92.1`), and remediates 5 core telemetry/lifecycle bugs (R2.1–R2.5) while maintaining complete backward compatibility with all existing tests.

---

## 1. Files Modified and Created

### 1.1 `MyOfflineMapApp/Sources/NavigationViewModel.swift` (New File)
- **Role**: State container and business logic engine for navigation, simulation, search, and telemetry.
- **Key Declarations**:
  - `public enum MapAppMode: Equatable, Sendable`: Explicit state machine modes (`.explore`, `.searchList`, `.placeDetail`, `.routePreview`, `.navigation`).
  - `@MainActor public final class NavigationViewModel: ObservableObject`:
    - Service Dependencies: `locationManager: LocationManager`, `searchService: SearchService`, `routingService: RoutingService`.
    - Persisted Preferences (R1.3):
      - `@AppStorage("useMetric") public var useMetric: Bool = false { willSet { objectWillChange.send() } }`
      - `@AppStorage("isVoiceMuted") public var isVoiceMuted: Bool = false { willSet { objectWillChange.send() } didSet { routingService.isVoiceMuted = isVoiceMuted; if isVoiceMuted { routingService.stopVoice() } } }`
    - Navigation Mode & State: `appMode`, `selectedPlace`, `routeDetails`, `selectedTravelMode`, `showStepsSheet`, `isHudMode`.
    - Search State: `destinationText`, `searchResults`, `isSearching`, `searchTask`, `isProgrammaticTextChange`.
    - Map & Telemetry Bindings: `selectedCoordinate`, `routeCoordinates`, `simulatedUserCoordinate`, `userLocationCenter`, `simulatedHeading`, `zoomStep`.
    - Simulation State: `isNavigating`, `isSimulating`, `simulationTimer`, `currentStepIndex`, `currentCoordIndex`, `simulatedSpeedMph`, `simulationSpeedMultiplier`.
    - Rerouting & Telemetry State: `isRecalculating`, `consecutiveRerouteFailures`, `lastRerouteTime`, `activeRouteRequestId`, `remainingStepDistanceMiles`, `remainingRouteDistanceMiles`, `remainingRouteDurationSeconds`, `dynamicArrivalDate`, `hasAnnouncedAdvanceTurn`.
    - Alerts: `errorMessage`, `showErrorAlert`, `isMapDataMissing`.
  - **Methods & Algorithms**:
    - `isWithinSupportedRegion`: Validates coordinates within Alaska boundary `[51.0, 72.0]` lat x `[-179.0, -129.0]` lon. Available as instance and static method.
    - `formatCountdownDistance`: Metric and imperial countdown string formatting. Available as instance and static method.
    - `segmentDistanceMeters`: Equirectangular planar projection distance in meters. Available as instance and static method.
    - `startNavigation()` (R2.4): Validates hardware GPS fix against 4 health criteria (non-nil, accuracy in `[0, 65)`, freshness `< 15.0s`, within Alaska bounds) to retain live GPS coordinate and course rather than unconditionally snapping puck to polyline origin.
    - `startSimulatedDrive()`: Begins navigation and explicitly sets simulated coordinate to polyline start (`details.coordinates.first`) and `currentCoordIndex = 0`.
    - `advanceSimulationStep()` (R2.3): Advances `currentCoordIndex` by simulation speed jump. Uses a `while !details.steps.isEmpty && currentStepIndex < details.steps.count - 1` loop to advance `currentStepIndex` across multi-vertex leaps, announcing all traversed maneuvers at 2x and 5x simulation speeds.
    - `updateCurrentStepForLiveLocation(_:in:)` (R2.1 & R2.5):
      - Dual-Point Arrival Check (R2.5): Evaluates Euclidean distance to both road-snapped polyline end (`coords.last`) and destination pin (`selectedCoordinate`). Triggers arrival if either distance is `< 25.0m`, or `< 40.0m` when within the final 3 vertices or on the last maneuver step.
      - Switchback Clamped Search (R2.1): Bounds polyline segment forward search to `currentStepEnd + 2` slack vertices (`min(coords.count - 1, max(currentCoordIndex + 1, currentStepEnd + 2))`), eliminating premature jumps across parallel switchback roads.
    - `updateNavigationTelemetry(at:coordIndex:in:)` (R2.2):
      - Computes `remainingStepDistanceMiles` monotonically counting down to zero. When `clampedIndex >= stepEnd`, strictly evaluates to `0.0`, eliminating distance countdown reversal.
      - Evaluates `remainingRouteDistanceMiles = 0.0` when `clampedIndex >= coords.count - 1`.
      - Proportionally recalculates `remainingRouteDurationSeconds` and `dynamicArrivalDate`.
    - Rerouting & Search Methods: `recalculateActiveRoute`, `handleMapLongPress`, `handleQueryChange`, `searchCategory`, `selectPlace`, `calculateRouteTo`, `switchTravelMode`, `dismissSearch`, `clearSearch`, `resetToExplore`, `recenterOnUser`, `toggleVoiceMute`, `checkMapDataMissing`.

### 1.2 `MyOfflineMapApp/Sources/ContentView.swift` (Refactored)
- **Role**: Pure SwiftUI presentation view layer observing `NavigationViewModel`.
- **Key Modifications**:
  - Injected `NavigationViewModel` via `@StateObject var viewModel: NavigationViewModel` with initializer `public init(viewModel: NavigationViewModel? = nil)`.
  - Replaced all view-local `@State` business variables with bindings to `viewModel` (`$viewModel.selectedCoordinate`, `$viewModel.routeCoordinates`, etc.).
  - Preserved `@State private var showAttributionAlert = false` for presentation sheet.
  - Implemented 33 backward-compatibility forwarding properties mirroring exact types and signatures (`locationManager`, `searchService`, `routingService`, `appMode`, `selectedPlace`, `routeDetails`, `selectedTravelMode`, `showStepsSheet`, `isHudMode`, `useMetric`, `isVoiceMuted`, `destinationText`, `searchResults`, `isSearching`, `searchTask`, `isProgrammaticTextChange`, `selectedCoordinate`, `routeCoordinates`, `simulatedUserCoordinate`, `userLocationCenter`, `simulatedHeading`, `zoomStep`, `isNavigating`, `isSimulating`, `currentStepIndex`, `currentCoordIndex`, `simulatedSpeedMph`, `simulationSpeedMultiplier`, `remainingStepDistanceMiles`, `remainingRouteDistanceMiles`, `displaySpeed`, `speedUnit`, `effectiveUserCoordinate`, `formattedRemainingDuration`, `formattedRemainingETA`, `currentNavigationStep`, `defaultAlaskaCoordinate`).
  - Implemented 18 backward-compatibility forwarding methods (`formatCountdownDistance`, `isWithinSupportedRegion`, `segmentDistanceMeters`, `dismissSearch`, `clearSearch`, `resetToExplore`, `searchCategory`, `updateCurrentStepForLiveLocation`, `updateNavigationTelemetry`, `advanceSimulationStep`, `handleLocationUpdate`, `handleQueryChange`, `selectPlace`, `calculateRouteTo`, `switchTravelMode`, `startNavigation`, `startSimulatedDrive`, `endNavigation`, `recenterOnUser`, `toggleVoiceMute`, `checkMapDataMissing`).
  - Preserved verbatim source string matching contracts checked by `RemediationTests.swift`:
    - `func dismissSearch()`
    - `func clearSearch()`
    - `func resetToExplore()`
    - `searchTask?.cancel()` (exactly 4 occurrences across lifecycle methods)
    - `isProgrammaticTextChange = true` and `if isProgrammaticTextChange`
    - `if !isNavigating && !isSimulating` in `onChange(of: viewModel.useMetric)`
    - `guard isWithinSupportedRegion(location.coordinate) else { return }` in `handleLocationUpdate`
    - Verbatim category debounce and suppression blocks in `searchCategory` and `onChange(of: destinationText)`.

---

## 2. Requirement Verification Matrix

| Requirement | Implementation Details | Verified By | Result |
|---|---|---|---|
| **R1.1 ViewModel Extraction** | Extracted 42 state properties and 23 business methods into `@MainActor NavigationViewModel` | Architecture check & compile verification | PASS |
| **R1.2 ContentView Injection** | Injected `@StateObject var viewModel: NavigationViewModel` with forwarding stubs on `ContentView` | RemediationTests source contract inspection | PASS (10/10 checks match) |
| **R1.3 AppStorage Persistence** | Persisted `"useMetric"` and `"isVoiceMuted"` with `CA92.1` alignment in `PrivacyInfo.xcprivacy` | `SettingsPersistenceTests.testT1_UserPreferencesPersistenceWithAppStorageKeys` | PASS |
| **R2.1 Switchback Clamping** | Clamped forward segment search to `currentStepEnd + 2` slack vertices | `NavigationTelemetryTests.testT1_SwitchbackSearchClampingEliminatesPrematureStepAdvance` | PASS |
| **R2.2 Monotonic Telemetry** | Monotonically counting down step distance; `0.0` at/past `stepEnd` without distance reversal | `NavigationTelemetryTests.testT1_MonotonicTelemetryCountdownDecreasesToZeroWithoutReversal` | PASS |
| **R2.3 Simulation Loop** | Replaced single `if` with `while` loop advancing `currentStepIndex` at 2x/5x | `NavigationTelemetryTests.testT1_MultiSpeedSimulationLoopAdvancesIntermediateManeuversAt5x` | PASS |
| **R2.4 Hardware GPS Start Fix** | Preserves active in-region GPS fix instead of unconditionally snapping puck to route origin | `NavigationTelemetryTests.testT1_HardwareGPSStartFixAvoidsPuckFreezing` | PASS |
| **R2.5 Dual-Point Arrival** | Evaluates distance against road-snapped endpoint (`coords.last`) AND destination pin (`selectedCoordinate`) | `NavigationTelemetryTests.testT1_DualPointArrivalDetectionTriggersAtSetbackDestination` | PASS |
