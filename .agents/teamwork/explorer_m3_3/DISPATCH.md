# Dispatch: explorer_m3_3

## Objective
Investigate GPS Hardware Start & Arrival Detection (Requirements R2.4, R2.5) and Integration/Test Plan:
- In `startNavigation()`, do not unconditionally snap `simulatedUserCoordinate` to the polyline start when a valid in-region hardware GPS fix exists.
- In arrival detection, check distance against both the road-snapped endpoint (`coords.last`) and the destination pin (`selectedCoordinate`), allowing arrival completion when destinations are set back from the road.
- Synthesize the overall implementation and test strategy for Milestone 3.

## Working Directory
`.agents/teamwork/explorer_m3_3/`

## Scope & Files
- Read `ORIGINAL_REQUEST.md` (`/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/ORIGINAL_REQUEST.md`)
- Read `PROJECT.md` (`/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/PROJECT.md`)
- Inspect `MyOfflineMapApp/Sources/ContentView.swift` (specifically `startNavigation`, arrival detection in live and simulation updates)
- Inspect `MyOfflineMapApp/Sources/LocationManager.swift`
- Inspect `MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift` and `Tests/E2ETests/`

## Deliverables
Write an analysis report to `.agents/teamwork/explorer_m3_3/analysis.md` and deliver `handoff.md`.
Report on:
1. `startNavigation()` fix: how to check `locationManager.location` validity (accuracy, timestamp, distance to route start or region) before falling back to snapping `simulatedUserCoordinate = routeCoordinates.first`.
2. Arrival detection logic: dual-distance check against both road-snapped endpoint (`coords.last`) and destination pin (`selectedCoordinate`), arrival radius threshold, and state transitions to arrival celebration/view.
3. Impact on existing tests in `RemediationTests.swift` and E2E tests (`./Tests/E2ETests/run_e2e_tests.sh`).
4. Step-by-step implementation guide for Worker M3.
