import Foundation
import CoreLocation

/// Errors thrown by GPXParser.
public enum GPXParserError: LocalizedError, Equatable {
    case emptyData
    case corruptedXML(String)
    case xmlParsingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .emptyData:
            return "GPX data is empty or contains only whitespace."
        case .corruptedXML(let message):
            return "Corrupted GPX XML structure: \(message)"
        case .xmlParsingFailed(let message):
            return "GPX parsing failed: \(message)"
        }
    }
}

/// A high-performance, native XML parser for GPX 1.0 and 1.1 files using Foundation.XMLParser.
/// Supports tracks (<trk>/<trkseg>/<trkpt>), routes (<rte>/<rtept>), elevation, timestamps,
/// multi-segment trails, cumulative geodesic distance, and bounding box computation.
///
/// Thread-safe and re-entrant: Each parse invocation allocates a private delegate instance
/// so concurrent calls on a single GPXParser instance never collide or corrupt state.
public class GPXParser: NSObject, @unchecked Sendable {
    
    // MARK: - Date Formatters
    
    fileprivate static let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    fileprivate static let iso8601StandardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    fileprivate static let fallbackDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return formatter
    }()
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
    }
    
    // MARK: - Public API
    
    /// Parses GPX data from a file URL.
    public func parse(fileURL: URL) throws -> GPXTrack {
        let data = try Data(contentsOf: fileURL)
        return try parse(data: data, fileURL: fileURL)
    }
    
    /// Parses GPX data from an XML string.
    public func parse(xmlString: String, fileURL: URL? = nil) throws -> GPXTrack {
        guard let data = xmlString.data(using: .utf8) else {
            throw GPXParserError.corruptedXML("Unable to encode string as UTF-8")
        }
        return try parse(data: data, fileURL: fileURL)
    }
    
    /// Parses raw GPX Data into a single GPXTrack.
    /// If multiple tracks are present, combines all points into a unified track.
    public func parse(data: Data, fileURL: URL? = nil) throws -> GPXTrack {
        let (tracks, metadataName, metadataDesc) = try parseTracksWithMetadata(data: data, fileURL: fileURL)
        
        if tracks.isEmpty {
            // Return empty track if no track or route elements found
            let fallbackName = fileURL?.deletingPathExtension().lastPathComponent ?? metadataName ?? "Imported Trail"
            return GPXTrack(
                name: fallbackName,
                trackDescription: metadataDesc,
                points: [],
                totalDistance: 0.0,
                elevationGain: 0.0,
                elevationLoss: 0.0,
                minElevation: nil,
                maxElevation: nil,
                bounds: .zero,
                fileURL: fileURL,
                date: nil
            )
        }
        
        if tracks.count == 1 {
            return tracks[0]
        }
        
        // Multi-track: Combine all points into a single cohesive track
        var combinedPoints: [GPXTrackPoint] = []
        var totalGain: Double = 0.0
        var totalLoss: Double = 0.0
        var minEle: Double? = nil
        var maxEle: Double? = nil
        
        for track in tracks {
            for pt in track.points {
                let dist: Double
                if let lastPt = combinedPoints.last {
                    let segDist = Self.haversineDistance(
                        lat1: lastPt.coordinate.latitude, lon1: lastPt.coordinate.longitude,
                        lat2: pt.coordinate.latitude, lon2: pt.coordinate.longitude
                    )
                    dist = lastPt.cumulativeDistance + segDist
                } else {
                    dist = 0.0
                }
                combinedPoints.append(GPXTrackPoint(
                    coordinate: pt.coordinate,
                    elevation: pt.elevation,
                    time: pt.time,
                    cumulativeDistance: dist
                ))
            }
            totalGain += track.elevationGain
            totalLoss += track.elevationLoss
            if let tMin = track.minElevation {
                minEle = (minEle != nil) ? min(minEle!, tMin) : tMin
            }
            if let tMax = track.maxElevation {
                maxEle = (maxEle != nil) ? max(maxEle!, tMax) : tMax
            }
        }
        let totalDist = combinedPoints.last?.cumulativeDistance ?? 0.0
        let bounds = Self.calculateBounds(for: combinedPoints)
        let primaryName = tracks.first?.name ?? fileURL?.deletingPathExtension().lastPathComponent ?? "Combined Trail"
        
        return GPXTrack(
            name: primaryName,
            trackDescription: metadataDesc ?? tracks.first?.trackDescription,
            points: combinedPoints,
            totalDistance: totalDist,
            elevationGain: totalGain,
            elevationLoss: totalLoss,
            minElevation: minEle,
            maxElevation: maxEle,
            bounds: bounds,
            fileURL: fileURL,
            date: combinedPoints.first?.time
        )
    }
    
    /// Parses raw GPX Data into an array of distinct GPXTrack instances.
    public func parseTracks(data: Data, fileURL: URL? = nil) throws -> [GPXTrack] {
        let (tracks, _, _) = try parseTracksWithMetadata(data: data, fileURL: fileURL)
        return tracks
    }
    
    // MARK: - Internal Isolated Parsing
    
    private func parseTracksWithMetadata(
        data: Data,
        fileURL: URL? = nil
    ) throws -> (tracks: [GPXTrack], metadataName: String?, metadataDesc: String?) {
        guard !data.isEmpty else {
            throw GPXParserError.emptyData
        }
        
        // Check for all-whitespace data
        if let string = String(data: data, encoding: .utf8),
           string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw GPXParserError.emptyData
        }
        
        let delegate = GPXParserDelegate(fileURL: fileURL)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        
        let success = parser.parse()
        
        if let error = delegate.parserError {
            throw GPXParserError.corruptedXML(error.localizedDescription)
        }
        
        if !success, let parserError = parser.parserError {
            throw GPXParserError.xmlParsingFailed(parserError.localizedDescription)
        }
        
        let tracks = delegate.buildResultTracks()
        return (tracks, delegate.metadataName, delegate.metadataDesc)
    }
    
    // MARK: - Mathematical Calculations
    
    /// Calculates the great-circle distance between two coordinates using the Haversine formula (meters).
    /// Numerical precision clamping prevents sqrt(1 - a) evaluating to NaN on edge-case coordinates.
    public static func haversineDistance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let lat1Rad = lat1 * .pi / 180.0
        let lon1Rad = lon1 * .pi / 180.0
        let lat2Rad = lat2 * .pi / 180.0
        let lon2Rad = lon2 * .pi / 180.0
        
        let dLat = lat2Rad - lat1Rad
        let dLon = lon2Rad - lon1Rad
        
        let a = sin(dLat / 2.0) * sin(dLat / 2.0) +
                cos(lat1Rad) * cos(lat2Rad) *
                sin(dLon / 2.0) * sin(dLon / 2.0)
        let clampedA = min(1.0, max(0.0, a))
        let c = 2.0 * atan2(sqrt(clampedA), sqrt(1.0 - clampedA))
        let earthRadiusMeters = 6371000.0
        return earthRadiusMeters * c
    }
    
    /// Computes the bounding box for a set of track points.
    public static func calculateBounds(for points: [GPXTrackPoint]) -> GPXBounds {
        guard !points.isEmpty else {
            return .zero
        }
        
        var minLat = points[0].coordinate.latitude
        var maxLat = points[0].coordinate.latitude
        var minLon = points[0].coordinate.longitude
        var maxLon = points[0].coordinate.longitude
        
        for pt in points {
            let lat = pt.coordinate.latitude
            let lon = pt.coordinate.longitude
            if lat < minLat { minLat = lat }
            if lat > maxLat { maxLat = lat }
            if lon < minLon { minLon = lon }
            if lon > maxLon { maxLon = lon }
        }
        
        return GPXBounds(
            minLatitude: minLat,
            maxLatitude: maxLat,
            minLongitude: minLon,
            maxLongitude: maxLon
        )
    }
    
    // MARK: - Date Parsing Helper
    
    /// Gracefully parses ISO8601 or RFC 3339 timestamps. Returns nil on failure without crashing.
    public static func parseDate(_ string: String) -> Date? {
        if let date = iso8601FractionalFormatter.date(from: string) {
            return date
        }
        if let date = iso8601StandardFormatter.date(from: string) {
            return date
        }
        if let date = fallbackDateFormatter.date(from: string) {
            return date
        }
        return nil
    }
}

// MARK: - Isolated XMLParserDelegate

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    
    let fileURL: URL?
    var parserError: Error?
    
    var metadataName: String?
    var metadataDesc: String?
    
    private var currentElement: String = ""
    private var currentText: String = ""
    
    // Hierarchy flags
    private var inMetadata: Bool = false
    private var inTrack: Bool = false
    private var inRoute: Bool = false
    private var inTrackSegment: Bool = false
    private var inPoint: Bool = false
    
    // Current Track / Route metadata
    private var currentTrackName: String?
    private var currentTrackDesc: String?
    private var currentRouteName: String?
    private var currentRouteDesc: String?
    
    // Current Point parsing
    private var currentLat: Double?
    private var currentLon: Double?
    private var currentEle: Double?
    private var currentTime: Date?
    
    // Parsed points accumulators
    private var currentTrackPoints: [GPXTrackPoint] = []
    private var currentRoutePoints: [GPXTrackPoint] = []
    
    // Cumulative metrics for current track
    private var cumulativeDistance: Double = 0.0
    private var previousCoordinate: CLLocationCoordinate2D?
    private var previousElevation: Double?
    private var totalElevationGain: Double = 0.0
    private var totalElevationLoss: Double = 0.0
    private var minElevation: Double?
    private var maxElevation: Double?
    
    // Output tracks
    private var parsedTracks: [GPXTrack] = []
    
    init(fileURL: URL?) {
        self.fileURL = fileURL
        super.init()
    }
    
    func buildResultTracks() -> [GPXTrack] {
        // If no <trk> elements were present, but <rte> was found, build track from route
        if parsedTracks.isEmpty && !currentRoutePoints.isEmpty {
            let routeTrack = buildTrack(
                name: currentRouteName ?? metadataName ?? fileURL?.deletingPathExtension().lastPathComponent ?? "Route Trail",
                description: currentRouteDesc ?? metadataDesc,
                points: currentRoutePoints,
                gain: totalElevationGain,
                loss: totalElevationLoss,
                minEle: minElevation,
                maxEle: maxElevation
            )
            return [routeTrack]
        }
        return parsedTracks
    }
    
    // MARK: - XMLParserDelegate Callbacks
    
    func parserDidStartDocument(_ parser: XMLParser) {
        // Document started
    }
    
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let tag = elementName.lowercased()
        currentElement = tag
        currentText = ""
        
        switch tag {
        case "metadata":
            inMetadata = true
            
        case "trk":
            inTrack = true
            currentTrackName = nil
            currentTrackDesc = nil
            currentTrackPoints = []
            cumulativeDistance = 0.0
            previousCoordinate = nil
            previousElevation = nil
            totalElevationGain = 0.0
            totalElevationLoss = 0.0
            minElevation = nil
            maxElevation = nil
            
        case "trkseg":
            inTrackSegment = true
            
        case "rte":
            inRoute = true
            currentRouteName = nil
            currentRouteDesc = nil
            currentRoutePoints = []
            cumulativeDistance = 0.0
            previousCoordinate = nil
            previousElevation = nil
            totalElevationGain = 0.0
            totalElevationLoss = 0.0
            minElevation = nil
            maxElevation = nil
            
        case "trkpt", "rtept":
            inPoint = true
            currentLat = extractCoordinate(from: attributeDict, key: "lat")
            currentLon = extractCoordinate(from: attributeDict, key: "lon")
            currentEle = nil
            currentTime = nil
            
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }
    
    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let tag = elementName.lowercased()
        let trimmedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch tag {
        case "name":
            if inPoint {
                // Point-specific name; not track name
            } else if inTrack {
                if currentTrackName == nil && !trimmedText.isEmpty {
                    currentTrackName = trimmedText
                }
            } else if inRoute {
                if currentRouteName == nil && !trimmedText.isEmpty {
                    currentRouteName = trimmedText
                }
            } else if inMetadata {
                if metadataName == nil && !trimmedText.isEmpty {
                    metadataName = trimmedText
                }
            }
            
        case "desc":
            if inPoint {
                // Point description
            } else if inTrack {
                if currentTrackDesc == nil && !trimmedText.isEmpty {
                    currentTrackDesc = trimmedText
                }
            } else if inRoute {
                if currentRouteDesc == nil && !trimmedText.isEmpty {
                    currentRouteDesc = trimmedText
                }
            } else if inMetadata {
                if metadataDesc == nil && !trimmedText.isEmpty {
                    metadataDesc = trimmedText
                }
            }
            
        case "ele":
            if inPoint && !trimmedText.isEmpty {
                if let val = Double(trimmedText), val.isFinite {
                    currentEle = val
                } else {
                    currentEle = nil
                }
            }
            
        case "time":
            if inPoint && !trimmedText.isEmpty {
                currentTime = GPXParser.parseDate(trimmedText)
            }
            
        case "trkpt", "rtept":
            if inPoint {
                processPoint()
                inPoint = false
            }
            
        case "trkseg":
            inTrackSegment = false
            
        case "trk":
            if inTrack {
                let trackName = currentTrackName ?? metadataName ?? fileURL?.deletingPathExtension().lastPathComponent ?? "Imported Trail"
                let track = buildTrack(
                    name: trackName,
                    description: currentTrackDesc ?? metadataDesc,
                    points: currentTrackPoints,
                    gain: totalElevationGain,
                    loss: totalElevationLoss,
                    minEle: minElevation,
                    maxEle: maxElevation
                )
                parsedTracks.append(track)
                inTrack = false
            }
            
        case "rte":
            inRoute = false
            
        case "metadata":
            inMetadata = false
            
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parserError = parseError
    }
    
    // MARK: - Point Processing
    
    private func processPoint() {
        guard let lat = currentLat, let lon = currentLon else {
            return
        }
        
        // Defensive validation against NaN, Inf, and out-of-range coordinates
        guard lat.isFinite && lon.isFinite && (-90.0...90.0).contains(lat) && (-180.0...180.0).contains(lon) else {
            return
        }
        
        let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        
        // Calculate segment distance and cumulative distance
        if let prev = previousCoordinate {
            let segDist = GPXParser.haversineDistance(
                lat1: prev.latitude, lon1: prev.longitude,
                lat2: coord.latitude, lon2: coord.longitude
            )
            cumulativeDistance += segDist
        }
        previousCoordinate = coord
        
        // Calculate elevation metrics (only if finite)
        if let ele = currentEle, ele.isFinite {
            if let minE = minElevation {
                minElevation = min(minE, ele)
            } else {
                minElevation = ele
            }
            if let maxE = maxElevation {
                maxElevation = max(maxE, ele)
            } else {
                maxElevation = ele
            }
            
            if let prevEle = previousElevation {
                let diff = ele - prevEle
                if diff > 0 {
                    totalElevationGain += diff
                } else if diff < 0 {
                    totalElevationLoss += (-diff)
                }
            }
            previousElevation = ele
        }
        
        let validElevation = (currentEle?.isFinite == true) ? currentEle : nil
        let point = GPXTrackPoint(
            coordinate: coord,
            elevation: validElevation,
            time: currentTime,
            cumulativeDistance: cumulativeDistance
        )
        
        if inTrack {
            currentTrackPoints.append(point)
        } else if inRoute {
            currentRoutePoints.append(point)
        }
    }
    
    private func buildTrack(
        name: String,
        description: String?,
        points: [GPXTrackPoint],
        gain: Double,
        loss: Double,
        minEle: Double?,
        maxEle: Double?
    ) -> GPXTrack {
        let totalDistance = points.last?.cumulativeDistance ?? 0.0
        let bounds = GPXParser.calculateBounds(for: points)
        
        return GPXTrack(
            name: name,
            trackDescription: description,
            points: points,
            totalDistance: totalDistance,
            elevationGain: gain,
            elevationLoss: loss,
            minElevation: minEle,
            maxElevation: maxEle,
            bounds: bounds,
            fileURL: fileURL,
            date: points.first?.time
        )
    }
    
    // MARK: - Coordinate Attribute Extraction
    
    private func extractCoordinate(from attributes: [String: String], key: String) -> Double? {
        // Case-insensitive key lookup (e.g. lat, Lat, LAT)
        if let val = attributes[key] ?? attributes[key.lowercased()] ?? attributes[key.uppercased()] {
            if let num = Double(val), num.isFinite {
                return num
            }
            return nil
        }
        for (k, v) in attributes {
            if k.caseInsensitiveCompare(key) == .orderedSame {
                if let num = Double(v), num.isFinite {
                    return num
                }
                return nil
            }
        }
        return nil
    }
}
