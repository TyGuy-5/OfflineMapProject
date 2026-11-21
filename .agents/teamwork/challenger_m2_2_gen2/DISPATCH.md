## 2026-11-07T07:01:18Z
You are challenger_m2_2_gen2 (teamwork_challenger) replacing challenger_m2_2 for Milestone 2: Location, Map Rendering & Asset Storage.

## CRITICAL EXECUTION CONSTRAINT
DO NOT USE `BypassSandbox: true` UNDER ANY CIRCUMSTANCES. All commands must execute within the default sandbox. You do NOT need to write external scripts or compile standalone swift files. You can verify everything by running:
1. `./Tests/E2ETests/run_e2e_tests.sh` (tests MapView recentering, zoom deduplication, full coordinate equality, vehicle annotation)
2. `xcodebuild test -project MyOfflineMapApp.xcodeproj -scheme MyOfflineMapApp -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16' -only-testing:MyOfflineMapAppTests/RemediationTests/test10_CarAnnotationCoordinateUpdatesInPlace -only-testing:MyOfflineMapAppTests/RemediationTests/test12_PhysicalDeviceHostPathProbing -only-testing:MyOfflineMapAppTests/RemediationTests/testAdversarial07_CarAnnotationRapid60HzUpdatesAndKVOInPlace -only-testing:MyOfflineMapAppTests/RemediationTests/testAdversarial09_PhysicalDeviceHostPathGuardElision`
3. Static grep verification: `grep -c "#filePath" MyOfflineMapApp/Sources/OfflineDataManager.swift`

## Working Directory
Write your progress and stress test report to:
`/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/challenger_m2_2_gen2/`

## Mandatory Reference Documents
1. `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/ORIGINAL_REQUEST.md`
2. `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/PROJECT.md`
3. `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/worker_m2/handoff.md`

## Adversarial Verification Mission
Perform empirical adversarial testing on `MapView.swift` (R5.1, R5.2, R5.3) and `OfflineDataManager.swift` (R6.3):
1. **MapView Coordinator Consumption Flags (R5.1)**:
   - Verify that rapid repeated recenter/zoom calls do not cause compounding animations, and consumption flags cleanly reset when bindings become nil.
2. **Full Route Coordinates Equality Check (R5.2)**:
   - Verify that O(N) coordinate equality correctly flags reroutes with identical endpoints and length but interior deviations (> 0.00001 deg).
3. **Navigation Vehicle Annotation Image (R5.3)**:
   - Verify `mapView(_:imageFor:)` returns `"navigation-vehicle-arrow"` for `carAnnotation` and `nil` for other annotations.
4. **OfflineDataManager Backup Exclusion (R6.3)**:
   - Verify Documents root remains backup-eligible (`isExcludedFromBackup = false`), while `.pmtiles`, `.tar`, `.db`, `.json` are excluded.
   - Verify `#filePath` appears exactly once in `OfflineDataManager.swift`.

## Verdict Requirement
In your handoff report (`.agents/teamwork/challenger_m2_2_gen2/handoff.md`), provide an explicit verdict:
`APPROVE` or `REQUEST_CHANGES` with empirical evidence.
When finished, send a message to orchestrator with your verdict and summary.
