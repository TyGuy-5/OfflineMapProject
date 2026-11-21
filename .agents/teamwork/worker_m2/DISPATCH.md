## 2026-11-07T06:47:14Z
You are worker_m2 (teamwork_worker) assigned to implement Milestone 2: Location, Map Rendering & Asset Storage for MyOfflineMapApp.

## Working Directory
Write your progress and handoff to:
`/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/worker_m2/`

## Mandatory Reference Documents
You MUST read the following authoritative documents before modifying any code:
1. `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/ORIGINAL_REQUEST.md`
2. `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/PROJECT.md`
3. `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/orchestrator/handoff.md`
4. `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m2_1/handoff.md`
5. `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m2_2/handoff.md`
6. `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m2_3/handoff.md`

## MANDATORY INTEGRITY WARNING
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Write Ownership Boundaries
You have EXCLUSIVE write ownership over these 3 files:
1. `MyOfflineMapApp/Sources/LocationManager.swift`
2. `MyOfflineMapApp/Sources/MapView.swift`
3. `MyOfflineMapApp/Sources/OfflineDataManager.swift`
Do NOT modify any other files.

## Detailed Requirements for Milestone 2

### 1. `LocationManager.swift` (R2.6)
- **Degraded GPS Accuracy Handling (lines 94-105)**:
  In `locationManager(_:didUpdateLocations:)`:
  When `latest.horizontalAccuracy < 0 || latest.horizontalAccuracy >= 65.0`, you MUST set:
  ```swift
  Task { @MainActor in
      self.isGpsSignalLow = true
      self.smoothedSpeedMph = 0
      self.smoothedSpeedKmh = 0
      self.isStationary = true
      self.previousSpeedMps = 0.0
  }
  return
  ```
  Ensure all velocity smoothing fields and stationary flags are properly updated on `@MainActor`.
- **`deinit` Unstructured Task Elimination (lines 44-51)**:
  Replace the unstructured `Task { @MainActor in UIDevice.current.endGeneratingDeviceOrientationNotifications() }` with safe synchronous or queued execution:
  ```swift
  if Thread.isMainThread {
      UIDevice.current.endGeneratingDeviceOrientationNotifications()
  } else {
      DispatchQueue.main.async {
          UIDevice.current.endGeneratingDeviceOrientationNotifications()
      }
  }
  ```
  Keep `headingUpdateTask?.cancel()`.

### 2. `MapView.swift` (R5.1, R5.2, R5.3)
- **R5.1: Camera Recenter & Zoom Level Animation Deduplication**:
  In `Coordinator`, track consumption state with boolean flags:
  `private var isRecenterConsumed: Bool = false`
  `private var isZoomStepConsumed: Bool = false`
  In `updateUIView`:
  - For `parent.shouldRecenter`: only call `uiView.setCenter(userCoord, animated: true)` if `!context.coordinator.isRecenterConsumed`. Mark `isRecenterConsumed = true`. When `!parent.shouldRecenter`, reset `isRecenterConsumed = false`.
  - For `parent.zoomStep != 0`: only call `uiView.setZoomLevel(...)` if `!context.coordinator.isZoomStepConsumed`. Mark `isZoomStepConsumed = true`. When `parent.zoomStep == 0`, reset `isZoomStepConsumed = false`.
- **R5.2: Complete Route Coordinates Comparison**:
  In `updateUIView`, replace the 3-point coordinate comparison with a complete O(N) array check comparing count and every coordinate pair with tolerance `0.00001` degrees for both latitude and longitude:
  ```swift
  var coordinatesChanged = false
  if context.coordinator.lastRouteCoordinates.count != parent.routeCoordinates.count {
      coordinatesChanged = true
  } else {
      for i in 0..<parent.routeCoordinates.count {
          let c1 = parent.routeCoordinates[i]
          let c2 = context.coordinator.lastRouteCoordinates[i]
          if abs(c1.latitude - c2.latitude) > 0.00001 || abs(c1.longitude - c2.longitude) > 0.00001 {
              coordinatesChanged = true
              break
          }
      }
  }
  ```
- **R5.3: Vehicle Directional Annotation Icon**:
  - In `updateCarAnnotation`: set `context.coordinator.carAnnotation = car` BEFORE calling `uiView.addAnnotation(car)` so `mapView(_:imageFor:)` resolves the annotation identity.
  - Implement `mapView(_:imageFor:)` on `Coordinator`:
    When `annotation === carAnnotation`, return an `MLNAnnotationImage` vector-rendered 40x40 circular puck with blue background, white circular border, and a white directional triangle/arrow pointing North (as specified in `explorer_m2_2/handoff.md` and `orchestrator/handoff.md`) with reuse identifier `"navigation-vehicle-arrow"`.

### 3. `OfflineDataManager.swift` (R6.3)
- **Scoped iCloud Backup Exclusion**:
  In `prepareIfNeeded()`:
  - Do NOT mark the root `docsURL` as excluded from iCloud backup. Ensure `docsURL` retains standard backup eligibility (`isExcludedFromBackup = false`).
  - Implement a helper function `excludeOfflineAssetsInDocuments(docsURL: URL)` that enumerates or targets offline data files (`.pmtiles`, `.tar`, `.db`, `.json`) in `Documents` and sets `isExcludedFromBackup = true` on those specific asset files.
- **CRITICAL AUDIT RESTRICTION**:
  `RemediationTests.swift:1145` (`test73_SourceSecurityAudit`) asserts `#filePath` appears **EXACTLY ONCE** in `OfflineDataManager.swift`.
  **DO NOT ADD ANY NEW `#filePath` TOKENS** in `OfflineDataManager.swift`.

## Verification Commands
After implementing, execute builds and tests:
```bash
export DEVELOPER_DIR="/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/Xcode.app/Contents/Developer"
export PATH="/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/Xcode.app/Contents/Developer/usr/bin:$PATH"
xcodebuild test -project MyOfflineMapApp.xcodeproj -scheme MyOfflineMapApp -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16'
./Tests/E2ETests/run_e2e_tests.sh
```

## Completion Deliverable
Write a comprehensive report to:
`/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/worker_m2/handoff.md`
Include:
- Files modified and exact changes made
- Build and test results (with full command output summaries)
- Verification that existing tests continue to pass and no regressions were introduced.
When finished, send a message to orchestrator with your status and summary.
