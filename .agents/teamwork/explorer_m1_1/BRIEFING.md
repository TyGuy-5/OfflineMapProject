# BRIEFING — 2026-11-07T06:05:40Z

## Mission
Investigate `RoutingService.swift` for Milestone 1: R3.1 (`isVoiceMuted` synchronization), R3.2 (voice state reset in `stopVoice`), R3.3 (step deduplication logic in `speakTurnInstruction`), and R3.4 (route calculation initialization timeout fail-fast).

## 🔒 My Identity
- Archetype: teamwork_explorer
- Roles: investigator, synthesizer
- Working directory: /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m1_1
- Original parent: 353a2eeb-3a48-4ff7-be7e-6c7ece6b589d
- Milestone: Milestone 1

## 🔒 Key Constraints
- Read-only investigation — do NOT implement
- Deliver report to: /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m1_1/handoff.md
- Use send_message to report completion to parent orchestrator with summary and path

## Current Parent
- Conversation ID: 353a2eeb-3a48-4ff7-be7e-6c7ece6b589d
- Updated: not yet

## Investigation State
- **Explored paths**:
  - `MyOfflineMapApp/Sources/RoutingService.swift` (lines 1-568)
  - `MyOfflineMapApp/Sources/ContentView.swift` (lines 47-50, 475-485, 950-1345)
  - `MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift` (lines 480-498, 1215-1275)
  - `MyOfflineMapApp/Tests/MyOfflineMapAppTests/MyOfflineMapAppTests.swift` (lines 200-369)
  - `.agents/teamwork/ORIGINAL_REQUEST.md`, `.agents/teamwork/PROJECT.md`, `.agents/teamwork/explorer_survey_2/handoff.md`
- **Key findings**:
  - R3.1: `@Published` on `isVoiceMuted` introduces TSAN data races because Combine is not thread-safe across `@MainActor` and background threads. Replaced with private `_isVoiceMuted` synchronized by `voiceLock` in getter and setter. Guarded internal reads inside `speakTurnInstruction` and its `main.async` block without recursive lock calls.
  - R3.2: `stopVoice()` failed to reset `lastSpokenInstruction`, `lastSpokenStepId`, and `lastSpokenTime`, causing immediate route restarts within 6 seconds to silently swallow the first turn instruction. Resetting these three fields inside `voiceLock` to `""`, `nil`, and `.distantPast` fixes restart announcements.
  - R3.3: Step deduplication condition `(stepId != nil && stepId == lastSpokenStepId)` caused `isSameStep` to evaluate to `false` whenever `stepId == nil`, preventing deduplication of calls without explicit step IDs. Replacing with `(stepId != nil && lastSpokenStepId != nil) ? (stepId == lastSpokenStepId) : true` correctly deduplicates when `stepId == nil` while preserving distinct step separation for non-nil step IDs.
  - R3.4: `calculateRoute` ignored `initGroup.wait(timeout: .now() + 5.0)` return value (`_ =`), leading directly to an indefinite block on `queue.sync` if `setupValhalla()` was slow or hanging. Adding `guard initGroup.wait(timeout: .now() + 5.0) == .success else { return nil }` satisfies the fail-fast requirement cleanly.
- **Unexplored areas**: None within the scope of R3.1-R3.4.

## Key Decisions Made
- Confirmed that `@Published` is completely unused for Combine observation by callers (ContentView maintains its own `@State private var isVoiceMuted` and writes to `RoutingService.isVoiceMuted` imperatively).
- Designed non-recursive lock safety: setter unlocks `voiceLock` before calling `stopVoice()`; `speakTurnInstruction` accesses `_isVoiceMuted` directly rather than invoking the synchronized property getter.
- Preserved exact code strings inspected by `RemediationTests.swift` (`guard generation == currentGen else { return }` and `guard !self.speechSynthesizer.isSpeaking else { return }`).

## Artifact Index
- /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m1_1/DISPATCH.md — Received dispatch message
- /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m1_1/BRIEFING.md — Persistent working memory
- /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m1_1/progress.md — Liveness progress heartbeat
- /Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/.agents/teamwork/explorer_m1_1/handoff.md — Final investigation handoff report
