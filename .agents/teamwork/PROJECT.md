# Project: MyOfflineMapApp Production Hardening & Remediation

## Architecture
- **Navigation Architecture**:
  - `NavigationViewModel`: `@MainActor ObservableObject` encapsulating all navigation, simulation, telemetry, and search state machine logic. Injected into `ContentView`.
  - `ContentView`: Pure SwiftUI view layer observing `NavigationViewModel`, containing UI layouts, bottom sheets, HUD reflection mode, and view bindings.
  - User Preferences: `useMetric` and `isVoiceMuted` persisted across launches via `@AppStorage` / `UserDefaults.standard` with keys `"useMetric"` and `"isVoiceMuted"`, matching `PrivacyInfo.xcprivacy` (`CA92.1`).
- **Routing & Audio Concurrency**:
  - `RoutingService`: Thread-safe voice guidance with `voiceLock` guarding `isVoiceMuted` and state fields (`lastSpokenInstruction`, `lastSpokenStepId`, `lastSpokenTime`, `activeSpeechGeneration`).
  - `stopVoice()` resets audio state to `.distantPast` ensuring immediate turnaround on route restarts.
  - `speakTurnInstruction` supports `stepId == nil` deduplication fallback.
  - `calculateRoute` enforces a 5.0-second fail-fast timeout on `initGroup.wait`, returning `nil` on timeout without deadlock.
- **Geocoding & Search**:
  - `SearchService.performReverseGeocode`: Full scan of the candidate bounding box (no `< 25.0m` premature break), computing Euclidean distance to return true closest POI.
  - `SearchService.parseCoordinates`: Regex-based coordinate parser supporting degree symbols (`°`, `º`, `˚`), cardinal directions (`N`, `S`, `E`, `W`), whitespace variations, and negative coordinate conversion.
  - Category search: Expanded FTS5 query for groceries (`"grocery"* OR "groceries"* OR "supermarket"* OR "market"*`) and extended `SearchResult.category` classification for chain brands (e.g. Fred Meyer, Carrs, Costco, Safeway).
- **MapLibre Rendering & Annotations**:
  - `MapView.Coordinator`: Consumption tracking flags (`isRecenterConsumed`, `isZoomStepConsumed`) preventing redundant camera recentering and compounding zoom animations during rapid SwiftUI updates.
  - Route change detection: Complete O(N) array coordinate equality comparison avoiding missed redraws on reroutes.
  - Vehicle annotation: `mapView(_:imageFor:)` delegate method providing a directional navigation arrow / vehicle icon instead of the default red pin.
- **System & Data Layer**:
  - `LocationManager`: Speedometer zeroing (`smoothedSpeedMph = 0`, `isStationary = true`) on degraded GPS (`horizontalAccuracy >= 65.0` or `< 0`), and synchronous/DispatchQueue cleanup in `deinit` avoiding unstructured async `Task`.
  - `OfflineDataManager`: iCloud backup exclusion restricted specifically to downloaded offline asset files (`.pmtiles`, `.tar`, `.db`, `.json`) in `Documents`, preserving user documents backup eligibility.
- **Testing & Documentation**:
  - `MyOfflineMapAppTests`: Removed undeclared `import ValhallaConfigModels`, updated `testBinnedTileRouting()` via `Valhalla(configPath:)`. Added comprehensive direct unit test coverage for `SearchService.parseCoordinates` across all degree symbol variations and hemispheres.
  - `RemediationTests`: Modernized to instantiate and test `NavigationViewModel` directly, eliminating brittle `#filePath` text inspection and unmounted `ContentView` mutations.
  - `DOCUMENTATION.md` and `docs/AUDIT_REPORT.md`: Sanitized all hardcoded machine paths and simulator UDIDs with generic and repo-relative references.

---

## Feature Inventory
| # | Feature | Description | Milestone | Status |
|---|---------|-------------|-----------|--------|
| 1 | R1.1 ViewModel Extraction | Extract navigation, search, and telemetry state/methods into `@MainActor ObservableObject NavigationViewModel` | M3 | DONE |
| 2 | R1.2 ViewModel Injection | Inject `NavigationViewModel` into `ContentView` to maintain identical user-facing behavior | M3 | DONE |
| 3 | R1.3 AppStorage Persistence | Persist `useMetric` and `isVoiceMuted` across launches via `@AppStorage` / `UserDefaults` keys matching `PrivacyInfo.xcprivacy` (`CA92.1`) | M3 | DONE |
| 4 | R2.1 Switchback Search Clamping | Restrict forward coordinate search in `updateCurrentStepForLiveLocation` to current maneuver's polyline segment range (clamped to `currentStep.endIndex + 2`) | M3 | DONE |
| 5 | R2.2 Monotonic Telemetry Distance | Ensure `remainingStepDistanceMiles` counts down monotonically and evaluates to zero at/past `stepEnd` | M3 | DONE |
| 6 | R2.3 Multi-Speed Simulation Loop | Advance `currentStepIndex` via `while` loop in `advanceSimulationStep()` so 2x/5x simulation announces all maneuvers | M3 | DONE |
| 7 | R2.4 GPS Hardware Start Fix | Do not unconditionally snap `simulatedUserCoordinate` to polyline start when a valid in-region hardware GPS fix exists | M3 | DONE |
| 8 | R2.5 Dual-Point Arrival Detection | Check arrival distance against both road-snapped endpoint (`coords.last`) and destination pin (`selectedCoordinate`) | M3 | DONE |
| 9 | R2.6 GPS Degradation & Deinit | Zero smoothed speed and set stationary state on weak GPS; remove unstructured async `Task` from `LocationManager.deinit` | M2 | DONE |
| 10 | R3.1 Voice Mute Concurrency | Synchronize `isVoiceMuted` access with `voiceLock` in `RoutingService` to eliminate TSAN data races | M1 | DONE |
| 11 | R3.2 Route Restart Turn Announcement | Reset `lastSpokenInstruction`, `lastSpokenStepId`, and `lastSpokenTime` to `.distantPast` in `stopVoice()` | M1 | DONE |
| 12 | R3.3 Step Deduplication | Support step deduplication in `speakTurnInstruction` when `stepId == nil` | M1 | DONE |
| 13 | R3.4 Route Timeout Fail-Fast | Return `nil` when `initGroup.wait(timeout: .now() + 5.0)` times out, without blocking indefinitely on `queue.sync` | M1 | DONE |
| 14 | R4.1 Reverse Geocode Full Scan | Remove `< 25.0` meter break in `performReverseGeocode` to scan full bounding box and select true closest POI | M1 | DONE |
| 15 | R4.2 Coordinate Parsing with Degrees/Cardinals | Support degree symbols (`°`, `º`, `˚`), cardinal directions (`N`, `S`, `E`, `W`), and negative coordinates in `parseCoordinates` | M1, M5 | DONE |
| 16 | R4.3 Category & Grocery Search | Expand FTS5 category queries for groceries and extend `SearchResult.category` classification | M1 | DONE |
| 17 | R5.1 MapView Animation Deduplication | Prevent redundant camera recentering and zoom level animations during rapid UI updates via `Coordinator` consumption flags | M2 | DONE |
| 18 | R5.2 Full Route Coordinates Equality | Implement complete O(N) coordinate equality comparison on `routeCoordinates` updates in `MapView` | M2 | DONE |
| 19 | R5.3 Directional Vehicle Annotation | Render directional navigation arrow / vehicle icon for `carAnnotation` via MapLibre annotation image delegate | M2 | DONE |
| 20 | R6.1 Test Suite Modernization | Refactor `RemediationTests.swift` to test `NavigationViewModel` directly without source file text inspection | M4 | DONE |
| 21 | R6.2 Valhalla Config Test Fix | Remove undeclared `import ValhallaConfigModels` and update `testBinnedTileRouting()` to initialize Valhalla via config path | M4 | DONE |
| 22 | R6.3 Scoped iCloud Backup Exclusion | Exclude only downloaded offline map asset files in Documents directory from iCloud backup rather than entire directory | M2 | DONE |
| 23 | R6.4 Documentation Sanitization | Sanitize hardcoded machine paths and simulator UDIDs in `DOCUMENTATION.md` and `docs/AUDIT_REPORT.md` | M4 | DONE |
| 24 | Final E2E Test Suite Pass | 100% pass of E2E test suite (Tiers 1-4) published by E2E track | M5 | DONE |
| 25 | Adversarial Coverage Hardening | White-box adversarial testing, degree symbol normalization, and bug fix hardening (Tier 5) | M5 | DONE |

---

## Milestones
| # | Name | Scope | Dependencies | Status | Outputs / Verification |
|---|------|-------|-------------|--------|------------------------|
| M1 | Routing & Search Concurrency Hardening | R3.1-R3.4 (RoutingService concurrency, voiceLock, timeout) and R4.1-R4.3 (SearchService reverse geocode, coordinate parsing, category queries) | none | DONE | RoutingService.swift, SearchService.swift, ContentView.swift:305. All 9 unit tests pass; TSAN clean across 64 threads; 69/69 E2E tests pass. Gate Result: PASS. |
| M2 | Location, Map Rendering & Asset Storage | R2.6 (LocationManager degraded GPS & deinit), R5.1-R5.3 (MapView animation deduplication, coordinate equality, vehicle annotation), and R6.3 (OfflineDataManager iCloud backup exclusion) | none | DONE | LocationManager.swift, MapView.swift, OfflineDataManager.swift. All 7 unit/remediation tests pass; 69/69 E2E tests pass; 4/4 adversarial stress tests pass (TSAN clean); #filePath count exactly 1; Forensic Auditor CLEAN. Gate Result: PASS. |
| M3 | Navigation ViewModel Architecture & Telemetry | R1.1-R1.3 (NavigationViewModel extraction, ContentView injection, AppStorage persistence) and R2.1-R2.5 (switchback clamping, monotonic telemetry, simulation loop, GPS hardware start, dual-point arrival) | M1, M2 | DONE | NavigationViewModel.swift, ContentView.swift. 37 nonmutating setters, 0 compiler errors; 10/10 string contracts pass; 55/55 empirical stress tests pass; 69/69 E2E tests pass; Forensic Auditor CLEAN. Gate Result: PASS. |
| M4 | Test Modernization, Build Config & Documentation | R6.1 (RemediationTests refactoring to test ViewModel directly), R6.2 (ValhallaConfigModels removal & testBinnedTileRouting fix), R6.4 (DOCUMENTATION.md and AUDIT_REPORT.md sanitization) | M3 | DONE | RemediationTests.swift (0 #filePath, 0 ContentView), MyOfflineMapAppTests.swift (0 ValhallaConfigModels), DOCUMENTATION.md & docs/AUDIT_REPORT.md (0 machine paths/UDIDs). Test target compiles with 0 errors; 39/39 GPS stress passed; 200-thread TSan audio concurrency clean; 69/69 E2E tests passed; Forensic Auditor CLEAN. Gate Result: PASS. |
| M5 | Final Milestone: E2E Test Pass & Adversarial Hardening | Phase 1: Pass 100% E2E test suite (Tiers 1-4); Phase 2: Adversarial coverage hardening (Tier 5) | M4, TEST_READY.md | DONE | SearchService.swift (regex and separator degree expansion [°º˚]), TestHarness.swift, MyOfflineMapAppTests.swift. Full test target compiles with 0 errors; 69/69 E2E tests pass (100%); 83/83 parser adversarial stress pass; 39/39 GPS stress pass; 9/9 audio concurrency (200 threads) pass; 34/34 degree parsing pass; 19/19 ViewModel stress pass; Forensic Auditor CLEAN. Gate Result: PASS. |

Parallel Track:
- **E2E Testing Track**: COMPLETE. TEST_INFRA.md and TEST_READY.md published. 69 tests across Tiers 1-4 passing 100% in 0.113s.

---

## Interface Contracts

### `RoutingService` ↔ `NavigationViewModel`
- `public var isVoiceMuted: Bool`: Thread-safe getter and setter synchronized via `voiceLock`.
- `public func stopVoice()`: Resets `activeSpeechGeneration`, `lastSpokenInstruction = ""`, `lastSpokenStepId = nil`, `lastSpokenTime = .distantPast`.
- `public func speakTurnInstruction(_ text: String, stepId: Int?, force: Bool)`: Thread-safe instruction announcement with non-nil and nil `stepId` deduplication.
- `public func calculateRoute(from:to:mode:useMetric:) -> RouteDetails?`: 5.0s timeout fail-fast returning `nil` on timeout.

### `SearchService` ↔ `NavigationViewModel`
- `public func performReverseGeocode(coordinate: CLLocationCoordinate2D) -> SearchResult?`: Scans full bounding box candidate list (up to 250 rows) for true minimum Euclidean distance POI.
- `public func parseCoordinates(query: String) -> CLLocationCoordinate2D?`: Parses decimal degrees, degree symbols (`°`, `º`, `˚`), and cardinal direction letters (`N`, `S`, `E`, `W`). Returns valid coordinates or `nil`.
- `public func performSearch(query: String, userLocation: CLLocationCoordinate2D?) -> [SearchResult]`: FTS5 prefix and expanded category queries.

### `LocationManager` ↔ `NavigationViewModel`
- `public private(set) var location: CLLocation?`: Observable GPS location.
- `public private(set) var smoothedSpeedMph: Int`: Smoothed speed in mph. Zeroed immediately when `horizontalAccuracy >= 65.0` or `< 0`.
- `public private(set) var isStationary: Bool`: Set to `true` when speed is 0 or GPS is degraded.
- `deinit`: Synchronous or queued notification de-registration without unstructured `Task`.

### `NavigationViewModel` ↔ `ContentView`
- `@MainActor public final class NavigationViewModel: ObservableObject`: Injected via `@StateObject` into `ContentView`.
- Exposes published properties for map, navigation, simulation, search, and telemetry state.
- Exposes action methods: `recenterOnUser()`, `handleLocationUpdate(_:)`, `startNavigation()`, `startSimulatedDrive()`, `advanceSimulationStep()`, `endNavigation()`, `handleQueryChange(_:)`, `searchCategory(_:)`, `selectPlace(_:)`, `switchTravelMode(_:)`, `dismissSearch()`, `clearSearch()`, `resetToExplore()`.
- Backward-compatibility forwarding stubs in `ContentView` preserve existing member-access semantics.

---

## Code Layout
- `MyOfflineMapApp/Sources/NavigationViewModel.swift` [Owned by M3 Worker - COMPLETE]
- `MyOfflineMapApp/Sources/ContentView.swift` [Owned by M3 Worker - COMPLETE]
- `MyOfflineMapApp/Sources/RoutingService.swift` [Owned by M1 Worker - COMPLETE]
- `MyOfflineMapApp/Sources/SearchService.swift` [Owned by M1 & M5 Worker - COMPLETE]
- `MyOfflineMapApp/Sources/LocationManager.swift` [Owned by M2 Worker - COMPLETE]
- `MyOfflineMapApp/Sources/MapView.swift` [Owned by M2 Worker - COMPLETE]
- `MyOfflineMapApp/Sources/OfflineDataManager.swift` [Owned by M2 Worker - COMPLETE]
- `MyOfflineMapApp/Tests/MyOfflineMapAppTests/MyOfflineMapAppTests.swift` [Owned by M4 & M5 Worker - COMPLETE]
- `MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift` [Owned by M4 Worker - COMPLETE]
- `DOCUMENTATION.md` [Owned by M4 Worker - COMPLETE]
- `docs/AUDIT_REPORT.md` [Owned by M4 Worker - COMPLETE]
- `Tests/E2ETests/` [Owned by E2E Testing Track - COMPLETE]
