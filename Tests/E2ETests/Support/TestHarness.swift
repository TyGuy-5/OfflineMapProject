// TestHarness.swift — Opaque contract models and domain engines for E2E testing

import Foundation
import CoreLocation

// MARK: - Domain Models

public struct OpaqueSearchResult: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let lat: Double
    public let lon: Double
    
    public init(id: Int64, name: String, lat: Double, lon: Double) {
        self.id = id
        self.name = name
        self.lat = lat
        self.lon = lon
    }
    
    public var category: String {
        OpaqueCategoryClassifier.classify(name: name)
    }
    
    public var iconName: String {
        switch category {
        case "gas": return "fuelpump.fill"
        case "coffee": return "cup.and.saucer.fill"
        case "food": return "fork.knife"
        case "hotel": return "bed.double.fill"
        case "parking": return "parkingsign.circle.fill"
        case "park": return "leaf.fill"
        case "hospital": return "cross.case.fill"
        case "airport": return "airplane"
        case "grocery": return "cart.fill"
        default: return "mappin.circle.fill"
        }
    }
    
    public func distanceMiles(from coord: CLLocationCoordinate2D?) -> Double? {
        guard let coord = coord else { return nil }
        let latRad = coord.latitude * .pi / 180.0
        let dx = (lon - coord.longitude) * 111320.0 * cos(latRad)
        let dy = (lat - coord.latitude) * 110540.0
        let meters = sqrt(dx * dx + dy * dy)
        return meters * 0.000621371
    }
    
    public func formattedDistance(from coord: CLLocationCoordinate2D?, useMetric: Bool = false) -> String {
        guard let miles = distanceMiles(from: coord) else {
            return String(format: "%.4f, %.4f", lat, lon)
        }
        if useMetric {
            let meters = miles * 1609.34
            if meters < 1000 {
                return "\(Int(meters)) m away"
            } else {
                return String(format: "%.1f km away", miles * 1.60934)
            }
        } else {
            if miles < 0.1 {
                return "\(Int(miles * 5280)) ft away"
            } else {
                return String(format: "%.1f mi away", miles)
            }
        }
    }
}

public struct OpaqueNavigationStep: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let instruction: String
    public let distanceMiles: Double
    public let durationSeconds: Double
    public let maneuverType: Int
    public let streetName: String?
    public let startIndex: Int
    public let endIndex: Int
    
    public init(
        instruction: String,
        distanceMiles: Double,
        durationSeconds: Double,
        maneuverType: Int,
        streetName: String?,
        startIndex: Int,
        endIndex: Int
    ) {
        self.instruction = instruction
        self.distanceMiles = distanceMiles
        self.durationSeconds = durationSeconds
        self.maneuverType = maneuverType
        self.streetName = streetName
        self.startIndex = startIndex
        self.endIndex = endIndex
    }
    
    public var iconName: String {
        switch maneuverType {
        case 1, 2, 3: return "arrow.up"
        case 4, 5, 6: return "mappin.circle.fill"
        case 8, 22, 23: return "arrow.up"
        case 9: return "arrow.up.right"
        case 10: return "arrow.turn.up.right"
        case 11: return "arrow.down.right"
        case 12: return "arrow.uturn.left"
        case 13: return "arrow.uturn.right"
        case 14: return "arrow.down.left"
        case 15: return "arrow.turn.up.left"
        case 16: return "arrow.up.left"
        case 17, 18, 19, 37, 38: return "arrow.triangle.merge"
        case 20, 21: return "arrow.up.right.and.arrow.down.left.rectangle"
        case 24: return "arrow.up.left"
        case 25: return "arrow.up.right"
        case 26, 27: return "arrow.triangle.capsulepath"
        default: return "arrow.up"
        }
    }
    
    public func formattedDistance(useMetric: Bool) -> String {
        if useMetric {
            let meters = distanceMiles * 1609.34
            if meters < 1000 {
                return "\(Int(meters)) m"
            } else {
                return String(format: "%.1f km", distanceMiles * 1.60934)
            }
        } else {
            if distanceMiles < 0.1 {
                let feet = Int(distanceMiles * 5280)
                return "\(feet) ft"
            } else {
                return String(format: "%.1f mi", distanceMiles)
            }
        }
    }
}

public struct OpaqueRouteDetails: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let coordinates: [CLLocationCoordinate2D]
    public let totalDistanceMiles: Double
    public let totalDurationSeconds: Double
    public let steps: [OpaqueNavigationStep]
    public let costing: String
    public let isFallback: Bool
    public let targetArrivalDate: Date
    
    public init(
        id: UUID = UUID(),
        coordinates: [CLLocationCoordinate2D],
        totalDistanceMiles: Double,
        totalDurationSeconds: Double,
        steps: [OpaqueNavigationStep],
        costing: String,
        isFallback: Bool = false
    ) {
        self.id = id
        self.coordinates = coordinates
        self.totalDistanceMiles = totalDistanceMiles
        self.totalDurationSeconds = totalDurationSeconds
        self.steps = steps
        self.costing = costing
        self.isFallback = isFallback
        self.targetArrivalDate = Date().addingTimeInterval(totalDurationSeconds)
    }
    
    public static func == (lhs: OpaqueRouteDetails, rhs: OpaqueRouteDetails) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Category Classifier & FTS5 Query Expansion (R4.3)

public struct OpaqueCategoryClassifier {
    public static func classify(name: String) -> String {
        let lower = name.lowercased()
        let words = Set(lower.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        
        let gasKeywords: Set<String> = ["gas", "gasoline", "fuel", "oil", "petrol", "chevron", "shell", "exxon", "texaco", "bp", "mobil", "conoco", "tesoro"]
        let coffeeKeywords: Set<String> = ["coffee", "cafe", "espresso", "starbucks", "barista"]
        let foodKeywords: Set<String> = ["restaurant", "restaurants", "pizza", "diner", "grill", "burger", "burgers", "bar", "bakery", "kitchen", "pub", "bistro", "steakhouse", "taco", "sushi", "dining"]
        let hotelKeywords: Set<String> = ["hotel", "motel", "inn", "resort", "suites", "lodge", "hostel"]
        let parkingKeywords: Set<String> = ["parking", "garage"]
        let parkKeywords: Set<String> = ["park", "parks", "trail", "lake", "forest"]
        let hospitalKeywords: Set<String> = ["hospital", "clinic", "medical", "health", "doctor", "pharmacy", "infirmary"]
        let airportKeywords: Set<String> = ["airport", "airfield", "airstrip"]
        // Expanded grocery brands & terms per R4.3
        let groceryKeywords: Set<String> = ["grocery", "groceries", "supermarket", "safeway", "walmart", "costco", "fred", "meyer", "carrs", "coop", "market"]
        
        if !words.isDisjoint(with: gasKeywords) {
            return "gas"
        } else if !words.isDisjoint(with: coffeeKeywords) {
            return "coffee"
        } else if !words.isDisjoint(with: foodKeywords) {
            return "food"
        } else if !words.isDisjoint(with: hotelKeywords) {
            return "hotel"
        } else if !words.isDisjoint(with: parkingKeywords) {
            return "parking"
        } else if !words.isDisjoint(with: parkKeywords) {
            return "park"
        } else if !words.isDisjoint(with: hospitalKeywords) {
            return "hospital"
        } else if !words.isDisjoint(with: airportKeywords) {
            return "airport"
        } else if !words.isDisjoint(with: groceryKeywords) || words.contains("market") {
            return "grocery"
        } else {
            return "place"
        }
    }
    
    public static func expandedFTS5GroceryQuery() -> String {
        return "\"grocery\"* OR \"groceries\"* OR \"supermarket\"* OR \"market\"* OR \"fred\"* OR \"safeway\"* OR \"carrs\"* OR \"costco\"*"
    }
}

// MARK: - Robust Coordinate Parser (R4.2)

public struct OpaqueCoordinateParser {
    public static func parse(query: String) -> CLLocationCoordinate2D? {
        // Regex supporting decimal degrees, degree symbols (°/º/˚), cardinal direction letters (N, S, E, W),
        // optional signs, and variable separator punctuation / whitespace.
        let pattern = #"^\s*([+-]?\d+(?:\.\d+)?)\s*[°º˚]?\s*([NSns]?)\s*[,;\s/]\s*([+-]?\d+(?:\.\d+)?)\s*[°º˚]?\s*([EWew]?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        
        let range = NSRange(query.startIndex..<query.endIndex, in: query)
        guard let match = regex.firstMatch(in: query, options: [], range: range) else {
            return nil
        }
        
        func matchString(at index: Int) -> String {
            guard let r = Range(match.range(at: index), in: query) else { return "" }
            return String(query[r])
        }
        
        let latStr = matchString(at: 1)
        let latDir = matchString(at: 2).uppercased()
        let lonStr = matchString(at: 3)
        let lonDir = matchString(at: 4).uppercased()
        
        guard var lat = Double(latStr), var lon = Double(lonStr) else { return nil }
        
        // Cardinal direction processing
        if latDir == "S" {
            lat = -abs(lat)
        } else if latDir == "N" && lat < 0 {
            lat = -lat // Avoid double negation
        }
        
        if lonDir == "W" {
            lon = -abs(lon)
        } else if lonDir == "E" && lon < 0 {
            lon = -lon
        }
        
        guard lat >= -90.0 && lat <= 90.0, lon >= -180.0 && lon <= 180.0 else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

// MARK: - Telemetry Engine (R2.1, R2.2, R2.5)

public struct OpaqueTelemetryEngine {
    public static func segmentDistanceMeters(p1: CLLocationCoordinate2D, p2: CLLocationCoordinate2D) -> Double {
        let latMid = (p1.latitude + p2.latitude) * 0.5 * .pi / 180.0
        let metersPerDegLat = 111132.95 - 559.82 * cos(2 * latMid) + 1.17 * cos(4 * latMid)
        let metersPerDegLon = 111412.84 * cos(latMid) - 93.5 * cos(3 * latMid)
        let dx = (p2.longitude - p1.longitude) * metersPerDegLon
        let dy = (p2.latitude - p1.latitude) * metersPerDegLat
        return sqrt(dx * dx + dy * dy)
    }
    
    public static func distanceToSegmentMeters(p: CLLocationCoordinate2D, a: CLLocationCoordinate2D, b: CLLocationCoordinate2D) -> Double {
        let latMid = (a.latitude + b.latitude) * 0.5 * .pi / 180.0
        let metersPerDegLat = 111132.95 - 559.82 * cos(2 * latMid) + 1.17 * cos(4 * latMid)
        let metersPerDegLon = 111412.84 * cos(latMid) - 93.5 * cos(3 * latMid)
        let dx = (b.longitude - a.longitude) * metersPerDegLon
        let dy = (b.latitude - a.latitude) * metersPerDegLat
        let segLenSq = dx * dx + dy * dy
        let px = (p.longitude - a.longitude) * metersPerDegLon
        let py = (p.latitude - a.latitude) * metersPerDegLat
        if segLenSq < 1.0 { return sqrt(px * px + py * py) }
        let dot = px * dx + py * dy
        let t = max(0.0, min(1.0, dot / segLenSq))
        let nearestX = t * dx
        let nearestY = t * dy
        let diffX = px - nearestX
        let diffY = py - nearestY
        return sqrt(diffX * diffX + diffY * diffY)
    }
    
    /// Update step and coordinate index for live location, with switchback clamping and dual-point arrival.
    public static func updateStepForLiveLocation(
        userCoord: CLLocationCoordinate2D,
        coords: [CLLocationCoordinate2D],
        steps: [OpaqueNavigationStep],
        currentStepIndex: inout Int,
        currentCoordIndex: inout Int,
        selectedCoordinate: CLLocationCoordinate2D?,
        hasAnnouncedAdvanceTurn: inout Bool,
        spokenInstructions: inout [(text: String, stepId: Int?)]
    ) -> Bool {
        guard !coords.isEmpty else { return false }
        
        // R2.5: Dual-Point Arrival Check
        // Check distance against both road-snapped endpoint (coords.last) and destination pin (selectedCoordinate)
        let distToRoadEnd = segmentDistanceMeters(p1: userCoord, p2: coords.last!)
        let distToPin = selectedCoordinate != nil ? segmentDistanceMeters(p1: userCoord, p2: selectedCoordinate!) : Double.greatestFiniteMagnitude
        let isNearEnd = currentCoordIndex >= max(0, coords.count - 3) || (!steps.isEmpty && currentStepIndex >= steps.count - 1)
        
        if distToRoadEnd < 25.0 || distToPin < 25.0 || (isNearEnd && (distToRoadEnd < 40.0 || distToPin < 40.0)) {
            spokenInstructions.append((text: "You have arrived at your destination.", stepId: nil))
            return true // Arrived!
        }
        
        // R2.1: Switchback Search Clamping
        // Clamped forward coordinate search to current maneuver's end index (+2 vertices slack)
        let currentStepEnd = (!steps.isEmpty && currentStepIndex < steps.count) ? steps[currentStepIndex].endIndex : coords.count - 1
        let searchStart = max(0, currentCoordIndex - 5)
        let searchEnd = min(coords.count - 1, max(currentCoordIndex + 1, currentStepEnd + 2))
        
        var closestIndex = currentCoordIndex
        var minSegDist = Double.greatestFiniteMagnitude
        if searchStart < searchEnd {
            for i in searchStart..<searchEnd {
                let dist = distanceToSegmentMeters(p: userCoord, a: coords[i], b: coords[i + 1])
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
        if !steps.isEmpty && currentStepIndex < steps.count {
            let currentStep = steps[currentStepIndex]
            let endCoord = coords[min(currentStep.endIndex, coords.count - 1)]
            let distToEndMeters = segmentDistanceMeters(p1: userCoord, p2: endCoord)
            
            if (distToEndMeters < 35.0 || currentCoordIndex >= currentStep.endIndex) && currentStepIndex < steps.count - 1 {
                currentStepIndex += 1
                hasAnnouncedAdvanceTurn = false
                currentCoordIndex = max(currentCoordIndex, currentStep.endIndex)
                let nextStep = steps[currentStepIndex]
                spokenInstructions.append((text: nextStep.instruction, stepId: currentStepIndex * 10 + 2))
            } else if currentStepIndex < steps.count - 1 && !hasAnnouncedAdvanceTurn && distToEndMeters < 250.0 {
                hasAnnouncedAdvanceTurn = true
                let nextStep = steps[currentStepIndex + 1]
                spokenInstructions.append((text: "In \(Int(distToEndMeters)) m, \(nextStep.instruction)", stepId: (currentStepIndex + 1) * 10 + 1))
            }
        }
        
        return false
    }
    
    /// R2.2: Monotonic Telemetry Distance Calculation
    /// Remaining step distance counts down monotonically and evaluates to exactly 0.0 when user reaches or passes stepEnd.
    public static func calculateTelemetry(
        userCoord: CLLocationCoordinate2D,
        coordIndex: Int,
        coords: [CLLocationCoordinate2D],
        steps: [OpaqueNavigationStep],
        currentStepIndex: Int,
        totalDistanceMiles: Double,
        totalDurationSeconds: Double
    ) -> (remainingStepDistanceMiles: Double, remainingRouteDistanceMiles: Double, remainingRouteDurationSeconds: Double) {
        guard coords.count >= 2 else {
            return (0.0, 0.0, 0.0)
        }
        let clampedIndex = min(max(0, coordIndex), coords.count - 1)
        
        // 1. Calculate remaining step distance
        let currentStep: OpaqueNavigationStep? = (currentStepIndex < steps.count) ? steps[currentStepIndex] : steps.last
        var stepDistanceMiles: Double = 0.0
        if let currentStep = currentStep {
            let stepEnd = max(0, min(currentStep.endIndex, coords.count - 1))
            if clampedIndex >= stepEnd {
                // At or past step end: strictly zero out, preventing distance reversal!
                stepDistanceMiles = 0.0
            } else {
                var stepDistMeters = segmentDistanceMeters(p1: userCoord, p2: coords[clampedIndex + 1])
                if clampedIndex + 1 < stepEnd {
                    for i in (clampedIndex + 1)..<stepEnd {
                        if i + 1 < coords.count {
                            stepDistMeters += segmentDistanceMeters(p1: coords[i], p2: coords[i + 1])
                        }
                    }
                }
                stepDistanceMiles = max(0.0, stepDistMeters * 0.000621371)
            }
        }
        
        // 2. Remaining total route distance
        var routeDistMeters = 0.0
        if clampedIndex < coords.count - 1 {
            routeDistMeters += segmentDistanceMeters(p1: userCoord, p2: coords[clampedIndex + 1])
            if clampedIndex + 1 < coords.count - 1 {
                for i in (clampedIndex + 1)..<(coords.count - 1) {
                    routeDistMeters += segmentDistanceMeters(p1: coords[i], p2: coords[i + 1])
                }
            }
        } else {
            // At or past final destination waypoint
            routeDistMeters = 0.0
        }
        let routeMiles = max(0.0, routeDistMeters * 0.000621371)
        
        // 3. Proportional remaining duration
        let remainingDuration: Double
        if totalDistanceMiles > 0 {
            let ratio = max(0.0, min(1.0, routeMiles / totalDistanceMiles))
            remainingDuration = totalDurationSeconds * ratio
        } else {
            remainingDuration = 0.0
        }
        
        return (stepDistanceMiles, routeMiles, remainingDuration)
    }
}

// MARK: - Simulation Engine (R2.3)

public struct OpaqueSimulationEngine {
    /// R2.3: Multi-Speed Simulation Loop
    /// Advances currentStepIndex via while loop so 2x and 5x simulation does not skip intermediate maneuvers.
    public static func advanceSimulation(
        coords: [CLLocationCoordinate2D],
        steps: [OpaqueNavigationStep],
        speedMultiplier: Double,
        currentCoordIndex: inout Int,
        currentStepIndex: inout Int,
        spokenTurns: inout [String]
    ) -> Bool {
        guard !coords.isEmpty else { return false }
        guard currentCoordIndex < coords.count - 1 else {
            spokenTurns.append("You have arrived at your destination.")
            return true // Simulation complete
        }
        
        let stepJump = Int(max(1, speedMultiplier))
        let nextIndex = min(coords.count - 1, currentCoordIndex + stepJump)
        currentCoordIndex = nextIndex
        
        // Advance currentStepIndex via loop rather than a single if check
        while !steps.isEmpty && currentStepIndex < steps.count - 1 {
            let nextStep = steps[currentStepIndex + 1]
            if currentCoordIndex >= nextStep.startIndex {
                currentStepIndex += 1
                spokenTurns.append(nextStep.instruction)
            } else {
                break
            }
        }
        return false
    }
}

// MARK: - Audio Concurrency & Voice Guidance Controller (R3.1, R3.2, R3.3)

public final class OpaqueVoiceController: @unchecked Sendable {
    private let voiceLock = NSLock()
    private var _isVoiceMuted: Bool = false
    private var lastSpokenInstruction: String = ""
    private var lastSpokenStepId: Int? = nil
    private var lastSpokenTime: Date = Date.distantPast
    private var activeSpeechGeneration: Int = 0
    private var spokenHistory: [String] = []
    
    public init() {}
    
    public var isVoiceMuted: Bool {
        get {
            voiceLock.lock()
            defer { voiceLock.unlock() }
            return _isVoiceMuted
        }
        set {
            voiceLock.lock()
            _isVoiceMuted = newValue
            if newValue {
                // Muting triggers stopVoice under lock
                activeSpeechGeneration += 1
            }
            voiceLock.unlock()
        }
    }
    
    /// R3.2: stopVoice resets lastSpokenTime to .distantPast, enabling route restarts within 6 seconds
    public func stopVoice() {
        voiceLock.lock()
        defer { voiceLock.unlock() }
        activeSpeechGeneration += 1
        lastSpokenInstruction = ""
        lastSpokenStepId = nil
        lastSpokenTime = Date.distantPast
    }
    
    /// R3.3: speakTurnInstruction with deduplication for both non-nil and nil stepId
    public func speakTurnInstruction(_ text: String, stepId: Int? = nil, force: Bool = false) -> Bool {
        voiceLock.lock()
        defer { voiceLock.unlock() }
        
        guard !_isVoiceMuted && !text.isEmpty else {
            return false
        }
        
        let now = Date()
        let isSameText = (text == lastSpokenInstruction)
        // Deduplicate if stepId matches OR if both stepIds are nil and text matches within 6 seconds
        let isSameStep = (stepId != nil && stepId == lastSpokenStepId) || (stepId == nil && lastSpokenStepId == nil)
        let timeSinceLastPrompt = now.timeIntervalSince(lastSpokenTime)
        
        if !force && isSameText && isSameStep && timeSinceLastPrompt < 6.0 {
            return false // Dropped duplicate
        }
        
        lastSpokenInstruction = text
        lastSpokenStepId = stepId
        lastSpokenTime = now
        activeSpeechGeneration += 1
        spokenHistory.append(text)
        return true
    }
    
    public func getSpokenHistory() -> [String] {
        voiceLock.lock()
        defer { voiceLock.unlock() }
        return spokenHistory
    }
    
    public func resetHistory() {
        voiceLock.lock()
        defer { voiceLock.unlock() }
        spokenHistory.removeAll()
    }
}

// MARK: - Location Telemetry & Degradation Observer (R2.6)

public final class OpaqueLocationObserver: @unchecked Sendable {
    private let lock = NSLock()
    private var _smoothedSpeedMph: Int = 0
    private var _isStationary: Bool = true
    private var _isGpsSignalLow: Bool = false
    
    public init() {}
    
    public var smoothedSpeedMph: Int {
        lock.lock()
        defer { lock.unlock() }
        return _smoothedSpeedMph
    }
    
    public var isStationary: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isStationary
    }
    
    public var isGpsSignalLow: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isGpsSignalLow
    }
    
    /// R2.6: Zero smoothed speed and set stationary state when GPS accuracy degrades
    public func processLocationFix(horizontalAccuracy: Double, rawSpeedMps: Double, ageSeconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        
        // Discard stale fixes older than 15s without warning
        if ageSeconds >= 15.0 {
            return
        }
        
        if horizontalAccuracy < 0 || horizontalAccuracy >= 65.0 {
            _isGpsSignalLow = true
            _smoothedSpeedMph = 0
            _isStationary = true
        } else {
            _isGpsSignalLow = false
            let speedMph = max(0, Int(rawSpeedMps * 2.23694))
            _smoothedSpeedMph = speedMph
            _isStationary = (speedMph == 0)
        }
    }
}

// MARK: - Reverse Geocoder Full-Scan Engine (R4.1)

public struct OpaqueReverseGeocoder {
    /// R4.1: Scans full bounding box candidate list without premature < 25m break, selecting true closest candidate
    public static func findClosestPOI(queryCoord: CLLocationCoordinate2D, candidates: [OpaqueSearchResult]) -> OpaqueSearchResult? {
        var closest: OpaqueSearchResult? = nil
        var minDistanceMeters = Double.greatestFiniteMagnitude
        let latRad = queryCoord.latitude * .pi / 180.0
        let cosLat = cos(latRad)
        
        for candidate in candidates {
            let dx = (candidate.lon - queryCoord.longitude) * 111320.0 * cosLat
            let dy = (candidate.lat - queryCoord.latitude) * 110540.0
            let d = sqrt(dx * dx + dy * dy)
            if d < minDistanceMeters {
                minDistanceMeters = d
                closest = candidate
            }
            // Notice: NO break at < 25.0 meters! Scans all candidates in bounding box.
        }
        return closest
    }
}

// MARK: - MapView Coordinator State Tracker (R5.1, R5.2)

public final class OpaqueMapViewCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    public var isRecenterConsumed: Bool = false
    public var isZoomStepConsumed: Bool = false
    public var lastDrawnRouteCoordinates: [CLLocationCoordinate2D]? = nil
    public var redrawCount: Int = 0
    public var centerAnimationCount: Int = 0
    public var zoomAnimationCount: Int = 0
    
    public init() {}
    
    /// R5.1: Recenter and zoom step consumption deduplication
    public func applyRecenter(coordinate: CLLocationCoordinate2D?) {
        lock.lock()
        defer { lock.unlock() }
        guard let _ = coordinate, !isRecenterConsumed else { return }
        isRecenterConsumed = true
        centerAnimationCount += 1
    }
    
    public func applyZoomStep(step: Double?) {
        lock.lock()
        defer { lock.unlock() }
        guard let _ = step, !isZoomStepConsumed else { return }
        isZoomStepConsumed = true
        zoomAnimationCount += 1
    }
    
    /// R5.2: Complete O(N) coordinate equality check on route coordinates
    public func updateRouteCoordinates(newRoute: [CLLocationCoordinate2D]) {
        lock.lock()
        defer { lock.unlock() }
        
        let hasChanged: Bool = {
            guard let last = lastDrawnRouteCoordinates else { return true }
            if last.count != newRoute.count { return true }
            for i in 0..<newRoute.count {
                if abs(last[i].latitude - newRoute[i].latitude) > 0.00001 ||
                   abs(last[i].longitude - newRoute[i].longitude) > 0.00001 {
                    return true
                }
            }
            return false
        }()
        
        if hasChanged {
            lastDrawnRouteCoordinates = newRoute
            redrawCount += 1
        }
    }
}

// MARK: - Scoped Backup Exclusion Tracker (R6.3)

public struct OpaqueBackupExclusionManager {
    /// R6.3: Excludes only offline map asset files in Documents, preserving user documents root
    public static func isAssetExcluded(filename: String) -> Bool {
        let assetExtensions = [".pmtiles", ".tar", ".db", ".json"]
        let lower = filename.lowercased()
        for ext in assetExtensions {
            if lower.hasSuffix(ext) {
                return true
            }
        }
        return false
    }
}
