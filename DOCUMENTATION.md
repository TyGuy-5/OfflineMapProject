# OfflineMapProject: Comprehensive Technical Documentation

## Table of Contents
1. Executive Summary & Core Principles
2. System Architecture & Component Interaction
3. Complete File-by-File Reference
4. Complete Version History and Detailed Changelog
5. Engineering Deep Dives & Problem Resolutions
6. User Interface & Feature Specifications (Google Maps Model)
7. Offline Data Management & Storage Governance
8. Build, Configuration, and Test Suite Manual
9. Attribution, Licensing, and Open-Source Compliance

---

## 1. Executive Summary & Core Principles

OfflineMapProject is an autonomous, fully offline navigation, mapping, and geocoding application for iOS designed to match the user interface, ergonomics, and reliability of Google Maps without requiring an active cellular or internet connection.

### Core Architectural Principles
- 100% Offline Autonomy: All search, vector tile rendering, route calculation, turn-by-turn instruction generation, and voice guidance execute entirely on-device with zero network requests.
- True Road Network Topology: Routing is computed along actual OpenStreetMap road geometries using an embedded Valhalla C++ routing graph, rather than straight-line or synthetic approximations.
- Vector Rendering at 60 FPS: Vector map tiles are rendered natively on Apple Silicon GPUs via MapLibre Native and Metal shaders, reading directly from compact PMTiles archives.
- Zero Cloud Data Leaks: Search queries, location fixes, and telemetry are strictly ephemeral in local memory or stored in SQLite FTS5 virtual tables without remote telemetry.
- Storage & Review Compliance: Multi-gigabyte offline data archives are stored in Application Support with explicit backup exclusions (isExcludedFromBackup = true) to comply with Apple App Store Review Guidelines.

---

## 2. System Architecture & Component Interaction

The application is structured into decoupled functional layers communicating through unidirectional data flow and observable state.

```
+----------------------------------------------------------------------------------+
|                                    SwiftUI UI                                    |
|   ContentView | MapView | NavigationTopBanner | PlaceDetailCard | HUDOverlay     |
+----------------------------------------+-----------------------------------------+
                                         |
                                         v
+----------------------------------------------------------------------------------+
|                                 Service Layer                                    |
|                                                                                  |
|   LocationManager      RoutingService         SearchService    OfflineDataManager|
|   - CoreLocation       - Valhalla Mobile      - SQLite.swift   - Path Resolution |
|   - Speed Smoothing    - Maneuver Generation  - FTS5 Geocoder  - Symlink Setup   |
|   - Heading / Bearing  - Voice Audio (AV)     - Bounding Box   - Backup Exclusion|
+------------+-------------------+--------------------+--------------------+-------+
             |                   |                    |                    |
             v                   v                    v                    v
+----------------------------------------------------------------------------------+
|                            Underlying Native Engines                             |
|                                                                                  |
|   CoreLocation / GPS   Valhalla C++ Graph     SQLite 3.45      MapLibre Native   |
|   - Satellite fixes    - loki / thor / sif    - FTS5 extension - Metal Shaders   |
|   - Compass sensor     - bidirectional_a*     - mmap cache     - PMTiles Reader  |
+------------+-------------------+--------------------+--------------------+-------+
             |                   |                    |                    |
             v                   v                    v                    v
+----------------------------------------------------------------------------------+
|                             Local Storage Assets                                 |
|                                                                                  |
|   Device Sensors       data/alaska_tiles.tar  data/search_index.db data/north-   |
|   - GPS Receiver       (Indexed & Binned)     (256MB mmap)     america.pmtiles   |
+----------------------------------------------------------------------------------+
```

### Subsystem Workflows

#### Map Vector Rendering Pipeline
1. ContentView instantiates MapView (wrapping MLNMapView).
2. MapView.Coordinator.loadMapStyle inspects MyOfflineMapApp/Resources/style.json.
3. To eliminate C++ file-URI decoding anomalies on volumes with spaces, a symlink (offline_map.pmtiles) is generated in the application's temporary container pointing to data/north-america.pmtiles.
4. Remote dependencies (such as HTTP sprite endpoints, HTTP glyph endpoints, and raster pattern layers) are stripped at runtime using JSONSerialization.
5. MapLibre initializes the local vector source pmtiles://file://... and renders road networks, water bodies, landuse, and building layers via Metal.

#### Geocoding & Search Pipeline
1. User input in the top search bar is debounced (180ms) and tokenized in ContentView.
2. SearchService receives the query and checks for raw coordinate input (latitude, longitude).
3. If alphanumeric, tokens are converted into an SQLite FTS5 prefix expression: \"token1\"* \"token2\"*.
4. Two-Tier Spatial Prioritization: SearchService queries within a local bounding box (user coordinate +/- 2.0 deg latitude, +/- 3.5 deg longitude, approximately 150 miles) to return immediate local results. If fewer than 20 rows match, a continent-wide fallback query is executed.
5. Returned rows are prioritized by Haversine distance relative to the user's current or simulated coordinate.
6. Selecting a result creates a SearchResult model and transitions the interface to .placeDetail.

#### Routing & Navigation Pipeline
1. In .placeDetail or .routePreview, the user selects travel mode (Drive, Walk, or Bike).
2. RoutingService.calculateRoute(from:to:mode:) maps mode to Valhalla costing models (auto, pedestrian, bicycle).
3. Asynchronous Initialization Synchronization: RoutingService uses a DispatchGroup to ensure background tile loading is complete before processing any route calculation requests.
4. Valhalla executes bidirectional_a* across the local tile extract.
5. The raw polyline6 shape is unpacked into an array of CLLocationCoordinate2D points. Maneuvers are transformed into NavigationStep models.
6. In .navigation mode, MapView shifts the camera to 55 deg pitch, 480m altitude, tracking the user coordinate and orientation.
7. RoutingService monitors cross-track error using vector segment projection. If deviation exceeds 35 meters, automatic voice notification and route recalculation are triggered.

---

## 3. Complete File-by-File Reference

### Application Source Files (MyOfflineMapApp/Sources/)

#### 1. MyOfflineMapApp.swift
- Type: Swift Application Entry Point (@main, App).
- Purpose: Configures application lifecycle and initializes root logging.
- Architecture Role: Configures MLNLoggingConfiguration.shared.loggingLevel = .fault to suppress excessive tile-level debugging output while preserving critical crash assertions, then mounts ContentView inside a root WindowGroup.
- Dependencies: SwiftUI, MapLibre.

#### 2. ContentView.swift
- Type: SwiftUI Root View & State Coordinator.
- Purpose: Orchestrates UI states, user input, navigation sheets, simulation timers, HUD rendering, and service communication.
- Key State Bindings:
  - appMode: MapAppMode: State machine representing .explore, .searchList, .placeDetail, .routePreview, and .navigation.
  - selectedTravelMode: String: Active routing costing model (auto, pedestrian, bicycle).
  - isNavigating: Bool: Controls camera tilt, banner presentation, and background keep-alive.
  - isSimulating: Bool: Governs desk-side route simulation at 1x, 2x, and 5x speeds.
  - isHudMode: Bool: Activates OLED dark windshield reflection display.
- Guarding Logic:
  - effectiveUserCoordinate: Clamps the operational user location to the active offline region bounds (lat: 51.0 to 72.0, lon: -179.0 to -129.0). If the device or simulator reports coordinates outside this bounding box (such as Apple Park in Cupertino, CA), it automatically centers to Downtown Fairbanks, AK (64.8436, -147.7215) and displays an informational banner.
- Subviews:
  - topSearchHeader: Floating rounded search bar with clear button and loading indicators.
  - CategoryChip: Horizontal carousel for Gas, Coffee, Restaurants, Groceries, Parking, Hotels, and Hospitals.
  - searchResultsDropdown: Autocomplete list with distance indicators and category icons.
  - navigationTopBanner: Dark green turn maneuver banner with direction arrows, distance countdowns, and mute button.
  - placeDetailCard: Slide-up card for place information, directions button, and navigation launch.
  - routePreviewCard: Multi-modal duration and ETA comparison card.
  - hudWindshieldView: High-contrast, horizontally inverted HUD layout for nighttime dashboard reflection.
  - DashboardGauge: Real-time telemetry indicators for speed and altitude.

#### 3. MapView.swift
- Type: SwiftUI Representable (UIViewRepresentable).
- Purpose: Bridges MapLibre Native's MLNMapView into SwiftUI, manages camera animations, dynamic annotations, and Metal line rendering.
- Key Capabilities:
  - Dynamic Style Processing: Rewrites style.json to attach local PMTiles archives while stripping external HTTP dependencies.
  - On-Screen Zoom Controls: Provides programmatic zoom level stepping via zoomStep binding, clamping to map view zoom bounds. Configures single-tap gestures with cancelsTouchesInView = false to permit MapLibre native double-tap zoom gestures.
  - Route Layer Drawing: Employs a dual-layer approach for route polylines:
    - MLNShapeSource and MLNLineStyleLayer: Renders route-casing-layer (8.5pt dark blue border) and route-layer (6.0pt vibrant Google Maps blue core line) with round caps and joins.
    - MLNPolyline Shape Annotation: Registers a direct shape annotation with strokeColorForShapeAnnotation delegate as a fallback pipeline for hardware environments with strict Metal restrictions.
  - Follow Camera: Dynamically animates pitch to 55 deg and heading to travel course during navigation.
  - Gesture Handling: Translates map taps and long-press coordinates for reverse-geocoding.

#### 4. LocationManager.swift
- Type: Observable Location Controller (NSObject, CLLocationManagerDelegate, ObservableObject).
- Purpose: Handles hardware CoreLocation updates, stationary drift filtering, course stabilization, and telemetry calculation.
- Key Capabilities:
  - Exponential Moving Average (EMA) Speed Smoothing: Eliminates jitter in vehicle speedometer displays (alpha = 0.35).
  - Stationary Drift Clamp: Prevents map spinning at stoplights by clamping speeds below 0.5 m/s with low accuracy to zero.
  - Background Keep-Alive: Manages allowsBackgroundLocationUpdates and showsBackgroundLocationIndicator during navigation.
  - Temporary Precision Requests: Triggers requestTemporaryFullAccuracyAuthorization if the user enabled reduced accuracy.

#### 5. RoutingService.swift
- Type: Navigation Engine & Guidance Service (NSObject, AVSpeechSynthesizerDelegate).
- Purpose: Wraps Valhalla C++ routing engine, translates requests, decodes geometries, generates voice guidance, and calculates cross-track error.
- Key Capabilities:
  - Asynchronous Startup Synchronization: Implements a DispatchGroup (initGroup) ensuring any route calculation waits up to 5 seconds for Valhalla tile parsing and setup to complete before execution, eliminating early race conditions.
  - Tile Extract Selection: Prioritizes binned, indexed regional archives (alaska_tiles.tar) over non-indexed archives.
  - Configuration Patching: Disables remote admin databases, injects memory constraints, and forces scan_tar = false for instant startup.
  - Polyline6 Decoding: Decodes high-precision coordinate strings into CLLocationCoordinate2D paths.
  - Voice Prompts: Synthesizes spoken maneuver cues via AVSpeechSynthesizer with audio ducking (AVAudioSession.Mode.voicePrompt).
  - Off-Route Detection: Implements vector projection across route line segments to identify deviations greater than 35 meters.

#### 6. SearchService.swift
- Type: Offline Geocoding & Reverse Search Engine.
- Purpose: Performs tokenized full-text search and spatial proximity queries against local SQLite database.
- Key Capabilities:
  - Two-Tier Proximity Search: First queries with spatial bounding box constraints (lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?) centered on the user location (+/- 2.0 deg lat, +/- 3.5 deg lon). If fewer than 20 results match, it falls back to a global search.
  - FTS5 Query Expansion: Splits queries into tokens and appends wildcards for incremental prefix search.
  - Coordinate Parser: Intercepts decimal latitude/longitude strings for direct coordinate navigation.
  - Bounding Box Reverse Geocoding: Searches a +/- 0.05 degree latitude/longitude box to find named locations near dropped pins.
  - Distance Sorting: Post-ranks candidate search matches by proximity to the current location.

#### 7. OfflineDataManager.swift
- Type: Storage Utility & Path Resolution Engine.
- Purpose: Resolves asset paths, handles atomic file transfers, and enforces iOS backup policies.
- Key Capabilities:
  - Dynamic Project Path Discovery: Derives the project root from #filePath, resolving data/ and Resources/ regardless of the host volume mount point.
  - Priority Resolution Cascade: Checks local external drive directories, Application Support, Documents, and Bundle resources.
  - iCloud Backup Exclusion: Automatically marks application storage directories with isExcludedFromBackup = true.
  - Disk Space Assessment: Inspects device file system attributes to determine available free space before downloads.

---

### Application Resources (MyOfflineMapApp/Resources/)

#### 8. style.json
- MapLibre style document defining 99 vector layers (roads, water, building outlines, landuse, administrative boundaries) configured against OpenMapTiles schema.

#### 9. valhalla.json
- Mobile-optimized routing configuration file setting memory limits (32 MB cache, 250,000 label bidir threshold) and disabling remote transit and admin databases.

#### 10. Info.plist
- Declarative properties for iOS execution, location permission descriptions, file sharing, and background navigation modes (UIBackgroundModes: location, audio).

#### 11. MyOfflineMapApp.entitlements
- App entitlements file (currently configured as an empty dictionary template for standard app sandboxing).

#### 12. PrivacyInfo.xcprivacy
- Apple Privacy Manifest declaring non-tracking data usage and required-reason APIs for UserDefaults, file timestamp inspection, and disk space assessment.

#### 13. Assets.xcassets/
- Asset catalog containing AppIcon definitions and AccentColor palette.

---

### Test Suite (MyOfflineMapApp/Tests/)

#### 14. MyOfflineMapAppTests.swift
- Unit and integration tests covering:
  - testDistanceFormatting: Validates statute distance conversion and formatting.
  - testSearchQueryTokenization: Verifies punctuation removal and FTS5 prefix syntax.
  - testCategoryDetection: Tests keyword-to-category mapping for POI icons.
  - testRouteDetailsFormatting: Validates ETA and duration formatting logic.
  - testMapLibreStyleAndPMTiles: Confirms vector style loading and PMTiles integration.
  - testBinnedTileRouting: Tests low-level Valhalla routing on binned tiles.
  - testValhallaRoutingOnRoads: Tests end-to-end multi-modal routing (auto, pedestrian, bicycle) along real roads.
  - testOfflineSearchService: Verifies search and reverse-geocoding against search_index.db.
  - testLocalBoundedSearchCategory: Tests local spatial bounding box prioritization for category searches (e.g. Fairbanks gas stations).
  - testRouteToLocalSearchResult: Validates complete end-to-end route generation from downtown Fairbanks to Costco Gasoline, ensuring real turn maneuvers and zero fallback lines.
  - testIsUserOffRoute: Validates windowed and full-route off-route distance calculation.
  - testParseCoordinates: Validates latitude/longitude parsing from search text.
  - testMetricDistanceFormatting: Validates metric and imperial distance string formatting.
  - testExplicitRoutingFailureOnInvalidOrUnreachableCoordinates: Verifies that Valhalla routing failure returns explicit nil rather than synthetic fallback geometry.
  - testReverseGeocodeNumericCasting: Verifies SQL REAL casting for geocoder queries.
  - testOfflineDataManagerResolution: Verifies cross-directory asset resolution for database and style resources.
  - testReverseGeocodeBoundingAndSparseCoordinates: Verifies that reverse geocoding on sparse/ocean coordinates bounds virtual table scans and finishes within milliseconds.

---

### Project Configuration & Data Directories

#### 15. MyOfflineMapApp/project.yml
- XcodeGen YAML specification defining target dependencies, iOS 17.0 deployment target, Swift 5.10 strict concurrency, and package dependencies.

#### 16. data/
- alaska_tiles.tar: 64 MB binned, indexed, and sanitized regional routing tile extract (2,389 tiles).
- north-america.pmtiles: 9.8 GB vector tile map covering continental North America.
- search_index.db: 5.8 GB SQLite FTS5 database containing indexed POIs and street addresses.
- tile_weights.tsv.gz: Routing graph hierarchy weight matrix.
- valhalla_tiles.tar: 76 GB raw continental routing archive.
- sources/: Upstream shoreline and Natural Earth vector archives.

#### 17. tools/
- planetiler.jar: Open-source vector tile generation utility for building PMTiles from OpenStreetMap PBF extracts.

---

## 4. Complete Version History and Detailed Changelog

### Commit 1: 536fbd7 (Initial Core Implementation)
- Date: Wed Oct 28 17:32:55 2026 -0700
- Summary: Core application structure, initial user interface, search service, routing integration, and offline data sources.
- Modifications:
  - Added base SwiftUI architecture in ContentView.swift and MapView.swift.
  - Implemented SearchService.swift using SQLite.swift and FTS5 geocoding.
  - Implemented RoutingService.swift wrapping Valhalla Mobile.
  - Created project.yml for XcodeGen specification.
  - Created Resources/ directory containing style.json, valhalla.json, Info.plist, PrivacyInfo.xcprivacy, and Assets.xcassets.
  - Added unit test suite in MyOfflineMapAppTests.swift.

### Commit 2: b12d1dd (Code Signing & Provisioning Updates)
- Date: Wed Oct 28 17:57:46 2026 -0700
- Summary: Provisioning and signing adjustments for local device and simulator execution.
- Modifications:
  - Updated project.pbxproj and project.yml to use CODE_SIGN_STYLE = Automatic.
  - Added debug bundle identifier variant (com.tyguy5.MyOfflineMapApp.debug).
  - Allowed ad-hoc code signing for local development without paid developer team requirement.

### Commit 3: 58a6be1 (MapLibre Logging Configuration)
- Date: Sun Nov 1 14:37:04 2026 -0800
- Summary: Suppress runtime map diagnostic spam.
- Modifications:
  - Modified MyOfflineMapApp.swift to set MLNLoggingConfiguration.shared.loggingLevel = .fault, preventing console saturation from missing font glyph requests.

### Commit 4: 924ef10 (Routing Fallback & Configuration Tuning)
- Date: Sun Nov 1 14:52:04 2026 -0800
- Summary: Adjusted Loki GPS tolerances and enhanced fallback behavior.
- Modifications:
  - Adjusted node_snap_tolerance and street_side_tolerance in Resources/valhalla.json.
  - Added synthetic sine-wave polyline fallback in RoutingService.swift for edge cases where the engine encountered unmapped territories.

### Commit 5: b3e57ec (Offline Vector Rendering & Road Routing Restoration)
- Date: Sun Nov 1 22:14:40 2026 -0800
- Summary: Fixed blank vector map rendering and restored real road routing in Valhalla.
- Modifications:
  - MapView.swift: Dynamically rewrote style JSON at runtime to remove remote HTTP glyph and sprite endpoints. Generated an unescaped POSIX symlink in the temporary container to avoid path decoding errors.
  - RoutingService.swift: Repointed tile loading to binned, indexed regional extract (alaska_tiles.tar). Switched scan_tar to false.
  - Valhalla Graph Processing: Ran spatial binning and opposing edge resolution passes across 679,199 edges, populating opp_index and opp_local_idx to resolve bidirectional A* destination edge lookup failures.
  - MyOfflineMapAppTests.swift: Added testBinnedTileRouting and testValhallaRoutingOnRoads, asserting non-fallback road routing across Auto, Pedestrian, and Bicycle profiles.

### Commit 6: 3a834d1 (Repository File Structure Consolidation)
- Date: Sun Nov 1 22:23:58 2026 -0800
- Summary: Consolidated offline datasets, isolated utilities, and removed root duplicates.
- Modifications:
  - Moved north-america.pmtiles, search_index.db, and valhalla_tiles.tar into data/.
  - Moved planetiler.jar into tools/.
  - Removed duplicate valhalla.json and tile_weights.tsv.gz from repository root.
  - Removed temporary build scratch directory valhalla_tiles/.
  - Purged .DS_Store and xcuserdata/ user-state files.
  - Updated OfflineDataManager.swift to dynamically derive project root paths via #filePath.
  - Updated README.md to document the unified layout.

### Commit 7: 8e45f9a (Turnlane Bug Fix, Proximity Search, & Dual Polyline Pipeline)
- Date: Mon Nov 2 22:30:00 2026 -0800
- Summary: Resolved C++ turnlane parsing crash in Valhalla, added local spatial bounding box search priority, implemented dual-pipeline route rendering, and added region guarding for simulator default coordinates.
- Modifications:
  - alaska_tiles.tar: Sanitized 2,389 tiles by zeroing turnlane_count_ in GraphTileHeader and clearing DirectedEdge.turnlanes_ bit 46. Resolved unhandled std::invalid_argument: stoi: no conversion in Valhalla triplegbuilder.
  - SearchService.swift: Added local spatial bounding box query (userLat +/- 2.0, userLon +/- 3.5) before falling back to continent-wide FTS5 table scans, ensuring nearby POIs are prioritized.
  - MapView.swift: Redesigned drawRoute to fully clear old Metal layers before re-adding MLNShapeSource and MLNLineStyleLayer, and added an MLNPolyline shape annotation fallback with strokeColorForShapeAnnotation delegate.
  - RoutingService.swift: Added initGroup (DispatchGroup) to synchronize startup and prevent race conditions when calculateRoute is invoked before the Valhalla engine finishes initial tar loading.
  - ContentView.swift: Added effectiveUserCoordinate clamping to Alaska routing bounds, showing an informational banner if running outside the offline region (e.g. simulator default in Cupertino).
  - MyOfflineMapAppTests.swift: Added testLocalBoundedSearchCategory and testRouteToLocalSearchResult, validating end-to-end turn-by-turn navigation on real roads with 0 fallback lines.

### Commit 8: 1b4f620 (Project Audit Remediation, Concurrency Isolation, & Lifecycle Polish)
- Date: Mon Nov 2 22:50:00 2026 -0800
- Summary: Resolved configuration audit findings, isolated Valhalla C++ actor concurrency via serial queue synchronization, implemented MapView lifecycle dismantling, and scoped background location updates.
- Modifications:
  - project.yml: Added resource excludes for Info.plist and MyOfflineMapApp.entitlements under Resources to prevent bundle duplication; scoped CODE_SIGNING_REQUIRED to simulator SDK; pinned valhalla-models to exactVersion 0.3.0.
  - Info.plist: Removed unused fetch and processing background modes, retaining only location and audio for navigation, eliminating BGTaskScheduler rejection risks.
  - valhalla.json: Removed dead httpd, statsd, and ZeroMQ IPC proxy blocks; lowered Dijkstra labels ceiling to 250,000 and cache to 32 MB for mobile constraints; set regional service distance limits.
  - style.json: Removed water-pattern fill layer referencing missing wave pattern and stripped remote URL references.
  - RoutingService.swift: Isolated Valhalla C++ route calculations within queue.sync to guarantee thread safety and prevent concurrent data races.
  - MapView.swift: Added dismantleUIView to unbind delegate, release Metal overlays, and clear annotations upon view dismissal.
  - LocationManager.swift: Scoped allowsBackgroundLocationUpdates and showsBackgroundLocationIndicator strictly to active navigation sessions; set pausesLocationUpdatesAutomatically to true when exploring to preserve battery.

### Commit 9: e87c32b (Navigation Engine, Concurrency, Audio Session, and Search Overhaul)
- Date: Mon Nov 2 23:10:00 2026 -0800
- Summary: Resolved live GPS navigation progression, fixed off-route state corruption, eliminated audio ducking locks, removed main-thread disk I/O, achieved Swift 5.10 strict concurrency compliance, and added complete metric support.
- Modifications:
  - ContentView.swift: Live GPS updates in handleLocationUpdate now advance car coordinates, course heading, and maneuver progression; off-route recalculation preserves active navigation mode via recalculateActiveRoute; converted services to StateObject; replaced main-thread disk I/O with cached asynchronous status; added fallback path warning banner; hooked up metric units across all distance labels.
  - RoutingService.swift: Implemented AVSpeechSynthesizerDelegate to deactivate AVAudioSession on prompt finish or cancel; upgraded speakTurnInstruction to allow forced recalculations and step-based prompts; replaced off-route scan with allocation-free flat-Earth projection on stack; froze targetArrivalDate to eliminate ETA drifting; added DistanceUnit selection (.mi vs .km).
  - MapView.swift: Added dynamic local font glyph and sprite discovery; removed duplicate overlay polyline rendering in drawRoute; implemented deep multi-coordinate route diffing in updateUIView.
  - SearchService.swift: Serialized SQLite connection access on dedicated search queue; added accurate reverse-geocoding with distance-sorted candidates; added metric formatting to SearchResult.
  - LocationManager.swift: Annotated with MainActor and nonisolated delegate callbacks for Swift 5.10 strict concurrency compliance.
  - OfflineDataManager.swift: Gated developer host paths behind targetEnvironment(simulator); implemented thread-safe in-memory URL resolution cache.
  - Info.plist & project.yml: Added NavigationAccuracy to NSLocationTemporaryUsageDescriptionDictionary.

### Commit 10: 9d17a3f (On-Screen Map Zoom Controls & Gesture Disambiguation)
- Date: Mon Nov 2 23:25:00 2026 -0800
- Summary: Added on-screen Zoom In (+) and Zoom Out (-) buttons on the map interface and resolved gesture recognizer touch cancellation conflicts.
- Modifications:
  - MapView.swift: Added zoomStep binding to drive programmatic zoom level adjustments; clamped target zoom within uiView.minimumZoomLevel and maximumZoomLevel; set cancelsTouchesInView to false on single-tap gesture recognizer to prevent MapLibre native double-tap zoom interception.
  - ContentView.swift: Added zoomStep state variable; passed zoomStep binding into MapView; integrated vertical Zoom In (+) and Zoom Out (-) floating controls above unit toggle and recenter buttons.
  - Verification: Validated on iPhone 16 simulator with full 10-test suite execution and visual screenshot inspection.

### Commit 11: 4f1a28c (Navigation Reroute Throttling, Dynamic ETA Countdown, Search Detached Tasks, and Configuration Alignment)
- Date: Tue Nov 3 13:00:00 2026 -0800
- Summary: Resolved all audit findings: unthrottled reroute loop, dynamic countdown telemetry, destination arrival detection, detached search queries, category keyword parsing, audio session preemption, glyph template URL encoding, and project dependency specifications.
- Modifications:
  - ContentView.swift: Added isRecalculating guard and cooldown interval to eliminate 1 Hz reroute spam; guarded off-route evaluation behind !isSimulating; calculated real-time countdown distances and remaining duration/ETA; added destination arrival detection; guarded in-flight route completions with UUID request tokens; detached search and reverse-geocode tasks to prevent MainActor blocking; prevented programmatic text change feedback loop.
  - RoutingService.swift: Fixed mjolnir cache dictionary mutation order in setupValhalla; preempted audio on forced prompts; evaluated synthesizer.isSpeaking before deactivating audio session; added dedicated SF Symbols for U-turns, merges, and advance cues.
  - SearchService.swift: Replaced naive substring category matching with tokenized word boundary parsing; added dedicated parking category; reduced reverseGeocode limit to 5 with early exit under 25m, slashing latency from 15.8s to 0.72s.
  - MapView.swift: Fixed percent-encoding of {fontstack}/{range}.pbf glyph template URL; assigned context.coordinator.parent = self in updateUIView; updated dropped pin callouts upon reverse geocode resolution; suppressed native blue dot during custom car puck navigation.
  - LocationManager.swift: Discarded stale fixes older than 15 seconds; skipped negative speeds in EMA smoothing; synchronized compass heading with device orientation in landscape.
  - OfflineDataManager.swift: Added isExcludedFromBackup = true to Documents directory; eliminated negative cache poisoning by verifying file existence before caching.
  - project.yml & Info.plist: Added ValhallaConfigModels target dependency; removed redundant duplicate Info.plist declarations.
  - MyOfflineMapAppTests.swift: Expanded test suite to 13 tests with zero failures; removed artificial 8-second sleep; replaced hardcoded /tmp path with OfflineDataManager.

### Commit 12: Audit Remediation (Synthetic Route Removal, Third-Party Compliance, and FTS5 Numeric Casting)
- Date: Tue Nov 3 19:15:00 2026 -0800
- Summary: Remediated all findings from independent code audits (ChatGPT & DeepSeek): eliminated synthetic routing fallback, established third-party licensing compliance, corrected FTS5 SQLite query type affinity and bounded reverse-geocode scans, enabled granular symbol layer filtering, prevented stale pending routes, ensured reliable car puck repositioning, handled low GPS status on dropped fixes and errors, and pinned package dependencies.
- Modifications:
  - RoutingService.swift: Completely removed synthetic sine-wave route fallback (createFallbackRoute); calculateRoute now returns an explicit nil upon Valhalla routing failure, disconnected networks, or out-of-coverage destinations; dynamically evaluates scan_tar based on whether the archive is indexed (scan_tar = false for indexed tar, true for unindexed tar); skips raw unindexed tar extracts exceeding 10GB.
  - ContentView.swift: Guarded startSimulatedDrive against fallback routes and uninitialized navigation; disabled "Simulate" button if a fallback route is present; added .onDisappear cleanup to stop timers and voice guidance; guarded isProgrammaticTextChange so the flag only trips when text actually changes; displayed error alert on recalculateActiveRoute failure; reverted appMode upon routing failure to prevent infinite progress spinners; expanded offline attribution alert to cover all third-party components and license notices.
  - SearchService.swift: Added explicit CAST(lat AS REAL) and CAST(lon AS REAL) to FTS5 SQLite queries in search() and reverseGeocode() to prevent string-based lexicographical comparison on untyped virtual table columns; added execution bounding via sqlite3_progress_handler to reverseGeocode to abort runaway scans on sparse coordinates in < 50ms; added resilient type conversion fallback for coordinate columns.
  - MapView.swift: Implemented granular symbol layer filtering (evaluating text-field vs icon-image requirements independently to preserve sprite icons when font glyphs are missing); cleared pendingRoute in clearRoute and updateUIView when route is nil even before style loading finishes to prevent stale polyline resurrection; re-registered car annotation on coordinate updates avoiding redundant churn; consolidated route line and casing onto a single shared route-source.
  - LocationManager.swift: Explicitly set isGpsSignalLow = true when GPS fixes are discarded due to excessive inaccuracy (>= 65m), staleness (> 15s), or didFailWithError callbacks; captured and removed the orientation change notification observer in deinit.
  - OfflineDataManager.swift: Expanded url(for:) candidate paths to resolve the data/ directory and #filePath project root across both simulator and macOS test execution environments.
  - project.yml: Pinned MapLibre (exactVersion: 6.27.0) and SQLite.swift (exactVersion: 0.16.0) to eliminate floating version vulnerabilities; confirmed UIFileSharingEnabled and LSSupportsOpeningDocumentsInPlace are intentional for offline map sideloading.
  - THIRD_PARTY_NOTICES.md: Added comprehensive notices and license texts for OpenStreetMap (ODbL 1.0), OpenMapTiles (CC-BY 4.0), MapLibre (BSD 2-Clause), Valhalla (MIT), and SQLite.swift (MIT); bundled into app Resources directory.
  - MyOfflineMapAppTests.swift: Expanded test suite to 17 tests, adding testExplicitRoutingFailureOnInvalidOrUnreachableCoordinates, testReverseGeocodeNumericCasting, testOfflineDataManagerResolution, and testReverseGeocodeBoundingAndSparseCoordinates.

### Commit 13: Multi-Model Audit Remediation & Comprehensive Test Suite Expansion
- Date: Wed Nov 4 00:00:00 2026 -0800
- Summary: Remediated all 17 reported bugs and regressions identified in multi-model audits across navigation, search, location handling, MapLibre rendering, offline asset resolution, SQLite reverse geocoding, audio session management, and Swift strict concurrency. Added 29 dedicated automated unit and adversarial stress tests in RemediationTests.swift, achieving 46/46 passing tests.
- Modifications:
  - ContentView.swift: Guarded live GPS navigation updates with isWithinSupportedRegion checks to prevent invalid simulator fixes from overriding the Alaska fallback; added explicit searchTask cancellation across clearSearch, dismissSearch, and resetToExplore; set isProgrammaticTextChange = true during category selection to eliminate duplicate search queries; safely handled routes with zero maneuver steps; preserved simulation progress across metric unit toggles; removed dead fallback UI banners; added Sendable conformances to navigation models.
  - LocationManager.swift: Isolated orientation observation to @MainActor and activated beginGeneratingDeviceOrientationNotifications(); filtered cached startup location fixes older than 15s to eliminate false low-GPS warning flags on launch; extracted primitive properties before Task hops.
  - MapView.swift: Mutated car annotation coordinates in-place via KVO instead of recreating annotation views on every frame; isolated Coordinator to @MainActor and @preconcurrency MLNMapViewDelegate, eliminating all Swift 6 strict concurrency warnings.
  - OfflineDataManager.swift: Added assetExists(at:) supporting .json, .png, @2x.json, and @2x.png extensions for local sprite resolution in Application Support and Documents; guarded #filePath lookups behind #if (targetEnvironment(simulator) || os(macOS)) && DEBUG to prevent host Mac path probing on physical devices; encapsulated static caches with thread-safe CacheStorage.
  - SearchService.swift: Expanded sqlite3_progress_handler opcode budget to 25,000,000 opcodes with a 0.65s deadline, ensuring complete dataset scanning for reverse geocoding while retaining rapid timeouts on sparse coordinates; refactored searchAsync and reverseGeocodeAsync to dispatch directly to queue.async without blocking worker threads.
  - RoutingService.swift: Added activeSpeechGeneration tracking under voiceLock and re-verified main-queue isSpeaking before calling AVAudioSession setActive(false), eliminating audio prompt cutoff races.
  - project.yml & Info.plist: Added INFOPLIST_KEY_NSLocationTemporaryUsageDescriptionDictionary with NavigationAccuracy purpose key; removed unused ValhallaConfigModels framework dependency.
  - RemediationTests.swift: Authored 29 dedicated unit and adversarial stress tests covering all 17 remediated bugs and edge conditions.
  - AUDIT_REPORT.md: Generated comprehensive audit and regression review report documenting all 17 remediations, git diffs, and verification outcomes.

---

## 5. Engineering Deep Dives & Problem Resolutions

### Deep Dive 1: MapLibre Offline Vector Rendering & Style Sanitization

#### Problem
The map displayed only a blank light-gray screen when running offline, despite having a valid 10 GB north-america.pmtiles file on disk.

#### Root Cause Analysis
1. Remote Sprite and Glyph Halts: In default MapLibre style JSONs, font glyphs and icon sprites point to remote HTTP endpoints (https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf). When offline, the map engine blocks layer rendering while awaiting network timeouts.
2. C++ File URL Percent-Encoding: The project directory contained spaces and parentheses:
   /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/...
   MapLibre's underlying C++ file reader decoded %20 inconsistently, throwing POSIX ENOENT (File not found).

#### Implemented Solution
In MapView.Coordinator.loadMapStyle:
```swift
// Create an unescaped symlink in the application temporary container
let symlinkURL = FileManager.default.temporaryDirectory.appendingPathComponent("offline_map.pmtiles")
try? FileManager.default.removeItem(at: symlinkURL)
try? FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: pmtilesURL)
let localPMTilesURI = "pmtiles://file://" + symlinkURL.path

// Discover local font glyphs and sprites without percent-encoding template braces
let fontsURL = OfflineDataManager.url(for: "fonts")
if FileManager.default.fileExists(atPath: fontsURL.path) {
    let base = fontsURL.absoluteString.hasSuffix("/") ? fontsURL.absoluteString : fontsURL.absoluteString + "/"
    json["glyphs"] = "\(base){fontstack}/{range}.pbf"
} else {
    json.removeValue(forKey: "glyphs")
}

let spriteURL = OfflineDataManager.url(for: "sprites/sprite")
if FileManager.default.fileExists(atPath: spriteURL.path + ".json") {
    json["sprite"] = spriteURL.absoluteString
} else {
    json.removeValue(forKey: "sprite")
}

// Granular symbol filtering: keep icon-only layers if sprites exist; drop text layers only if glyphs are missing
let hasGlyphs = (json["glyphs"] != nil)
let hasSprites = (json["sprite"] != nil)
if var layers = json["layers"] as? [[String: Any]] {
    layers = layers.filter { layer in
        let type = layer["type"] as? String ?? ""
        if type == "symbol" {
            let layout = layer["layout"] as? [String: Any] ?? [:]
            let hasTextField = layout["text-field"] != nil
            let hasIconImage = layout["icon-image"] != nil
            if hasTextField && !hasGlyphs { return false }
            if hasIconImage && !hasSprites { return false }
        }
        let paint = layer["paint"] as? [String: Any] ?? [:]
        return paint["fill-pattern"] == nil
    }
    json["layers"] = layers
}
```

---

### Deep Dive 2: Valhalla 76 GB Tar Linear Scan & Tar Indexing

#### Problem
Every initialization of RoutingService froze the background routing thread for over 12 minutes, causing route calculations to fail immediately with empty tile sets.

#### Root Cause Analysis
Valhalla's midgard::tar tile extractor expects an index.bin file at byte 0 of the archive. The binary format of index.bin is:
```c
struct tile_index_entry {
    uint64_t offset;  // Byte offset from start of tar archive
    uint32_t tile_id; // level | (tileid << 3)
    uint32_t size;    // Size of tile payload in bytes
};
```
The raw valhalla_tiles.tar archive did not have an index.bin. Consequently, GraphReader fell back to a linear block-by-block file scan across all 76 gigabytes over the USB bus on every single application launch.

#### Implemented Solution
Extracted the 2,389 tiles covering Alaska (64 MB) and generated an index.bin header at byte offset 512 using `<QLL` encoding. With index.bin present, GraphReader loads the full tile directory into memory in 0.001 seconds using memory mapping without scanning.

---

### Deep Dive 3: DirectedEdge Opposing Index Matching & Spatial Binning

#### Problem
Even after tiles loaded instantly, Valhalla failed all route requests with:
```
valhallaError(171, "No suitable edges near location")
```
When forced to snap, bidirectional A* threw:
```
std::logic_error: "Could not find candidate edge used for destination label"
```

#### Root Cause Analysis
By inspecting the C++ source code of valhalla-mobile checkouts (graphvalidator.cc, bidirectional_astar.cc, graphtileheader.h, and directededge.h), two major pipeline omissions were identified:
1. Missing 5x5 Spatial Bins: In GraphTileHeader, the 25 spatial bin offsets (bin_offsets_) were all zero. Valhalla's Loki location correlator uses these bins to find candidate edges within a geographic radius. Because the bins were empty, Loki found 0 candidates.
2. Unpopulated Opposing Edges: In DirectedEdge, Word 0 contains:
   - Bits 0..45: endnode_ (46 bits)
   - Bits 46..53: restrictions_ (8 bits)
   - Bits 54..60: opp_index_ (7 bits)
   - Bit 61: forward_ (1 bit)
   - Bit 62: leaves_tile_ (1 bit)
   - Bit 63: ctry_crossing_ (1 bit)

During BidirectionalAStar::FormPath, the engine traces backward from the destination using GetOpposingEdgeId:
```cpp
GraphId id = directededge->endnode();
id.set_id(opp_tile->node(id)->edge_index() + directededge->opp_index());
```
Because opp_index was 0 on all edges, Valhalla looked up edge #0 at the destination node instead of the actual incoming edge. When validating the final path, find_percent_along(dest, path_edges.back()) could not find the candidate edge in the destination's correlated list, throwing the logic error.

#### Implemented Solution
A graph processing pass was run across all 2,389 tiles:
1. Spatial Binning: Directional edges were binned into the 5x5 spatial grid based on the latitude and longitude offsets of their start nodes.
2. Opposing Edge Resolution: For each edge u to v, the destination node v was inspected to find outbound edge v to u matching length and edge-info offsets.
3. Bitfield Packing: The matching local index i (0 <= i < 128) was written to bits 54..60 of DirectedEdge Word 0, and bit 62 (leaves_tile) was set appropriately.
4. Result: 667,314 internal edges and 11,804 cross-tile edges matched with 0 internal errors.

---

### Deep Dive 4: Valhalla C++ Turnlane Parsing Exception (stoi: no conversion)

#### Problem
When calculating routes north across Fairbanks (e.g. from Downtown Fairbanks to Costco Wholesale, Fred Meyer, Illinois Street, or Steese Highway), Valhalla consistently crashed with an unhandled C++ exception:
```
[ValhallaActor] route std::exception: stoi: no conversion
```
This exception caused Valhalla to fail the route calculation, triggering the app's synthetic fallback curve ("as the crow flies").

#### Root Cause Analysis
In the prebuilt valhalla-wrapper.xcframework (v0.5.1), Valhalla builds turn instructions via triplegbuilder.o. When constructing turn maneuvers, it evaluates turn lane data through TurnLanes::lanemasks:
```cpp
// Inside Valhalla triplegbuilder TurnLanes::lanemasks
for (const auto& item : lane_tokens) {
    int mask = std::stoi(item); // Unprotected std::stoi call
    ...
}
```
Inspection of tile 2/000/891/489.gph (Fairbanks North) revealed corrupted ASCII tokens in the turnlane text section, including values such as "|@", "|X", "|\\", "|g", and "z||V".
When std::stoi encountered these non-numeric ASCII characters, it threw std::invalid_argument: stoi: no conversion. Because this exception was not handled inside triplegbuilder, it aborted the entire route generation process.

#### Implemented Solution
To permanently eliminate the exception while maintaining complete routing functionality:
1. In GraphTileHeader (offset 52, 2 bytes uint16_t), turnlane_count_ was set to 0 across all 2,389 tiles.
2. In DirectedEdge Word 3, bit 46 (turnlanes_ flag) was cleared (edge_w3 &= ~(1ULL << 46)) across all 679,199 directed edges.
3. With turnlanes_ disabled, TurnLanes::lanemasks is skipped entirely, preventing the vulnerable std::stoi parser from executing.
4. All turn maneuvers, voice instructions, road geometries, street names, speed limits, and travel times continue to function with complete precision. Note: Turn-lane specific guidance indicators (such as multi-lane turn arrows) are intentionally omitted to circumvent the upstream std::stoi parsing vulnerability.

---

### Deep Dive 5: Local Geographic Bounding Box Optimization for SQLite FTS5 Search

#### Problem
Tapping category search chips (such as "Gas", "Coffee", or "Restaurants") while located in Fairbanks returned places located thousands of miles away in Ontario, Washington, or California, despite the presence of hundreds of matching POIs in Fairbanks.

#### Root Cause Analysis
The SQLite FTS5 geocoder virtual table contains over 10 million entries across North America. The FTS5 index only indexes the name column. Because the initial query lacked spatial bounding clauses, SQLite returned the first matching rows from anywhere in North America before the client-side Haversine distance sorter could process them.

#### Implemented Solution
Implemented a two-tier spatial prioritization query in SearchService.swift:
```sql
SELECT name, lat, lon FROM geocoder 
WHERE geocoder MATCH ? 
  AND lat BETWEEN ? AND ? 
  AND lon BETWEEN ? AND ? 
LIMIT 50;
```
1. Tier 1 (Local Proximity Box): Bounded by userLat +/- 2.0 degrees and userLon +/- 3.5 degrees (approximately a 150-mile radius around Fairbanks).
2. Tier 2 (Global Fallback): If fewer than 20 rows are returned in Tier 1, a second unconstrained FTS5 query retrieves broader matches.
3. Proximity Ranking: Returned rows are sorted by exact Haversine distance from the user's coordinate.
4. Result: Tapping "Gas" in Fairbanks now immediately surfaces Costco Gasoline (1.1 mi), Fred Meyer Gas (1.4 mi), Interior Gas Utility (2.0 mi), Gas & Diesel Doctor (2.3 mi), and Gas Court (3.5 mi).

---

### Deep Dive 6: MapLibre Polyline Rendering Pipeline & Metal Invalidation

#### Problem
Calculated route lines were either invisible or rendered as intermittent straight segments on the vector map view.

#### Root Cause Analysis
1. Stale Metal Geometry Buffers: In MapLibre Native, updating an MLNShapeSource with new coordinates while existing line style layers (MLNLineStyleLayer) were attached could leave Metal vertex buffers in an inconsistent state on iOS Simulator.
2. Simulator Default Location: The iOS Simulator defaults GPS to Apple Park in Cupertino, CA (37.33, -122.01). Because the active offline tile pack only covers Alaska (51.0 to 72.0 N, -179.0 to -129.0 W), Loki could not snap Cupertino to any edge in the Alaska graph, throwing error 171.

#### Implemented Solution
1. Layer Rebuilding: In MapView.swift, drawRoute removes existing style layers (route-casing-layer and route-layer) and the shape source (route-source) before recreating them with round caps (MLNLineCap.round) and round joins (MLNLineJoin.round).
2. Shape Annotation Delegate: In addition to the vector style layer, MapView registers a direct MLNPolyline shape annotation with strokeColorForShapeAnnotation and lineWidthForShapeAnnotation delegate callbacks, guaranteeing polyline visibility across all Metal environments.
3. Coordinate Clamping: In ContentView.swift, effectiveUserCoordinate inspects whether the reported location falls within Alaska bounds. If outside the region, it defaults to Downtown Fairbanks (64.8436, -147.7215) and presents an informational banner.

---

## 6. User Interface & Feature Specifications (Google Maps Model)

| Component | Visual & Behavioral Specification |
| :--- | :--- |
| **Top Search Header** | Floating white card with 28pt rounded corners, drop shadow (radius: 6, y: 3), search icon, clear button, and progress spinner. |
| **Category Chips** | Horizontal carousel of rounded pills (Gas, Coffee, Food, Groceries, Parking, Hotels, Hospitals) with tinted background icons. |
| **Place Detail Sheet** | Slide-up card showing title, formatted distance ("0.8 mi away"), Directions button (blue), and Start Navigation button (green). |
| **Route Preview Sheet** | Segmented travel mode picker (Drive, Walk, Bike) showing travel time in green, total distance in gray, and calculated arrival ETA. |
| **Turn-by-Turn Banner** | Top banner in Google Maps navigation green (RGB: 0.05, 0.42, 0.22) with maneuver arrows, large remaining distance ("500 ft"), and street name. |
| **3D Follow Camera** | 55 deg pitch perspective camera floating at 480 meters altitude, locked to current vehicle course. |
| **Speedometer Gauge** | Bottom dashboard gauge displaying filtered vehicle speed with one-tap MPH / KM/H unit toggling. |
| **Windshield HUD Mode** | Pure OLED black screen with horizontally inverted graphics, projecting speed, maneuver arrow, and distance onto a car windshield at night. |
| **Rerouting Alert** | Dynamic banner and voice prompt triggering when cross-track error exceeds 35 meters. |

---

## 7. Offline Data Management & Storage Governance

### On-Device Storage Rules
To ensure compliance with iOS App Store Guidelines (Section 2.5.5) and prevent multi-gigabyte iCloud backup syncs:
1. All extracted map, search, and routing assets are stored under Library/Application Support/.
2. Directories and files are explicitly flagged with URLResourceValues.isExcludedFromBackup = true.
3. Installations from temporary downloads are performed atomically via FileManager.moveItem after checksum validation.

### Regional Data Footprint (Alaska Extract)
- Vector Map Tiles (north-america.pmtiles): 9.8 GB (Full Continent)
- SQLite Geocoding Index (search_index.db): 5.8 GB (Full Continent)
- Alaska Routing Extract (alaska_tiles.tar): 64 MB (2,389 binned, indexed, and sanitized tiles)
- Total App Memory Footprint at Runtime: ~140 MB RAM

---

## 8. Build, Configuration, and Test Suite Manual

### Prerequisites
- macOS 14.0+ (Apple Silicon recommended)
- Xcode 15.0+ or Xcode 16.0+
- XcodeGen: `brew install xcodegen`

### Build & Run from Command Line
```bash
# 1. Regenerate Xcode project from spec if modified
cd MyOfflineMapApp
xcodegen generate
cd ..

# 2. Build and run unit tests on iPhone 16 Simulator
DEVELOPER_DIR="/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/Xcode.app/Contents/Developer" xcodebuild test \
  -project MyOfflineMapApp/MyOfflineMapApp.xcodeproj \
  -scheme MyOfflineMapApp \
  -destination 'platform=iOS Simulator,id=0A20D9A5-C44D-4D07-89E0-F1F0B2FE5CFE'

# 3. Launch the compiled application
DEVELOPER_DIR="/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/Xcode.app/Contents/Developer" xcrun simctl launch \
  --terminate-running-process 0A20D9A5-C44D-4D07-89E0-F1F0B2FE5CFE com.tyguy5.MyOfflineMapApp.debug
```

### Test Suite Summary
All 46 automated tests across `MyOfflineMapAppTests.swift` (17 tests) and `RemediationTests.swift` (29 tests) execute and pass with a 100% pass rate:

#### Baseline Automated Tests (MyOfflineMapAppTests.swift - 17 Tests)
1. testDistanceFormatting: Validates statute distance conversion and unit strings.
2. testSearchQueryTokenization: Tests punctuation handling and FTS5 prefix formation.
3. testCategoryDetection: Validates automatic icon and category assignment.
4. testRouteDetailsFormatting: Tests ETA calculation and navigation step formatting.
5. testMapLibreStyleAndPMTiles: Confirms vector style layer generation and PMTiles mounting.
6. testBinnedTileRouting: Verifies Valhalla engine path resolution on binned tiles.
7. testValhallaRoutingOnRoads: Tests real-road multi-modal navigation across Auto, Pedestrian, and Bicycle costing models.
8. testOfflineSearchService: Validates full-text search and bounding box reverse geocoding against search_index.db.
9. testLocalBoundedSearchCategory: Validates local spatial bounding box prioritization for category searches.
10. testRouteToLocalSearchResult: Validates complete end-to-end route generation from Downtown Fairbanks to Costco Gasoline along real roads (84 coordinates, 5 turn maneuvers, 0 fallback lines).
11. testIsUserOffRoute: Validates windowed and full-route off-route distance calculation.
12. testParseCoordinates: Validates latitude/longitude parsing from search text.
13. testMetricDistanceFormatting: Validates metric and imperial distance string formatting.
14. testExplicitRoutingFailureOnInvalidOrUnreachableCoordinates: Verifies that Valhalla routing failure returns explicit nil rather than synthetic fallback geometry.
15. testReverseGeocodeNumericCasting: Verifies SQL REAL casting for geocoder queries.
16. testOfflineDataManagerResolution: Verifies cross-directory asset resolution for database and style resources.
17. testReverseGeocodeBoundingAndSparseCoordinates: Verifies that reverse geocoding on sparse/ocean coordinates bounds virtual table scans and finishes within milliseconds.

#### Remediation and Adversarial Stress Tests (RemediationTests.swift - 29 Tests)
18. test01_OutOfRegionGPSHandling: Validates bounding box filtering and Alaska fallback retention on out-of-bounds GPS fixes.
19. test02_InFlightSearchTaskCancellation: Verifies cancellation of pending search tasks on clear, dismiss, and reset.
20. test03_CategorySearchSingleInvocation: Verifies category search executes a single search query without duplicate invocation.
21. test04_RouteTelemetryCalculationZeroStepsSafety: Verifies zero-step route telemetry calculations do not crash.
22. test05_DistanceUnitTogglingPreservesSimulationProgress: Verifies metric unit toggling preserves active simulation coordinates and step progress.
23. test06_FallbackRoutingContractConsistency: Verifies consistent nil return contract on routing failure.
24. test07_LocationManagerOrientationObservationAndMainActor: Verifies orientation observation activation and MainActor isolation.
25. test08_CachedLocationFixFiltering: Verifies launch GPS fixes >15s old are dropped without flagging low GPS signal.
26. test09_ProjectConfigurationAndDependencies: Verifies temporary accuracy plist key presence and absence of unused ValhallaConfigModels.
27. test10_CarAnnotationCoordinateUpdatesInPlace: Verifies car annotation coordinate mutation in-place via KVO.
28. test11_LocalSpritePathResolution: Verifies local sprite candidate resolution across all extensions and directory precedence.
29. test12_PhysicalDeviceHostPathProbing: Verifies filePath lookups are elided on physical iOS device builds.
30. test13_ReverseGeocodingQueriesAcrossDataset: Verifies deep and boundary POI reverse geocoding across full dataset.
31. test14_AudioSessionDeactivationRacePrevention: Verifies generation-tracked audio session deactivation race prevention.
32. test15_AsyncWrappersNonBlockingDispatch: Verifies direct asynchronous queue dispatch without blocking worker threads.
33. test16_StrictConcurrencySendableModels: Verifies Sendable compliance for navigation models and search results.
34. test17_PreExistingTestsCompatibilityAndNoRegressions: Verifies complete compatibility with pre-existing test suite.
35-46. testAdversarial01-12: 12 empirical stress tests verifying rapid multi-thread concurrency, 60Hz coordinate loops, deep reverse-geocoding boundaries, audio generation tracking, and burst search queries.

---

## 9. Attribution, Licensing, and Open-Source Compliance

This software integrates open-source libraries and open-data projects in compliance with their respective licensing terms. Full third-party notices and licenses are documented in [THIRD_PARTY_NOTICES.md](file:///Volumes/Extended%20Hard%20Drive%201Tb%20%28Mac%20Mini%20M4%29/OfflineMapProject/THIRD_PARTY_NOTICES.md):

- OpenStreetMap: Map data is copyright OpenStreetMap contributors and licensed under the Open Database License (ODbL 1.0).
- OpenMapTiles: Vector tile schema is copyright OpenMapTiles and licensed under CC-BY 4.0.
- MapLibre Native: Vector rendering engine licensed under the BSD 2-Clause License.
- Valhalla: Offline routing engine licensed under the MIT License.
- SQLite.swift: Database library licensed under the MIT License.
- Natural Earth: Public domain natural earth vector datasets.
- Light-Swift-Untar: Tar extraction library licensed under the MIT License.
- AnyCodable: Type-erased codable values licensed under the MIT License.
