Harden and remediate MyOfflineMapApp for production release by applying bug fixes across navigation, routing concurrency, SQLite/FTS5 geocoding, and MapLibre rendering, and refactoring navigation state into an isolated ViewModel for robust unit testing.

Working directory: /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject
Integrity mode: development

## Requirements

### R1. Navigation State Machine and ViewModel Architecture
- Extract navigation, search, and telemetry state properties and methods out of `ContentView` into an `@MainActor` `ObservableObject` `NavigationViewModel`.
- Inject `NavigationViewModel` into `ContentView` to maintain identical user-facing behavior while separating state management from view layout.
- Persist user preferences (`useMetric` and `isVoiceMuted`) across launches using `@AppStorage` keys, aligning with `PrivacyInfo.xcprivacy`.

### R2. Navigation Telemetry, Step Progression, and GPS Lifecycle Fixes
- Restrict forward coordinate search in `updateCurrentStepForLiveLocation` to the current maneuver's polyline segment range (clamped to `currentStep.endIndex + 2`) to eliminate premature step advancement on switchbacks and proximate road segments.
- Correct `updateNavigationTelemetry` so that `remainingStepDistanceMiles` counts down monotonically and evaluates to zero (or distance to destination endpoint) when the user reaches or passes `stepEnd`, preventing distance reversal.
- In `advanceSimulationStep()`, advance `currentStepIndex` via a loop rather than a single `if` check so simulation at 2x and 5x speeds does not skip intermediate maneuvers.
- In `startNavigation()`, do not unconditionally snap `simulatedUserCoordinate` to the polyline start when a valid in-region hardware GPS fix exists.
- In arrival detection, check distance against both the road-snapped endpoint (`coords.last`) and the destination pin (`selectedCoordinate`), allowing arrival completion when destinations are set back from the road.
- In `LocationManager.swift`, zero out smoothed speed and set stationary state when GPS accuracy degrades (`horizontalAccuracy >= 65.0` or `< 0`), and remove the unstructured async `Task` from `deinit`.

### R3. Routing Engine and Audio Concurrency Safety
- In `RoutingService.swift`, synchronize `isVoiceMuted` access with `voiceLock` to eliminate data races between SwiftUI bindings and background audio threads.
- In `stopVoice()`, reset `lastSpokenInstruction`, `lastSpokenStepId`, and `lastSpokenTime` to `.distantPast` so restarting navigation within 6 seconds on the same route reliably announces the initial turn.
- Fix step deduplication in `speakTurnInstruction` so calls where `stepId == nil` are correctly handled.
- Ensure route calculation fails fast by cleanly returning `nil` when `initGroup.wait(timeout: .now() + 5.0)` times out, without blocking indefinitely on `queue.sync`.

### R4. Geocoding Optimization and Input Parsing
- In `SearchService.swift`, remove the premature `< 25.0` meter break in `performReverseGeocode` so the search scans the candidate bounding box and selects the true closest POI.
- Update `parseCoordinates` to accept coordinates with degree symbols (`°`) and cardinal direction suffixes (`N`, `S`, `E`, `W`), parsing negative values correctly.
- Refine category classification and search queries for POI categories such as groceries.

### R5. MapLibre Rendering and Navigation Annotations
- In `MapView.swift`, prevent redundant camera recentering and zoom level animations during rapid UI updates by tracking consumption state in `Coordinator`.
- Perform a complete coordinate equality check on `routeCoordinates` updates instead of sampling 3 vertices, avoiding missed redraws on reroutes.
- Render a directional navigation arrow / vehicle icon for `carAnnotation` using MapLibre annotation image delegate methods instead of the default red pin.

### R6. Build Configuration, Test Suite Modernization, and Documentation
- Refactor `RemediationTests.swift` to test state transitions and logic on `NavigationViewModel` directly, replacing brittle source-code file string matching and unmounted `ContentView` mutations.
- Remove the undeclared `import ValhallaConfigModels` and update `testBinnedTileRouting()` in `MyOfflineMapAppTests.swift` to initialize Valhalla via config path.
- In `OfflineDataManager.swift`, exclude only downloaded offline map asset files in the Documents directory from iCloud backup rather than excluding the entire directory.
- Sanitize `DOCUMENTATION.md` and `docs/AUDIT_REPORT.md` by replacing hardcoded user-specific local machine paths (`/Volumes/Extended Hard Drive...`) and simulator UDIDs with generic or repo-relative paths.

## Acceptance Criteria

### Navigation Telemetry & Progression
- [ ] Navigation on switchback or parallel polyline segments does not jump forward beyond the current maneuver's end index (+2 vertices slack).
- [ ] `remainingStepDistanceMiles` decreases monotonically towards zero and never increases after `clampedIndex >= stepEnd`.
- [ ] Multi-speed simulation (1x, 2x, 5x) announces and advances every intermediate maneuver without dropping steps.
- [ ] Starting navigation with valid hardware GPS does not freeze the puck at the route starting coordinate.
- [ ] Destination arrival triggers when approaching within threshold of either the snapped polyline end or the actual destination coordinate.

### Concurrency & Audio Voice Prompts
- [ ] Toggling `isVoiceMuted` concurrently with speech instruction synthesis executes without data race warnings under Thread Sanitizer.
- [ ] Canceling navigation and restarting the same route within 6 seconds speaks the first turn instruction.
- [ ] Routing requests abort cleanly within 5.0 seconds if the Valhalla initialization group times out.
- [ ] Weak GPS signals (`horizontalAccuracy >= 65m`) immediately zero out speedometer values (`smoothedSpeedMph = 0`).

### Search & Geocoding
- [ ] Reverse geocoding in dense POI areas returns the candidate with the minimum distance to the query point.
- [ ] `parseCoordinates` successfully parses coordinate queries with degree signs and cardinal directions (e.g. `64.8436° N, 147.7215° W`).

### Rendering & User Interface
- [ ] Rapid consecutive zoom or recenter requests do not cause duplicated `setZoomLevel` calls in `MapView`.
- [ ] Rerouting to an alternative route with identical vertex count triggers route redrawing.
- [ ] Navigation vehicle icon displays as a directional symbol rather than a standard pin annotation.
- [ ] `useMetric` and `isVoiceMuted` settings persist across app relaunches via `@AppStorage`.

### Architecture, Test Suite & Documentation
- [ ] `NavigationViewModel` manages navigation, search, and telemetry state, injected into `ContentView`.
- [ ] `RemediationTests` and `MyOfflineMapAppTests` compile cleanly and pass via `xcodebuild test` without relying on source file text inspection.
- [ ] `PrivacyInfo.xcprivacy` matches the codebase's actual API usage (`@AppStorage` / `UserDefaults`).
- [ ] `DOCUMENTATION.md` and `docs/AUDIT_REPORT.md` contain no hardcoded `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/` paths or specific machine simulator UDIDs.