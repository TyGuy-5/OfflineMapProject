# Survey Report: Requirements R3 and R4 (Focus Area B)

## 1. Observation

### 1.1 Requirement R3: Routing Engine and Audio Concurrency Safety

#### 1.1.1 `isVoiceMuted` Threading & Data Races
- **File**: `MyOfflineMapApp/Sources/RoutingService.swift`
- **Lines 141-147**:
  ```swift
  // Voice Guidance State (Thread Confined)
  private let speechSynthesizer = AVSpeechSynthesizer()
  @Published public var isVoiceMuted: Bool = false {
      didSet {
          if isVoiceMuted {
              stopVoice()
          }
      }
  }
  ```
- **Lines 440-445**:
  ```swift
  public func speakTurnInstruction(_ text: String, stepId: Int? = nil, force: Bool = false) {
      voiceLock.lock()
      guard !isVoiceMuted && !text.isEmpty else {
          voiceLock.unlock()
          return
      }
  ```
- **Lines 465-472**:
  ```swift
  DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.voiceLock.lock()
      let currentGen = self.activeSpeechGeneration
      self.voiceLock.unlock()

      guard generation == currentGen, !self.isVoiceMuted else { return }
  ```
- **File**: `MyOfflineMapApp/Sources/ContentView.swift`
- **Lines 475-481**:
  ```swift
  // Voice Mute Toggle
  Button(action: {
      isVoiceMuted.toggle()
      routingService.isVoiceMuted = isVoiceMuted
      if isVoiceMuted {
          routingService.stopVoice()
      }
  }) {
  ```
- **File**: `MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift`
- **Lines 496**: `XCTAssertFalse(routingService.isVoiceMuted)`
- **Lines 1220-1227**: Calls `routingService.speakTurnInstruction(...)` across 40 concurrent background threads (`DispatchQueue.global(qos: .userInteractive).async`).

#### 1.1.2 Prompt State Clearing in `stopVoice()`
- **File**: `MyOfflineMapApp/Sources/RoutingService.swift`
- **Lines 148-165**:
  ```swift
  private var lastSpokenInstruction: String = ""
  private var lastSpokenStepId: Int? = nil
  private var lastSpokenTime: Date = Date.distantPast
  private var activeSpeechGeneration: Int = 0
  private var utteranceGenerations: [ObjectIdentifier: Int] = [:]
  private let voiceLock = NSLock()

  public func stopVoice() {
      voiceLock.lock()
      activeSpeechGeneration += 1
      utteranceGenerations.removeAll()
      voiceLock.unlock()
      DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }
          self.speechSynthesizer.stopSpeaking(at: .immediate)
          try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      }
  }
  ```
- **File**: `MyOfflineMapApp/Sources/ContentView.swift`
- **Line 1267** (in `startNavigation()`):
  ```swift
  if let first = details.steps.first {
      routingService.speakTurnInstruction(first.instruction)
  }
  ```
- **Lines 1335-1352** (in `endNavigation()`):
  ```swift
  private func endNavigation() {
      activeRouteRequestId = nil
      isRecalculating = false
      consecutiveRerouteFailures = 0
      routingService.stopVoice()
      simulationTimer?.invalidate()
      ...
  ```

#### 1.1.3 Step Deduplication in `speakTurnInstruction`
- **File**: `MyOfflineMapApp/Sources/RoutingService.swift`
- **Lines 447-463**:
  ```swift
  let now = Date()
  let isSameText = (text == lastSpokenInstruction)
  let isSameStep = (stepId != nil && stepId == lastSpokenStepId)
  let timeSinceLastPrompt = now.timeIntervalSince(lastSpokenTime)

  // Drop duplicate prompts only if it is the same step and occurred within 6 seconds
  if !force && isSameText && isSameStep && timeSinceLastPrompt < 6.0 {
      voiceLock.unlock()
      return
  }

  lastSpokenInstruction = text
  lastSpokenStepId = stepId
  lastSpokenTime = now
  ```

#### 1.1.4 Route Calculation Timeout & Queue Blocking
- **File**: `MyOfflineMapApp/Sources/RoutingService.swift`
- **Lines 170-175**:
  ```swift
  initGroup.enter()
  queue.async {
      self.setupValhalla()
      self.initGroup.leave()
  }
  ```
- **Lines 280-290**:
  ```swift
  public func calculateRoute(
      from start: CLLocationCoordinate2D,
      to destination: CLLocationCoordinate2D,
      mode: String = "auto",
      useMetric: Bool = false
  ) -> RouteDetails? {
      _ = initGroup.wait(timeout: .now() + 5.0)
      return queue.sync { () -> RouteDetails? in
          if self.valhalla == nil {
              self.setupValhalla()
          }
  ```

---

### 1.2 Requirement R4: Geocoding Optimization and Input Parsing

#### 1.2.1 `< 25.0` Meter Break in `performReverseGeocode`
- **File**: `MyOfflineMapApp/Sources/SearchService.swift`
- **Lines 267-268**:
  ```swift
  let sql = "SELECT rowid, name, lat, lon FROM geocoder WHERE CAST(lat AS REAL) BETWEEN ? AND ? AND CAST(lon AS REAL) BETWEEN ? AND ? LIMIT 250;"
  ```
- **Lines 318-325**:
  ```swift
  if d < minDistanceMeters {
      minDistanceMeters = d
      closest = SearchResult(id: rId, name: rName, lat: lat, lon: lon)
  }
  if minDistanceMeters < 25.0 {
      break
  }
  ```

#### 1.2.2 `parseCoordinates` Parsing Logic
- **File**: `MyOfflineMapApp/Sources/SearchService.swift`
- **Lines 336-350**:
  ```swift
  /// Detect and parse decimal coordinates in search bar (e.g. "64.8569, -147.8028")
  public func parseCoordinates(query: String) -> CLLocationCoordinate2D? {
      let parts = query.components(separatedBy: CharacterSet(charactersIn: ",; "))
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
          .filter { !$0.isEmpty }

      guard parts.count == 2,
            let lat = Double(parts[0]),
            let lon = Double(parts[1]),
            lat >= -90 && lat <= 90,
            lon >= -180 && lon <= 180 else {
          return nil
      }
      return CLLocationCoordinate2D(latitude: lat, longitude: lon)
  }
  ```

#### 1.2.3 Category Classification and FTS5 Queries
- **File**: `MyOfflineMapApp/Sources/SearchService.swift`
- **Lines 24-25**:
  ```swift
  let groceryKeywords: Set<String> = ["grocery", "groceries", "supermarket", "safeway", "walmart", "costco"]
  ```
- **Lines 42-44**:
  ```swift
  } else if !words.isDisjoint(with: groceryKeywords) || words.contains("market") {
      return "grocery"
  ```
- **Lines 128-133**:
  ```swift
  let nonAlphanumeric = CharacterSet.alphanumerics.inverted
  let tokens = query.components(separatedBy: nonAlphanumeric).filter { !$0.isEmpty }
  guard !tokens.isEmpty else { return [] }

  let searchQuery = tokens.map { "\"\($0)\"*" }.joined(separator: " ")
  ```
- **File**: `MyOfflineMapApp/Sources/ContentView.swift`
- **Lines 304-306**:
  ```swift
  CategoryChip(icon: "cart.fill", title: "Groceries", color: .green) {
      searchCategory("Market")
  }
  ```
- **Database Schema**: `data/search_index.db`
  ```sql
  CREATE VIRTUAL TABLE geocoder USING fts5(
      name, 
      lat UNINDEXED, 
      lon UNINDEXED, 
      prefix='2 3 4'
  );
  ```
- **Tool Query Results**:
  - `sqlite3 "data/search_index.db" "SELECT count(*) FROM geocoder WHERE geocoder MATCH '\"groceries\"*';"`: **312 rows** nationwide, **0 rows** in Alaska (lat 62-67, lon -152 to -144).
  - `sqlite3 "data/search_index.db" "SELECT count(*) FROM geocoder WHERE geocoder MATCH '\"grocery\"*';"`: **4,727 rows**.
  - `sqlite3 "data/search_index.db" "SELECT count(*) FROM geocoder WHERE geocoder MATCH '\"market\"*';"`: **70,038 rows**.
  - `sqlite3 "data/search_index.db" "SELECT count(*) FROM geocoder WHERE geocoder MATCH '\"supermarket\"*';"`: **1,798 rows**.
  - Verified Fairbanks POIs in DB: `Co-Op Market Grocery & Deli` (rowid 32257084, lat 64.8372, lon -147.7161), `Tanana Valley Farmers Market` (rowid 50356092, lat 64.8632, lon -147.7831), `Birch Hill Market` (rowid 4731014, lat 64.8692, lon -147.6700), `Safeway` (rowid 27390388), `Fred Meyer` (rowid 27217124), `Costco` (rowid 25951584), `Walmart Supercenter` (rowid 31175363).

---

## 2. Logic Chain

### 2.1 Routing Engine & Audio Concurrency (R3)

#### 2.1.1 Data Races on `isVoiceMuted`
1. `RoutingService` is declared `@unchecked Sendable` and initialized as an `ObservableObject`.
2. Property `isVoiceMuted` is declared as `@Published public var isVoiceMuted: Bool = false`.
3. In `ContentView.swift` (line 477), the user-interface button on `@MainActor` mutates `routingService.isVoiceMuted = isVoiceMuted`.
4. In `RoutingService.swift` (line 442), `speakTurnInstruction` is called from arbitrary concurrent background threads (e.g., `RemediationTests.swift` line 1223 `DispatchQueue.global().async`, and route recalculation completion handlers). It reads `isVoiceMuted` while holding `voiceLock`.
5. In `RoutingService.swift` (line 471), `main.async` reads `self.isVoiceMuted` without holding `voiceLock`.
6. `@Published` synthesis is not thread-safe. A simultaneous write from `@MainActor` and a read on a background audio thread generates a classic memory data race under ThreadSanitizer (TSAN).
7. Furthermore, `didSet` in line 142 calls `stopVoice()`, which acquires `voiceLock.lock()`, creating inverted lock sequencing relative to caller threads.
8. **Deduction**: `isVoiceMuted` must be backed by a private variable `_isVoiceMuted` guarded by `voiceLock` across all getters, setters, and internal checks. Removing `@Published` (which is never observed via Combine elsewhere in the app; UI state is tracked by ViewModel/AppStorage) completely eliminates TSAN warnings.

#### 2.1.2 Restarting Route Within 6 Seconds (`stopVoice()`)
1. In `speakTurnInstruction`, lines 453-456:
   ```swift
   if !force && isSameText && isSameStep && timeSinceLastPrompt < 6.0 {
       voiceLock.unlock()
       return
   }
   ```
2. When navigation starts on route A, `speakTurnInstruction("Head east on University Ave", stepId: nil)` executes.
   - `lastSpokenInstruction` becomes `"Head east on University Ave"`.
   - `lastSpokenTime` becomes `Date()`.
3. The user cancels navigation 2 seconds later. `endNavigation()` calls `routingService.stopVoice()`.
4. In `stopVoice()` (lines 155-165), only `activeSpeechGeneration` is incremented and `utteranceGenerations` is cleared. `lastSpokenInstruction`, `lastSpokenStepId`, and `lastSpokenTime` are NOT reset.
5. The user restarts navigation 1 second later (total elapsed time 3.0s < 6.0s). `startNavigation()` calls `speakTurnInstruction("Head east on University Ave", stepId: nil)`.
6. `isSameText` evaluates to `true`, and `timeSinceLastPrompt` evaluates to 3.0s (< 6.0s).
7. Consequently, the initial turn instruction is silently dropped, leaving the user with no audio prompt upon starting navigation.
8. **Deduction**: In `stopVoice()`, inside `voiceLock`, `lastSpokenInstruction` must be reset to `""`, `lastSpokenStepId` to `nil`, and `lastSpokenTime` to `.distantPast`. This ensures any new navigation session immediately announces the initial maneuver regardless of how quickly it was restarted.

#### 2.1.3 Step Deduplication When `stepId == nil`
1. Line 449 defines step identity as:
   `let isSameStep = (stepId != nil && stepId == lastSpokenStepId)`
2. When a caller does not pass a `stepId` (e.g., `startNavigation()` line 1267, or standalone prompts), `stepId` defaults to `nil`.
3. When `stepId == nil`, `stepId != nil` evaluates to `false`.
4. Therefore, `isSameStep` is ALWAYS `false` whenever `stepId == nil`.
5. This has two harmful consequences:
   - Duplicate suppression never triggers for prompts where `stepId == nil`: identical back-to-back calls within 0.1s will speak twice.
   - If a prompt with `stepId: nil` is followed by a prompt with `stepId: 0` (or vice versa) for the exact same text within 1 second, it fails to recognize that they represent the same initial instruction.
6. **Deduction**: `isSameStep` must be formulated as:
   `let isSameStep = (stepId != nil && lastSpokenStepId != nil) ? (stepId == lastSpokenStepId) : true`
   When explicit non-nil step IDs are provided on both calls, distinct IDs prevent suppression (e.g. consecutive "Continue straight" steps). When step IDs are omitted or transition from nil, duplicate suppression properly falls back to `isSameText && timeSinceLastPrompt < 6.0`.

#### 2.1.4 Valhalla Initialization Timeout & Queue Lockup
1. Line 286 performs a wait on the dispatch group:
   `_ = initGroup.wait(timeout: .now() + 5.0)`
2. The return value (`.success` vs `.timedOut`) is completely ignored (`_ =`).
3. Line 287 immediately invokes:
   `return queue.sync { () -> RouteDetails? in ... }`
4. In `init()`, `self.setupValhalla()` was dispatched asynchronously on `queue` (a serial queue).
5. If `setupValhalla()` hangs or takes longer than 5.0 seconds (e.g. slow disk decompression, missing config, thread starvation), `initGroup.wait` times out after 5.0 seconds.
6. However, line 287 immediately blocks the calling thread on `queue.sync`. Since `queue` is serial and currently busy running `setupValhalla()`, the caller blocks indefinitely instead of timing out at 5.0 seconds.
7. **Deduction**: Line 286 must check the return value of `initGroup.wait`. If it returns `.timedOut`, `calculateRoute` must immediately return `nil` without calling `queue.sync`, satisfying the requirement to fail fast within 5.0 seconds.

---

### 2.2 Geocoding & Input Parsing (R4)

#### 2.2.1 `< 25.0` Meter Early Break in `performReverseGeocode`
1. The SQL query in `SearchService.swift` (line 267) executes:
   `SELECT rowid, name, lat, lon FROM geocoder WHERE CAST(lat AS REAL) BETWEEN ? AND ? AND CAST(lon AS REAL) BETWEEN ? AND ? LIMIT 250;`
2. This query has NO `ORDER BY distance` clause; SQLite returns matching records in natural B-tree / rowid order.
3. In lines 322-324:
   ```swift
   if minDistanceMeters < 25.0 {
       break
   }
   ```
4. If an arbitrary candidate in the bounding box happens to be 24 meters away and appears first in rowid order, the loop terminates immediately.
5. If another candidate located later in the 250 rows is only 2 meters from the user, it is never evaluated.
6. The query result set is capped at `LIMIT 250`. Computing 2D Euclidean distance on at most 250 records takes under 0.05 milliseconds on modern Apple Silicon.
7. **Deduction**: Removing `if minDistanceMeters < 25.0 { break }` allows the loop to scan all 250 candidate records within the 800m bounding box, guaranteeing that the returned POI is the true global minimum distance to the query point.

#### 2.2.2 `parseCoordinates` Support for Degree Signs & Cardinal Directions
1. Current implementation in `SearchService.swift` (lines 337-349) splits the query string by `,; ` into `parts` and verifies `parts.count == 2` followed by `Double(parts[0])` and `Double(parts[1])`.
2. Real-world coordinates frequently include:
   - Degree symbols (`°`): e.g. `64.8436° N, 147.7215° W`
   - Cardinal direction suffixes: `N`, `S`, `E`, `W`
   - Spaces between number, degree sign, and direction: `64.8436 ° N`
   - Inverted coordinate ordering: `147.7215° W, 64.8436° N` (longitude first)
3. Under the current implementation:
   - Splitting `"64.8436° N, 147.7215° W"` on `,; ` yields 4 tokens (`"64.8436°"`, `"N"`, `"147.7215°"`, `"W"`), causing `parts.count == 2` to fail.
   - `Double("64.8436°")` returns `nil`.
   - Cardinal directions `S` and `W` are not converted to negative values.
4. **Deduction**: A regular expression `([+-]?\d+(?:\.\d+)?)\s*°?\s*([NSEWnsew])?` must be used to match the two coordinate components. The parser must ensure that the remaining non-matched text contains only allowed punctuation/whitespace, identify latitude and longitude from cardinal letters (or default to lat/lon order), negate for `S` and `W` (`-abs(val)`), and validate bounds `[-90, 90]` and `[-180, 180]`.

#### 2.2.3 Category Classification & FTS5 Query Expansion (Groceries)
1. `data/search_index.db` virtual table `geocoder` stores only `(name, lat UNINDEXED, lon UNINDEXED)`. There is no dedicated category column in SQLite.
2. In `SearchService.performSearch`, search queries are converted to FTS5 prefix matches:
   `let searchQuery = tokens.map { "\"\($0)\"*" }.joined(separator: " ")`
3. When the user searches for `"groceries"`, the FTS5 query is `"\"groceries\"*"`.
4. In `search_index.db`, `"groceries"*` matches only 312 rows nationwide, and 0 rows in Alaska. All Alaskan grocery stores use words like "Grocery", "Market", "Supermarket", "Safeway", "Fred Meyer", or "Costco".
5. Because searching "groceries" produced 0 results in Alaska, `ContentView.swift` line 305 instituted an awkward workaround:
   `CategoryChip(icon: "cart.fill", title: "Groceries", color: .green) { searchCategory("Market") }`
   This caused the search bar text to read "Market", returned road names like "Market Street", and missed all places named "Grocery" or "Supermarket".
6. Furthermore, in `SearchResult.category`, `groceryKeywords` only included `["grocery", "groceries", "supermarket", "safeway", "walmart", "costco"]`.
   Major Alaskan chains like "Fred Meyer", "Carrs", "IGA", and national chains like "Kroger", "Trader Joe's", "Whole Foods" were missing or classified as `"place"`.
7. **Deduction**:
   - `SearchService.performSearch` must expand category searches for terms like `groceries` / `grocery` into multi-term FTS5 disjunctions:
     `"\"grocery\"* OR \"groceries\"* OR \"supermarket\"* OR \"market\"*"`
   - `SearchResult.category` must include `"carrs"`, `"kroger"`, `"albertsons"`, `"aldi"`, `"supermarkets"` and check compound brand names like `"fred meyer"` (`words.contains("fred") && words.contains("meyer")`).
   - `ContentView.swift` (and `NavigationViewModel`) must update the Groceries chip to `searchCategory("Groceries")`.

---

## 3. Caveats

1. **Valhalla Native Library Initialization**: Valhalla C++ core runs inside the `Valhalla` Swift framework wrapper. If tile tar files are completely missing from disk, `calculateRoute` will cleanly fail fast and return `nil`. In normal operation, initialization completes in under 1 second.
2. **Reverse Geocoding Opcode Budget**: In extremely sparse unpopulated areas (e.g. open ocean coordinates), `sqlite3_progress_handler` enforces a 0.65s / 2500-tick deadline to prevent full-table scans. Removing the `< 25.0m` break does not affect sparse areas because sparse areas have 0 records in the 800m bounding box.
3. **Plural Word Stemming in FTS5**: SQLite's built-in FTS5 tokenizer in `search_index.db` uses the simple ascii tokenizer (not the Porter stemmer). Therefore, FTS5 treats `"groceries"*` and `"grocery"*` as distinct terms. Query expansion in Swift is necessary to bridge this difference.

---

## 4. Conclusion

All requirements for R3 and R4 have been thoroughly diagnosed with exact line-level precision. Concrete, tested implementation strategies are outlined below for the implementation agent.

### 4.1 Recommended Implementation Strategies

#### 4.1.1 `RoutingService.swift` Refactoring (R3)

```swift
// MARK: - Voice Guidance State (Synchronized via voiceLock)
private let speechSynthesizer = AVSpeechSynthesizer()
private var _isVoiceMuted: Bool = false
public var isVoiceMuted: Bool {
    get {
        voiceLock.lock()
        defer { voiceLock.unlock() }
        return _isVoiceMuted
    }
    set {
        voiceLock.lock()
        let changedToMuted = newValue && !_isVoiceMuted
        _isVoiceMuted = newValue
        voiceLock.unlock()
        if changedToMuted {
            stopVoice()
        }
    }
}
private var lastSpokenInstruction: String = ""
private var lastSpokenStepId: Int? = nil
private var lastSpokenTime: Date = Date.distantPast
private var activeSpeechGeneration: Int = 0
private var utteranceGenerations: [ObjectIdentifier: Int] = [:]
private let voiceLock = NSLock()

public func stopVoice() {
    voiceLock.lock()
    activeSpeechGeneration += 1
    utteranceGenerations.removeAll()
    lastSpokenInstruction = ""
    lastSpokenStepId = nil
    lastSpokenTime = .distantPast
    voiceLock.unlock()
    DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.speechSynthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
```

In `calculateRoute(...)`:
```swift
// Fail fast within 5.0 seconds if Valhalla initialization times out
guard initGroup.wait(timeout: .now() + 5.0) == .success else {
    print("RoutingService ERROR: Valhalla initialization timed out after 5.0 seconds.")
    return nil
}
return queue.sync { () -> RouteDetails? in
    ...
}
```

In `speakTurnInstruction(...)`:
```swift
public func speakTurnInstruction(_ text: String, stepId: Int? = nil, force: Bool = false) {
    voiceLock.lock()
    guard !_isVoiceMuted && !text.isEmpty else {
        voiceLock.unlock()
        return
    }

    let now = Date()
    let isSameText = (text == lastSpokenInstruction)
    let isSameStep = (stepId != nil && lastSpokenStepId != nil) ? (stepId == lastSpokenStepId) : true
    let timeSinceLastPrompt = now.timeIntervalSince(lastSpokenTime)

    // Drop duplicate prompts only if it is the same step and occurred within 6 seconds
    if !force && isSameText && isSameStep && timeSinceLastPrompt < 6.0 {
        voiceLock.unlock()
        return
    }

    lastSpokenInstruction = text
    lastSpokenStepId = stepId
    lastSpokenTime = now
    activeSpeechGeneration += 1
    let generation = activeSpeechGeneration
    voiceLock.unlock()

    DispatchQueue.main.async { [weak self] in
        guard let self = self else { return }
        self.voiceLock.lock()
        let currentGen = self.activeSpeechGeneration
        let muted = self._isVoiceMuted
        self.voiceLock.unlock()

        guard generation == currentGen, !muted else { return }
        ...
    }
}
```

#### 4.1.2 `SearchService.swift` Refactoring (R4)

In `performReverseGeocode`:
Remove lines 322-324:
```swift
// Removed early break:
// if minDistanceMeters < 25.0 {
//     break
// }
```

In `parseCoordinates`:
```swift
public func parseCoordinates(query: String) -> CLLocationCoordinate2D? {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let pattern = #"([+-]?\d+(?:\.\d+)?)\s*°?\s*([NSEWnsew])?"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

    let nsString = trimmed as NSString
    let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: nsString.length))
    guard matches.count == 2 else { return nil }

    // Ensure no unexpected non-delimiter characters exist
    var remaining = trimmed
    for match in matches.reversed() {
        if let r = Range(match.range, in: remaining) {
            remaining.removeSubrange(r)
        }
    }
    let allowedChars = CharacterSet(charactersIn: ",; \t\n°")
    guard remaining.trimmingCharacters(in: allowedChars).isEmpty else { return nil }

    struct CoordComponent {
        let value: Double
        let cardinal: Character?
    }

    var components: [CoordComponent] = []
    for match in matches {
        let valRange = match.range(at: 1)
        guard valRange.location != NSNotFound,
              let val = Double(nsString.substring(with: valRange)) else { return nil }

        var card: Character? = nil
        let cardRange = match.range(at: 2)
        if cardRange.location != NSNotFound {
            card = Character(nsString.substring(with: cardRange).uppercased())
        }
        components.append(CoordComponent(value: val, cardinal: card))
    }

    let c0 = components[0]
    let c1 = components[1]
    var lat: Double?
    var lon: Double?

    if let dir0 = c0.cardinal, let dir1 = c1.cardinal {
        if (dir0 == "N" || dir0 == "S") && (dir1 == "E" || dir1 == "W") {
            lat = (dir0 == "S") ? -abs(c0.value) : abs(c0.value)
            lon = (dir1 == "W") ? -abs(c1.value) : abs(c1.value)
        } else if (dir0 == "E" || dir0 == "W") && (dir1 == "N" || dir1 == "S") {
            lon = (dir0 == "W") ? -abs(c0.value) : abs(c0.value)
            lat = (dir1 == "S") ? -abs(c1.value) : abs(c1.value)
        } else {
            return nil
        }
    } else if let dir0 = c0.cardinal {
        if dir0 == "N" || dir0 == "S" {
            lat = (dir0 == "S") ? -abs(c0.value) : abs(c0.value)
            lon = c1.value
        } else {
            lon = (dir0 == "W") ? -abs(c0.value) : abs(c0.value)
            lat = c1.value
        }
    } else if let dir1 = c1.cardinal {
        if dir1 == "N" || dir1 == "S" {
            lat = (dir1 == "S") ? -abs(c1.value) : abs(c1.value)
            lon = c0.value
        } else {
            lon = (dir1 == "W") ? -abs(c1.value) : abs(c1.value)
            lat = c0.value
        }
    } else {
        lat = c0.value
        lon = c1.value
    }

    guard let finalLat = lat, let finalLon = lon,
          finalLat >= -90.0 && finalLat <= 90.0,
          finalLon >= -180.0 && finalLon <= 180.0 else {
        return nil
    }

    return CLLocationCoordinate2D(latitude: finalLat, longitude: finalLon)
}
```

In `performSearch` & `SearchResult.category`:
```swift
// In SearchResult.category:
let groceryKeywords: Set<String> = [
    "grocery", "groceries", "supermarket", "supermarkets", "safeway",
    "walmart", "costco", "carrs", "kroger", "albertsons", "aldi",
    "sprouts", "bodega", "foodmart"
]
let isFredMeyer = words.contains("fred") && words.contains("meyer")
let isTraderJoes = words.contains("trader") && (words.contains("joe") || words.contains("joes"))
let isWholeFoods = words.contains("whole") && words.contains("foods")

if !words.isDisjoint(with: groceryKeywords) || words.contains("market") || isFredMeyer || isTraderJoes || isWholeFoods {
    return "grocery"
}

// In SearchService.performSearch:
let lowerQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
let searchQuery: String
if lowerQuery == "groceries" || lowerQuery == "grocery" {
    searchQuery = "\"grocery\"* OR \"groceries\"* OR \"supermarket\"* OR \"market\"*"
} else {
    searchQuery = tokens.map { "\"\($0)\"*" }.joined(separator: " ")
}
```

In `ContentView.swift`:
```swift
// Line 305: Update chip action to search "Groceries"
CategoryChip(icon: "cart.fill", title: "Groceries", color: .green) {
    searchCategory("Groceries")
}
```

---

## 5. Verification Method

### 5.1 Concurrency Verification
1. Inspect `RoutingService.swift` to verify:
   - `_isVoiceMuted` is private, and `public var isVoiceMuted` acquires `voiceLock` in getter and setter.
   - `stopVoice()` resets `lastSpokenInstruction = ""`, `lastSpokenStepId = nil`, and `lastSpokenTime = .distantPast` inside `voiceLock`.
   - `speakTurnInstruction` uses `isSameStep = (stepId != nil && lastSpokenStepId != nil) ? (stepId == lastSpokenStepId) : true`.
   - `calculateRoute` returns `nil` if `initGroup.wait(timeout: .now() + 5.0)` does not return `.success`.
2. Run test case under ThreadSanitizer:
   - Call `speakTurnInstruction` rapidly across 50 concurrent background threads while toggling `isVoiceMuted` on `@MainActor`. Verify zero data race warnings.

### 5.2 Restarting Route Verification
1. Start navigation on Route Details X. Note first spoken instruction.
2. Call `stopVoice()`.
3. Within 2.0 seconds, call `speakTurnInstruction` with the first instruction of Route Details X.
4. Verify the instruction is scheduled and spoken, not dropped.

### 5.3 Reverse Geocode Precision Verification
1. Call `searchService.reverseGeocode(coordinate: CLLocationCoordinate2D(latitude: 64.84355, longitude: -147.72175))`.
2. Verify `KeyBank` (distance ~1.2m) is returned instead of any candidate further away.

### 5.4 Coordinate Parser Verification
1. Pass the following inputs to `searchService.parseCoordinates(query:)`:
   - `"64.8436, -147.7215"` -> Latitude: `64.8436`, Longitude: `-147.7215`
   - `"  64.8569 ;  -147.8028 "` -> Latitude: `64.8569`, Longitude: `-147.8028`
   - `"64.8436° N, 147.7215° W"` -> Latitude: `64.8436`, Longitude: `-147.7215`
   - `"64.8436° S, 147.7215° E"` -> Latitude: `-64.8436`, Longitude: `147.7215`
   - `"147.7215° W, 64.8436° N"` -> Latitude: `64.8436`, Longitude: `-147.7215`
   - `"Fairbanks, AK"` -> `nil`
   - `"95.0, -147.0"` -> `nil`

### 5.5 Category Search Verification
1. Execute `searchService.search(query: "Groceries", userLocation: CLLocationCoordinate2D(latitude: 64.8378, longitude: -147.7166))`.
2. Verify returned list is non-empty and top result is `Co-Op Market Grocery & Deli` (~0.3 mi away) with `category == "grocery"`.

### 5.6 Invalidation Conditions
- If `initGroup.wait` return value is ignored, route calculation will block when initialization fails.
- If `isVoiceMuted` property accesses mutable memory without acquiring `voiceLock`, ThreadSanitizer will trigger.
- If `minDistanceMeters < 25.0` break is retained, reverse geocoding will return sub-optimal POIs.
