# TEST_INFRA.md — E2E Testing Infrastructure & Architecture Specification

**Project**: MyOfflineMapApp Production Hardening & Remediation  
**Track**: E2E Testing Track (teamwork_test_writer)  
**Status**: ACTIVE  
**Last Updated**: 2026-11-07  

---

## 1. Testing Philosophy & Architecture

The E2E testing infrastructure for **MyOfflineMapApp** is built strictly around **opaque-box, contract-driven, and behavior-oriented verification**. Rather than inspecting view-layer ASTs, regex-matching source files, or binding directly to internal private SwiftUI state, the test suite interacts with the application exclusively through its documented public interface contracts (as defined in `PROJECT.md` and `ORIGINAL_REQUEST.md`):

1. **Decoupled Opaque-Box Design**: Tests interact with domain models (`SearchResult`, `NavigationStep`, `RouteDetails`), service controllers (`SearchService`, `RoutingService`, `LocationManager`, `OfflineDataManager`), and navigation state contracts without relying on whether state lives in `ContentView` or has been extracted to `NavigationViewModel`.
2. **Deterministic & Isolated Execution**: Every test sets up its own isolated state, utilizes synthetic or sandbox-isolated stores (e.g. custom `UserDefaults` suite names, mock location providers, isolated temporary directories), and requires zero network access.
3. **Explicit Authoritative Oracles**: Expected outputs are derived mathematically (geodesic distance, Euclidean planar projection, monotonic inequalities), cryptographically/structurally (FTS5 SQLite table layout, MapLibre style schemas), or against the offline SQLite index in `data/search_index.db`.
4. **Dual-Environment Execution Engine**: The test suite is designed with dual-target compatibility:
   - **Standalone Native Swift CLI Runner**: Fully compilable and executable in headless Unix/macOS environments via `swiftc` without external package dependencies or Xcode UI requirements.
   - **XCTest / Xcode Integration**: Conditioned on `#if canImport(XCTest)` to integrate into `project.yml` and Xcode's `xcodebuild test` workflow for continuous integration.

---

## 2. Tiered Test Architecture

The test suite is organized into four hierarchical verification tiers:

```
┌────────────────────────────────────────────────────────┐
│     Tier 4: Real-World Application Scenarios (E2E)     │
│  Multi-step user workflows (Search -> Route -> Nav)    │
├────────────────────────────────────────────────────────┤
│     Tier 3: Cross-Feature Combinations (Pairwise)      │
│  Concurrent interactions across distinct subsystems     │
├────────────────────────────────────────────────────────┤
│     Tier 2: Boundary & Corner Cases (Adversarial)      │
│  Extreme values, bad inputs, malformed data, timeouts  │
├────────────────────────────────────────────────────────┤
│     Tier 1: Feature Coverage (Core Requirements)       │
│  >= 5 tests per feature across R1 - R6 specifications  │
└────────────────────────────────────────────────────────┘
```

### Tier 1: Feature Coverage (Core Requirements)
Covers baseline happy paths and expected behavior for every requirement in `ORIGINAL_REQUEST.md` (minimum 5 tests per feature):
- **Feature 1: Navigation State & Preferences (R1.1, R1.2, R1.3)**:
  - Explore -> RoutePreview -> Navigation -> Explore state machine transitions.
  - `@AppStorage` / `UserDefaults` persistence with keys `"useMetric"` and `"isVoiceMuted"` complying with `CA92.1`.
  - Metric vs. Imperial conversion and string formatting (`displaySpeed`, `formatCountdownDistance`, `altitudeValue`).
  - Search dismissal, place selection, and active query task state resets.
  - HUD windshield reflection mode toggle and mirror transformation state.
- **Feature 2: Navigation Telemetry & Progression (R2.1, R2.2)**:
  - Forward coordinate snapping clamped to `currentStep.endIndex + 2` on switchbacks.
  - Monotonic decrement of `remainingStepDistanceMiles` along active maneuvers.
  - Step distance evaluation to exactly `0.0` upon reaching or passing `stepEnd` (prevention of distance reversal).
  - Proportional route distance and ETA countdown calculations.
  - Advance turn warning announcement triggering when within 250 meters.
- **Feature 3: Simulation & GPS Lifecycle (R2.3, R2.4, R2.5, R2.6)**:
  - Multi-speed simulation loop at 1x advancing without dropping maneuvers.
  - Multi-speed simulation loop at 2x traversing steps cleanly.
  - Multi-speed simulation loop at 5x using `while` loop progression across multi-step jumps without skipping intermediate turns.
  - Navigation startup with valid hardware GPS retaining user position rather than snapping to polyline start.
  - Dual-point destination arrival triggering at setback destination pins (`selectedCoordinate`).
  - Dual-point destination arrival triggering at snapped road endpoints (`coords.last`).
  - Degradation of GPS (`horizontalAccuracy >= 65.0` or `< 0`) zeroing `smoothedSpeedMph` and setting `isStationary = true`.
- **Feature 4: Routing Engine & Audio Concurrency (R3.1, R3.2, R3.3, R3.4)**:
  - Synchronized `isVoiceMuted` thread safety under high-concurrency access.
  - Immediate turnaround on route restart: `stopVoice()` resetting `lastSpokenTime` to `.distantPast`.
  - Step deduplication for turn instructions with valid `stepId`.
  - Step deduplication fallback for turn instructions where `stepId == nil`.
  - Fail-fast 5.0-second timeout returning `nil` cleanly without hanging worker threads.
- **Feature 5: Geocoding & Input Parsing (R4.1, R4.2, R4.3)**:
  - Full candidate bounding box scan in `performReverseGeocode` without premature `< 25.0m` break.
  - Coordinate parser handling standard decimal degrees (`64.8436, -147.7215`).
  - Coordinate parser handling degree symbols (`64.8436°, -147.7215°`).
  - Coordinate parser handling cardinal direction suffixes (`64.8436° N, 147.7215° W`).
  - Coordinate parser handling southern and western hemisphere negative coordinates.
  - Expanded category queries for groceries (`"grocery"* OR "groceries"* OR "supermarket"* OR "market"*`) and chain brand classification (Fred Meyer, Safeway, Carrs, Costco).
- **Feature 6: MapLibre Rendering & Annotations (R5.1, R5.2, R5.3)**:
  - Recenter consumption tracking (`isRecenterConsumed`) preventing redundant camera resets.
  - Zoom step consumption tracking (`isZoomStepConsumed`) preventing compounding zoom animations.
  - Complete O(N) array coordinate equality comparison preventing missed redraws on reroutes.
  - Vehicle annotation image delegate configuration returning directional navigation icon instead of red pin.
- **Feature 7: System & Data Layer (R6.1, R6.2, R6.3, R6.4)**:
  - Scoped iCloud backup exclusion in `OfflineDataManager` protecting user Documents while excluding asset files.
  - Offline asset file resolution across candidate paths.
  - Supported Alaska bounding box GPS filtering (`[51.0, 72.0] x [-179.0, -129.0]`).

---

### Tier 2: Boundary & Corner Cases (Adversarial Robustness)
Covers boundary conditions, edge cases, malformed inputs, and resource stress (minimum 5 tests per feature):
- **Coordinate Boundaries**:
  - Exact poles and international date line boundaries (`±90.0`, `±180.0`, `0.0, 0.0`).
  - Out-of-bounds latitude/longitude values (`90.001`, `-90.001`, `180.001`, `-180.001`) safely rejected (`nil`).
  - Extreme whitespace, missing delimiters, and redundant signs (`" 64.8436 °  N  ,   --147.7215 "`).
  - Inverted coordinate ordering or alphanumeric gibberish.
  - Null-island / ocean coordinate queries.
- **Search Boundaries**:
  - Empty string and whitespace-only queries.
  - Single-character queries below minimum query length.
  - Special FTS5 characters and punctuation injection (`*`, `"`, `'`, `-`, `OR`, `AND`, `NOT`, `NEAR`).
  - Ultra-long queries (> 1,000 characters).
  - Reverse geocoding in sparse areas enforcing SQLite progress handler deadlines (< 0.7s).
- **Telemetry Boundaries**:
  - 0-step and 1-coordinate degenerate polylines (guaranteed non-crashing).
  - 2-vertex minimal road polylines.
  - Exact vertex switchback boundaries with proximate return paths.
  - Equidistant midpoint ambiguity between adjacent road segments.
  - User location beyond route destination (> 500m past polyline end).
- **Simulation Multi-Speed Boundaries**:
  - 1x speed on single-coordinate maneuver steps.
  - 2x speed landing exactly on maneuver boundaries.
  - 5x speed landing beyond polyline bounds (clean arrival).
  - Rapid mid-simulation speed multiplier toggling (1x -> 5x -> 2x).
  - Repeated cancellation and re-instantiation of simulation timers.
- **GPS Degradation Extremes**:
  - Exact threshold accuracy (`horizontalAccuracy = 65.0`).
  - Negative horizontal accuracy (`horizontalAccuracy = -1.0`).
  - Stale launch fix timestamp (> 15 seconds old discarded without warning).
  - Rapid oscillation between good GPS (5m) and degraded GPS (100m).
  - LocationManager lifecycle cleanup without hanging background tasks.

---

### Tier 3: Cross-Feature Combinations (Pairwise Interactions)
Verifies interactions between distinct subsystems operating simultaneously:
- **Pairwise 1: Route Restart + Voice Mute Toggle**:
  Cancelling active navigation, muting audio, restarting route within 3 seconds, unmuting, and verifying prompt playback.
- **Pairwise 2: Simulation 5x + Unit System Switching**:
  Running simulation at 5x speed while toggling `useMetric` dynamically mid-route, asserting telemetry units convert without resetting step index.
- **Pairwise 3: Cardinal Coordinate Search + Reverse Geocoding**:
  Parsing cardinal coordinate input (`64.8436° N, 147.7215° W`), creating a map pin, and performing reverse geocoding to resolve the closest POI.
- **Pairwise 4: GPS Accuracy Degradation during Navigation**:
  Driving along active route when GPS signal degrades to 85m; verifying speedometer immediately drops to 0 while rerouting guards prevent false recalculation.
- **Pairwise 5: Rapid Zoom & Recenter during Route Polyline Update**:
  Triggering simultaneous recenter and zoom steps while a new route is drawn, verifying flags prevent animation race conditions.
- **Pairwise 6: Category Search + Local Spatial Bounding Box**:
  Searching "Groceries" with active user location in Fairbanks, asserting local Fairbanks stores outrank distant stores.
- **Pairwise 7: Windshield HUD Reflection + Turn Maneuvers**:
  Enabling HUD mode and advancing through maneuvers, verifying mirror transformation preserves icon and direction attributes.
- **Pairwise 8: Background Route Calculation + Search Cancellation**:
  Initiating background Valhalla route calculation with 5s fail-fast timeout while concurrently cancelling and modifying search tasks on the main queue.

---

### Tier 4: Real-World Application Scenarios (Comprehensive Workflows)
End-to-end simulations of actual user sessions:
- **Scenario 1: Fairbanks Grocery Run (Downtown to Co-Op Market)**:
  User searches for "Groceries" in Fairbanks -> selects "Co-Op Market & Deli" -> previews route details -> begins navigation -> advances through all maneuvers via simulation -> arrives at destination -> verifies complete state reset.
- **Scenario 2: Setback Parking Lot Arrival**:
  User navigates to a destination whose parking lot is set back 35 meters from the road centerline. As the vehicle reaches the end of the road and turns into the lot, dual-point arrival triggers upon reaching the destination pin.
- **Scenario 3: Dense Urban Reverse Geocode at Switchback**:
  User long-presses near a switchback intersection with multiple POIs within 25m. The geocoder scans the full candidate bounding box and selects the candidate with the true minimum Euclidean distance.
- **Scenario 4: High-Speed Rural Commute with Unit Switching**:
  User drives a highway route at 5x simulation in imperial units, toggles to metric halfway through, verifies seamless speed and distance countdown transitions, and completes the commute.
- **Scenario 5: Mountainous Canyon GPS Signal Loss**:
  User navigates through a mountain pass where GPS accuracy degrades from 5m to 90m for several seconds before regaining full signal. Speedometer zeroes, low GPS banner displays, and guidance resumes seamlessly upon signal recovery.

---

## 3. Directory Layout & Artifact Index

```
OfflineMapProject/
├── Tests/
│   └── E2ETests/
│       ├── Runner/
│       │   ├── TestRunner.swift            # Core test harness, suite registry, report generator
│       │   └── main.swift                  # CLI entry point
│       ├── Support/
│       │   ├── TestAssertions.swift        # XCTest-compatible assertion library
│       │   ├── TestData.swift              # Shared route geometries, Fairbanks coordinates, POIs
│       │   └── TestHarness.swift           # Opaque mock controllers, state managers, timers
│       ├── Tier1_FeatureCoverage/
│       │   ├── NavigationTelemetryTests.swift
│       │   ├── RouteRestartAudioTests.swift
│       │   ├── GeocodingAndParsingTests.swift
│       │   ├── MapRenderingTests.swift
│       │   └── SettingsPersistenceTests.swift
│       ├── Tier2_BoundaryCases/
│       │   ├── CoordinateBoundaryTests.swift
│       │   ├── SearchBoundaryTests.swift
│       │   ├── TelemetryBoundaryTests.swift
│       │   ├── SimulationBoundaryTests.swift
│       │   └── GPSAccuracyBoundaryTests.swift
│       ├── Tier3_PairwiseCombinations/
│       │   ├── AudioSimulationCombinationsTests.swift
│       │   ├── GeocodingNavigationCombinationsTests.swift
│       │   └── TelemetryUnitCombinationsTests.swift
│       ├── Tier4_RealWorldScenarios/
│       │   ├── FairbanksGroceryScenarioTests.swift
│       │   ├── SetbackParkingScenarioTests.swift
│       │   ├── UrbanReverseGeocodeScenarioTests.swift
│       │   └── GPSDegradationScenarioTests.swift
│       └── run_e2e_tests.sh                # Executable runner script
└── .agents/teamwork/
    ├── TEST_INFRA.md                       # This document
    └── TEST_READY.md                       # Test runner command, coverage matrix, verification results
```

---

## 4. Test Runner Invocation Command

### Running the Standalone CLI E2E Runner
```bash
./Tests/E2ETests/run_e2e_tests.sh
```
Or directly via the Swift compiler:
```bash
TMPDIR=/tmp swiftc -module-cache-path /tmp/clang-cache \
  -o /tmp/e2e_runner \
  Tests/E2ETests/Support/*.swift \
  Tests/E2ETests/Tier1_FeatureCoverage/*.swift \
  Tests/E2ETests/Tier2_BoundaryCases/*.swift \
  Tests/E2ETests/Tier3_PairwiseCombinations/*.swift \
  Tests/E2ETests/Tier4_RealWorldScenarios/*.swift \
  Tests/E2ETests/Runner/TestRunner.swift \
  Tests/E2ETests/Runner/main.swift \
  && /tmp/e2e_runner
```

### Running via Xcode / xcodebuild
```bash
DEVELOPER_DIR="/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/Xcode.app/Contents/Developer" xcodebuild test \
  -project MyOfflineMapApp/MyOfflineMapApp.xcodeproj \
  -scheme MyOfflineMapApp \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## 5. Oracles and Derivation Strategy

| Test Domain | Oracle / Authoritative Source | Verification Technique |
|---|---|---|
| Geodesic & Planar Distances | Spherical Law of Cosines & Euclidean projection | Floating-point delta comparison (`accuracy: 1e-4`) against known physical benchmarks |
| Monotonic Step Countdown | Telemetry algorithm contract (`PROJECT.md` R2.2) | Strict monotonic inequality check ($d_{k+1} \le d_k$) and exact zero identity ($d = 0.0$ for $i \ge stepEnd$) |
| Coordinate Parsing | Regex specification (`PROJECT.md` R4.2) | Validated against latitude range $[-90, 90]$ and longitude range $[-180, 180]$ across degrees and cardinals |
| Reverse Geocoding | Full scan contract (`ORIGINAL_REQUEST.md` R4.1) | Candidate bounding box Euclidean distance evaluation; closest candidate minimum distance check |
| Category Classification | Brand dictionary & FTS5 expansion (`PROJECT.md` R4.3) | Categorical match check for gas, coffee, food, grocery, hotel, parking, park, hospital, airport |
| GPS Telemetry & Accuracy | CoreLocation contract (`ORIGINAL_REQUEST.md` R2.6) | Telemetry state evaluation on degraded accuracy ($\ge 65m$ and $< 0$) asserting zero speed |
| User Settings Persistence | UserDefaults specification (`PrivacyInfo.xcprivacy` CA92.1) | Direct inspection of isolated UserDefaults suite matching keys `"useMetric"` and `"isVoiceMuted"` |
| Concurrency & Voice Turnaround | Thread safety contract (`PROJECT.md` R3.1, R3.2) | Multi-threaded race condition stress tests and timestamp inspection |
