# Dispatch: worker_m3

## Objective
Implement Milestone 3: Navigation ViewModel Architecture & Telemetry (Requirements R1.1–R1.3, R2.1–R2.5)
- R1.1: Extract navigation, search, and telemetry state properties and methods out of `ContentView` into `@MainActor public final class NavigationViewModel: ObservableObject` (`MyOfflineMapApp/Sources/NavigationViewModel.swift`).
- R1.2: Inject `NavigationViewModel` into `ContentView` via `@StateObject` while maintaining backward-compatibility stubs and forwarding properties to ensure existing tests continue passing.
- R1.3: Persist user preferences (`useMetric` and `isVoiceMuted`) across launches via `@AppStorage` keys `"useMetric"` and `"isVoiceMuted"`, aligning with `PrivacyInfo.xcprivacy` (`CA92.1`).
- R2.1: Restrict forward coordinate search in `updateCurrentStepForLiveLocation` to current maneuver's polyline segment range (clamped to `currentStep.endIndex + 2`) to eliminate premature step advancement on switchbacks.
- R2.2: Ensure `remainingStepDistanceMiles` counts down monotonically and evaluates to zero when `clampedIndex >= stepEnd` without distance reversal.
- R2.3: In `advanceSimulationStep()`, advance `currentStepIndex` via a `while` loop rather than a single `if` check so simulation at 2x and 5x speeds announces all intermediate maneuvers.
- R2.4: In `startNavigation()`, do not unconditionally snap `simulatedUserCoordinate` to polyline start when a valid in-region hardware GPS fix exists.
- R2.5: In arrival detection, check distance against both road-snapped endpoint (`coords.last`) and destination pin (`selectedCoordinate`), allowing arrival completion when destinations are set back from the road.

## Working Directory
`.agents/teamwork/worker_m3/`

## Exclusive Write Ownership
- `MyOfflineMapApp/Sources/NavigationViewModel.swift`
- `MyOfflineMapApp/Sources/ContentView.swift`
Do NOT modify any other files.

## References
- ORIGINAL_REQUEST.md: `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/ORIGINAL_REQUEST.md`
- PROJECT.md: `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/PROJECT.md`
- Explorer 1 Handoff (ViewModel & Persistence): `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m3_1/handoff.md` and `analysis.md`
- Explorer 2 Handoff (Telemetry, Switchbacks & Simulation Loop): `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m3_2/handoff.md` and `analysis.md`
- Explorer 3 Handoff (Hardware GPS Start & Dual-Point Arrival): `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m3_3/handoff.md` and `analysis.md`

## Mandatory Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Verification Requirements
- Run `./Tests/E2ETests/run_e2e_tests.sh` to ensure all 69 tests pass.
- Verify backward compatibility for `RemediationTests.swift` by checking forwarding properties and stubs on `ContentView.swift`.
- Run commands strictly in-sandbox (DO NOT set `BypassSandbox: true`).
- Deliver report to `.agents/teamwork/worker_m3/changes.md` and summary in `.agents/teamwork/worker_m3/handoff.md`.


## 2026-11-07T07:20:31Z
You are worker_m3, a teamwork_worker agent.
Your working directory is: /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/worker_m3/

You MUST read ORIGINAL_REQUEST.md before starting:
/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/ORIGINAL_REQUEST.md
Also read PROJECT.md:
/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/PROJECT.md
Also read DISPATCH.md in your directory:
/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/worker_m3/DISPATCH.md
Read the 3 Explorer handoffs:
- /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m3_1/handoff.md (and analysis.md)
- /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m3_2/handoff.md (and analysis.md)
- /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m3_3/handoff.md (and analysis.md)

WRITE OWNERSHIP (CRITICAL):
You exclusively own and may modify ONLY these two files:
1. `MyOfflineMapApp/Sources/NavigationViewModel.swift` (create new file)
2. `MyOfflineMapApp/Sources/ContentView.swift` (refactor to inject NavigationViewModel and retain forwarding stubs)
Do NOT modify any other files.

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Key Requirements to Implement:
1. R1.1: Extract navigation, search, and telemetry state/methods into `@MainActor public final class NavigationViewModel: ObservableObject` in `NavigationViewModel.swift`.
2. R1.2: Inject `NavigationViewModel` into `ContentView` via `@StateObject` with default initializer `init(viewModel: NavigationViewModel = NavigationViewModel())`. Ensure `ContentView` retains backward-compatibility forwarding stubs and properties for all members tested by `RemediationTests.swift`.
3. R1.3: Persist `useMetric` and `isVoiceMuted` across launches via `@AppStorage` keys `"useMetric"` and `"isVoiceMuted"`, aligning with `PrivacyInfo.xcprivacy` (`CA92.1`). In `isVoiceMuted` observer, synchronize with `routingService.isVoiceMuted` and call `routingService.stopVoice()` when muted.
4. R2.1: Restrict forward coordinate search in `updateCurrentStepForLiveLocation` to current maneuver's polyline segment range (clamped to `currentStep.endIndex + 2`) to eliminate premature step advancement on switchbacks.
5. R2.2: Correct `updateNavigationTelemetry` so that `remainingStepDistanceMiles` decreases monotonically towards zero and evaluates to zero (no distance reversal) when `clampedIndex >= stepEnd`.
6. R2.3: In `advanceSimulationStep()`, advance `currentStepIndex` via a `while` loop rather than a single `if` check so simulation at 2x and 5x speeds announces all intermediate maneuvers.
7. R2.4: In `startNavigation()`, do not unconditionally snap `simulatedUserCoordinate` to polyline start when a valid in-region hardware GPS fix exists.
8. R2.5: In arrival detection, check distance against both the road-snapped endpoint (`coords.last`) and the destination pin (`selectedCoordinate`), allowing arrival completion when destinations are set back from the road.

Verification:
- Run `./Tests/E2ETests/run_e2e_tests.sh` to ensure all 69 tests pass.
- Verify in-sandbox (DO NOT use `BypassSandbox: true`).
- Write detailed changes to `.agents/teamwork/worker_m3/changes.md`.
- Write handoff summary to `.agents/teamwork/worker_m3/handoff.md`.
- When complete, send a message back with your report path.
