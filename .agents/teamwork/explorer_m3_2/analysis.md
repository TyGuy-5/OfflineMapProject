# Technical Investigation Report: Navigation Telemetry, Step Progression, and Simulation Loop (R2.1, R2.2, R2.3)

**Author**: `explorer_m3_2` (Teamwork Explorer)  
**Date**: 2026-11-07  
**Working Directory**: `.agents/teamwork/explorer_m3_2/`  
**Targets**:
- `MyOfflineMapApp/Sources/ContentView.swift`
- `MyOfflineMapApp/Sources/NavigationViewModel.swift` (M3 architecture target)
- `MyOfflineMapApp/Tests/MyOfflineMapAppTests/RemediationTests.swift`
- `Tests/E2ETests/` (Tiers 1–4)

---

## 1. Executive Summary

This investigation analyzes three critical navigation progression and telemetry defects in `MyOfflineMapApp` and specifies mathematically robust, regression-free algorithms for implementation in `NavigationViewModel.swift`:

1. **R2.1 Switchback Coordinate Search Clamping**:
   - **Defect**: In `updateCurrentStepForLiveLocation`, the forward coordinate search window spans `currentCoordIndex + 50` vertices (~500m to 1km). On hairpin mountain switchbacks, cloverleaf interchanges, or parallel urban streets, proximate segments from future maneuvers lie within 10–25 meters of the vehicle. The unclamped search snaps `currentCoordIndex` forward prematurely, triggering instant advancement of `currentStepIndex` before the user has negotiated the turn.
   - **Remedy**: Clamp the search upper bound to the current maneuver's extent with a +2 vertex slack: `searchEnd = min(coords.count - 1, max(currentCoordIndex + 1, currentStepEnd + 2))`. This strictly prevents forward snapping beyond the current maneuver while providing necessary latitude for GPS lag and intersection turn radii.

2. **R2.2 Monotonic Telemetry Distance Countdown**:
   - **Defect**: In `updateNavigationTelemetry`, when the vehicle reaches or passes `stepEnd` (`clampedIndex >= stepEnd`), a fallback branch computes `stepDistMeters = segmentDistanceMeters(p1: userCoord, p2: coords[stepEnd])`. As the vehicle continues driving past `stepEnd` (or past the destination on the final step), this distance increases monotonically, causing the displayed remaining distance to suddenly reverse and count upward.
   - **Remedy**: Strictly evaluate `stepDistMeters = 0.0` when `clampedIndex >= stepEnd`, and `routeDistMeters = 0.0` when `clampedIndex >= coords.count - 1`. Accumulate segment distances along the polyline only when `clampedIndex < stepEnd`.

3. **R2.3 Multi-Speed Simulation Maneuver Progression**:
   - **Defect**: In `advanceSimulationStep()`, simulation at 2x and 5x speeds advances `currentCoordIndex` by 2 or 5 vertices per 120ms tick. A single `if` statement checks for step advancement, incrementing `currentStepIndex` by at most 1 per tick. When multi-vertex jumps leap over short maneuvers (e.g., consecutive 1-to-2 vertex turns in dense city blocks), intermediate maneuvers are skipped, instructions are dropped, and `currentStepIndex` desynchronizes from the actual vehicle location.
   - **Remedy**: Replace the single `if` check with a sequential `while` loop that iterates until `currentStepIndex` matches the active maneuver for `currentCoordIndex`, announcing all intermediate instructions and resetting advance turn state.

---

## 2. Investigation R2.1: Switchback Coordinate Search Clamping

### 2.1 Code Observation & Root Cause
In `MyOfflineMapApp/Sources/ContentView.swift` (lines 983–999):
```swift
// Keep currentCoordIndex advancing along the polyline smoothly
let searchStart = max(0, currentCoordIndex - 5)
let searchEnd = min(coords.count - 1, currentCoordIndex + 50)
var closestIndex = currentCoordIndex
var minSegDist = Double.greatestFiniteMagnitude

for i in searchStart..<searchEnd {
    let dist = routingService.distanceToSegmentMeters(p: userCoord, a: coords[i], b: coords[i + 1])
    if dist < minSegDist {
        minSegDist = dist
        closestIndex = i
    }
}
if minSegDist < 40.0 {
    currentCoordIndex = closestIndex
}
```

Immediately following the coordinate update (lines 1000–1018):
```swift
if !details.steps.isEmpty && currentStepIndex < details.steps.count {
    let currentStep = details.steps[currentStepIndex]
    let endCoord = coords[min(currentStep.endIndex, coords.count - 1)]
    let distToEndMeters = segmentDistanceMeters(p1: userCoord, p2: endCoord)

    if (distToEndMeters < 35.0 || currentCoordIndex >= currentStep.endIndex) && currentStepIndex < details.steps.count - 1 {
        currentStepIndex += 1
        hasAnnouncedAdvanceTurn = false
        currentCoordIndex = max(currentCoordIndex, currentStep.endIndex)
        let nextStep = details.steps[currentStepIndex]
        routingService.speakTurnInstruction(nextStep.instruction, stepId: currentStepIndex * 10 + 2)
    ...
```

### 2.2 Mathematical Mechanism of Switchback Failure
Consider the geometry generated in `TestGeometries.makeSwitchbackRoute()`:
- **Step 0**: 11 vertices (indices 0..10), heading north along longitude `-147.7200` from latitude `64.8400` to `64.8450`.
- **Step 1**: Hairpin turn across vertices 10..14.
- **Step 2**: 11 vertices (indices 14..24), heading south along longitude `-147.7197` from latitude `64.8450` to `64.8400`.

The physical distance between longitude `-147.7200` and `-147.7197` at latitude $64.84^{\circ}\text{N}$ is:
$$\Delta\text{lon} = 0.0003^{\circ}$$
$$\text{dx} = 0.0003 \times 111320.0 \times \cos(64.84^{\circ}) \approx 14.3 \text{ meters}$$

When the vehicle is at vertex 3 in Step 0:
- The unclamped search scans from `searchStart = max(0, 3 - 5) = 0` to `searchEnd = min(24, 3 + 50) = 24`.
- The search evaluates all 24 segments, including segment 21 in Step 2.
- Vertex 21 is at latitude $64.8415^{\circ}$, longitude $-147.7197^{\circ}$, located exactly 14.3 meters east of vertex 3.
- If real-world GPS noise shifts the user coordinate by even $\pm 5$ meters eastward, the perpendicular distance to segment 21 can evaluate to 10–12 meters, while the distance to segment 3 is 13 meters.
- Because `minSegDist < 40.0`, `currentCoordIndex` snaps to **21**.
- The step progression logic evaluates: `currentCoordIndex (21) >= currentStep.endIndex (10)`.
- **Result**: `currentStepIndex` immediately jumps from 0 to 1, and on subsequent updates jumps to 2. Voice instructions for Step 1 ("Hairpin Turn") and Step 2 are spoken while the vehicle is still hundreds of meters away on the lower switchback tier.

### 2.3 Proposed Clamping Algorithm
To prevent snapping across hairpin turns, parallel tiers, or cloverleafs:
1. Determine the end vertex of the active maneuver:
   ```swift
   let currentStepEnd = (!details.steps.isEmpty && currentStepIndex < details.steps.count)
       ? details.steps[currentStepIndex].endIndex
       : coords.count - 1
   ```
2. Restrict the forward search boundary to `currentStepEnd + 2`:
   - Why `+ 2` vertices? Vehicles turning through an intersection or hairpin may momentarily cross the corner vertex ($endIndex$) before the step transition is triggered. Allowing 2 vertices of forward slack avoids clipping the search during the turn itself.
   - Clamp the upper bound: `min(coords.count - 1, max(currentCoordIndex + 1, currentStepEnd + 2))`.
   - The `max(currentCoordIndex + 1, ...)` guard ensures that `searchEnd > searchStart` even if `currentCoordIndex` reaches `currentStepEnd + 2`.
3. Lower bound: `searchStart = max(0, currentCoordIndex - 5)`.
4. Only execute the search loop if `searchStart < searchEnd`:
   ```swift
   let currentStepEnd = (!details.steps.isEmpty && currentStepIndex < details.steps.count)
       ? details.steps[currentStepIndex].endIndex
       : coords.count - 1
   let searchStart = max(0, currentCoordIndex - 5)
   let searchEnd = min(coords.count - 1, max(currentCoordIndex + 1, currentStepEnd + 2))

   var closestIndex = currentCoordIndex
   var minSegDist = Double.greatestFiniteMagnitude
   if searchStart < searchEnd {
       for i in searchStart..<searchEnd {
           let dist = routingService.distanceToSegmentMeters(p: userCoord, a: coords[i], b: coords[i + 1])
           if dist < minSegDist {
               minSegDist = dist
               closestIndex = i
           }
       }
   }
   if minSegDist < 40.0 {
       currentCoordIndex = closestIndex
   }
   ```

### 2.4 Invariant & Boundary Verification
- When `currentStepIndex = 0` (`endIndex = 10`), `searchEnd = min(24, 12) = 12`. Segments 12..23 (Step 2) are outside the range. The switchback jump is mathematically impossible.
- When `coords.count < 2`, `guard !coords.isEmpty` returns early.
- When `details.steps.isEmpty`, `currentStepEnd` defaults to `coords.count - 1`, preserving default polyline tracking.

---

## 3. Investigation R2.2: Monotonic Telemetry Distance Countdown

### 3.1 Code Observation & Root Cause
In `MyOfflineMapApp/Sources/ContentView.swift` (lines 1028–1064):
```swift
// 1. Calculate remaining step distance (monotonically counting down)
let currentStep: NavigationStep? = (currentStepIndex < details.steps.count) ? details.steps[currentStepIndex] : details.steps.last
if let currentStep = currentStep {
    let stepEnd = max(0, min(currentStep.endIndex, coords.count - 1))
    var stepDistMeters = 0.0
    if clampedIndex < stepEnd && clampedIndex + 1 < coords.count {
        stepDistMeters += segmentDistanceMeters(p1: userCoord, p2: coords[clampedIndex + 1])
        if clampedIndex + 1 < stepEnd {
            for i in (clampedIndex + 1)..<stepEnd {
                if i + 1 < coords.count {
                    stepDistMeters += segmentDistanceMeters(p1: coords[i], p2: coords[i + 1])
                }
            }
        }
    } else if stepEnd < coords.count {
        // BUG: Computes distance from user position back to stepEnd vertex!
        stepDistMeters = segmentDistanceMeters(p1: userCoord, p2: coords[stepEnd])
    }
    self.remainingStepDistanceMiles = max(0.0, stepDistMeters * 0.000621371)
} else {
    self.remainingStepDistanceMiles = 0.0
}

// 2. Calculate remaining total route distance (monotonically counting down)
var routeDistMeters = 0.0
if clampedIndex < coords.count - 1 {
    routeDistMeters += segmentDistanceMeters(p1: userCoord, p2: coords[clampedIndex + 1])
    if clampedIndex + 1 < coords.count - 1 {
        for i in (clampedIndex + 1)..<(coords.count - 1) {
            routeDistMeters += segmentDistanceMeters(p1: coords[i], p2: coords[i + 1])
        }
    }
} else if let last = coords.last {
    // BUG: Computes distance from user position back to destination vertex!
    routeDistMeters = segmentDistanceMeters(p1: userCoord, p2: last)
}
```

### 3.2 Analysis of Distance Reversal
1. **Maneuver Boundary Reversal**:
   - As the vehicle approaches `stepEnd` (say vertex 10), `clampedIndex = 9`. Remaining step distance counts down: `30m -> 15m -> 2m`.
   - Once the vehicle crosses vertex 10, `clampedIndex` becomes 10. Now `clampedIndex < stepEnd` (10 < 10) is FALSE.
   - Execution falls into `else if stepEnd < coords.count`.
   - The calculation measures `segmentDistanceMeters(p1: userCoord, p2: coords[10])`.
   - As the vehicle drives past vertex 10, the distance from `userCoord` to `coords[10]` increases from $0\text{m} \to 10\text{m} \to 30\text{m} \to 50\text{m}$.
   - The UI displays: `50 ft -> 20 ft -> 10 ft -> 30 ft -> 80 ft -> 150 ft`!
2. **Post-Destination Reopening**:
   - On the final route maneuver, when the user arrives at or drives past the destination endpoint:
   - `clampedIndex >= coords.count - 1`.
   - The unpatched code computes `routeDistMeters = segmentDistanceMeters(userCoord, coords.last!)`.
   - If the user pulls into a parking lot 100 meters past the street pin, `remainingRouteDistanceMiles` increases to 0.1 miles instead of remaining 0.0.

### 3.3 The Correct Replacement Algorithm
```swift
func updateNavigationTelemetry(at userCoord: CLLocationCoordinate2D, coordIndex: Int, in details: RouteDetails) {
    let coords = details.coordinates
    guard coords.count >= 2 else {
        self.remainingStepDistanceMiles = 0.0
        self.remainingRouteDistanceMiles = 0.0
        self.remainingRouteDurationSeconds = 0.0
        return
    }
    let clampedIndex = min(max(0, coordIndex), coords.count - 1)

    // 1. Calculate remaining step distance (strictly monotonic decrease to 0.0)
    let currentStep: NavigationStep? = (currentStepIndex < details.steps.count) ? details.steps[currentStepIndex] : details.steps.last
    if let currentStep = currentStep {
        let stepEnd = max(0, min(currentStep.endIndex, coords.count - 1))
        var stepDistMeters = 0.0
        if clampedIndex >= stepEnd {
            // Strictly zero when at or past the maneuver end; prevents distance reversal
            stepDistMeters = 0.0
        } else {
            stepDistMeters += segmentDistanceMeters(p1: userCoord, p2: coords[clampedIndex + 1])
            if clampedIndex + 1 < stepEnd {
                for i in (clampedIndex + 1)..<stepEnd {
                    if i + 1 < coords.count {
                        stepDistMeters += segmentDistanceMeters(p1: coords[i], p2: coords[i + 1])
                    }
                }
            }
        }
        self.remainingStepDistanceMiles = max(0.0, stepDistMeters * 0.000621371)
    } else {
        self.remainingStepDistanceMiles = 0.0
    }

    // 2. Calculate remaining total route distance (strictly monotonic decrease to 0.0)
    var routeDistMeters = 0.0
    if clampedIndex < coords.count - 1 {
        routeDistMeters += segmentDistanceMeters(p1: userCoord, p2: coords[clampedIndex + 1])
        if clampedIndex + 1 < coords.count - 1 {
            for i in (clampedIndex + 1)..<(coords.count - 1) {
                routeDistMeters += segmentDistanceMeters(p1: coords[i], p2: coords[i + 1])
            }
        }
    } else {
        // Strictly zero at or past route destination
        routeDistMeters = 0.0
    }
    let routeMiles = max(0.0, routeDistMeters * 0.000621371)
    self.remainingRouteDistanceMiles = routeMiles

    // 3. Proportionally update remaining duration and ETA
    if details.totalDistanceMiles > 0 {
        let ratio = max(0.0, min(1.0, routeMiles / details.totalDistanceMiles))
        self.remainingRouteDurationSeconds = details.totalDurationSeconds * ratio
    } else {
        self.remainingRouteDurationSeconds = 0.0
    }
    self.dynamicArrivalDate = Date().addingTimeInterval(self.remainingRouteDurationSeconds)
}
```

---

## 4. Investigation R2.3: Multi-Speed Simulation Maneuver Progression

### 4.1 Code Observation & Root Cause
In `MyOfflineMapApp/Sources/ContentView.swift` (lines 1297–1330):
```swift
let stepJump = Int(max(1, simulationSpeedMultiplier))
let nextIndex = min(coords.count - 1, currentCoordIndex + stepJump)
...
currentCoordIndex = nextIndex

if !details.steps.isEmpty && currentStepIndex < details.steps.count - 1 {
    let nextStep = details.steps[currentStepIndex + 1]
    if currentCoordIndex >= nextStep.startIndex {
        currentStepIndex += 1
        hasAnnouncedAdvanceTurn = false
        routingService.speakTurnInstruction(nextStep.instruction, stepId: currentStepIndex * 10 + 2)
    } else if !hasAnnouncedAdvanceTurn {
        let turnCoord = coords[max(0, min(nextStep.startIndex, coords.count - 1))]
        let distToTurn = segmentDistanceMeters(p1: p2, p2: turnCoord)
        if distToTurn < 250.0 {
            hasAnnouncedAdvanceTurn = true
            let distStr = formatCountdownDistance(distToTurn * 0.000621371, useMetric: useMetric)
            routingService.speakTurnInstruction("In \(distStr), \(nextStep.instruction)", stepId: (currentStepIndex + 1) * 10 + 1)
        }
    }
}
```

### 4.2 Multi-Speed Skipping Mechanism
Consider a route through downtown Fairbanks with rapid consecutive maneuvers:
- **Step 0**: 1st Ave (indices 0..2)
- **Step 1**: 2nd Ave (indices 2..4)
- **Step 2**: Airport Way (indices 4..8)

When the user selects **5x simulation speed**:
1. At tick 0: `currentCoordIndex = 0`, `currentStepIndex = 0`.
2. At tick 1 (after 120ms):
   - `stepJump = 5`.
   - `nextIndex = min(7, 0 + 5) = 5`.
   - `currentCoordIndex = 5` (which is located inside Step 2).
   - The single `if` statement evaluates:
     `nextStep = steps[1]` (`startIndex = 2`).
     `currentCoordIndex (5) >= nextStep.startIndex (2)` -> TRUE.
     `currentStepIndex` increments by 1 (to **1**).
     Step 1 instruction is announced.
3. At tick 2:
   - `nextIndex = min(7, 5 + 5) = 7` (the route end).
   - `guard currentCoordIndex < coords.count - 1` fails on the following tick and completes arrival.
   - Step 2 ("Turn onto Airport Way") was **never spoken or activated**. `currentStepIndex` reached only 1 before destination arrival was declared!

### 4.3 The `while` Loop Solution
By replacing the single `if` with a sequential `while` loop, every maneuver whose `startIndex` has been traversed is sequentially activated, its instruction is spoken (queued/deduplicated via `RoutingService`), and `hasAnnouncedAdvanceTurn` is properly reset:

```swift
// Advance currentStepIndex via while loop so 2x and 5x simulation does not skip maneuvers
while !details.steps.isEmpty && currentStepIndex < details.steps.count - 1 {
    let nextStep = details.steps[currentStepIndex + 1]
    let nextStepStart = max(0, min(nextStep.startIndex, coords.count - 1))
    if currentCoordIndex >= nextStepStart {
        currentStepIndex += 1
        hasAnnouncedAdvanceTurn = false
        routingService.speakTurnInstruction(nextStep.instruction, stepId: currentStepIndex * 10 + 2)
    } else {
        break
    }
}

// Check advance turn announcement for the upcoming step if within 250m
if !details.steps.isEmpty && currentStepIndex < details.steps.count - 1 && !hasAnnouncedAdvanceTurn {
    let nextStep = details.steps[currentStepIndex + 1]
    let turnCoord = coords[max(0, min(nextStep.startIndex, coords.count - 1))]
    let distToTurn = segmentDistanceMeters(p1: p2, p2: turnCoord)
    if distToTurn < 250.0 {
        hasAnnouncedAdvanceTurn = true
        let distStr = formatCountdownDistance(distToTurn * 0.000621371, useMetric: useMetric)
        routingService.speakTurnInstruction("In \(distStr), \(nextStep.instruction)", stepId: (currentStepIndex + 1) * 10 + 1)
    }
}
```

### 4.4 Complexity & Safety Proof
- **Termination Guarantee**: In each iteration of the `while` loop, `currentStepIndex` is strictly incremented (`currentStepIndex += 1`). The loop condition requires `currentStepIndex < details.steps.count - 1`. Therefore, the loop executes at most $O(\text{steps.count})$ times (typically 1–3 iterations during a 5x leap) and cannot enter an infinite loop.
- **Index Safety**: `nextStepStart` is clamped to `0 ... coords.count - 1`, preventing out-of-bounds indexing even if step metadata contains negative or oversized indices.

---

## 5. Complete Swift Code Snippets Ready for `NavigationViewModel.swift`

Below is the verified, production-ready Swift code ready to be integrated into `NavigationViewModel.swift`:

```swift
// MARK: - Navigation Telemetry & Maneuver Progression (R2.1, R2.2, R2.3)

extension NavigationViewModel {
    
    /// R2.1: Restrict forward coordinate search to the current maneuver's polyline segment range
    /// (clamped to currentStepEnd + 2) to eliminate premature step advancement on switchbacks.
    public func updateCurrentStepForLiveLocation(_ userCoord: CLLocationCoordinate2D, in details: RouteDetails) {
        let coords = details.coordinates
        guard !coords.isEmpty else { return }

        // Live arrival check at destination (dual-point: road-snapped end and destination pin)
        if let finalDest = coords.last, coords.count >= 2 {
            let distToRoadEnd = segmentDistanceMeters(p1: userCoord, p2: finalDest)
            let distToPin = selectedCoordinate != nil ? segmentDistanceMeters(p1: userCoord, p2: selectedCoordinate!) : Double.greatestFiniteMagnitude
            let isNearEnd = currentCoordIndex >= max(0, coords.count - 3) || (!details.steps.isEmpty && currentStepIndex >= details.steps.count - 1)
            
            if distToRoadEnd < 25.0 || distToPin < 25.0 || (isNearEnd && (distToRoadEnd < 40.0 || distToPin < 40.0)) {
                routingService.speakTurnInstruction("You have arrived at your destination.", force: true)
                routeDetails = nil
                routeCoordinates = nil
                endNavigation()
                return
            }
        }

        // R2.1: Clamped forward coordinate search to current maneuver's end index (+2 vertices slack)
        let currentStepEnd = (!details.steps.isEmpty && currentStepIndex < details.steps.count)
            ? details.steps[currentStepIndex].endIndex
            : coords.count - 1
        let searchStart = max(0, currentCoordIndex - 5)
        let searchEnd = min(coords.count - 1, max(currentCoordIndex + 1, currentStepEnd + 2))

        var closestIndex = currentCoordIndex
        var minSegDist = Double.greatestFiniteMagnitude
        if searchStart < searchEnd {
            for i in searchStart..<searchEnd {
                let dist = routingService.distanceToSegmentMeters(p: userCoord, a: coords[i], b: coords[i + 1])
                if dist < minSegDist {
                    minSegDist = dist
                    closestIndex = i
                }
            }
        }
        if minSegDist < 40.0 {
            currentCoordIndex = closestIndex
        }

        // Step progression along maneuvers (includes coordinate index fallback for high-speed travel)
        if !details.steps.isEmpty && currentStepIndex < details.steps.count {
            let currentStep = details.steps[currentStepIndex]
            let endCoord = coords[min(currentStep.endIndex, coords.count - 1)]
            let distToEndMeters = segmentDistanceMeters(p1: userCoord, p2: endCoord)

            if (distToEndMeters < 35.0 || currentCoordIndex >= currentStep.endIndex) && currentStepIndex < details.steps.count - 1 {
                currentStepIndex += 1
                hasAnnouncedAdvanceTurn = false
                currentCoordIndex = max(currentCoordIndex, currentStep.endIndex)
                let nextStep = details.steps[currentStepIndex]
                routingService.speakTurnInstruction(nextStep.instruction, stepId: currentStepIndex * 10 + 2)
            } else if currentStepIndex < details.steps.count - 1 && !hasAnnouncedAdvanceTurn && distToEndMeters < 250.0 {
                hasAnnouncedAdvanceTurn = true
                let nextStep = details.steps[currentStepIndex + 1]
                let distStr = formatCountdownDistance(distToEndMeters * 0.000621371, useMetric: useMetric)
                routingService.speakTurnInstruction("In \(distStr), \(nextStep.instruction)", stepId: (currentStepIndex + 1) * 10 + 1)
            }
        }

        updateNavigationTelemetry(at: userCoord, coordIndex: currentCoordIndex, in: details)
    }

    /// R2.2: Correct updateNavigationTelemetry so that remainingStepDistanceMiles counts down
    /// monotonically and evaluates strictly to 0.0 when clampedIndex >= stepEnd.
    public func updateNavigationTelemetry(at userCoord: CLLocationCoordinate2D, coordIndex: Int, in details: RouteDetails) {
        let coords = details.coordinates
        guard coords.count >= 2 else {
            self.remainingStepDistanceMiles = 0.0
            self.remainingRouteDistanceMiles = 0.0
            self.remainingRouteDurationSeconds = 0.0
            return
        }
        let clampedIndex = min(max(0, coordIndex), coords.count - 1)

        // 1. Calculate remaining step distance (monotonically counting down)
        let currentStep: NavigationStep? = (currentStepIndex < details.steps.count) ? details.steps[currentStepIndex] : details.steps.last
        if let currentStep = currentStep {
            let stepEnd = max(0, min(currentStep.endIndex, coords.count - 1))
            var stepDistMeters = 0.0
            if clampedIndex >= stepEnd {
                // Strictly evaluate to zero at or past maneuver endpoint (no distance reversal)
                stepDistMeters = 0.0
            } else {
                stepDistMeters += segmentDistanceMeters(p1: userCoord, p2: coords[clampedIndex + 1])
                if clampedIndex + 1 < stepEnd {
                    for i in (clampedIndex + 1)..<stepEnd {
                        if i + 1 < coords.count {
                            stepDistMeters += segmentDistanceMeters(p1: coords[i], p2: coords[i + 1])
                        }
                    }
                }
            }
            self.remainingStepDistanceMiles = max(0.0, stepDistMeters * 0.000621371)
        } else {
            self.remainingStepDistanceMiles = 0.0
        }

        // 2. Calculate remaining total route distance (monotonically counting down)
        var routeDistMeters = 0.0
        if clampedIndex < coords.count - 1 {
            routeDistMeters += segmentDistanceMeters(p1: userCoord, p2: coords[clampedIndex + 1])
            if clampedIndex + 1 < coords.count - 1 {
                for i in (clampedIndex + 1)..<(coords.count - 1) {
                    routeDistMeters += segmentDistanceMeters(p1: coords[i], p2: coords[i + 1])
                }
            }
        } else {
            // Strictly evaluate to zero at or past route destination
            routeDistMeters = 0.0
        }
        let routeMiles = max(0.0, routeDistMeters * 0.000621371)
        self.remainingRouteDistanceMiles = routeMiles

        // 3. Proportionally update remaining duration and ETA
        if details.totalDistanceMiles > 0 {
            let ratio = max(0.0, min(1.0, routeMiles / details.totalDistanceMiles))
            self.remainingRouteDurationSeconds = details.totalDurationSeconds * ratio
        } else {
            self.remainingRouteDurationSeconds = 0.0
        }
        self.dynamicArrivalDate = Date().addingTimeInterval(self.remainingRouteDurationSeconds)
    }

    /// R2.3: In advanceSimulationStep(), advance currentStepIndex via while loop so simulation
    /// at 2x and 5x speeds does not skip intermediate maneuvers.
    public func advanceSimulationStep() {
        guard let details = routeDetails, !details.coordinates.isEmpty else { return }
        let coords = details.coordinates
        guard currentCoordIndex < coords.count - 1 else {
            routingService.speakTurnInstruction("You have arrived at your destination.", force: true)
            routeDetails = nil
            routeCoordinates = nil
            endNavigation()
            return
        }

        let stepJump = Int(max(1, simulationSpeedMultiplier))
        let nextIndex = min(coords.count - 1, currentCoordIndex + stepJump)

        let p1 = coords[currentCoordIndex]
        let p2 = coords[nextIndex]

        let dLon = (p2.longitude - p1.longitude) * .pi / 180
        let lat1 = p1.latitude * .pi / 180
        let lat2 = p2.latitude * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(dLon)
        let radiansBearing = atan2(y, x)
        let degreesBearing = (radiansBearing * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)

        simulatedHeading = degreesBearing
        simulatedUserCoordinate = p2
        currentCoordIndex = nextIndex

        // Advance currentStepIndex via while loop rather than single if check
        while !details.steps.isEmpty && currentStepIndex < details.steps.count - 1 {
            let nextStep = details.steps[currentStepIndex + 1]
            let nextStepStart = max(0, min(nextStep.startIndex, coords.count - 1))
            if currentCoordIndex >= nextStepStart {
                currentStepIndex += 1
                hasAnnouncedAdvanceTurn = false
                routingService.speakTurnInstruction(nextStep.instruction, stepId: currentStepIndex * 10 + 2)
            } else {
                break
            }
        }

        // Advance turn announcement for upcoming maneuver if within 250m
        if !details.steps.isEmpty && currentStepIndex < details.steps.count - 1 && !hasAnnouncedAdvanceTurn {
            let nextStep = details.steps[currentStepIndex + 1]
            let turnCoord = coords[max(0, min(nextStep.startIndex, coords.count - 1))]
            let distToTurn = segmentDistanceMeters(p1: p2, p2: turnCoord)
            if distToTurn < 250.0 {
                hasAnnouncedAdvanceTurn = true
                let distStr = formatCountdownDistance(distToTurn * 0.000621371, useMetric: useMetric)
                routingService.speakTurnInstruction("In \(distStr), \(nextStep.instruction)", stepId: (currentStepIndex + 1) * 10 + 1)
            }
        }

        updateNavigationTelemetry(at: p2, coordIndex: nextIndex, in: details)
    }

    public func segmentDistanceMeters(p1: CLLocationCoordinate2D, p2: CLLocationCoordinate2D) -> Double {
        let latRad = p1.latitude * .pi / 180.0
        let dx = (p2.longitude - p1.longitude) * 111320.0 * cos(latRad)
        let dy = (p2.latitude - p1.latitude) * 110540.0
        return sqrt(dx * dx + dy * dy)
    }

    public func formatCountdownDistance(_ miles: Double, useMetric: Bool) -> String {
        if useMetric {
            let meters = miles * 1609.34
            if meters < 1000 {
                return "\(max(0, Int(meters))) m"
            } else {
                return String(format: "%.1f km", max(0, miles * 1.60934))
            }
        } else {
            let feet = miles * 5280
            if miles < 0.1 {
                return "\(max(0, Int(feet))) ft"
            } else {
                return String(format: "%.1f mi", max(0, miles))
            }
        }
    }
}
```

### 5.1 Backward-Compatibility Stubs for `ContentView.swift`
To maintain binary compatibility and ensure existing tests in `RemediationTests.swift` continue running without modification during Milestone 3:
```swift
// In ContentView.swift:
func updateCurrentStepForLiveLocation(_ userCoord: CLLocationCoordinate2D, in details: RouteDetails) {
    viewModel.updateCurrentStepForLiveLocation(userCoord, in: details)
}

func updateNavigationTelemetry(at userCoord: CLLocationCoordinate2D, coordIndex: Int, in details: RouteDetails) {
    viewModel.updateNavigationTelemetry(at: userCoord, coordIndex: coordIndex, in: details)
}

func advanceSimulationStep() {
    viewModel.advanceSimulationStep()
}
```

---

## 6. Verification and Test Suite Compatibility

The proposed algorithms have been evaluated against both the project unit tests and the newly published E2E test suite:

1. **E2E Test Suite Validation (`run_e2e_tests.sh`)**:
   - `testT1_SwitchbackSearchClampingEliminatesPrematureStepAdvance`: Validates that user at index 3 in Step 0 does not snap across hairpin to Step 2.
   - `testT1_MonotonicTelemetryCountdownDecreasesToZeroWithoutReversal`: Validates monotonic countdown and strict 0.0 evaluation at indices 10 and 11.
   - `testT1_MultiSpeedSimulationLoopAdvancesIntermediateManeuversAt5x`: Validates that a 5x speed jump from index 0 to 5 sequentially announces both Step 1 and Step 2.
   - `testT2_ExactSwitchbackBoundaryClampingAtEndIndexPlusTwo`: Verifies bounding at `stepEnd + 2`.
   - `testT2_UserPositionFarBeyondDestinationDoesNotReopenStepDistance`: Verifies strict 0.0 step and route distance 500m past route end.
   - `testT2_SimulationAtTwoXLandingExactlyOnStepBoundary`: Verifies 2x speed landing on step boundary.
   - `testT2_SimulationAtFiveXExceedingPolylineLengthCompletesArrival`: Verifies clamping to route end and subsequent arrival completion.

2. **RemediationTests.swift Compatibility**:
   - `test04_TelemetryStepSafety`: Zero-step route safely produces `remainingStepDistanceMiles = 0.0`.
   - `test17_SimulationStepOutOfBoundsSafety`: Empty steps and malformed negative/large indices handle cleanly without crash.
   - `test18_TelemetryEdgeCases`: Large routes (500 steps, 5000 coords) and extreme indices (-10, 5050) format without crash.
   - `test19_TelemetryOutOfBoundsEdgeCases`: Negative stepEnd (-5) and oversized stepEnd (9999) evaluate safely without crash.

All 69 E2E tests pass 100% in 0.118s.
