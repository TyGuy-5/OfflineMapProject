## 2026-11-07T10:18:32Z

You are worker_m4 for Milestone 4 (Test Modernization, Build Config & Documentation).

Your working directory is:
/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/worker_m4

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

MANDATORY INSTRUCTIONS:
1. Read the original user request at /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/ORIGINAL_REQUEST.md before starting work.
2. Read /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/PROJECT.md and /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/worker_m4/DISPATCH.md.
3. Review the Explorer reports:
   - /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m4_1/handoff.md (RemediationTests refactoring)
   - /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m4_2/handoff.md and .agents/teamwork/explorer_m4_2/r6_2_valhalla_config.patch
   - /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m4_3/handoff.md and .agents/teamwork/explorer_m4_3/sanitization.patch

YOUR WRITE BOUNDARIES (Exclusively Owned Files):
- `MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift`
- `MyOfflineMapApp/Tests/MyOfflineMapAppTests/MyOfflineMapAppTests.swift`
- `DOCUMENTATION.md`
- `docs/AUDIT_REPORT.md`
Do NOT modify `OfflineDataManager.swift` (#filePath count must remain exactly 1).

TASKS TO EXECUTE:
1. R6.4 Documentation Sanitization:
   Apply the 11 line replacements from `explorer_m4_3` (via patch or direct edit) to sanitize `DOCUMENTATION.md` and `docs/AUDIT_REPORT.md`. Confirm 0 instances of `/Volumes/Extended Hard Drive` and 0 machine UDIDs remain in those files.
2. R6.2 Valhalla Config Test Fix:
   Apply the changes from `explorer_m4_2` to `MyOfflineMapApp/Tests/MyOfflineMapAppTests/MyOfflineMapAppTests.swift`: remove `import ValhallaConfigModels` and update `testBinnedTileRouting()` to initialize Valhalla via config path using `valhalla.json`.
3. R6.1 RemediationTests Modernization:
   Refactor `MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift` following the design in `explorer_m4_1/handoff.md`.
   - Replace all 12 unmounted `ContentView()` mutations with direct tests on `NavigationViewModel`.
   - Replace all 10 `#filePath` source file string matching inspections with genuine behavioral tests on `NavigationViewModel` (search cancellation, category deduplication flag, metric/imperial unit toggle during simulation, boundary GPS dropping, R2.1–R2.5 telemetry and progression).
   - Ensure 0 `#filePath` references remain in `RemediationTests.swift`.
   - Preserve all existing concurrency, audio, and location manager stress tests (`ConcurrencyAudioStressTests`, `LocationManagerAdversarialStressTests`).
4. Verification:
   - Run `./Tests/E2ETests/run_e2e_tests.sh` (must pass 69/69).
   - Verify `#filePath` count in `OfflineDataManager.swift` is still 1.
   - Verify `#filePath` count in `RemediationTests.swift` is 0.
   - Verify `swiftc` compiles without errors.
5. Deliver handoff report to `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/worker_m4/handoff.md` and send a completion message to the parent orchestrator.
