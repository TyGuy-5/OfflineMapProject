# Handoff Report: Phase 0 Survey - Focus Area C (Requirements R5 & R6)

**Agent**: `explorer_survey_3` (teamwork_explorer)  
**Date**: 2026-11-07T05:56:00Z  
**Scope**: Requirements R5 (MapLibre Rendering & Navigation Annotations) and R6 (Build Configuration, Test Suite Modernization, and Documentation)  
**Working Directory**: `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_survey_3`  

---

## 1. Observation

### R5: MapLibre Rendering and Navigation Annotations

#### Observation 1.1: Camera Recentering and Zoom Level Animations in `MapView.swift`
- **File**: `MyOfflineMapApp/Sources/MapView.swift`
- **Lines**: 94–109
- **Code Extract**:
```swift
94:         // Recenter on user if requested
95:         if let userCoord = userLocationCenter {
96:             uiView.setCenter(userCoord, zoomLevel: 15, animated: true)
97:             DispatchQueue.main.async {
98:                 self.userLocationCenter = nil
99:             }
100:         }
101: 
102:         // Zoom in / out control
103:         if let step = zoomStep {
104:             let targetZoom = max(uiView.minimumZoomLevel, min(uiView.maximumZoomLevel, uiView.zoomLevel + step))
105:             uiView.setZoomLevel(targetZoom, animated: true)
106:             DispatchQueue.main.async {
107:                 self.zoomStep = nil
108:             }
109:         }
```
- **Context**: In `ContentView.swift:549-557`, zoom buttons set `zoomStep = 1.0` or `zoomStep = -1.0`. In `ContentView.swift:1388-1394`, `recenterOnUser()` sets `userLocationCenter = user`.
- **Finding**: Inside `updateUIView`, `uiView.setCenter` and `uiView.setZoomLevel` execute immediately. The binding reset (`self.userLocationCenter = nil` and `self.zoomStep = nil`) is asynchronously scheduled via `DispatchQueue.main.async`. If rapid UI updates occur before the async block executes (such as GPS updates, speed updates, or user interactions), `updateUIView` is called again with the binding still non-nil. This triggers duplicate `setCenter` and `setZoomLevel` invocations, causing animation collisions and unwanted compounding zoom levels.

#### Observation 1.2: Route Coordinate Change Detection in `MapView.swift`
- **File**: `MyOfflineMapApp/Sources/MapView.swift`
- **Lines**: 134–153
- **Code Extract**:
```swift
134:         if let route = routeCoordinates {
135:             let hasChanged: Bool = {
136:                 guard let last = coordinator.lastRouteCoordinates else { return true }
137:                 if last.count != route.count { return true }
138:                 guard let f1 = last.first, let f2 = route.first,
139:                       let l1 = last.last, let l2 = route.last else { return true }
140:                 if abs(f1.latitude - f2.latitude) > 0.00001 || abs(f1.longitude - f2.longitude) > 0.00001 ||
141:                    abs(l1.latitude - l2.latitude) > 0.00001 || abs(l1.longitude - l2.longitude) > 0.00001 {
142:                     return true
143:                 }
144:                 let mid = route.count / 2
145:                 let m1 = last[mid]
146:                 let m2 = route[mid]
147:                 return abs(m1.latitude - m2.latitude) > 0.00001 || abs(m1.longitude - m2.longitude) > 0.00001
148:             }()
149: 
150:             if hasChanged {
151:                 coordinator.lastRouteCoordinates = route
152:                 coordinator.drawRoute(on: uiView, coordinates: route)
153:             }
```
- **Finding**: The change detector only samples three vertices: index `0`, index `route.count - 1`, and index `route.count / 2`. If a reroute occurs where the new polyline happens to have the same count and the start, midpoint, and destination coordinates coincide within 0.00001 degrees (e.g. alternate routing around a loop, switchback reroute, or detour reuniting at the midpoint), `hasChanged` evaluates to `false`. Consequently, `coordinator.drawRoute` is skipped and the map fails to update.

#### Observation 1.3: Vehicle Annotation Rendering in `MapView.swift`
- **File**: `MyOfflineMapApp/Sources/MapView.swift`
- **Lines**: 180–190, 310–332, 387–398
- **Code Extract**:
```swift
180:     @MainActor
181:     public class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
...
189:         var carAnnotation: MLNPointAnnotation?
...
310:         func updateCarAnnotation(on mapView: MLNMapView, coordinate: CLLocationCoordinate2D) {
311:             if let existing = carAnnotation {
312:                 if existing.coordinate.latitude == coordinate.latitude && existing.coordinate.longitude == coordinate.longitude {
313:                     return
314:                 }
315:                 // MLNPointAnnotation's coordinate property is KVO-compliant.
316:                 // Setting coordinate directly updates the annotation view position smoothly without flicker.
317:                 existing.coordinate = coordinate
318:             } else {
319:                 let car = MLNPointAnnotation()
320:                 car.coordinate = coordinate
321:                 car.title = "Current Position"
322:                 mapView.addAnnotation(car)
323:                 carAnnotation = car
324:             }
325:         }
```
- **Finding**: `Coordinator` conforms to `MLNMapViewDelegate` but does NOT implement `mapView(_:imageFor:)` (or `mapView(_:viewFor:)`). When `carAnnotation` is added, MapLibre falls back to its default pin image (a standard red pushpin). This causes the vehicle marker during turn-by-turn navigation to look like a red pin rather than a navigation vehicle icon or directional arrow.

---

### R6: Build Configuration, Test Suite Modernization, and Documentation

#### Observation 1.4: Test Suite Brittle Inspections in `RemediationTests.swift`
- **File**: `MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift` (1,499 lines)
- **Direct Observations**:
  1. **Direct `ContentView` struct mutation**:
     - Line 15: `let view = ContentView()` -> `view.isWithinSupportedRegion(...)`
     - Line 59: `var view = ContentView()` -> `view.dismissSearch()`, `view.clearSearch()`
     - Line 137: `var view = ContentView()` -> `view.routeDetails = detailsWithZeroSteps`, `view.updateNavigationTelemetry(...)`
     - Line 585: `let view = ContentView()`
     - Line 670: `var view = ContentView()` -> `view.searchCategory(...)`, `view.searchTask`
     - Line 750: `var view = ContentView()`
     - Line 862: `let view = ContentView()`
     - Line 1289: `var view = ContentView()` -> `view.advanceSimulationStep()`
     - Line 1349: `var view = ContentView()` -> `view.updateNavigationTelemetry(...)`
  2. **Source-code file disk reading and string assertion via `#filePath`**:
     - Lines 81–107 (`test02_InFlightSearchTaskCancellation`): Reads `Sources/ContentView.swift`, asserts `content.contains("func dismissSearch()")` and `content.components(separatedBy: "searchTask?.cancel()").count - 1 >= 4`.
     - Lines 118–133 (`test03_CategorySearchSingleInvocation`): Reads `Sources/ContentView.swift`, asserts `content.contains("isProgrammaticTextChange = true")`.
     - Lines 191–203 (`test05_DistanceUnitTogglingPreservesSimulationProgress`): Reads `Sources/ContentView.swift`, asserts `content.contains("if !isNavigating && !isSimulating")`.
     - Lines 439–460 (`test12_PhysicalDeviceHostPathProbing`): Reads `Sources/OfflineDataManager.swift`.
     - Lines 655–665 (`testAdversarial01_OutOfRegionGPSHandling`): Reads `Sources/ContentView.swift`, asserts `content.contains("guard isWithinSupportedRegion(location.coordinate) else { return }")`.
     - Lines 731–746 (`testAdversarial03_CategorySearchDeduplication`): Reads `Sources/ContentView.swift`, asserts exact string matching with newline breaks `if destinationText != category {\n isProgrammaticTextChange = true...`.
     - Lines 865–875 (`testAdversarial05_SimulationMetricTogglingProgressPreservation`): Reads `Sources/ContentView.swift`, asserts `content.contains("if !isNavigating && !isSimulating")`.
     - Lines 1122–1149 (`testAdversarial09_PhysicalDeviceHostPathGuardElision`): Reads `Sources/OfflineDataManager.swift`, asserts regex `#if\\s*\\(targetEnvironment...`.
     - Lines 1243–1254 (`testAdversarial11_AudioSessionDeactivationConcurrencyStress`): Reads `Sources/RoutingService.swift`, asserts `source.contains("guard generation == currentGen else { return }")`.

#### Observation 1.5: Missing Dependency & Valhalla Config in `MyOfflineMapAppTests.swift`
- **File**: `MyOfflineMapApp/Tests/MyOfflineMapAppTests/MyOfflineMapAppTests.swift`
- **Lines**: 6, 154–165
- **Code Extract**:
```swift
6: import ValhallaConfigModels
...
154:     func testBinnedTileRouting() throws {
155:         let testTarPath = OfflineDataManager.url(for: "alaska_tiles.tar").path
156:         guard FileManager.default.fileExists(atPath: testTarPath) else {
157:             throw XCTSkip("alaska_tiles.tar not available on disk")
158:         }
159:         var config = ValhallaConfig()
160:         config.mjolnir?.tileExtract = testTarPath
161:         config.mjolnir?.trafficExtract = nil
162:         config.mjolnir?.tileDir = nil
163:         config.loki?.useConnectivity = false
164:         let valhalla = try Valhalla(config)
```
- **Context in `project.yml`**: Targets depend on `Valhalla` (package: `valhalla-mobile`) and `ValhallaModels` (package: `valhalla-models`). `ValhallaConfigModels` is NOT a package dependency in `project.yml`.
- **Finding in `RoutingService.swift:270-273`**: The main application initializes Valhalla by loading `valhalla.json`, updating the json dictionary, writing it to a temporary file `valhalla_runtime.json`, and invoking `Valhalla(configPath: tempConfigURL.path)`. `ValhallaConfig` and `import ValhallaConfigModels` are completely unnecessary and prevent compilation if `ValhallaConfigModels` is missing.

#### Observation 1.6: iCloud Backup Exclusion in `OfflineDataManager.swift`
- **File**: `MyOfflineMapApp/Sources/OfflineDataManager.swift`
- **Lines**: 52–59
- **Code Extract**:
```swift
52:         // Exclude Documents directory from iCloud backup to avoid backing up multi-gigabyte offline data
53:         if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
54:             try? FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
55:             var resourceValues = URLResourceValues()
56:             resourceValues.isExcludedFromBackup = true
57:             var mutableURL = docsURL
58:             try? mutableURL.setResourceValues(resourceValues)
59:         }
```
- **Finding**: Setting `isExcludedFromBackup = true` on the entire `Documents` directory (`docsURL`) violates Apple App Store Data Storage Guidelines (Guideline 5.1.1). User-facing files in `Documents` must remain eligible for iCloud backup; only downloaded, reproducible map tiles and database archives (`.pmtiles`, `.tar`, `.db`, `.json`) should be marked with `isExcludedFromBackup = true`.

#### Observation 1.7: Hardcoded Local Paths & Simulator UDIDs in Documentation
- **Tool Commands**:
  - `grep -n "Extended Hard Drive" DOCUMENTATION.md docs/AUDIT_REPORT.md`
  - `grep -E -n "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}" DOCUMENTATION.md docs/AUDIT_REPORT.md`
- **Results**:
  - `DOCUMENTATION.md:394`: `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/...`
  - `DOCUMENTATION.md:621`: `DEVELOPER_DIR="/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/Xcode.app/Contents/Developer" xcodebuild test \`
  - `DOCUMENTATION.md:624`: `-destination 'platform=iOS Simulator,id=0A20D9A5-C44D-4D07-89E0-F1F0B2FE5CFE'`
  - `DOCUMENTATION.md:627`: `DEVELOPER_DIR="/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/Xcode.app/Contents/Developer" xcrun simctl launch \`
  - `DOCUMENTATION.md:628`: `--terminate-running-process 0A20D9A5-C44D-4D07-89E0-F1F0B2FE5CFE com.tyguy5.MyOfflineMapApp.debug`
  - `DOCUMENTATION.md:677`: `file:///Volumes/Extended%20Hard%20Drive%201Tb%20%28Mac%20Mini%20M4%29/OfflineMapProject/THIRD_PARTY_NOTICES.md`
  - `docs/AUDIT_REPORT.md:92`: `DEVELOPER_DIR="/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/Xcode.app/Contents/Developer" xcodebuild test \`
  - `docs/AUDIT_REPORT.md:93`: `-project "/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/MyOfflineMapApp/MyOfflineMapApp.xcodeproj" \`
  - `docs/AUDIT_REPORT.md:95`: `-destination 'platform=iOS Simulator,id=0A20D9A5-C44D-4D07-89E0-F1F0B2FE5CFE'`
  - `docs/AUDIT_REPORT.md:105`: `DEVELOPER_DIR="/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/Xcode.app/Contents/Developer" xcodebuild clean build \`
  - `docs/AUDIT_REPORT.md:106`: `-project "/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/MyOfflineMapApp/MyOfflineMapApp.xcodeproj" \`
  - `docs/AUDIT_REPORT.md:108`: `-destination 'platform=iOS Simulator,id=0A20D9A5-C44D-4D07-89E0-F1F0B2FE5CFE' 2>&1 | grep ...`

---

## 2. Logic Chain

### R5 Logic Chain:
1. **Camera Recenter & Zoom Deduplication**:
   - `updateUIView` is the synchronization bridge between SwiftUI state and UIKit/MapLibre.
   - Modifying a `@Binding` via `DispatchQueue.main.async` takes effect on a subsequent turn of the main runloop.
   - If SwiftUI invokes `updateUIView` again before that runloop turn (due to GPS ticks, animations, or telemetry state changes), the binding remains non-nil.
   - By adding boolean consumption flags (`isRecenterConsumed`, `isZoomStepConsumed`) or tracking the last consumed value on `Coordinator` (which persists across `updateUIView` calls), `setCenter` and `setZoomLevel` execute exactly once per user intent. When the binding becomes `nil`, the flag resets to `false`.

2. **Route Coordinates Equality**:
   - The current 3-vertex sampling (`first`, `mid`, `last`) produces false negatives whenever a reroute yields the same number of coordinates and coincidental alignment at the route's midpoint.
   - CoreLocation coordinates are stored as `Double` pairs (`latitude`, `longitude`).
   - A full O(N) array comparison iterating over all coordinates (using epsilon `1e-6` degrees) takes ~10 microseconds for 1,000 vertices, which is negligible against the 16.6ms 60fps frame budget while guaranteeing 100% reroute detection accuracy.

3. **Directional Vehicle Icon Rendering**:
   - MapLibre's `MLNMapViewDelegate` protocol specifies `mapView(_:imageFor:) -> MLNAnnotationImage?`.
   - When this delegate method is omitted, MapLibre defaults to a red pushpin.
   - Implementing `mapView(_:imageFor:)` to check `annotation === carAnnotation || annotation.title == "Current Position"` and returning an `MLNAnnotationImage` of a directional vehicle icon/arrow (e.g. rendered via `UIGraphicsImageRenderer` or `UIImage(systemName: "location.north.fill")`) replaces the red pin with a native navigation puck.

### R6 Logic Chain:
1. **Test Modernization**:
   - Testing an unmounted `ContentView` struct directly tests implementation details of SwiftUI view layouts rather than business logic. In R1, state properties are moved to `NavigationViewModel`.
   - Reading `.swift` source code files off disk via `#filePath` in test methods makes the test suite brittle to formatting, comment changes, and directory relocations, while failing to test actual runtime behavior.
   - Instantiating `@MainActor NavigationViewModel` in `RemediationTests.swift` and testing methods/properties (`updateNavigationTelemetry`, `advanceSimulationStep`, `searchCategory`, `handleLocationUpdate`, `searchTask`) tests real state transitions directly with no file I/O.

2. **ValhallaConfigModels**:
   - `project.yml` does not declare `ValhallaConfigModels`.
   - `RoutingService` demonstrates that `Valhalla(configPath:)` with runtime JSON configuration is the standard, tested mechanism in the project.
   - Updating `testBinnedTileRouting()` to use `Valhalla(configPath:)` aligns the test suite with production code and removes the undeclared dependency.

3. **iCloud Backup Exclusion Scope**:
   - Marking the entire `Documents` directory as excluded prevents user documents from being backed up, violating Apple's Review Guidelines.
   - Restricting backup exclusion to downloaded offline asset files in Documents (`.pmtiles`, `.tar`, `.db`, `.json`) complies with Apple guidelines while preventing multi-gigabyte offline data from inflating user iCloud storage.

4. **Documentation Sanitization**:
   - Hardcoded paths to `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/` and simulator UDID `0A20D9A5-C44D-4D07-89E0-F1F0B2FE5CFE` break copy-paste instructions on any other developer machine or CI environment.
   - Replacing them with repo-relative paths and generic simulator selectors (`name=iPhone 16` or `booted`) ensures documentation is portable and professional.

---

## 3. Caveats

1. **MapLibre Version & Threading**:
   - MapLibre Native 6.27.0 `MLNMapViewDelegate` methods must be executed on `@MainActor`. `Coordinator` is already annotated with `@MainActor` and `@preconcurrency MLNMapViewDelegate`.
2. **SF Symbol Availability in MapLibre Images**:
   - `UIImage(systemName:)` produces vector SF Symbols that need to be rasterized with a tint color before returning to MapLibre as an `MLNAnnotationImage`. Alternatively, a programmatically drawn puck via `UIGraphicsImageRenderer` avoids any symbol version dependencies and gives full control over border, shadow, and arrow geometry.
3. **Valhalla Tile Tar Path in Unit Tests**:
   - `testBinnedTileRouting()` skips if `alaska_tiles.tar` is not present on disk. The test must write its temporary `valhalla_test_config.json` to `FileManager.default.temporaryDirectory` and clean it up.
4. **Xcode Developer Directory**:
   - On the current host machine, command-line tools point to `/Library/Developer/CommandLineTools` rather than full Xcode. Any command execution requiring `xcodebuild` requires `DEVELOPER_DIR="/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/Xcode.app/Contents/Developer"`, but repo documentation must specify generic standard paths like `/Applications/Xcode.app/Contents/Developer` or omit `DEVELOPER_DIR` for standard systems.

---

## 4. Conclusion & Concrete Implementation Recommendations

### Recommended Changes for R5 (`MapView.swift`):
1. **Camera Recenter & Zoom Deduplication**:
   - Add state tracking to `MapView.Coordinator`:
     ```swift
     var isRecenterConsumed: Bool = false
     var isZoomStepConsumed: Bool = false
     ```
   - In `updateUIView`:
     ```swift
     if let userCoord = userLocationCenter {
         if !coordinator.isRecenterConsumed {
             coordinator.isRecenterConsumed = true
             uiView.setCenter(userCoord, zoomLevel: 15, animated: true)
             DispatchQueue.main.async { self.userLocationCenter = nil }
         }
     } else {
         coordinator.isRecenterConsumed = false
     }

     if let step = zoomStep {
         if !coordinator.isZoomStepConsumed {
             coordinator.isZoomStepConsumed = true
             let targetZoom = max(uiView.minimumZoomLevel, min(uiView.maximumZoomLevel, uiView.zoomLevel + step))
             uiView.setZoomLevel(targetZoom, animated: true)
             DispatchQueue.main.async { self.zoomStep = nil }
         }
     } else {
         coordinator.isZoomStepConsumed = false
     }
     ```

2. **Full Route Coordinates Equality Check**:
   - Replace lines 135–148 with:
     ```swift
     let hasChanged: Bool = {
         guard let last = coordinator.lastRouteCoordinates else { return true }
         if last.count != route.count { return true }
         for i in 0..<route.count {
             let c1 = last[i]
             let c2 = route[i]
             if abs(c1.latitude - c2.latitude) > 0.000001 || abs(c1.longitude - c2.longitude) > 0.000001 {
                 return true
             }
         }
         return false
     }()
     ```

3. **Car Annotation Image Delegate**:
   - In `MapView.Coordinator`, implement:
     ```swift
     public func mapView(_ mapView: MLNMapView, imageFor annotation: MLNAnnotation) -> MLNAnnotationImage? {
         if annotation === carAnnotation || annotation.title == "Current Position" {
             let identifier = "navigation-vehicle-arrow"
             if let existing = mapView.dequeueReusableAnnotationImage(withIdentifier: identifier) {
                 return existing
             }
             let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
             let image = renderer.image { ctx in
                 let cgCtx = ctx.cgContext
                 // Outer circle with shadow
                 cgCtx.setFillColor(UIColor.white.cgColor)
                 cgCtx.fillEllipse(in: CGRect(x: 4, y: 4, width: 32, height: 32))
                 // Inner blue circle
                 cgCtx.setFillColor(UIColor(red: 0.10, green: 0.45, blue: 0.91, alpha: 1.0).cgColor)
                 cgCtx.fillEllipse(in: CGRect(x: 6, y: 6, width: 28, height: 28))
                 // White forward triangle pointer
                 let path = UIBezierPath()
                 path.move(to: CGPoint(x: 20, y: 11))
                 path.addLine(to: CGPoint(x: 27, y: 25))
                 path.addLine(to: CGPoint(x: 20, y: 22))
                 path.addLine(to: CGPoint(x: 13, y: 25))
                 path.close()
                 UIColor.white.setFill()
                 path.fill()
             }
             return MLNAnnotationImage(image: image, reuseIdentifier: identifier)
         }
         return nil
     }
     ```

### Recommended Changes for R6:
1. **`MyOfflineMapAppTests.swift`**:
   - Delete line 6: `import ValhallaConfigModels`
   - Rewrite `testBinnedTileRouting()`: load `valhalla.json`, inject `testTarPath` into `mjolnir["tile_extract"]`, write temporary JSON, and instantiate `try Valhalla(configPath: tempConfigURL.path)`.
2. **`OfflineDataManager.swift`**:
   - Replace lines 52–59 in `prepareIfNeeded()` with a scoped file-by-file exclusion for known offline asset extensions (`pmtiles`, `tar`, `db`, `json`) in Documents. Do NOT set `isExcludedFromBackup` on the Documents directory URL itself.
3. **`RemediationTests.swift`**:
   - Instantiate `NavigationViewModel` directly instead of mutating unmounted `ContentView` structs.
   - Remove `#filePath` disk reads and substring matching in `test02`, `test03`, `test05`, `test12`, `testAdversarial01`, `testAdversarial03`, `testAdversarial05`, `testAdversarial09`, `testAdversarial11`. Replace with direct observable property, mock input, and state assertions on `NavigationViewModel`.
4. **Documentation Sanitization**:
   - Sanitize all 7 path references and 4 simulator UDID references across `DOCUMENTATION.md` and `docs/AUDIT_REPORT.md` using the exact inventory provided in Section 1.7.

---

## 5. Verification Method

### Test Commands to Run:
```bash
# 1. Regenerate Xcode project spec
cd MyOfflineMapApp && xcodegen generate && cd ..

# 2. Execute unit tests
xcodebuild test \
  -project MyOfflineMapApp/MyOfflineMapApp.xcodeproj \
  -scheme MyOfflineMapApp \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Specific Invalidation / Verification Conditions:
1. **Redundant Zoom/Recenter Invalidation**:
   - Call `updateUIView` twice in immediate succession with `zoomStep = 1.0`.
   - Assert `setZoomLevel` is called exactly once, and second call is ignored until `zoomStep` resets to `nil`.
2. **Reroute Redraw Invalidation**:
   - Feed two distinct routes with identical coordinate counts where only intermediate vertices differ.
   - Assert `hasChanged` evaluates to `true` and `drawRoute` is called.
3. **Vehicle Annotation Invalidation**:
   - Instantiate `MapView.Coordinator`, add `carAnnotation`, invoke `coordinator.mapView(mapView, imageFor: carAnnotation)`.
   - Assert return value is non-nil and its reuse identifier matches `"navigation-vehicle-arrow"`.
4. **ValhallaConfigModels Invalidation**:
   - Compile `MyOfflineMapAppTests` with `import ValhallaConfigModels` removed. Assert zero compilation errors.
5. **iCloud Backup Exclusion Invalidation**:
   - Inspect `FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first`.
   - Assert `(try? docsURL.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup != true`.
   - Assert asset files within Documents have `isExcludedFromBackup == true`.
6. **Documentation Sanitization Invalidation**:
   - Run `grep -rn "/Volumes/Extended Hard Drive" DOCUMENTATION.md docs/AUDIT_REPORT.md` (must return 0 matches).
   - Run `grep -rn "0A20D9A5-C44D-4D07-89E0-F1F0B2FE5CFE" DOCUMENTATION.md docs/AUDIT_REPORT.md` (must return 0 matches).
