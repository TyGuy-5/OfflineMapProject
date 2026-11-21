## 2026-11-07T05:51:33Z
From: 353a2eeb-3a48-4ff7-be7e-6c7ece6b589d (parent)
Mission: Phase 0 Survey - Focus Area B (Requirements R3 and R4)
Investigate the codebase for Requirements R3 and R4:
1. R3: Routing Engine and Audio Concurrency Safety:
   - Inspect `RoutingService.swift`: find all places where `isVoiceMuted` is accessed or modified. Investigate threading and synchronization with `voiceLock`. Identify data races between SwiftUI bindings and background audio threads.
   - Inspect `stopVoice()`: identify how audio/speech state is cleared, and verify how to reset `lastSpokenInstruction`, `lastSpokenStepId`, and `lastSpokenTime` to `.distantPast` so restarting navigation within 6 seconds reliably announces the initial turn.
   - Inspect `speakTurnInstruction`: identify how step deduplication is implemented and why calls where `stepId == nil` fail or are mishandled.
   - Inspect route calculation initialization and queue management: find where `initGroup.wait(timeout: .now() + 5.0)` is used, why it might block on `queue.sync`, and how route calculation can fail fast by cleanly returning `nil` on timeout without blocking indefinitely.
2. R4: Geocoding Optimization and Input Parsing:
   - Inspect `SearchService.swift`: examine `performReverseGeocode`, locate the `< 25.0` meter break condition, and analyze how removing it allows scanning the full candidate bounding box to select the true closest POI.
   - Inspect `parseCoordinates`: locate current coordinate parsing implementation, examine regex/parsing logic, and determine how to accept coordinates with degree symbols (`°`) and cardinal direction suffixes (`N`, `S`, `E`, `W`) while properly handling negative values (e.g. `S` and `W`).
   - Inspect category classification and search queries for POI categories such as groceries. Identify how categories are mapped, queried, and classified in SQLite/FTS5.
