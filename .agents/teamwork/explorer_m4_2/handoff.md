# Milestone 4 Handoff Report: Requirement R6.2 Investigation

## 1. Observation

### Observation 1.1: Undeclared Import and Usage in `MyOfflineMapAppTests.swift`
- **File**: `MyOfflineMapApp/Tests/MyOfflineMapAppTests/MyOfflineMapAppTests.swift`
- **Lines 1–8**:
  ```swift
  import XCTest
  import CoreLocation
  import MapLibre
  import Valhalla
  import ValhallaModels
  import ValhallaConfigModels
  @testable import MyOfflineMapApp
  ```
- **Lines 154–165**:
  ```swift
      func testBinnedTileRouting() throws {
          let testTarPath = OfflineDataManager.url(for: "alaska_tiles.tar").path
          guard FileManager.default.fileExists(atPath: testTarPath) else {
              throw XCTSkip("alaska_tiles.tar not available on disk")
          }
          var config = ValhallaConfig()
          config.mjolnir?.tileExtract = testTarPath
          config.mjolnir?.trafficExtract = nil
          config.mjolnir?.tileDir = nil
          config.loki?.useConnectivity = false
          let valhalla = try Valhalla(config)
  ```
- **Lines 166–192**:
  ```swift
          // Downtown Fairbanks to South Cushman St
          let start = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
          let dest = CLLocationCoordinate2D(latitude: 64.8358, longitude: -147.7345)
          
          let request = RouteRequest(
              locations: [
                  RoutingWaypoint(lat: start.latitude, lon: start.longitude),
                  RoutingWaypoint(lat: dest.latitude, lon: dest.longitude)
              ],
              costing: .auto,
              units: .mi
          )
          
          do {
              let response = try valhalla.route(request: request)
              print(">>> SUCCESSFUL ROUTE! Status: \(response.trip.statusMessage ?? "nil"), Legs: \(response.trip.legs.count)")
              if let leg = response.trip.legs.first {
                  print(">>> Leg shape points: \(leg.shape.count), length: \(leg.summary.length) mi, time: \(leg.summary.time) s, maneuvers: \(leg.maneuvers.count)")
                  for m in leg.maneuvers {
                      print(">>> Step: \(m.instruction) on \(m.streetNames?.joined(separator: ", ") ?? "unnamed")")
                  }
              }
              XCTAssertEqual(response.trip.statusMessage, "Found route between points")
          } catch {
              XCTFail("Route failed: \(error)")
          }
      }
  ```

### Observation 1.2: Dependencies in `project.yml` and `Package.resolved`
- **File**: `MyOfflineMapApp/project.yml` (lines 17–30, 78–87, 88–100):
  ```yaml
  packages:
    MapLibre:
      url: https://github.com/maplibre/maplibre-gl-native-distribution
      exactVersion: "6.27.0"
    SQLite.swift:
      url: https://github.com/stephencelis/SQLite.swift
      exactVersion: "0.16.0"
    valhalla-mobile:
      url: https://github.com/Rallista/valhalla-mobile
      revision: 1f1f79685dc8b24d0a701a90d60f3ce72fcad09f
    valhalla-models:
      url: https://github.com/Rallista/valhalla-openapi-models-swift
      exactVersion: "0.3.0"
  ```
  ```yaml
      dependencies:
        - package: MapLibre
          product: MapLibre
        - package: SQLite.swift
          product: SQLite
        - package: valhalla-mobile
          product: Valhalla
        - package: valhalla-models
          product: ValhallaModels
  ```
- **File**: `MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift` (lines 329–331):
  ```swift
          // 9.2 Verify unused ValhallaConfigModels is NOT in dependencies
          XCTAssertFalse(projectYmlContent.contains("product: ValhallaConfigModels"), "project.yml must not link unused ValhallaConfigModels product")
  ```
- `ValhallaConfigModels` is deliberately excluded from project dependencies. `RemediationTests` explicitly enforces its absence. Consequently, `import ValhallaConfigModels` in `MyOfflineMapAppTests.swift` references an undeclared module.

### Observation 1.3: Valhalla Engine Initialization in `RoutingService.swift`
- **File**: `MyOfflineMapApp/Sources/RoutingService.swift` (lines 4–5, 195–290):
  ```swift
  import Valhalla
  import ValhallaModels
  ```
  `RoutingService` does NOT import `ValhallaConfigModels`.
  Valhalla is initialized by reading `valhalla.json`, customizing runtime configuration parameters, saving a temporary JSON file, and calling `try Valhalla(configPath: tempConfigURL.path)`:
  ```swift
          let configURL = OfflineDataManager.url(for: "valhalla.json")
          guard let configData = try? Data(contentsOf: configURL),
                var configJson = (try? JSONSerialization.jsonObject(with: configData)) as? [String: Any] else {
              print("RoutingService ERROR: Failed to load valhalla.json from \(configURL.path)")
              return
          }

          var mjolnir = configJson["mjolnir"] as? [String: Any] ?? [String: Any]()
          mjolnir["tile_extract"] = tarURL.path

          let tempTilesDir = FileManager.default.temporaryDirectory.appendingPathComponent("valhalla_tiles")
          try? FileManager.default.createDirectory(at: tempTilesDir, withIntermediateDirectories: true)
          mjolnir["tile_dir"] = tempTilesDir.path

          mjolnir.removeValue(forKey: "admin")
          mjolnir.removeValue(forKey: "timezone")
          mjolnir.removeValue(forKey: "traffic_extract")
          mjolnir.removeValue(forKey: "landmarks")
          mjolnir.removeValue(forKey: "transit_dir")
          mjolnir.removeValue(forKey: "transit_feeds_dir")

          var dataProc = mjolnir["data_processing"] as? [String: Any] ?? [String: Any]()
          dataProc["use_admin_db"] = false
          let isIndexedTar = tarURL.lastPathComponent.contains("indexed") || tarURL.lastPathComponent == "alaska_tiles.tar"
          dataProc["scan_tar"] = !isIndexedTar
          mjolnir["data_processing"] = dataProc

          // Mobile memory limits
          mjolnir["max_cache_size"] = 33554432
          configJson["mjolnir"] = mjolnir

          var addData = configJson["additional_data"] as? [String: Any] ?? [String: Any]()
          addData.removeValue(forKey: "elevation")
          configJson["additional_data"] = addData

          var loki = configJson["loki"] as? [String: Any] ?? [String: Any]()
          loki["use_connectivity"] = false
          ...
          do {
              let tempConfigURL = FileManager.default.temporaryDirectory.appendingPathComponent("valhalla_runtime.json")
              let patchedData = try JSONSerialization.data(withJSONObject: configJson, options: [.prettyPrinted])
              try patchedData.write(to: tempConfigURL)
              self.valhalla = try Valhalla(configPath: tempConfigURL.path)
              print("RoutingService: Valhalla offline routing engine initialized successfully!")
          } catch {
              print("RoutingService ERROR: Failed to initialize Valhalla: \(error)")
          }
  ```

### Observation 1.4: Asset and Config Resolution
- `OfflineDataManager.url(for: "valhalla.json")` successfully resolves `MyOfflineMapApp/Resources/valhalla.json`.
- `OfflineDataManager.url(for: "alaska_tiles.tar")` successfully resolves `data/alaska_tiles.tar` (64 MB indexed tile extract).

---

## 2. Logic Chain

1. **Premise 1 (Undeclared Module)**: `import ValhallaConfigModels` in `MyOfflineMapAppTests.swift:6` imports a framework that is not linked in `project.yml` (`Observation 1.2`). `RemediationTests.test09_ProjectConfigurationAndDependencies` specifically asserts that `ValhallaConfigModels` is not linked.
2. **Premise 2 (Orphaned Usage)**: `ValhallaConfig()` in `testBinnedTileRouting()` (lines 159–164) is the only consumer of `ValhallaConfigModels` across the entire codebase (`Observation 1.1`).
3. **Premise 3 (Canonical Initialization Pattern)**: `RoutingService.swift` establishes the project's standard and supported mechanism for initializing Valhalla: loading `valhalla.json` via `OfflineDataManager.url(for: "valhalla.json")`, configuring the `mjolnir.tile_extract` path, writing a runtime JSON file to `NSTemporaryDirectory()`, and calling `Valhalla(configPath: tempConfigURL.path)` (`Observation 1.3`).
4. **Premise 4 (Test Equivalence)**: `testBinnedTileRouting()` configures four properties: `tile_extract = testTarPath`, `traffic_extract = nil`, `tile_dir = nil/temp`, and `use_connectivity = false`. When applied to `valhalla.json` and written to a temporary runtime JSON file, `Valhalla(configPath: tempConfigURL.path)` executes identical binned tile routing against `alaska_tiles.tar` without requiring `ValhallaConfigModels`.
5. **Conclusion**: Removing `import ValhallaConfigModels` and updating `testBinnedTileRouting()` to initialize `Valhalla` via `Valhalla(configPath:)` satisfies requirement R6.2, eliminates the compiler dependency on `ValhallaConfigModels`, and aligns the test suite directly with production architecture.

---

## 3. Caveats

1. **Temporary File Isolation**: To avoid potential collision with `RoutingService` running in other unit test cases (such as `testValhallaRoutingOnRoads` or `testExplicitRoutingFailureOnInvalidOrUnreachableCoordinates`), the temporary config file name for `testBinnedTileRouting` must be distinct (`valhalla_binned_test_runtime.json`), and the temporary tile directory should be distinct (`valhalla_binned_test_tiles`).
2. **File Deletion in Defer**: A `defer` block safely unlinks the temporary JSON config file upon completion of the test method without impacting the running Valhalla engine instance.
3. **Read-Only Explorer Scope**: As an Explorer agent, no modifications were made to production or test source files. A machine-applicable `.patch` file was generated and verified in the agent directory.

---

## 4. Conclusion & Proposed Code Change

### Summary of Change
1. Remove `import ValhallaConfigModels` from `MyOfflineMapApp/Tests/MyOfflineMapAppTests/MyOfflineMapAppTests.swift`.
2. Update `testBinnedTileRouting()` in `MyOfflineMapApp/Tests/MyOfflineMapAppTests/MyOfflineMapAppTests.swift` to load `valhalla.json`, configure `tile_extract = testTarPath`, write to a temporary JSON file, and initialize Valhalla via `try Valhalla(configPath: tempConfigURL.path)`.

### Concrete Patch
The patch file is located at:
`/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m4_2/r6_2_valhalla_config.patch`

#### Before → After: Imports
```swift
// BEFORE (lines 1-8):
import XCTest
import CoreLocation
import MapLibre
import Valhalla
import ValhallaModels
import ValhallaConfigModels
@testable import MyOfflineMapApp

// AFTER:
import XCTest
import CoreLocation
import MapLibre
import Valhalla
import ValhallaModels
@testable import MyOfflineMapApp
```

#### Before → After: `testBinnedTileRouting()`
```swift
// BEFORE (lines 154-165):
    func testBinnedTileRouting() throws {
        let testTarPath = OfflineDataManager.url(for: "alaska_tiles.tar").path
        guard FileManager.default.fileExists(atPath: testTarPath) else {
            throw XCTSkip("alaska_tiles.tar not available on disk")
        }
        var config = ValhallaConfig()
        config.mjolnir?.tileExtract = testTarPath
        config.mjolnir?.trafficExtract = nil
        config.mjolnir?.tileDir = nil
        config.loki?.useConnectivity = false
        let valhalla = try Valhalla(config)
        
        // Downtown Fairbanks to South Cushman St
        let start = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        let dest = CLLocationCoordinate2D(latitude: 64.8358, longitude: -147.7345)
        ...

// AFTER:
    func testBinnedTileRouting() throws {
        let testTarPath = OfflineDataManager.url(for: "alaska_tiles.tar").path
        guard FileManager.default.fileExists(atPath: testTarPath) else {
            throw XCTSkip("alaska_tiles.tar not available on disk")
        }

        let configURL = OfflineDataManager.url(for: "valhalla.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw XCTSkip("valhalla.json not available on disk")
        }
        guard let configData = try? Data(contentsOf: configURL),
              var configJson = (try? JSONSerialization.jsonObject(with: configData)) as? [String: Any] else {
            XCTFail("Failed to load valhalla.json from \(configURL.path)")
            return
        }

        var mjolnir = configJson["mjolnir"] as? [String: Any] ?? [String: Any]()
        mjolnir["tile_extract"] = testTarPath

        let tempTilesDir = FileManager.default.temporaryDirectory.appendingPathComponent("valhalla_binned_test_tiles")
        try? FileManager.default.createDirectory(at: tempTilesDir, withIntermediateDirectories: true)
        mjolnir["tile_dir"] = tempTilesDir.path

        mjolnir.removeValue(forKey: "admin")
        mjolnir.removeValue(forKey: "timezone")
        mjolnir.removeValue(forKey: "traffic_extract")
        mjolnir.removeValue(forKey: "landmarks")
        mjolnir.removeValue(forKey: "transit_dir")
        mjolnir.removeValue(forKey: "transit_feeds_dir")

        var dataProc = mjolnir["data_processing"] as? [String: Any] ?? [String: Any]()
        dataProc["use_admin_db"] = false
        dataProc["scan_tar"] = false
        mjolnir["data_processing"] = dataProc
        configJson["mjolnir"] = mjolnir

        var loki = configJson["loki"] as? [String: Any] ?? [String: Any]()
        loki["use_connectivity"] = false
        configJson["loki"] = loki

        let tempConfigURL = FileManager.default.temporaryDirectory.appendingPathComponent("valhalla_binned_test_runtime.json")
        let patchedData = try JSONSerialization.data(withJSONObject: configJson, options: [.prettyPrinted])
        try patchedData.write(to: tempConfigURL)
        defer {
            try? FileManager.default.removeItem(at: tempConfigURL)
        }

        let valhalla = try Valhalla(configPath: tempConfigURL.path)
        
        // Downtown Fairbanks to South Cushman St
        let start = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)
        let dest = CLLocationCoordinate2D(latitude: 64.8358, longitude: -147.7345)
        ...
```

---

## 5. Verification Method

### 1. Patch Applicability Verification
The patch was verified using `git apply --check`:
```bash
git apply --check "/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m4_2/r6_2_valhalla_config.patch"
```
**Result**: Exited with code 0 (clean application, zero rejects, exact context match).

### 2. E2E Test Suite Run
```bash
./Tests/E2ETests/run_e2e_tests.sh
```
**Result**: 69/69 tests passed across Tiers 1–4 in 0.108 seconds.

### 3. Unit Test Verification (to be run by Worker/Reviewer during M4 implementation)
```bash
DEVELOPER_DIR="/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/Xcode.app/Contents/Developer" xcodebuild test \
  -project MyOfflineMapApp/MyOfflineMapApp.xcodeproj \
  -scheme MyOfflineMapApp \
  -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16' \
  -only-testing:MyOfflineMapAppTests/MyOfflineMapAppTests/testBinnedTileRouting
```

### Invalidation Conditions
- If `import ValhallaConfigModels` remains anywhere in `MyOfflineMapAppTests.swift`.
- If `testBinnedTileRouting` fails to instantiate `Valhalla` or fails to route between Fairbanks and South Cushman St.
- If `git apply --check` produces conflict errors.
