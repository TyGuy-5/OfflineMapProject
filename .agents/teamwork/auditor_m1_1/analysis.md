# Forensic Integrity Analysis — Milestone 1

**Target Work Products**:
- `MyOfflineMapApp/Sources/RoutingService.swift`
- `MyOfflineMapApp/Sources/SearchService.swift`
- `MyOfflineMapApp/Sources/ContentView.swift`

## Audit Phase 1: Mode-Agnostic Investigation (Observe All)

### 1. Hardcoded Test Value Analysis
- **RoutingService.swift**:
  - Inspected all string literals and numeric constants.
  - No mock routing responses, no test coordinate arrays, no hardcoded strings designed to satisfy test assertions.
  - Concurrency tokens and generation counters are dynamically generated and incremented (`activeSpeechGeneration += 1`, `ObjectIdentifier(utterance)`).
  - Reset values in `stopVoice()` are standard sentinel defaults (`lastSpokenInstruction = ""`, `lastSpokenStepId = nil`, `lastSpokenTime = .distantPast`).
  - Observation: CLEAN.

- **SearchService.swift**:
  - Inspected `performReverseGeocode`: Distance calculation uses standard spherical approximation (`dx = (lon - coordinate.longitude) * 111320.0 * cosLat`, `dy = (lat - coordinate.latitude) * 110540.0`, `d = sqrt(dx * dx + dy * dy)`). No hardcoded IDs or coordinate overrides.
  - Inspected `parseCoordinates`: Parses dynamically via regex `([+-]?\d+(?:\.\d+)?)\s*°?\s*([NSEWnsew])?`, validates residual separators (`CharacterSet(charactersIn: ",; \t\n°/")`), converts cardinal signs (`S`/`W` -> negative), validates lat `[-90, 90]` and lon `[-180, 180]`. No test-case-specific query branches.
  - Inspected `performSearch` & `SearchResult.category`: FTS5 expansion applies generically to normalized `"groceries"` and `"grocery"`. Classification handles major store brands generically. No hardcoded mock search results.
  - Observation: CLEAN.

- **ContentView.swift**:
  - Line 305 CategoryChip changed `searchCategory("Market")` to `searchCategory("Groceries")`.
  - Observation: CLEAN.

### 2. Facade / Dummy Implementation Analysis
- **Routing Concurrency**:
  - `_isVoiceMuted` is protected by `voiceLock.lock()` / `voiceLock.unlock()`.
  - In setter, lock is released before calling `stopVoice()`, preventing self-deadlock on `NSLock`.
  - In `speakTurnInstruction`, `_isVoiceMuted` is checked under lock synchronously, and re-checked under lock on the main queue before speech invocation.
  - In `calculateRoute`, `initGroup.wait(timeout: .now() + 5.0) == .success` return value is genuinely checked, failing fast with `nil` if timeout occurs.
  - `AVSpeechSynthesizerDelegate` callbacks safely clean up `utteranceGenerations` under `voiceLock` and verify active generation and speaking state before audio session deactivation.
  - Observation: Real implementation, no facades.

- **SearchService Reverse Geocode & Parser**:
  - Removed `< 25.0` early break in `performReverseGeocode`. Scans entire candidate set returned by SQLite query (up to 250 rows).
  - True minimum Euclidean distance is calculated and tracked in `minDistanceMeters`.
  - Observation: Real implementation, no facades.

### 3. Boundary & Git Diff Analysis
- Changes confined exclusively to:
  - `MyOfflineMapApp/Sources/ContentView.swift` (1 line modified)
  - `MyOfflineMapApp/Sources/RoutingService.swift` (33 lines modified)
  - `MyOfflineMapApp/Sources/SearchService.swift` (119 lines modified)
- No unauthorized file deletions, modifications, or external dependencies introduced.
- Observation: CLEAN.

### 4. Artifact Analysis
- No pre-populated result files, mock test logs, or attestation files found in workspace.
