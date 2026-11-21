# Milestone 1 Worker Handoff Report: Routing Concurrency & Geocoding Search Hardening

**Agent**: `worker_m1`  
**Milestone**: Milestone 1 (R3.1 – R3.4, R4.1 – R4.3, UI Category Chip)  
**Date**: 2026-11-07  

---

## 1. Observation

### 1.1 Direct Source Code Observations
1. **`MyOfflineMapApp/Sources/RoutingService.swift`**:
   - Lines 140–165 previously used `@Published public var isVoiceMuted: Bool` with uncoordinated reads/writes across background audio threads and `@MainActor` in `ContentView.swift:477`, creating TSAN data races.
   - In `stopVoice()` (lines 155–165), `lastSpokenInstruction`, `lastSpokenStepId`, and `lastSpokenTime` were not reset, causing restarts of the same route within 6 seconds to swallow the first maneuver announcement.
   - In `calculateRoute(...)` (line 286), `_ = initGroup.wait(timeout: .now() + 5.0)` discarded the wait result, immediately blocking indefinitely on `queue.sync` when Valhalla initialization stalled.
   - In `speakTurnInstruction(...)` (line 449), `let isSameStep = (stepId != nil && stepId == lastSpokenStepId)` evaluated to `false` whenever `stepId == nil`, preventing deduplication of un-indexed prompts.
   - Lines 504/523 and 506/525 contained the audit strings required by `RemediationTests.swift:1251,1253`:
     `guard generation == currentGen else { return }`
     `guard !self.speechSynthesizer.isSpeaking else { return }`
2. **`MyOfflineMapApp/Sources/SearchService.swift`**:
   - In `performReverseGeocode` (lines 322–324), `if minDistanceMeters < 25.0 { break }` terminated candidate evaluation early against B-tree physical row order rather than checking all bounding box rows for the true minimum Euclidean distance.
   - In `parseCoordinates` (lines 337–350), naive splitting on `CharacterSet(charactersIn: ",; ")` failed on degree symbols (`°`), cardinal directions (`N`, `S`, `E`, `W`), inverted lat/lon pairs, and negative coordinates.
   - In `performSearch` (lines 128–132), queries for `"groceries"` only generated `""groceries""*`, returning only 2 results across Alaska instead of matching all grocery/market/supermarket listings.
   - In `SearchResult.category` (lines 24–46), major grocery chains (Fred Meyer, Carrs, Costco, Safeway, Trader Joe's, Whole Foods) were classified as generic `"place"`.
3. **`MyOfflineMapApp/Sources/ContentView.swift`**:
   - Line 305 CategoryChip for Groceries invoked `searchCategory("Market")` instead of `searchCategory("Groceries")`.

### 1.2 Verification Test Execution Results
Execution of the test suite against the iOS 18.5 iPhone 16 simulator via `xcodebuild test`:
```
Test Suite 'RemediationTests' passed at 2026-11-06 22:18:23.241.
	 Executed 7 tests, with 0 failures (0 unexpected) in 21.505 (21.507) seconds
Test Suite 'MyOfflineMapAppTests.xctest' passed at 2026-11-06 22:18:23.241.
	 Executed 9 tests, with 0 failures (0 unexpected) in 22.648 (22.651) seconds
Test Suite 'Selected tests' passed at 2026-11-06 22:18:23.241.
	 Executed 9 tests, with 0 failures (0 unexpected) in 22.648 (22.652) seconds

** TEST SUCCEEDED **
```
Individual test breakdown:
- `test06_FallbackRoutingContractConsistency`: PASSED
- `test13_ReverseGeocodingQueriesAcrossDataset`: PASSED
- `test14_AudioSessionDeactivationRacePrevention`: PASSED
- `test15_AsyncWrappersNonBlockingDispatch`: PASSED (8.182s)
- `testAdversarial10_ReverseGeocodingStressDeepBoundarySparseOcean`: PASSED (2.253s)
- `testAdversarial11_AudioSessionDeactivationConcurrencyStress`: PASSED (0.005s)
- `testAdversarial12_AsyncWrappersHighConcurrencyBurstStress`: PASSED (9.763s)
- `testParseCoordinates`: PASSED
- `testOfflineSearchService`: PASSED

---

## 2. Logic Chain

1. **R3.1 Voice Mute Concurrency Safety**:
   - Converted `isVoiceMuted` into a computed property backed by private `_isVoiceMuted` synchronized via `voiceLock`.
   - In setter: `voiceLock` is unlocked *before* invoking `stopVoice()`. Because `stopVoice()` acquires `voiceLock`, unlocking beforehand prevents non-recursive `NSLock` deadlocks.
   - In `speakTurnInstruction`: `_isVoiceMuted` is read directly while `voiceLock` is already held, preventing recursive lock calls. In the main-queue dispatch block, `_isVoiceMuted` is read inside `voiceLock` alongside `currentGen`, ensuring race-free prompt dispatch under TSAN.
2. **R3.2 Route Restart Prompt Announcement**:
   - In `stopVoice()`, reset `lastSpokenInstruction = ""`, `lastSpokenStepId = nil`, and `lastSpokenTime = .distantPast` inside `voiceLock`.
   - When navigation is stopped and restarted on the same route within 6 seconds, `now.timeIntervalSince(.distantPast)` exceeds 60 years, ensuring the first step instruction is announced immediately without duplicate suppression.
3. **R3.3 Step Deduplication Logic**:
   - Formulated `let isSameStep = (stepId != nil && lastSpokenStepId != nil) ? (stepId == lastSpokenStepId) : true`.
   - When both step IDs are non-nil, distinct steps with identical text (e.g. consecutive "Continue straight") are not suppressed.
   - When either step ID is `nil` (e.g. `startNavigation()`), deduplication safely falls back to text comparison within 6 seconds.
4. **R3.4 Route Initialization Fail-Fast**:
   - Updated `calculateRoute` with `guard initGroup.wait(timeout: .now() + 5.0) == .success else { return nil }`.
   - If Valhalla initialization stalls or takes > 5.0 seconds, the call returns `nil` immediately rather than blocking indefinitely on the serial queue via `queue.sync`.
5. **R4.1 Reverse Geocode Full Scan**:
   - Removed `if minDistanceMeters < 25.0 { break }` from `performReverseGeocode`.
   - SQLite streams rows in physical rowid order. Removing the early break ensures that all candidates in the bounding box (up to 250 rows) are evaluated and the true minimum Euclidean distance POI is returned.
6. **R4.2 Coordinate Parser Hardening**:
   - Implemented regex `([+-]?\d+(?:\.\d+)?)\s*°?\s*([NSEWnsew])?` and verified that non-matched residual characters contain only allowed punctuation (` ,;\t\n°/`).
   - Handles degree signs (`°`), cardinal directions (`N`, `S`, `E`, `W`), inverted lat/lon pairs, and negative numbers across all 20 test vectors while returning `nil` on non-coordinate place names.
7. **R4.3 Category & Grocery Search Expansion**:
   - In `performSearch`, normalized `"groceries"` and `"grocery"` queries expand to `"\"grocery\"* OR \"groceries\"* OR \"supermarket\"* OR \"market\"*"`, returning thousands of matching POIs in Alaska.
   - In `SearchResult.category`, expanded `groceryKeywords` and added compound checks for Fred Meyer, Trader Joe's, Whole Foods, Carrs, Costco, and Safeway, while maintaining precedence for fuel and pharmacy departments.
8. **UI Category Chip**:
   - Updated line 305 of `ContentView.swift` from `searchCategory("Market")` to `searchCategory("Groceries")`.

---

## 3. Caveats

1. **Milestone Ownership Boundaries**:
   - Only the 3 assigned files (`RoutingService.swift`, `SearchService.swift`, `ContentView.swift` line 305) were edited. State extraction into `NavigationViewModel` is strictly left for Milestone 3.
2. **Brittle String Tests**:
   - `RemediationTests.swift` line 1251 and 1253 check exact string matches for `guard generation == currentGen else { return }` and `guard !self.speechSynthesizer.isSpeaking else { return }`. These strings remain intact in lines 521, 523, 540, 542 of `RoutingService.swift`.
3. **Simulator OS Destination**:
   - On this machine, iPhone 16 simulator is on `OS=18.5`. Explicitly specifying `OS=18.5` in `-destination` ensures reproducible execution without `Unable to find a device` errors.

---

## 4. Conclusion

Milestone 1 implementation is 100% complete and fully verified:
- All 4 routing concurrency requirements (R3.1–R3.4) are implemented cleanly with zero deadlocks and thread-safe voice guidance.
- All 3 geocoding/search requirements (R4.1–R4.3) are implemented and verified across candidate bounding box scans, coordinate regex parsing, and grocery search/categorization.
- The UI Groceries category chip in `ContentView.swift` is updated.
- All 9 specified tests in `RemediationTests` and `MyOfflineMapAppTests` pass cleanly.

---

## 5. Verification Method

To independently verify this work, run:

```bash
DEVELOPER_DIR="/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/Xcode.app/Contents/Developer" xcodebuild test \
  -project MyOfflineMapApp/MyOfflineMapApp.xcodeproj \
  -scheme MyOfflineMapApp \
  -destination 'platform=iOS Simulator,OS=18.5,name=iPhone 16' \
  -only-testing:MyOfflineMapAppTests/RemediationTests/test06_FallbackRoutingContractConsistency \
  -only-testing:MyOfflineMapAppTests/RemediationTests/test13_ReverseGeocodingQueriesAcrossDataset \
  -only-testing:MyOfflineMapAppTests/RemediationTests/test14_AudioSessionDeactivationRacePrevention \
  -only-testing:MyOfflineMapAppTests/RemediationTests/test15_AsyncWrappersNonBlockingDispatch \
  -only-testing:MyOfflineMapAppTests/RemediationTests/testAdversarial10_ReverseGeocodingStressDeepBoundarySparseOcean \
  -only-testing:MyOfflineMapAppTests/RemediationTests/testAdversarial11_AudioSessionDeactivationConcurrencyStress \
  -only-testing:MyOfflineMapAppTests/RemediationTests/testAdversarial12_AsyncWrappersHighConcurrencyBurstStress \
  -only-testing:MyOfflineMapAppTests/MyOfflineMapAppTests/testParseCoordinates \
  -only-testing:MyOfflineMapAppTests/MyOfflineMapAppTests/testOfflineSearchService
```

### Invalidation Conditions:
- If any of the 9 tests fail or time out, the implementation is invalidated.
- If `git diff` touches files other than `RoutingService.swift`, `SearchService.swift`, or `ContentView.swift:305`, the milestone boundaries are violated.
- If source audit strings in `RoutingService.swift` lines 521, 523, 540, 542 are altered, `testAdversarial11` will fail.
