# Dispatch: challenger_m3_1

## Objective
Adversarial Stress Testing of Navigation Telemetry, Switchbacks, Monotonicity, and Simulation Progression (Requirements R2.1–R2.5):
- Empirically stress-test switchback geometries: verify that parallel road segments within 10-20 meters do NOT cause premature step advancement beyond `currentStep.endIndex + 2`.
- Empirically stress-test distance countdown monotonicity: verify that driving past `stepEnd` or destination endpoint evaluates remaining distance to 0.0 and never increases or reverses.
- Empirically stress-test multi-speed simulation at 1x, 2x, and 5x: verify that every intermediate maneuver is announced and advanced without dropping steps.
- Empirically stress-test hardware GPS start fix: verify puck does not freeze at route origin when valid GPS fix exists.
- Empirically stress-test dual-point arrival detection: verify arrival triggers for destinations set back 30-40 meters from the road.
- Run the full E2E test suite: `./Tests/E2ETests/run_e2e_tests.sh`.

## Working Directory
`.agents/teamwork/challenger_m3_1/`

## Constraints
- Run all test commands strictly in-sandbox (DO NOT use `BypassSandbox: true`).
- Read `ORIGINAL_REQUEST.md`: `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/ORIGINAL_REQUEST.md`.
- Read `PROJECT.md`: `/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/PROJECT.md`.
- Output verdict in `handoff.md`: `APPROVE` or `REQUEST_CHANGES`.
- Send message back when complete.


## 2026-11-07T07:35:20Z
You are challenger_m3_1, a teamwork_challenger agent.
Your working directory is: /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/challenger_m3_1/

You MUST read ORIGINAL_REQUEST.md before starting:
/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/ORIGINAL_REQUEST.md
Also read PROJECT.md:
/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/PROJECT.md
Also read DISPATCH.md in your directory:
/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/challenger_m3_1/DISPATCH.md
Read worker_m3 deliverables:
- /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/worker_m3/changes.md
- /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/worker_m3/handoff.md

Objective:
Adversarial Stress Testing of Navigation Telemetry, Switchbacks, Monotonicity, and Simulation Progression (Requirements R2.1–R2.5):
- Empirically stress-test switchback geometries: verify that parallel road segments within 10-20 meters do NOT cause premature step advancement beyond `currentStep.endIndex + 2`.
- Empirically stress-test distance countdown monotonicity: verify that driving past `stepEnd` or destination endpoint evaluates remaining distance to 0.0 and never increases or reverses.
- Empirically stress-test multi-speed simulation at 1x, 2x, and 5x: verify that every intermediate maneuver is announced and advanced without dropping steps.
- Empirically stress-test hardware GPS start fix: verify puck does not freeze at route origin when valid GPS fix exists.
- Empirically stress-test dual-point arrival detection: verify arrival triggers for destinations set back 30-40 meters from the road.
- Run the full E2E test suite: `./Tests/E2ETests/run_e2e_tests.sh`.

CRITICAL CONSTRAINTS:
- You are a verifier. DO NOT edit or modify production source code or test files.
- Run all test commands strictly in-sandbox (DO NOT use BypassSandbox: true).
- If compiling stress scripts, compile into `.agents/teamwork/challenger_m3_1/` or execute via swift scripts in-sandbox without elevated privileges.
- Deliver stress test report to `.agents/teamwork/challenger_m3_1/challenge_report.md` and handoff report to `.agents/teamwork/challenger_m3_1/handoff.md`.
- Conclude with a clear binary verdict: APPROVE or REQUEST_CHANGES.
- Send a message back when complete.
