# Phase 0 Survey & Investigation Report: Requirements R1 & R2
**Target Module**: Navigation State Machine, ViewModel Architecture, Navigation Telemetry, Step Progression, and GPS Lifecycle  
**Author**: `explorer_survey_1` (Phase 0 Survey - Focus Area A)  
**Date**: 2026-11-07  

---

## Executive Summary
This investigation isolates the root causes of UI-state entanglement in `ContentView.swift`, uncovers telemetry distance reversal, premature step advancement on switchbacks, simulation turn skipping at high speeds, puck freezing on navigation startup, destination arrival blind spots, and GPS degradation/lifecycle flaws in `LocationManager.swift`. Concrete architectural designs and line-level code remediations are provided to extract an `@MainActor` `NavigationViewModel` and resolve all R1 and R2 defects cleanly while ensuring 100% backward compatibility for downstream test refactoring.

---

## 1. Observation

### 1.1 R1: Navigation, Search, and Telemetry State in `ContentView.swift`
In `MyOfflineMapApp/Sources/ContentView.swift` (lines 12–58, 98–106), `ContentView` directly declares 32 `@State` variables and 3 `@StateObject` service instances, creating tight coupling between the SwiftUI rendering tree and navigation business logic:

```swift
// ContentView.swift: lines 13-58
struct ContentView: View {
    @StateObject private var locationManager = LocationManager()

    // Mode state
    @State private var appMode: MapAppMode = .explore
    @State private var selectedPlace: SearchResult?
    @State var routeDetails: RouteDetails?
    @State private var selectedTravelMode: String = "auto"
    @State private var showStepsSheet = false
    @State private var showAttributionAlert = false
    @State private var isHudMode = false // Windshield HUD Reflection Mode
    @State var useMetric = false // mph vs km/h

    // Search state
    @State private var destinationText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false
    @State var searchTask: Task<Void, Never>?

    // Map bindings
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var routeCoordinates: [CLLocationCoordinate2D]?
    @State var simulatedUserCoordinate: CLLocationCoordinate2D?
    @State private var userLocationCenter: CLLocationCoordinate2D?
    @State private var simulatedHeading: Double?
    @State private var zoomStep: Double?

    // Navigation & simulation state
    @State var isNavigating = false
    @State var isSimulating = false
    @State private var simulationTimer: Timer?
    @State var currentStepIndex = 0
    @State var currentCoordIndex = 0
    @State private var simulatedSpeedMph: Int = 0
    @State private var simulationSpeedMultiplier: Double = 1.0
    @State private var isVoiceMuted = false
    @State var isProgrammaticTextChange = false
    @State private var isRecalculating = false
    @State private var consecutiveRerouteFailures = 0
    @State private var lastRerouteTime = Date.distantPast
    @State private var activeRouteRequestId: UUID? = nil
    @State var remainingStepDistanceMiles: Double = 0.0
    @State private var remainingRouteDistanceMiles: Double = 0.0
    @State private var remainingRouteDurationSeconds: Double = 0.0
    @State private var dynamicArrivalDate: Date = Date()
    @State private var hasAnnouncedAdvanceTurn = false

    // Alerts & Services: lines 98-106
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    @State private var isMapDataMissing: Bool = false

    @StateObject private var searchService = SearchService()
    @StateObject private var routingService = RoutingService()
```

Additionally, `ContentView.swift` defines 21 business logic and telemetry calculation methods (lines 65–81, 108–141, 510–524, 919–1394):
- Formatting: `formatCountdownDistance(_:useMetric:)`, `formattedRemainingDuration`, `formattedRemainingETA`, `displaySpeed`, `speedUnit`, `altitudeValue`, `altitudeUnit`.
- Region & Location: `isWithinSupportedRegion(_:)`, `effectiveUserCoordinate`, `recenterOnUser()`.
- Navigation & Telemetry: `handleLocationUpdate(_:)`, `updateCurrentStepForLiveLocation(_:in:)`, `updateNavigationTelemetry(at:coordIndex:in:)`, `segmentDistanceMeters(p1:p2:)`, `recalculateActiveRoute(to:)`, `startNavigation()`, `startSimulatedDrive()`, `advanceSimulationStep()`, `endNavigation()`.
- Search & Place Selection: `handleMapLongPress(at:)`, `handleQueryChange(_:)`, `searchCategory(_:)`, `selectPlace(_:)`, `calculateRouteTo(_:completion:)`, `switchTravelMode(_:)`, `dismissSearch()`, `clearSearch()`, `resetToExplore()`.

### 1.2 R1: User Preferences Persistence & `PrivacyInfo.xcprivacy`
- In `ContentView.swift`, line 23:
  ```swift
  @State var useMetric = false // mph vs km/h
  ```
- In `ContentView.swift`, line 47:
  ```swift
  @State private var isVoiceMuted = false
  ```
- When the app terminates or restarts, `useMetric` and `isVoiceMuted` reset to `false`.
- In `MyOfflineMapApp/Resources/PrivacyInfo.xcprivacy` (lines 30–36):
  ```xml
  <dict>
      <key>NSPrivacyAccessedAPIType</key>
      <string>NSPrivacyAccessedAPITypeUserDefaults</string>
      <key>NSPrivacyAccessedAPITypeReasons</key>
      <array>
          <string>CA92.1</string>
      </array>
  </dict>
  ```
  `NSPrivacyAccessedAPITypeUserDefaults` is already declared with reason code `CA92.1` ("Access user defaults to read and write information that is only accessible to the app itself"). Persisting `useMetric` and `isVoiceMuted` under keys `"useMetric"` and `"isVoiceMuted"` via `@AppStorage` / `UserDefaults.standard` strictly conforms to this privacy declaration.

---

### 1.3 R2: Forward Coordinate Search in `updateCurrentStepForLiveLocation`
In `ContentView.swift` (lines 983–998):
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
`searchEnd` scans up to 50 vertices forward regardless of step boundaries. On hairpin switchbacks or parallel road segments, `closestIndex` jumps across to future maneuvers, and line 1006 (`currentCoordIndex >= currentStep.endIndex`) triggers premature maneuver advancement.

---

### 1.4 R2: Telemetry Distance Calculation and Reversal in `updateNavigationTelemetry`
In `ContentView.swift` (lines 1028–1048):
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
        stepDistMeters = segmentDistanceMeters(p1: userCoord, p2: coords[stepEnd])
    }
    self.remainingStepDistanceMiles = max(0.0, stepDistMeters * 0.000621371)
} else {
    self.remainingStepDistanceMiles = 0.0
}
```
When `clampedIndex >= stepEnd`, the condition in line 1042 (`else if stepEnd < coords.count`) executes `stepDistMeters = segmentDistanceMeters(p1: userCoord, p2: coords[stepEnd])`. As the vehicle proceeds past `coords[stepEnd]`, the Euclidean distance from `userCoord` to the passed vertex *increases*, producing a distance reversal (e.g. 5m -> 0m -> 15m).

---

### 1.5 R2: Intermediate Step Dropping in `advanceSimulationStep()`
In `ContentView.swift` (lines 1297–1330):
```swift
let stepJump = Int(max(1, simulationSpeedMultiplier))
let nextIndex = min(coords.count - 1, currentCoordIndex + stepJump)
...
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
At 2x and 5x speeds (`stepJump = 2` or `5`), `currentCoordIndex` can traverse multiple step start indices in a single timer interval. Because line 1317 is a single `if`, `currentStepIndex` increments at most once, permanently skipping intermediate maneuvers.

---

### 1.6 R2: Unconditional Polyline Start Snapping in `startNavigation()`
In `ContentView.swift` (lines 1250–1269):
```swift
private func startNavigation() {
    guard let details = routeDetails, !details.coordinates.isEmpty else { return }
    isNavigating = true
    appMode = .navigation
    currentStepIndex = 0
    currentCoordIndex = 0
    hasAnnouncedAdvanceTurn = false
    remainingRouteDistanceMiles = details.totalDistanceMiles
    remainingRouteDurationSeconds = details.totalDurationSeconds
    dynamicArrivalDate = details.targetArrivalDate
    if let first = details.steps.first {
        remainingStepDistanceMiles = first.distanceMiles
    }
    simulatedUserCoordinate = details.coordinates.first
    locationManager.setNavigationActive(true)

    if let first = details.steps.first {
        routingService.speakTurnInstruction(first.instruction)
    }
}
```
Line 1263 sets `simulatedUserCoordinate = details.coordinates.first`. In `ContentView.swift` line 136 (`effectiveUserCoordinate`) and `MapView.swift` line 164 (`carAnnotation`), `simulatedUserCoordinate` takes precedence over `locationManager.location`. If the device has a valid hardware GPS lock within the region, the puck and camera snap back to vertex 0 and remain frozen until a subsequent location update arrives.

---

### 1.7 R2: Road-Snapped Only Arrival Detection
In `ContentView.swift` (lines 970–981):
```swift
// Live arrival check at destination
if let finalDest = coords.last, coords.count >= 2 {
    let distToFinalDest = segmentDistanceMeters(p1: userCoord, p2: finalDest)
    let isNearEnd = currentCoordIndex >= max(0, coords.count - 3) || (!details.steps.isEmpty && currentStepIndex >= details.steps.count - 1)
    if distToFinalDest < 25.0 || (isNearEnd && distToFinalDest < 40.0) {
        routingService.speakTurnInstruction("You have arrived at your destination.", force: true)
        routeDetails = nil
        routeCoordinates = nil
        endNavigation()
        return
    }
}
```
Arrival evaluates only `coords.last`. If `selectedCoordinate` is located off-road (e.g. 35m into a parking lot or building compound), the user arrives at the destination pin without ever getting within 25m of the road-snapped `coords.last`.

---

### 1.8 R2: GPS Accuracy Degradation & Unstructured `Task` in `LocationManager.swift`
In `MyOfflineMapApp/Sources/LocationManager.swift`:
1. Weak signal handling (lines 94–100):
   ```swift
   // Only flag weak GPS signal for current fixes with poor or negative horizontal accuracy
   if latest.horizontalAccuracy < 0 || latest.horizontalAccuracy >= 65.0 {
       Task { @MainActor in
           self.isGpsSignalLow = true
       }
       return
   }
   ```
   When GPS accuracy degrades (`>= 65.0` or `< 0`), `smoothedSpeedMph` and `smoothedSpeedKmh` are never reset, and `isStationary` remains `false`.
2. Unstructured async `Task` in `deinit` (lines 44–51):
   ```swift
   deinit {
       if let observer = orientationObserver {
           NotificationCenter.default.removeObserver(observer)
       }
       Task { @MainActor in
           UIDevice.current.endGeneratingDeviceOrientationNotifications()
       }
   }
   ```
   `Task { @MainActor in ... }` in `deinit` creates an unmanaged asynchronous task from a deallocating object, violating Swift strict concurrency and risking post-deinit side effects.

---

## 2. Logic Chain

```
Observation 1.1 (ContentView owns 35 state props & 21 business methods)
    │
    ▼
[Logic Step 1]: In SwiftUI, mutating @State on unmounted view structs in tests is undefined behavior.
Extracting these into an @MainActor ObservableObject (NavigationViewModel) provides clean state
management, isolates UI rendering, and allows direct unit testing of state transitions.
    │
    ▼
Observation 1.2 (useMetric and isVoiceMuted reset on app launch; PrivacyInfo declares CA92.1)
    │
    ▼
[Logic Step 2]: Storing useMetric and isVoiceMuted via @AppStorage / UserDefaults with keys
"useMetric" and "isVoiceMuted" satisfies CA92.1 (app-internal preferences). The ViewModel should
load these on init and persist changes via property observers or @AppStorage bindings.
    │
    ▼
Observation 1.3 (searchEnd scans currentCoordIndex + 50 forward)
    │
    ▼
[Logic Step 3]: On hairpin switchbacks, polyline vertices 30 nodes ahead can be < 15m away across
a canyon or bend. Restricting searchEnd to min(coords.count - 1, currentStep.endIndex + 2)
guarantees the search window never jumps beyond the active maneuver (+2 vertices slack).
    │
    ▼
Observation 1.4 (stepDistMeters = segmentDistanceMeters(p1: userCoord, p2: coords[stepEnd]))
    │
    ▼
[Logic Step 4]: When clampedIndex >= stepEnd, measuring distance to coords[stepEnd] measures
backwards from the user's position, increasing distance. Clamping remainingStepDistanceMiles
to 0.0 once clampedIndex >= stepEnd guarantees monotonic countdown to 0.0.
    │
    ▼
Observation 1.5 (single if check advances at most one step per tick in advanceSimulationStep)
    │
    ▼
[Logic Step 5]: At 2x and 5x simulation speeds, currentCoordIndex jumps by 2 to 5 vertices per tick.
Replacing the single if check with a while loop advances currentStepIndex through all crossed steps,
ensuring all intermediate maneuvers are announced and advanced.
    │
    ▼
Observation 1.6 (simulatedUserCoordinate unconditionally snaps to details.coordinates.first)
    │
    ▼
[Logic Step 6]: When starting navigation with a valid in-region hardware fix, the user coordinate
should initialize from locationManager.location. Only when no valid hardware fix exists should it
snap to details.coordinates.first.
    │
    ▼
Observation 1.7 (arrival check tests only coords.last)
    │
    ▼
[Logic Step 7]: Testing min(distanceTo(coords.last), distanceTo(selectedCoordinate)) allows
arrival detection when a destination is set back from the road in a parking lot or driveway.
    │
    ▼
Observation 1.8 (LocationManager weak GPS leaves speed intact; deinit spawns Task)
    │
    ▼
[Logic Step 8]: When horizontalAccuracy < 0 || >= 65.0, immediately zeroing smoothedSpeedMph,
smoothedSpeedKmh, previousSpeedMps, and setting isStationary = true prevents stuck speedometers.
Replacing Task in deinit with synchronous MainActor.assumeIsolated or checking Thread.isMainThread
/ DispatchQueue.main eliminates unstructured task creation in deinit.
```

---

## 3. Recommended Implementation Architecture

### 3.1 Architecture: `NavigationViewModel`
Create a new file: `MyOfflineMapApp/Sources/NavigationViewModel.swift`.

```swift
import Foundation
import CoreLocation
import SwiftUI
import Combine

@MainActor
public final class NavigationViewModel: ObservableObject {
    // Services
    public let locationManager: LocationManager
    public let searchService: SearchService
    public let routingService: RoutingService

    // App & Mode State
    @Published public var appMode: MapAppMode = .explore
    @Published public var selectedPlace: SearchResult?
    @Published public var routeDetails: RouteDetails?
    @Published public var selectedTravelMode: String = "auto"
    @Published public var showStepsSheet: Bool = false
    @Published public var showAttributionAlert: Bool = false
    @Published public var isHudMode: Bool = false

    // Persistent User Preferences (@AppStorage / UserDefaults)
    @Published public var useMetric: Bool {
        didSet {
            UserDefaults.standard.set(useMetric, forKey: "useMetric")
        }
    }
    @Published public var isVoiceMuted: Bool {
        didSet {
            UserDefaults.standard.set(isVoiceMuted, forKey: "isVoiceMuted")
            routingService.isVoiceMuted = isVoiceMuted
            if isVoiceMuted {
                routingService.stopVoice()
            }
        }
    }

    // Search State
    @Published public var destinationText: String = ""
    @Published public var searchResults: [SearchResult] = []
    @Published public var isSearching: Bool = false
    public var searchTask: Task<Void, Never>?

    // Map Bindings
    @Published public var selectedCoordinate: CLLocationCoordinate2D?
    @Published public var routeCoordinates: [CLLocationCoordinate2D]?
    @Published public var simulatedUserCoordinate: CLLocationCoordinate2D?
    @Published public var userLocationCenter: CLLocationCoordinate2D?
    @Published public var simulatedHeading: Double?
    @Published public var zoomStep: Double?

    // Navigation & Simulation State
    @Published public var isNavigating: Bool = false
    @Published public var isSimulating: Bool = false
    public var simulationTimer: Timer?
    @Published public var currentStepIndex: Int = 0
    @Published public var currentCoordIndex: Int = 0
    @Published public var simulatedSpeedMph: Int = 0
    @Published public var simulationSpeedMultiplier: Double = 1.0
    @Published public var isProgrammaticTextChange: Bool = false
    @Published public var isRecalculating: Bool = false
    @Published public var consecutiveRerouteFailures: Int = 0
    @Published public var lastRerouteTime: Date = Date.distantPast
    @Published public var activeRouteRequestId: UUID? = nil
    @Published public var remainingStepDistanceMiles: Double = 0.0
    @Published public var remainingRouteDistanceMiles: Double = 0.0
    @Published public var remainingRouteDurationSeconds: Double = 0.0
    @Published public var dynamicArrivalDate: Date = Date()
    @Published public var hasAnnouncedAdvanceTurn: Bool = false

    // Alerts
    @Published public var errorMessage: String?
    @Published public var showErrorAlert: Bool = false
    @Published public var isMapDataMissing: Bool = false

    private var cancellables = Set<AnyCancellable>()

    public init(
        locationManager: LocationManager = LocationManager(),
        searchService: SearchService = SearchService(),
        routingService: RoutingService = RoutingService()
    ) {
        self.locationManager = locationManager
        self.searchService = searchService
        self.routingService = routingService

        // Load persisted preferences
        self.useMetric = UserDefaults.standard.bool(forKey: "useMetric")
        self.isVoiceMuted = UserDefaults.standard.bool(forKey: "isVoiceMuted")
        self.routingService.isVoiceMuted = self.isVoiceMuted

        // Wire location updates
        locationManager.$location
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loc in
                self?.handleLocationUpdate(loc)
            }
            .store(in: &cancellables)
    }
```

### 3.2 Injection into `ContentView.swift`
In `ContentView.swift`:
```swift
struct ContentView: View {
    @StateObject private var viewModel: NavigationViewModel

    public init(viewModel: NavigationViewModel = NavigationViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    // Direct forwarding properties for test and preview compatibility:
    var routeDetails: RouteDetails? {
        get { viewModel.routeDetails }
        set { viewModel.routeDetails = newValue }
    }
    var remainingStepDistanceMiles: Double {
        get { viewModel.remainingStepDistanceMiles }
        set { viewModel.remainingStepDistanceMiles = newValue }
    }
    var currentStepIndex: Int {
        get { viewModel.currentStepIndex }
        set { viewModel.currentStepIndex = newValue }
    }
    var currentCoordIndex: Int {
        get { viewModel.currentCoordIndex }
        set { viewModel.currentCoordIndex = newValue }
    }
    var useMetric: Bool {
        get { viewModel.useMetric }
        set { viewModel.useMetric = newValue }
    }
```

### 3.3 Proposed Code Changes for R2

#### Fix 1: Coordinate Search Range Clamping (`updateCurrentStepForLiveLocation`)
```swift
// Proposed replacement in updateCurrentStepForLiveLocation
let searchStart = max(0, currentCoordIndex - 5)
let maxForwardIndex: Int
if !details.steps.isEmpty && currentStepIndex < details.steps.count {
    let currentStep = details.steps[currentStepIndex]
    maxForwardIndex = min(coords.count - 1, currentStep.endIndex + 2)
} else {
    maxForwardIndex = min(coords.count - 1, currentCoordIndex + 50)
}
let searchEnd = max(searchStart, min(coords.count - 1, maxForwardIndex))
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

#### Fix 2: Telemetry Monotonic Countdown & No Reversal (`updateNavigationTelemetry`)
```swift
// Proposed replacement in updateNavigationTelemetry
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
        self.remainingStepDistanceMiles = max(0.0, stepDistMeters * 0.000621371)
    } else {
        // At or past stepEnd: strictly zero out to prevent distance reversal
        self.remainingStepDistanceMiles = 0.0
    }
} else {
    self.remainingStepDistanceMiles = 0.0
}
```

#### Fix 3: Multi-Speed Simulation Step Advancement Loop (`advanceSimulationStep`)
```swift
// Proposed replacement in advanceSimulationStep
if !details.steps.isEmpty {
    while currentStepIndex < details.steps.count - 1 {
        let nextStep = details.steps[currentStepIndex + 1]
        if currentCoordIndex >= nextStep.startIndex {
            currentStepIndex += 1
            hasAnnouncedAdvanceTurn = false
            routingService.speakTurnInstruction(nextStep.instruction, stepId: currentStepIndex * 10 + 2)
        } else {
            break
        }
    }

    if currentStepIndex < details.steps.count - 1 && !hasAnnouncedAdvanceTurn {
        let nextStep = details.steps[currentStepIndex + 1]
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

#### Fix 4: GPS Hardware Fix Preservation in `startNavigation()`
```swift
// Proposed replacement in startNavigation
if let hardwareFix = locationManager.location?.coordinate, isWithinSupportedRegion(hardwareFix) {
    simulatedUserCoordinate = hardwareFix
    if let course = locationManager.location?.course, course >= 0 {
        simulatedHeading = course
    } else if locationManager.heading >= 0 {
        simulatedHeading = locationManager.heading
    }
} else {
    simulatedUserCoordinate = details.coordinates.first
}
```

#### Fix 5: Dual Road-End and Destination-Pin Arrival Detection
```swift
// Proposed replacement in updateCurrentStepForLiveLocation arrival check
if coords.count >= 2 {
    var distToArrival = Double.infinity
    if let roadEnd = coords.last {
        distToArrival = min(distToArrival, segmentDistanceMeters(p1: userCoord, p2: roadEnd))
    }
    if let pin = selectedCoordinate {
        distToArrival = min(distToArrival, segmentDistanceMeters(p1: userCoord, p2: pin))
    }
    let isNearEnd = currentCoordIndex >= max(0, coords.count - 3) || (!details.steps.isEmpty && currentStepIndex >= details.steps.count - 1)
    if distToArrival < 25.0 || (isNearEnd && distToArrival < 40.0) {
        routingService.speakTurnInstruction("You have arrived at your destination.", force: true)
        routeDetails = nil
        routeCoordinates = nil
        endNavigation()
        return
    }
}
```

#### Fix 6: LocationManager Degraded GPS Speed & Deinit Safety
In `MyOfflineMapApp/Sources/LocationManager.swift`:
```swift
// Lines 94-100 replacement:
if latest.horizontalAccuracy < 0 || latest.horizontalAccuracy >= 65.0 {
    Task { @MainActor in
        self.isGpsSignalLow = true
        self.smoothedSpeedMph = 0
        self.smoothedSpeedKmh = 0
        self.isStationary = true
        self.previousSpeedMps = 0.0
    }
    return
}

// Lines 44-51 replacement:
deinit {
    if let observer = orientationObserver {
        NotificationCenter.default.removeObserver(observer)
    }
    if Thread.isMainThread {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    } else {
        DispatchQueue.main.async {
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
    }
}
```

---

## 4. Caveats & Risks

1. **Test Suite Source Code Matching**:
   `RemediationTests.swift` currently contains tests that read `ContentView.swift` via `String(contentsOf: ...)` and check for text like `"func dismissSearch()"` and `"isProgrammaticTextChange = true"`. If those methods are moved exclusively to `NavigationViewModel.swift`, those source-inspection tests will fail unless either:
   - Forwarding stubs remain in `ContentView.swift`, or
   - `RemediationTests.swift` is refactored per Requirement R6 to test `NavigationViewModel` directly.
   Recommendation: Implement forwarding stubs in `ContentView` during R1/R2 and remove or redirect the source-code string assertions in Phase 1 (R6).

2. **Simulation Audio Announcements at High Speed**:
   Advancing through multiple steps in a single `while` loop at 5x speed may invoke `speakTurnInstruction` multiple times in rapid succession. `RoutingService` must properly queue or prioritize speech instructions (handled in R3 with audio locks and generations).

3. **Xcode Project Membership**:
   Adding `NavigationViewModel.swift` under `MyOfflineMapApp/Sources/` is supported by XcodeGen (`project.yml` targets `Sources`), but developers must run `xcodegen generate` or ensure `MyOfflineMapApp.xcodeproj` includes the new file reference.

---

## 5. Conclusion
Requirements R1 and R2 can be completely implemented with zero regression:
- Extracting `NavigationViewModel` provides a clean `@MainActor` state machine that decouples state from UI rendering.
- Storing `useMetric` and `isVoiceMuted` via `@AppStorage` / `UserDefaults` complies with `PrivacyInfo.xcprivacy` under reason `CA92.1`.
- Clamping forward coordinate search to `currentStep.endIndex + 2` prevents switchback snapping.
- Zeroing remaining step distance when `clampedIndex >= stepEnd` eliminates distance reversal.
- A `while` loop in `advanceSimulationStep()` prevents skipped maneuvers at 2x and 5x simulation speeds.
- Checking hardware GPS prior to polyline snapping in `startNavigation()` stops vehicle puck freezing.
- Evaluating arrival against both `coords.last` and `selectedCoordinate` handles off-road setback destinations.
- Zeroing speedometer and stationary state on degraded GPS and cleaning up `deinit` in `LocationManager.swift` restores GPS telemetry and concurrency safety.

---

## 6. Verification Method

### Independent Verification Commands & Checks:
1. **Switchback Coordinate Clamping Verification**:
   - Construct a route with a sharp hairpin turn where polyline coordinates at index 25 (step 2) are within 10 meters of coordinate at index 5 (step 1).
   - Simulate a location update at index 5.
   - Assert `currentCoordIndex <= currentStep.endIndex + 2`.
   - Assert `currentStepIndex == 0`.

2. **Monotonic Telemetry Countdown Verification**:
   - For a step ending at coordinate index 10, feed coordinate indices 8, 9, 10, 11 to `updateNavigationTelemetry`.
   - Assert `remainingStepDistanceMiles` monotonically decreases from index 8 to 10, and evaluates to exactly `0.0` at index 10 and 11.
   - Assert no increase occurs at index 11.

3. **Multi-Speed Simulation Advancement Verification**:
   - Create a route with 3 consecutive short steps (starts at 0, 3, 6).
   - Set `simulationSpeedMultiplier = 5.0`.
   - Call `advanceSimulationStep()`.
   - Assert `currentStepIndex` advances across all intermediate steps to step 2 without skipping.

4. **Hardware GPS Initialization Verification**:
   - Deliver a valid location fix (e.g. `(64.8450, -147.7200)`) to `locationManager`.
   - Call `startNavigation()` on a route starting at `(64.8400, -147.7100)`.
   - Assert `simulatedUserCoordinate == CLLocationCoordinate2D(latitude: 64.8450, longitude: -147.7200)`.

5. **Setback Destination Arrival Verification**:
   - Route coordinates ending at `(64.8400, -147.7100)`.
   - Selected coordinate (destination pin) at `(64.8402, -147.7103)` (30 meters from road endpoint).
   - User location at `(64.8402, -147.7102)` (8 meters from destination pin, 30 meters from road end).
   - Call `updateCurrentStepForLiveLocation`.
   - Assert arrival triggers (`isNavigating == false`, `routeDetails == nil`).

6. **GPS Degradation Telemetry Verification**:
   - Deliver `CLLocation` with `horizontalAccuracy = 75.0` to `LocationManager`.
   - Under `@MainActor`, assert `locationManager.isGpsSignalLow == true`, `locationManager.smoothedSpeedMph == 0`, and `locationManager.isStationary == true`.
