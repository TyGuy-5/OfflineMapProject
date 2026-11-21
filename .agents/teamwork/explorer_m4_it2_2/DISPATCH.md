# Dispatch: Explorer M4 Iteration 2.2 (testAdversarial01 Coordinate Distance Fix)

## Issue
Challenger `challenger_m4_1` identified a runtime assertion failure in `MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift:645-684` (`testAdversarial01_OutOfRegionGPSHandling`):
Destination coordinate at line 646 is `CLLocationCoordinate2D(latitude: 64.8440, longitude: -147.7210)`. The in-region test fix at line 79 is `CLLocationCoordinate2D(latitude: 64.8438, longitude: -147.7212)`.
Euclidean distance is 24.0m (< 25m arrival threshold), triggering destination arrival, which calls `endNavigation()` and resets `simulatedUserCoordinate` to `nil`. Consequently, line 682 evaluates `0.0 == 64.8438` and fails.

## Instructions
1. Inspect `testAdversarial01_OutOfRegionGPSHandling` in `RemediationTests.swift`.
2. Formulate the exact coordinate fix (e.g. setting destination coordinate in `coords` to `CLLocationCoordinate2D(latitude: 64.8500, longitude: -147.7210)`, which is ~685m away).
3. Verify that all other test methods in `RemediationTests.swift` that test `handleLocationUpdate` or `updateCurrentStepForLiveLocation` use coordinates sufficiently distant from arrival thresholds unless testing arrival.
4. Deliver your report to `.agents/teamwork/explorer_m4_it2_2/handoff.md`.


## 2026-11-07T10:40:16Z
You are explorer_m4_it2_2 for Milestone 4 Iteration 2 (testAdversarial01 Coordinate Distance Fix).

Your working directory is:
/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m4_it2_2

MANDATORY INSTRUCTIONS:
1. Read the original request at /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/ORIGINAL_REQUEST.md before starting work.
2. Read /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/PROJECT.md, /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/challenger_m4_1/challenge_report.md, and /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m4_it2_2/DISPATCH.md.
3. Investigate the runtime failure in `testAdversarial01_OutOfRegionGPSHandling()` in `RemediationTests.swift:645-684`:
   Line 646 destination coordinate is 24.0m from the in-region fix, triggering the 25m arrival threshold, calling `endNavigation()`, and resetting `simulatedUserCoordinate` to `nil`.
4. Formulate the exact fix: setting line 646 destination coordinate to `CLLocationCoordinate2D(latitude: 64.8500, longitude: -147.7210)` (~685m away), and check all other tests in `RemediationTests.swift` for similar accidental arrival conditions.
5. Deliver handoff report to `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m4_it2_2/handoff.md` and report to the parent orchestrator via send_message.
Do NOT modify production or test source files yourself (Explorers are read-only).
