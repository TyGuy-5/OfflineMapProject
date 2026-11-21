//
//  NavigationViewModel.swift
//  MyOfflineMapApp
//
//  Created for Production Hardening & Remediation (Milestone 3).
//  Encapsulates all navigation state machine, search, simulation, and telemetry logic.
//

import SwiftUI
import CoreLocation
import Combine
#if canImport(UIKit)
import UIKit
#endif

public enum MapAppMode: Equatable, Sendable {
    case explore
    case searchList
    case placeDetail
    case routePreview
    case navigation
}

@MainActor
public final class NavigationViewModel: ObservableObject {

    // MARK: - Service Dependencies
    public let locationManager: LocationManager
    public let searchService: SearchService
    public let routingService: RoutingService

    // MARK: - Navigation Mode State
    @Published public var appMode: MapAppMode = .explore
    @Published public var selectedPlace: SearchResult?
    @Published public var routeDetails: RouteDetails?
    @Published public var selectedTravelMode: String = "auto"
    @Published public var showStepsSheet: Bool = false
    @Published public var isHudMode: Bool = false

    // MARK: - Persisted User Preferences (AppStorage / CA92.1)
    @AppStorage("useMetric") public var useMetric: Bool = false {
        willSet {
            objectWillChange.send()
        }
    }

    @AppStorage("isVoiceMuted") public var isVoiceMuted: Bool = false {
        willSet {
            objectWillChange.send()
        }
        didSet {
            routingService.isVoiceMuted = isVoiceMuted
            if isVoiceMuted {
                routingService.stopVoice()
            }
        }
    }

    // MARK: - Search State
    @Published public var destinationText: String = ""
    @Published public var searchResults: [SearchResult] = []
    @Published public var isSearching: Bool = false
    public var searchTask: Task<Void, Never>?
    @Published public var isProgrammaticTextChange: Bool = false

    // MARK: - Map Bindings & Telemetry State
    @Published public var selectedCoordinate: CLLocationCoordinate2D?
    @Published public var routeCoordinates: [CLLocationCoordinate2D]?
    @Published public var simulatedUserCoordinate: CLLocationCoordinate2D?
    @Published public var userLocationCenter: CLLocationCoordinate2D?
    @Published public var simulatedHeading: Double?
    @Published public var zoomStep: Double?

    // MARK: - Navigation & Simulation State
    @Published public var isNavigating: Bool = false
    @Published public var isSimulating: Bool = false
    private var simulationTimer: Timer?
    @Published public var currentStepIndex: Int = 0
    @Published public var currentCoordIndex: Int = 0
    @Published public var simulatedSpeedMph: Int = 0
    @Published public var simulationSpeedMultiplier: Double = 1.0

    // MARK: - Rerouting & Telemetry Internal State
    public var isRecalculating: Bool = false
    public var consecutiveRerouteFailures: Int = 0
    public var lastRerouteTime: Date = .distantPast
    public var activeRouteRequestId: UUID? = nil
    @Published public var remainingStepDistanceMiles: Double = 0.0
    @Published public var remainingRouteDistanceMiles: Double = 0.0
    @Published public var remainingRouteDurationSeconds: Double = 0.0
    @Published public var dynamicArrivalDate: Date = Date()
    public var hasAnnouncedAdvanceTurn: Bool = false

    // MARK: - Alerts
    @Published public var errorMessage: String?
    @Published public var showErrorAlert: Bool = false
    @Published public var isMapDataMissing: Bool = false

    // MARK: - Static Constants & Formatters
    public static let defaultAlaskaCoordinate = CLLocationCoordinate2D(latitude: 64.8436, longitude: -147.7215)

    private static let hudEtaFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Initializer
    public init(
        locationManager: LocationManager? = nil,
        searchService: SearchService? = nil,
        routingService: RoutingService? = nil
    ) {
        self.locationManager = locationManager ?? LocationManager()
        self.searchService = searchService ?? SearchService()
        self.routingService = routingService ?? RoutingService()

        // Sync initial persisted audio mute preference to routing service
        self.routingService.isVoiceMuted = self.isVoiceMuted
    }

    // MARK: - Computed Properties
    public var displaySpeed: Int {
        if isSimulating {
            return useMetric ? Int(Double(simulatedSpeedMph) * 1.60934) : simulatedSpeedMph
        }
        return useMetric ? locationManager.smoothedSpeedKmh : locationManager.smoothedSpeedMph
    }

    public var speedUnit: String {
        useMetric ? "km/h" : "mph"
    }

    public var altitudeValue: Int {
        let alt = locationManager.location?.altitude ?? 0
        return useMetric ? Int(alt) : Int(alt * 3.28084)
    }

    public var altitudeUnit: String {
        useMetric ? "m" : "ft"
    }

    public var effectiveUserCoordinate: CLLocationCoordinate2D {
        if let sim = simulatedUserCoordinate { return sim }
        if let user = locationManager.location?.coordinate, isWithinSupportedRegion(user) {
            return user
        }
        return Self.defaultAlaskaCoordinate
    }

    public var currentNavigationStep: NavigationStep {
        guard let steps = routeDetails?.steps, !steps.isEmpty else {
            return NavigationStep(
                instruction: "Proceed along route",
                distanceMiles: 0.5,
                durationSeconds: 60,
                maneuverType: 1,
                streetName: nil,
                startIndex: 0,
                endIndex: 1
            )
        }
        let safeIndex = min(max(0, currentStepIndex), steps.count - 1)
        return steps[safeIndex]
    }

    public var formattedRemainingDuration: String {
        let minutes = Int(remainingRouteDurationSeconds / 60)
        if minutes < 60 {
            return "\(max(1, minutes)) min"
        } else {
            let hours = minutes / 60
            let remMin = minutes % 60
            return "\(hours) hr \(remMin) min"
        }
    }

    public var formattedRemainingETA: String {
        Self.hudEtaFormatter.string(from: dynamicArrivalDate)
    }

    // MARK: - Helper Methods
    public func isWithinSupportedRegion(_ coord: CLLocationCoordinate2D) -> Bool {
        Self.isWithinSupportedRegion(coord)
    }

    public static func isWithinSupportedRegion(_ coord: CLLocationCoordinate2D) -> Bool {
        return coord.latitude >= 51.0 && coord.latitude <= 72.0 &&
               coord.longitude >= -179.0 && coord.longitude <= -129.0
    }

    public func formatCountdownDistance(_ miles: Double, useMetric: Bool) -> String {
        Self.formatCountdownDistance(miles, useMetric: useMetric)
    }

    public static func formatCountdownDistance(_ miles: Double, useMetric: Bool) -> String {
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

    public func segmentDistanceMeters(p1: CLLocationCoordinate2D, p2: CLLocationCoordinate2D) -> Double {
        Self.segmentDistanceMeters(p1: p1, p2: p2)
    }

    public static func segmentDistanceMeters(p1: CLLocationCoordinate2D, p2: CLLocationCoordinate2D) -> Double {
        let latRad = p1.latitude * .pi / 180.0
        let dx = (p2.longitude - p1.longitude) * 111320.0 * cos(latRad)
        let dy = (p2.latitude - p1.latitude) * 110540.0
        return sqrt(dx * dx + dy * dy)
    }

    // MARK: - Location & Navigation Progression
    public func handleLocationUpdate(_ location: CLLocation?) {
        guard let location = location, isNavigating, let details = routeDetails, let coords = routeCoordinates else { return }

        // Skip off-route checks during simulation
        if isSimulating {
            return
        }

        // Ignore out-of-region fixes to avoid overriding Alaska fallback and breaking rerouting
        guard isWithinSupportedRegion(location.coordinate) else { return }

        // Live real GPS driving updates
        simulatedUserCoordinate = location.coordinate
        if location.course >= 0 {
            simulatedHeading = location.course
        } else if locationManager.heading >= 0 {
            simulatedHeading = locationManager.heading
        }

        // Step progression along route maneuvers & live countdown telemetry
        updateCurrentStepForLiveLocation(location.coordinate, in: details)

        // Off-route check with in-progress guard and exponential backoff on failures
        guard !isRecalculating else { return }
        let now = Date()
        let cooldown = 7.0 * pow(2.0, Double(min(consecutiveRerouteFailures, 4)))
        guard now.timeIntervalSince(lastRerouteTime) > cooldown else { return }

        // Scale threshold by horizontal accuracy (at least 40m, up to 75m in urban canyons)
        let baseThreshold = 40.0
        let accuracySlack = max(0.0, location.horizontalAccuracy - 20.0)
        let effectiveThreshold = min(75.0, baseThreshold + accuracySlack)

        let isOff = routingService.isUserOffRoute(
            userLocation: location.coordinate,
            routeCoordinates: coords,
            thresholdMeters: effectiveThreshold,
            activeCoordIndex: currentCoordIndex
        )
        if isOff, let dest = selectedCoordinate {
            print("NavigationViewModel: Off-route detected! Recalculating route...")
            lastRerouteTime = now
            routingService.speakTurnInstruction("Recalculating route.", force: true)
            recalculateActiveRoute(to: dest)
        }
    }

    public func updateCurrentStepForLiveLocation(_ userCoord: CLLocationCoordinate2D, in details: RouteDetails) {
        let coords = details.coordinates
        guard !coords.isEmpty else { return }

        // R2.5: Dual-Point Arrival Check
        // Check distance against both the road-snapped endpoint (coords.last) and destination pin (selectedCoordinate)
        if coords.count >= 2 {
            let distToRoadEnd = segmentDistanceMeters(p1: userCoord, p2: coords.last!)
            let distToPin: Double
            if let destPin = selectedCoordinate {
                distToPin = segmentDistanceMeters(p1: userCoord, p2: destPin)
            } else {
                distToPin = .greatestFiniteMagnitude
            }
            let isNearEnd = currentCoordIndex >= max(0, coords.count - 3) || (!details.steps.isEmpty && currentStepIndex >= details.steps.count - 1)

            if distToRoadEnd < 25.0 || distToPin < 25.0 || (isNearEnd && (distToRoadEnd < 40.0 || distToPin < 40.0)) {
                routingService.speakTurnInstruction("You have arrived at your destination.", force: true)
                routeDetails = nil
                routeCoordinates = nil
                endNavigation()
                return
            }
        }

        // R2.1: Switchback Search Clamping
        // Clamped forward coordinate search to current maneuver's end index (+2 vertices slack)
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

        // Step progression along maneuvers
        if !details.steps.isEmpty && currentStepIndex < details.steps.count {
            let currentStep = details.steps[currentStepIndex]
            let endCoord = coords[max(0, min(currentStep.endIndex, coords.count - 1))]
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

    public func updateNavigationTelemetry(at userCoord: CLLocationCoordinate2D, coordIndex: Int, in details: RouteDetails) {
        let coords = details.coordinates
        guard coords.count >= 2 else {
            self.remainingStepDistanceMiles = 0.0
            self.remainingRouteDistanceMiles = 0.0
            self.remainingRouteDurationSeconds = 0.0
            self.dynamicArrivalDate = Date()
            return
        }
        let clampedIndex = min(max(0, coordIndex), coords.count - 1)

        // 1. Calculate remaining step distance (monotonically counting down)
        // R2.2: Evaluates to zero when clampedIndex >= stepEnd without distance reversal
        let currentStep: NavigationStep? = (currentStepIndex < details.steps.count) ? details.steps[currentStepIndex] : details.steps.last
        if let currentStep = currentStep {
            let stepEnd = max(0, min(currentStep.endIndex, coords.count - 1))
            if clampedIndex >= stepEnd {
                self.remainingStepDistanceMiles = 0.0
            } else {
                var stepDistMeters = 0.0
                if clampedIndex + 1 < coords.count {
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
            }
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
            routeDistMeters = 0.0
        }
        let routeMiles = max(0.0, routeDistMeters * 0.000621371)
        self.remainingRouteDistanceMiles = routeMiles

        // 3. Proportionally update remaining duration and ETA
        if details.totalDistanceMiles > 0 {
            let ratio = max(0.0, min(1.0, routeMiles / details.totalDistanceMiles))
            self.remainingRouteDurationSeconds = details.totalDurationSeconds * ratio
        } else {
            self.remainingRouteDurationSeconds = 0
        }
        self.dynamicArrivalDate = Date().addingTimeInterval(self.remainingRouteDurationSeconds)
    }

    public func recalculateActiveRoute(to dest: CLLocationCoordinate2D) {
        guard isNavigating && !isRecalculating else { return }
        isRecalculating = true
        let start = effectiveUserCoordinate
        let travelMode = selectedTravelMode
        let metric = useMetric
        let reqId = UUID()
        self.activeRouteRequestId = reqId
        let router = routingService

        DispatchQueue.global(qos: .userInitiated).async {
            let details = router.calculateRoute(from: start, to: dest, mode: travelMode, useMetric: metric)
            DispatchQueue.main.async {
                defer { self.isRecalculating = false }
                guard self.isNavigating && self.activeRouteRequestId == reqId else { return }
                if let details = details, !details.coordinates.isEmpty {
                    self.consecutiveRerouteFailures = 0
                    self.routeDetails = details
                    self.routeCoordinates = details.coordinates
                    self.currentStepIndex = 0
                    self.currentCoordIndex = 0
                    self.hasAnnouncedAdvanceTurn = false
                    self.remainingRouteDistanceMiles = details.totalDistanceMiles
                    self.remainingRouteDurationSeconds = details.totalDurationSeconds
                    self.dynamicArrivalDate = details.targetArrivalDate
                    if let first = details.steps.first {
                        self.remainingStepDistanceMiles = first.distanceMiles
                        self.routingService.speakTurnInstruction(first.instruction, stepId: 0, force: true)
                    }
                } else {
                    self.consecutiveRerouteFailures += 1
                    if self.consecutiveRerouteFailures == 1 {
                        self.errorMessage = "Rerouting failed: Current location or destination is outside offline road network."
                        self.showErrorAlert = true
                    }
                }
            }
        }
    }

    // MARK: - Map Interaction Actions
    public func handleMapLongPress(at coordinate: CLLocationCoordinate2D) {
        let tempPlace = SearchResult(
            id: 0,
            name: String(format: "Dropped Pin (%.4f, %.4f)", coordinate.latitude, coordinate.longitude),
            lat: coordinate.latitude,
            lon: coordinate.longitude
        )
        selectPlace(tempPlace)
        let searcher = searchService

        Task.detached(priority: .userInitiated) {
            if let resolved = await searcher.reverseGeocodeAsync(coordinate: coordinate) {
                await MainActor.run {
                    if self.selectedCoordinate?.latitude == coordinate.latitude &&
                       self.selectedCoordinate?.longitude == coordinate.longitude {
                        let latRad = coordinate.latitude * .pi / 180.0
                        let dx = (resolved.lon - coordinate.longitude) * 111320.0 * cos(latRad)
                        let dy = (resolved.lat - coordinate.latitude) * 110540.0
                        let distMeters = sqrt(dx * dx + dy * dy)
                        if distMeters <= 75.0 && resolved.id != 0 {
                            if self.destinationText != resolved.name {
                                self.isProgrammaticTextChange = true
                            }
                            self.selectedPlace = SearchResult(
                                id: resolved.id,
                                name: resolved.name,
                                lat: coordinate.latitude,
                                lon: coordinate.longitude
                            )
                            self.destinationText = resolved.name
                        }
                    }
                }
            }
        }
    }

    // MARK: - Search Actions
    public func handleQueryChange(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count >= 2 {
            appMode = .searchList
            isSearching = true
            let userLoc = effectiveUserCoordinate
            let searcher = searchService
            searchTask = Task.detached(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 180_000_000)
                if Task.isCancelled { return }
                let results = await searcher.searchAsync(query: trimmed, userLocation: userLoc)
                if !Task.isCancelled {
                    await MainActor.run {
                        self.searchResults = results
                        self.isSearching = false
                    }
                }
            }
        } else {
            searchResults = []
            isSearching = false
            if appMode == .searchList {
                appMode = .explore
            }
        }
    }

    public func searchCategory(_ category: String) {
        if destinationText != category {
            isProgrammaticTextChange = true
            destinationText = category
        }
        handleQueryChange(category)
    }

    public func selectPlace(_ place: SearchResult) {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
        if destinationText != place.name {
            isProgrammaticTextChange = true
        }
        selectedPlace = place
        selectedCoordinate = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)
        destinationText = place.name
        searchResults = []
        appMode = .placeDetail
    }

    public func calculateRouteTo(_ place: SearchResult, completion: (@MainActor @Sendable () -> Void)? = nil) {
        let dest = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)
        let start = effectiveUserCoordinate
        let travelMode = selectedTravelMode
        let metric = useMetric
        let reqId = UUID()
        self.activeRouteRequestId = reqId
        let router = routingService

        appMode = .routePreview
        routeDetails = nil
        routeCoordinates = nil

        DispatchQueue.global(qos: .userInitiated).async {
            let details = router.calculateRoute(from: start, to: dest, mode: travelMode, useMetric: metric)
            DispatchQueue.main.async {
                guard self.activeRouteRequestId == reqId else { return }
                if let details = details, !details.coordinates.isEmpty {
                    self.routeDetails = details
                    self.routeCoordinates = details.coordinates
                    self.remainingRouteDistanceMiles = details.totalDistanceMiles
                    self.remainingRouteDurationSeconds = details.totalDurationSeconds
                    self.dynamicArrivalDate = details.targetArrivalDate
                    if let first = details.steps.first {
                        self.remainingStepDistanceMiles = first.distanceMiles
                    }
                    completion?()
                } else {
                    self.errorMessage = "Could not calculate route to \(place.name)."
                    self.showErrorAlert = true
                    self.appMode = self.selectedPlace != nil ? .placeDetail : .explore
                }
            }
        }
    }

    public func switchTravelMode(_ mode: String) {
        selectedTravelMode = mode
        if let place = selectedPlace {
            calculateRouteTo(place)
        }
    }

    // MARK: - Navigation Lifecycle Actions
    public func startNavigation() {
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

        // R2.4: GPS Hardware Start Fix
        // Do not unconditionally snap simulatedUserCoordinate to polyline start when a valid hardware GPS fix exists
        if let loc = locationManager.location,
           loc.horizontalAccuracy >= 0 && loc.horizontalAccuracy < 65.0,
           abs(loc.timestamp.timeIntervalSinceNow) < 15.0,
           isWithinSupportedRegion(loc.coordinate) {
            simulatedUserCoordinate = loc.coordinate
            if loc.course >= 0 {
                simulatedHeading = loc.course
            } else if locationManager.heading >= 0 {
                simulatedHeading = locationManager.heading
            }
        } else {
            simulatedUserCoordinate = details.coordinates.first
        }

        locationManager.setNavigationActive(true)

        if let first = details.steps.first {
            routingService.speakTurnInstruction(first.instruction)
        }
    }

    public func startSimulatedDrive() {
        guard let details = routeDetails, !details.coordinates.isEmpty else { return }
        startNavigation()
        guard isNavigating else { return }
        isSimulating = true
        // Explicitly begin simulated drive at route start
        simulatedUserCoordinate = details.coordinates.first
        currentCoordIndex = 0
        simulatedSpeedMph = selectedTravelMode == "pedestrian" ? 3 : (selectedTravelMode == "bicycle" ? 12 : 45)

        simulationTimer?.invalidate()
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceSimulationStep()
            }
        }
    }

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

        let p1 = coords[max(0, min(currentCoordIndex, coords.count - 1))]
        let p2 = coords[nextIndex]

        let dLon = (p2.longitude - p1.longitude) * .pi / 180
        let lat1 = p1.latitude * .pi / 180
        let lat2 = p2.latitude * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let radiansBearing = atan2(y, x)
        let degreesBearing = (radiansBearing * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)

        simulatedHeading = degreesBearing
        simulatedUserCoordinate = p2
        currentCoordIndex = nextIndex

        // R2.3: In advanceSimulationStep(), advance currentStepIndex via while loop so 2x and 5x simulation does not skip maneuvers
        while !details.steps.isEmpty && currentStepIndex < details.steps.count - 1 {
            let nextStep = details.steps[currentStepIndex + 1]
            let startBound = max(0, min(nextStep.startIndex, coords.count - 1))
            if currentCoordIndex >= startBound {
                currentStepIndex += 1
                hasAnnouncedAdvanceTurn = false
                routingService.speakTurnInstruction(nextStep.instruction, stepId: currentStepIndex * 10 + 2)
            } else {
                break
            }
        }

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

    public func endNavigation() {
        activeRouteRequestId = nil
        isRecalculating = false
        consecutiveRerouteFailures = 0
        routingService.stopVoice()
        simulationTimer?.invalidate()
        simulationTimer = nil
        isNavigating = false
        isSimulating = false
        isHudMode = false
        simulatedUserCoordinate = nil
        simulatedHeading = nil
        simulatedSpeedMph = 0
        currentStepIndex = 0
        currentCoordIndex = 0
        locationManager.setNavigationActive(false)
        appMode = routeDetails != nil ? .routePreview : .explore
    }

    public func dismissSearch() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        searchResults = []
        if appMode == .searchList {
            appMode = .explore
        }
    }

    public func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        destinationText = ""
        searchResults = []
        dismissSearch()
    }

    public func resetToExplore() {
        endNavigation()
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
        destinationText = ""
        searchResults = []
        selectedPlace = nil
        selectedCoordinate = nil
        routeCoordinates = nil
        routeDetails = nil
        appMode = .explore
    }

    public func recenterOnUser() {
        if let user = locationManager.location?.coordinate, isWithinSupportedRegion(user) {
            userLocationCenter = user
        } else {
            userLocationCenter = Self.defaultAlaskaCoordinate
        }
    }

    public func toggleVoiceMute() {
        isVoiceMuted.toggle()
    }

    public func checkMapDataMissing() {
        let pmtilesPath = OfflineDataManager.url(for: "north-america.pmtiles").path
        self.isMapDataMissing = !FileManager.default.fileExists(atPath: pmtilesPath)
    }
}
