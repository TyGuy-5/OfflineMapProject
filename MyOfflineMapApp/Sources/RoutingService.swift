import Foundation
import CoreLocation
import AVFoundation
import Valhalla
import ValhallaModels

public struct NavigationStep: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let instruction: String
    public let distanceMiles: Double
    public let durationSeconds: Double
    public let maneuverType: Int
    public let streetName: String?
    public let startIndex: Int
    public let endIndex: Int

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

    public var formattedDistance: String {
        formattedDistance(useMetric: false)
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

public struct RouteDetails: Identifiable, Equatable, @unchecked Sendable {
    public let id: UUID
    public let coordinates: [CLLocationCoordinate2D]
    public let totalDistanceMiles: Double
    public let totalDurationSeconds: Double
    public let steps: [NavigationStep]
    public let costing: String
    public let isFallback: Bool
    public let targetArrivalDate: Date

    public init(
        id: UUID = UUID(),
        coordinates: [CLLocationCoordinate2D],
        totalDistanceMiles: Double,
        totalDurationSeconds: Double,
        steps: [NavigationStep],
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

    public static func == (lhs: RouteDetails, rhs: RouteDetails) -> Bool {
        lhs.id == rhs.id
    }

    public var formattedDuration: String {
        let minutes = Int(totalDurationSeconds / 60)
        if minutes < 60 {
            return "\(max(1, minutes)) min"
        } else {
            let hours = minutes / 60
            let remMin = minutes % 60
            return "\(hours) hr \(remMin) min"
        }
    }

    public var formattedDistance: String {
        formattedDistance(useMetric: false)
    }

    public func formattedDistance(useMetric: Bool) -> String {
        if useMetric {
            return String(format: "%.1f km", totalDistanceMiles * 1.60934)
        } else {
            return String(format: "%.1f mi", totalDistanceMiles)
        }
    }

    private static let etaFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    public var formattedETA: String {
        RouteDetails.etaFormatter.string(from: targetArrivalDate)
    }
}

public final class RoutingService: NSObject, @unchecked Sendable, AVSpeechSynthesizerDelegate, ObservableObject {
    private var valhalla: Valhalla?
    private var isInitializing = false
    private let initGroup = DispatchGroup()
    private let queue = DispatchQueue(label: "com.offline.routing", qos: .userInitiated)

    public var isEngineReady: Bool {
        queue.sync { valhalla != nil }
    }

    // Voice Guidance State (Thread Confined)
    private let speechSynthesizer = AVSpeechSynthesizer()
    @Published public var isVoiceMuted: Bool = false {
        didSet {
            if isVoiceMuted {
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
        voiceLock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.speechSynthesizer.stopSpeaking(at: .immediate)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    public override init() {
        super.init()
        speechSynthesizer.delegate = self
        initGroup.enter()
        queue.async {
            self.setupValhalla()
            self.initGroup.leave()
        }
    }

    private func setupValhalla() {
        guard valhalla == nil && !isInitializing else { return }
        isInitializing = true
        defer { isInitializing = false }

        let configURL = OfflineDataManager.url(for: "valhalla.json")
        let tarCandidates = [
            "alaska_tiles.tar",
            "valhalla_tiles_indexed.tar",
            "valhalla_tiles.tar"
        ]
        var selectedTarURL: URL?
        for candidate in tarCandidates {
            let u = OfflineDataManager.url(for: candidate)
            if FileManager.default.fileExists(atPath: u.path) {
                if candidate == "valhalla_tiles.tar", let attrs = try? FileManager.default.attributesOfItem(atPath: u.path), let size = attrs[.size] as? UInt64, size > 10_000_000_000 {
                    print("RoutingService WARN: Skipping raw full extract \(candidate) due to size (\(size) bytes) exceeding mobile budget.")
                    continue
                }
                selectedTarURL = u
                break
            }
        }

        guard let tarURL = selectedTarURL, FileManager.default.fileExists(atPath: tarURL.path) else {
            print("RoutingService ERROR: No Valhalla tile tar found!")
            return
        }

        print("RoutingService: Selected tile tar extract at: \(tarURL.path)")

        guard let configData = try? Data(contentsOf: configURL),
              var configJson = (try? JSONSerialization.jsonObject(with: configData)) as? [String: Any] else {
            print("RoutingService ERROR: Failed to load valhalla.json from \(configURL.path)")
            return
        }

        var mjolnir = configJson["mjolnir"] as? [String: Any] ?? [String: Any]()
        mjolnir["tile_extract"] = tarURL.path

        let tempTilesDir = FileManager.default.temporaryDirectory.appendingPathComponent("valhalla_tiles")
        try? FileManager.default.createDirectory(at: tempTilesDir, withIntermediateDirectories: true)
        mjolnir["tile_dir"] = tempTilesDir.path

        mjolnir.removeValue(forKey: "admin")
        mjolnir.removeValue(forKey: "timezone")
        mjolnir.removeValue(forKey: "traffic_extract")
        mjolnir.removeValue(forKey: "landmarks")
        mjolnir.removeValue(forKey: "transit_dir")
        mjolnir.removeValue(forKey: "transit_feeds_dir")

        var dataProc = mjolnir["data_processing"] as? [String: Any] ?? [String: Any]()
        dataProc["use_admin_db"] = false
        let isIndexedTar = tarURL.lastPathComponent.contains("indexed") || tarURL.lastPathComponent == "alaska_tiles.tar"
        dataProc["scan_tar"] = !isIndexedTar
        mjolnir["data_processing"] = dataProc

        // Mobile memory limits
        mjolnir["max_cache_size"] = 33554432
        configJson["mjolnir"] = mjolnir

        var addData = configJson["additional_data"] as? [String: Any] ?? [String: Any]()
        addData.removeValue(forKey: "elevation")
        configJson["additional_data"] = addData

        var loki = configJson["loki"] as? [String: Any] ?? [String: Any]()
        loki["use_connectivity"] = false
        var lokiDefaults = loki["service_defaults"] as? [String: Any] ?? [String: Any]()
        lokiDefaults["radius"] = 500
        lokiDefaults["minimum_reachability"] = 0
        lokiDefaults["search_cutoff"] = 100000
        lokiDefaults["node_snap_tolerance"] = 25
        lokiDefaults["street_side_tolerance"] = 25
        loki["service_defaults"] = lokiDefaults
        configJson["loki"] = loki

        var thor = configJson["thor"] as? [String: Any] ?? [String: Any]()
        thor["clear_reserved_memory"] = true
        thor["max_reserved_labels_count_dijkstras"] = 250000
        thor["max_reserved_labels_count_bidir_dijkstras"] = 150000
        configJson["thor"] = thor

        var serviceLimits = configJson["service_limits"] as? [String: Any] ?? [String: Any]()
        if var auto = serviceLimits["auto"] as? [String: Any] {
            auto["max_distance"] = 1000000.0
            serviceLimits["auto"] = auto
        }
        configJson["service_limits"] = serviceLimits

        configJson.removeValue(forKey: "httpd")
        configJson.removeValue(forKey: "statsd")

        do {
            let tempConfigURL = FileManager.default.temporaryDirectory.appendingPathComponent("valhalla_runtime.json")
            let patchedData = try JSONSerialization.data(withJSONObject: configJson, options: [.prettyPrinted])
            try patchedData.write(to: tempConfigURL)
            self.valhalla = try Valhalla(configPath: tempConfigURL.path)
            print("RoutingService: Valhalla offline routing engine initialized successfully!")
        } catch {
            print("RoutingService ERROR: Failed to initialize Valhalla: \(error)")
        }
    }

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

            let costingModel: CostingModel
            switch mode.lowercased() {
            case "pedestrian", "walk":
                costingModel = .pedestrian
            case "bicycle", "bike":
                costingModel = .bicycle
            default:
                costingModel = .auto
            }

            guard let valhalla = self.valhalla else {
                print("RoutingService ERROR: Valhalla offline routing engine not initialized.")
                return nil
            }

            let units: DistanceUnit = useMetric ? .km : .mi
            let routeRequest = RouteRequest(
                locations: [
                    RoutingWaypoint(lat: start.latitude, lon: start.longitude),
                    RoutingWaypoint(lat: destination.latitude, lon: destination.longitude)
                ],
                costing: costingModel,
                units: units
            )

            do {
                let routeResponse = try valhalla.route(request: routeRequest)
                guard let firstLeg = routeResponse.trip.legs.first else {
                    print("RoutingService WARN: No trip legs returned by Valhalla engine.")
                    return nil
                }

                let coords = self.decodePolyline6(firstLeg.shape)
                guard !coords.isEmpty else {
                    print("RoutingService WARN: Empty shape coordinates returned by Valhalla.")
                    return nil
                }

                var navSteps: [NavigationStep] = []
                for m in firstLeg.maneuvers {
                    let stepDistMiles = useMetric ? (m.length / 1.60934) : m.length
                    let step = NavigationStep(
                        instruction: m.instruction,
                        distanceMiles: stepDistMiles,
                        durationSeconds: m.time,
                        maneuverType: m.type,
                        streetName: m.streetNames?.first,
                        startIndex: m.beginShapeIndex,
                        endIndex: m.endShapeIndex
                    )
                    navSteps.append(step)
                }

                let totalDistanceMiles = useMetric ? (firstLeg.summary.length / 1.60934) : firstLeg.summary.length
                let totalTime = firstLeg.summary.time

                print("RoutingService: Successfully calculated real road route! (\(coords.count) coordinates, \(navSteps.count) maneuvers, \(String(format: "%.2f", totalDistanceMiles)) mi)")

                return RouteDetails(
                    coordinates: coords,
                    totalDistanceMiles: totalDistanceMiles,
                    totalDurationSeconds: totalTime,
                    steps: navSteps,
                    costing: mode,
                    isFallback: false
                )
            } catch {
                print("RoutingService ERROR: Valhalla route error (\(error)) - returning explicit failure.")
                return nil
            }
        }
    }

    // MARK: - Fast Allocation-Free Off-Route Detection
    public func isUserOffRoute(
        userLocation: CLLocationCoordinate2D,
        routeCoordinates: [CLLocationCoordinate2D],
        thresholdMeters: Double = 35.0,
        activeCoordIndex: Int? = nil
    ) -> Bool {
        guard routeCoordinates.count >= 2 else { return false }

        // Localized search window when active progress is known to avoid O(N) full-route scan
        let startIndex: Int
        let endIndex: Int
        if let current = activeCoordIndex {
            startIndex = max(0, current - 5)
            endIndex = min(routeCoordinates.count - 1, current + 35)
        } else {
            startIndex = 0
            endIndex = routeCoordinates.count - 1
        }

        var minDistance = Double.greatestFiniteMagnitude
        for i in startIndex..<endIndex {
            let dist = distanceToSegmentMeters(p: userLocation, a: routeCoordinates[i], b: routeCoordinates[i + 1])
            if dist < minDistance {
                minDistance = dist
            }
        }

        // If local window exceeds threshold and we were using a subset, double check full route
        if minDistance > thresholdMeters && activeCoordIndex != nil {
            for i in 0..<(routeCoordinates.count - 1) {
                let dist = distanceToSegmentMeters(p: userLocation, a: routeCoordinates[i], b: routeCoordinates[i + 1])
                if dist < minDistance {
                    minDistance = dist
                }
            }
        }

        return minDistance > thresholdMeters
    }

    /// Fast flat-Earth projection distance with ZERO heap allocations
    public func distanceToSegmentMeters(
        p: CLLocationCoordinate2D,
        a: CLLocationCoordinate2D,
        b: CLLocationCoordinate2D
    ) -> Double {
        let latRad = a.latitude * .pi / 180.0
        let cosLat = cos(latRad)
        let metersPerDegLon = 111320.0 * cosLat
        let metersPerDegLat = 110540.0

        let dx = (b.longitude - a.longitude) * metersPerDegLon
        let dy = (b.latitude - a.latitude) * metersPerDegLat
        let segLenSq = dx * dx + dy * dy

        let px = (p.longitude - a.longitude) * metersPerDegLon
        let py = (p.latitude - a.latitude) * metersPerDegLat

        if segLenSq < 1.0 {
            return sqrt(px * px + py * py)
        }

        let dot = px * dx + py * dy
        let t = max(0.0, min(1.0, dot / segLenSq))

        let nearestX = t * dx
        let nearestY = t * dy

        let diffX = px - nearestX
        let diffY = py - nearestY
        return sqrt(diffX * diffX + diffY * diffY)
    }

    // MARK: - Voice Navigation & Audio Session Management
    public func speakTurnInstruction(_ text: String, stepId: Int? = nil, force: Bool = false) {
        voiceLock.lock()
        guard !isVoiceMuted && !text.isEmpty else {
            voiceLock.unlock()
            return
        }

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
        activeSpeechGeneration += 1
        let generation = activeSpeechGeneration
        voiceLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.voiceLock.lock()
            let currentGen = self.activeSpeechGeneration
            self.voiceLock.unlock()

            guard generation == currentGen, !self.isVoiceMuted else { return }

            if force || self.speechSynthesizer.isSpeaking {
                self.speechSynthesizer.stopSpeaking(at: .immediate)
            }
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)

            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")

            self.voiceLock.lock()
            self.utteranceGenerations[ObjectIdentifier(utterance)] = generation
            self.voiceLock.unlock()

            self.speechSynthesizer.speak(utterance)
        }
    }

    // AVSpeechSynthesizerDelegate: Deactivate audio session to restore background music / media volume
    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        voiceLock.lock()
        let generation = utteranceGenerations.removeValue(forKey: ObjectIdentifier(utterance)) ?? activeSpeechGeneration
        voiceLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.voiceLock.lock()
            let currentGen = self.activeSpeechGeneration
            self.voiceLock.unlock()

            // If a newer prompt has been scheduled since this completion was posted, do not deactivate
            guard generation == currentGen else { return }
            // Re-verify synthesizer speaking state on main queue before calling setActive(false)
            guard !self.speechSynthesizer.isSpeaking else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        voiceLock.lock()
        let generation = utteranceGenerations.removeValue(forKey: ObjectIdentifier(utterance)) ?? activeSpeechGeneration
        voiceLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.voiceLock.lock()
            let currentGen = self.activeSpeechGeneration
            self.voiceLock.unlock()

            // If a newer prompt has been scheduled since this cancellation was posted, do not deactivate
            guard generation == currentGen else { return }
            // Re-verify synthesizer speaking state on main queue before calling setActive(false)
            guard !self.speechSynthesizer.isSpeaking else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }


    private func decodePolyline6(_ polyline: String) -> [CLLocationCoordinate2D] {
        var coordinates = [CLLocationCoordinate2D]()
        let bytes = Array(polyline.utf8)
        var index = 0
        var lat = 0
        var lon = 0

        while index < bytes.count {
            var byte = 0
            var shift = 0
            var result = 0
            while index < bytes.count {
                byte = Int(bytes[index]) - 63
                index += 1
                result |= (byte & 0x1f) << shift
                shift += 5
                if byte < 0x20 { break }
            }
            if shift == 0 { break }
            lat += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1))

            shift = 0
            result = 0
            while index < bytes.count {
                byte = Int(bytes[index]) - 63
                index += 1
                result |= (byte & 0x1f) << shift
                shift += 5
                if byte < 0x20 { break }
            }
            if shift == 0 { break }
            lon += ((result & 1) != 0 ? ~(result >> 1) : (result >> 1))

            coordinates.append(CLLocationCoordinate2D(latitude: Double(lat) / 1e6, longitude: Double(lon) / 1e6))
        }
        return coordinates
    }
}
