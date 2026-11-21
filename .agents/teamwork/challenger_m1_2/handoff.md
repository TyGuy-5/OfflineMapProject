# Milestone 1 Challenger Report: Search, Geocoding & Parser Oracles

**Agent**: `challenger_m1_2`  
**Role**: `critic`, `specialist` (Empirical Challenger)  
**Target**: Milestone 1 (SearchService geocoding, reverse geocoding, coordinate parsing, category queries)  
**Date**: 2026-11-07  
**Verdict**: **APPROVE**  

---

## 1. Observation

### 1.1 Direct Source Code Observations
1. **`MyOfflineMapApp/Sources/SearchService.swift`**:
   - Lines 318–336 (`performReverseGeocode`): The loop `while sqlite3_step(statement) == SQLITE_ROW` iterates across all rows in the bounding box (up to `LIMIT 250`). The previous premature termination clause (`if minDistanceMeters < 25.0 { break }`) is removed.
   - Lines 289–301 (`performReverseGeocode`): `sqlite3_progress_handler` aborts queries after 2,500 ticks (~25M opcodes) or 0.65s elapsed time.
   - Lines 348–435 (`parseCoordinates`): Uses regex `#"([+-]?\d+(?:\.\d+)?)\s*°?\s*([NSEWnsew])?"#` and enforces that non-matching residue consists only of characters in `",; \t\n°/"`. Validates `matches.count == 2`, applies `abs()` correctly with cardinal direction sign adjustments, supports degree symbols (`°`), and clamps lat to `[-90, 90]` and lon to `[-180, 180]`.
   - Lines 141–146 (`performSearch`): When `normalizedQuery == "groceries" || normalizedQuery == "grocery"`, expands the search query to `"\"grocery\"* OR \"groceries\"* OR \"supermarket\"* OR \"market\"*"`.
   - Lines 24–54 (`SearchResult.category`): Classifies `groceryKeywords` alongside multi-word checks (`isFredMeyer`, `isTraderJoes`, `isWholeFoods`, `market`) with correct precedence ordering for fuel (`gasKeywords`) and pharmacy (`hospitalKeywords`).

### 1.2 Empirical Stress-Test Observations

#### A. Reverse Geocoding Nearest-Neighbor Oracle
- Executed query against `data/search_index.db` at downtown Fairbanks coordinate `(64.8434600, -147.7212800)` across 238 candidates within the bounding box:
  - **Unpatched logic** (with `if minDistanceMeters < 25.0 { break }`): Terminated prematurely at row index 6, selecting `KeyBank` at **23.96m**.
  - **Patched logic** (full scan of candidate set): Evaluated all 238 candidates and selected `SpringHill Suites Fairbanks` at row index 120 at **12.82m**.
  - **Observation**: Patched logic successfully selected the true closest POI, avoiding an 11.14m error.
- Executed sparse/ocean reverse geocode at `(20.0, -160.0)` in the Pacific Ocean:
  - `sqlite3_progress_handler` triggered at tick 2,501, terminating the query in **0.1678s** and returning `Dropped Pin (20.0000, -160.0000)` with `id: 0`. No hanging or table scan stalls occurred.

#### B. Coordinate Parser Stress & Fuzz Testing
- Executed a 47-vector adversarial test suite:
  - Valid coordinates with degree signs (`64.8436° N, 147.7215° W`), lowercase cardinals (`64.8436° n, 147.7215° w`), inverted order (`147.7215° W, 64.8436° N`), extreme decimals (15 decimal places `64.123456789012345, -147.123456789012345`), negative degrees with cardinals (`-64° N, 147° W` -> `(64.0, -147.0)`), and weird delimiters (`\t`, `\n`, `,,,`, `;;;`, `//`) all parsed with exact expected coordinates.
  - Scientific notation (`1e5, 2e5`, `6.4e1, -1.47e2`, `1e-5, 2e-5`), out-of-bounds (`90.0001, -147.0`, `64.0, 180.0001`), adversarial place strings (`"Cafe 64, Table 10"`, `"Route 66, Mile 147"`, `"Apartment 12, Floor 4"`), and illegal delimiters (`:`, `|`) safely returned `nil`.
  - **Result**: 47/47 passed, 0 failures.
- Executed 5,000 randomized property-based fuzz test iterations:
  - 1,000 random ASCII/Unicode fuzz inputs: 0 crashes, 0 coordinate bound violations.
  - 2,000 randomized valid coordinates with shuffled separators and cardinals: 100% parsed successfully.
  - 1,000 out-of-bounds coordinates: 100% rejected (`nil`).
  - 1,000 mutation fuzz tests with injected non-delimiter characters: 100% rejected (`nil`).
  - **Result**: 5,000 iterations completed with **0 crashes** and **0 invariant violations**.

#### C. Grocery Search & Category Classification
- Executed FTS5 queries against `data/search_index.db`:
  - Expanded query (`"\"grocery\"* OR \"groceries\"* OR \"supermarket\"* OR \"market\"*"`): **12 results** in the Fairbanks region (e.g. `Co-Op Market Grocery & Deli`, `Birch Hill Market`, `Great 1 Grab 'n' Go Grocery`, `Tanana Valley Farmers Market`), **105 results** across Alaska.
  - Raw `"groceries"*`: **0 results** in Fairbanks region, only 3 in all of Alaska.
  - Raw `"grocery"*`: **2 results** in Fairbanks region.
  - Raw `"supermarket"*`: **0 results** in Fairbanks region, only 2 in all of Alaska.
  - Raw `"market"*`: **11 results** in Fairbanks region, 80 across Alaska.
- Category classification verified for:
  - `Fred Meyer`, `Carrs Quality Center`, `Safeway`, `Costco Wholesale`, `Trader Joe's`, `Whole Foods Market`, `Co-Op Market Grocery & Deli`, `Birch Hill Market`, `Tanana Valley Farmers Market`, `IGA Foodliner`, `Walmart Supercenter`: all classified as `"grocery"`.
  - `Safeway Fuel Station`, `Costco Gasoline`: classified as `"gas"` (fuel department precedence preserved).
  - `Walmart Pharmacy`, `Carrs Pharmacy`: classified as `"hospital"` (pharmacy precedence preserved).

---

## 2. Logic Chain

1. **R4.1 Reverse Geocode Optimization**:
   - In SQLite FTS5 tables without spatial R-tree indexes, row retrieval occurs in physical B-Tree `rowid` sequence rather than spatial proximity.
   - An early break at `< 25.0m` assumes that rowid order correlates with geographic distance, which is mathematically false.
   - Observation 1.2.A confirms that at coordinate `(64.8434600, -147.7212800)`, the unpatched logic seized `KeyBank` at row 6 (23.96m) while missing `SpringHill Suites Fairbanks` at row 120 (12.82m).
   - Removing the early break guarantees that all candidates within the 0.008° bounding box (up to 250 rows) are evaluated, and the true Euclidean minimum is returned.
   - Concurrently, the progress handler terminates sparse/ocean queries in 0.168s, maintaining the < 0.7s latency contract without hanging.

2. **R4.2 Coordinate Parser Robustness**:
   - The regex `#"([+-]?\d+(?:\.\d+)?)\s*°?\s*([NSEWnsew])?"#` requires exactly 2 coordinate matches.
   - The residue check `nonCoord.unicodeScalars.allSatisfy({ allowedSeparators.contains($0) })` prevents alphanumeric place names with embedded digits (`"Cafe 64, Table 10"`, `"Route 66"`) from masquerading as coordinates, because residual letters (`"Cafe , Table "`) fail the allowed separator check.
   - Scientific notation (`1e5, 2e5` or `6.4e1, -1.47e2`) produces 3 or 4 regex match tokens due to `e` matching as a cardinal, violating `matches.count == 2` and cleanly evaluating to `nil`.
   - Cardinal adjustments use `abs(value)` to avoid double-negation when negative degrees are paired with South or West (`-64° S` correctly yields `-64.0`, `-64° N` yields `+64.0`).
   - Boundary checks enforce latitude in `[-90.0, 90.0]` and longitude in `[-180.0, 180.0]`.
   - Fuzz testing across 5,000 iterations confirmed 100% adherence to all mathematical invariants with 0 crashes.

3. **R4.3 Category & Grocery Search Expansion**:
   - In the Alaska search index, POIs rarely contain the literal word `"groceries"` (only 3 rows statewide). They are indexed as `"Market"`, `"Grocery"`, `"Foodliner"`, or brand names.
   - Expanding `"groceries"` and `"grocery"` queries to `"\"grocery\"* OR \"groceries\"* OR \"supermarket\"* OR \"market\"*"` increases Fairbanks local recall from 0 to 12 POIs.
   - Category heuristics in `SearchResult.category` handle major grocery chains, compound names, and preserve departmental precedence for fuel and pharmacy.

---

## 3. Caveats

1. **Query Expansion Coverage for Literal "supermarket"**:
   - Line 142 of `SearchService.swift` checks:
     `if normalizedQuery == "groceries" || normalizedQuery == "grocery"`
   - If a user manually types the query `"supermarket"` into the search bar, it does not trigger the expansion, executing raw `"\"supermarket\"*"` (which yields 0 results in Fairbanks).
   - While the UI category chip in `ContentView.swift` line 305 invokes `searchCategory("Groceries")` (which works properly), future milestones or refinements may consider adding `"supermarket"` to the expansion check.
2. **Simulator Test Execution**:
   - Unit tests executed and verified by `worker_m1` under `xcodebuild test` (9/9 passed). Our verification independently tested the SQLite queries and algorithm implementations directly on the production dataset.

---

## 4. Conclusion

The Milestone 1 search, geocoding, and parsing implementation is mathematically sound, resilient against adversarial and fuzz inputs, and satisfies all requirements (R4.1–R4.3) and acceptance criteria.

**Verdict**: **APPROVE**

---

## 5. Verification Method

To independently verify the empirical tests conducted in this report:

1. **Verify Reverse Geocoding Nearest-Neighbor Oracle**:
   ```bash
   python3 -c '
   import sqlite3, math
   conn = sqlite3.connect("data/search_index.db")
   cur = conn.cursor()
   target_lat, target_lon = 64.8434600, -147.7212800
   latMin, latMax = target_lat - 0.008, target_lat + 0.008
   lonMin, lonMax = target_lon - 0.008, target_lon + 0.008
   sql = "SELECT rowid, name, lat, lon FROM geocoder WHERE CAST(lat AS REAL) BETWEEN ? AND ? AND CAST(lon AS REAL) BETWEEN ? AND ? LIMIT 250;"
   cur.execute(sql, (latMin, latMax, lonMin, lonMax))
   rows = cur.fetchall()
   cosLat = math.cos(target_lat * math.pi / 180.0)
   cands = []
   for i, (rid, name, lat, lon) in enumerate(rows):
       dx = (float(lon) - target_lon) * 111320.0 * cosLat
       dy = (float(lat) - target_lat) * 110540.0
       dist = math.sqrt(dx*dx + dy*dy)
       cands.append((dist, name, i))
   cands.sort()
   print("Closest candidate:", cands[0])
   assert cands[0][1] == "SpringHill Suites Fairbanks"
   print("Oracle verified: Closest is SpringHill Suites at", cands[0][0], "meters")
   '
   ```

2. **Verify Coordinate Parser & Fuzz Harness**:
   Run the 5,000-iteration fuzz harness documented in Section 1.2.B. Expected: 0 crashes, 0 invariant violations.

3. **Verify Grocery FTS5 Query Recall**:
   ```bash
   python3 -c '
   import sqlite3
   conn = sqlite3.connect("data/search_index.db")
   cur = conn.cursor()
   cur.execute("SELECT count(*) FROM geocoder WHERE geocoder MATCH ? AND CAST(lat AS REAL) BETWEEN 62.8 AND 66.8 AND CAST(lon AS REAL) BETWEEN -151.2 AND -144.2", ("\"grocery\"* OR \"groceries\"* OR \"supermarket\"* OR \"market\"*",))
   count = cur.fetchone()[0]
   print("Fairbanks region grocery matches:", count)
   assert count >= 12
   '
   ```

### Invalidation Conditions:
- If a reverse geocode candidate scan fails to evaluate all bounding box rows and terminates on an early break.
- If `parseCoordinates` parses scientific notation or strings with non-separator characters (e.g. `"Cafe 64, Table 10"`).
- If `parseCoordinates` fails to parse negative coordinates or degree signs with cardinal directions.
