import Foundation
import CoreLocation
#if canImport(Darwin)
import Darwin
#endif

#if canImport(MapLibre)
import MapLibre
#else
public struct MLNCoordinateBounds: Equatable, Sendable {
    public var sw: CLLocationCoordinate2D
    public var ne: CLLocationCoordinate2D
    
    public init(sw: CLLocationCoordinate2D, ne: CLLocationCoordinate2D) {
        self.sw = sw
        self.ne = ne
    }
    
    public static func == (lhs: MLNCoordinateBounds, rhs: MLNCoordinateBounds) -> Bool {
        return lhs.sw.latitude == rhs.sw.latitude &&
               lhs.sw.longitude == rhs.sw.longitude &&
               lhs.ne.latitude == rhs.ne.latitude &&
               lhs.ne.longitude == rhs.ne.longitude
    }
}
#endif

public enum TrailDownloaderError: LocalizedError, Equatable {
    case boundingBoxTooLarge(latSpan: Double, lonSpan: Double, limit: Double)
    case invalidBoundingBox(String)
    case networkError(String)
    case httpError(statusCode: Int, responseBody: String?)
    case storageError(String)
    case regionNotFound(String)
    
    public var errorDescription: String? {
        switch self {
        case .boundingBoxTooLarge(let latSpan, let lonSpan, let limit):
            return String(format: "Bounding box span (lat: %.3f°, lon: %.3f°) exceeds maximum allowable limit of %.1f°. Please zoom in closer.", latSpan, lonSpan, limit)
        case .invalidBoundingBox(let reason):
            return "Invalid bounding box coordinates: \(reason)"
        case .networkError(let message):
            return "Network error while downloading trails: \(message)"
        case .httpError(let statusCode, let body):
            return "Overpass API returned HTTP \(statusCode): \(body ?? "Unknown error")"
        case .storageError(let message):
            return "Failed to store trail GeoJSON: \(message)"
        case .regionNotFound(let name):
            return "Downloaded region not found: \(name)"
        }
    }
}

/// Actor responsible for querying OpenStreetMap trails from Overpass API,
/// converting results to GeoJSON, and persisting them in Application Support/Trails/
/// with backup exclusion flags.
public actor RegionalTrailDownloader {
    public static let shared = RegionalTrailDownloader()
    
    public static let maxSpanDegrees: Double = 0.5
    public static let defaultEndpoint = URL(string: "https://overpass-api.de/api/interpreter")!
    
    private let session: URLSession
    private let apiEndpoint: URL
    private let converter: GeoJSONConverter
    private let fileManager: FileManager
    private let customBaseDirectory: URL?
    
    public init(
        session: URLSession = .shared,
        apiEndpoint: URL = RegionalTrailDownloader.defaultEndpoint,
        converter: GeoJSONConverter = GeoJSONConverter(),
        fileManager: FileManager = .default,
        baseDirectory: URL? = nil
    ) {
        self.session = session
        self.apiEndpoint = apiEndpoint
        self.converter = converter
        self.fileManager = fileManager
        self.customBaseDirectory = baseDirectory
    }
    
    /// Resolves the Application Support/Trails directory, creating it and marking it excluded from backup if necessary.
    public func getTrailsDirectory() throws -> URL {
        let baseURL: URL
        if let custom = customBaseDirectory {
            baseURL = custom
        } else {
            do {
                baseURL = try fileManager.url(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask,
                    appropriateFor: nil,
                    create: true
                )
            } catch {
                baseURL = fileManager.temporaryDirectory.appendingPathComponent("Application Support", isDirectory: true)
            }
        }
        let trailsDir = baseURL.appendingPathComponent("Trails", isDirectory: true)
        if !fileManager.fileExists(atPath: trailsDir.path) {
            try fileManager.createDirectory(at: trailsDir, withIntermediateDirectories: true)
            var rv = URLResourceValues()
            rv.isExcludedFromBackup = true
            var mutableDir = trailsDir
            try? mutableDir.setResourceValues(rv)
            #if canImport(Darwin)
            var attrVal: [UInt8] = Array("com.apple.backupd\0".utf8)
            setxattr(mutableDir.path, "com.apple.metadata:com_apple_backup_excludeItem", &attrVal, attrVal.count, 0, 0)
            #endif
        }
        return trailsDir
    }
    
    /// Validates the bounding box against safety guardrails (max span <= 0.5 degrees, valid coordinate range).
    public func validateBoundingBox(south: Double, west: Double, north: Double, east: Double) throws {
        guard south >= -90.0 && south <= 90.0,
              north >= -90.0 && north <= 90.0,
              west >= -180.0 && west <= 180.0,
              east >= -180.0 && east <= 180.0 else {
            throw TrailDownloaderError.invalidBoundingBox("Coordinates out of range [-90, 90] / [-180, 180]")
        }
        
        guard south < north else {
            throw TrailDownloaderError.invalidBoundingBox("South latitude (\(south)) must be strictly less than North latitude (\(north))")
        }
        
        guard west <= east else {
            throw TrailDownloaderError.invalidBoundingBox("West longitude (\(west)) must be less than or equal to East longitude (\(east))")
        }
        
        let latSpan = north - south
        let lonSpan = east - west
        
        if latSpan > Self.maxSpanDegrees || lonSpan > Self.maxSpanDegrees {
            throw TrailDownloaderError.boundingBoxTooLarge(
                latSpan: latSpan,
                lonSpan: lonSpan,
                limit: Self.maxSpanDegrees
            )
        }
    }
    
    /// Constructs the Overpass QL query string with inline geometry for trails in the bounding box.
    public func buildOverpassQuery(south: Double, west: Double, north: Double, east: Double) -> String {
        let s = String(format: "%.6f", south)
        let w = String(format: "%.6f", west)
        let n = String(format: "%.6f", north)
        let e = String(format: "%.6f", east)
        
        return """
        [out:json][timeout:30];
        (
          way["highway"="path"](\(s),\(w),\(n),\(e));
          way["highway"="track"](\(s),\(w),\(n),\(e));
          way["highway"="footway"]["footway"!="sidewalk"](\(s),\(w),\(n),\(e));
          way["highway"="cycleway"](\(s),\(w),\(n),\(e));
          way["highway"="bridleway"](\(s),\(w),\(n),\(e));
        );
        out body geom;
        """
    }
    
    /// Sanitizes region name for safe filesystem storage.
    public func sanitizeRegionName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "trails_\(Int(Date().timeIntervalSince1970))"
        }
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\":<> ").union(.controlCharacters)
        let components = trimmed.components(separatedBy: invalidCharacters)
        let sanitized = components.filter { !$0.isEmpty }.joined(separator: "_")
        return sanitized.isEmpty ? "trails_\(Int(Date().timeIntervalSince1970))" : sanitized
    }
    
    /// Downloads trails using an MLNCoordinateBounds object.
    public func downloadTrails(bbox: MLNCoordinateBounds, regionName: String) async throws -> URL {
        return try await downloadTrails(
            south: bbox.sw.latitude,
            west: bbox.sw.longitude,
            north: bbox.ne.latitude,
            east: bbox.ne.longitude,
            regionName: regionName
        )
    }
    
    /// Downloads trails within explicit coordinate bounds, converts to GeoJSON, and saves locally with isExcludedFromBackup = true.
    public func downloadTrails(
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        regionName: String
    ) async throws -> URL {
        // 1. Guardrail validation
        try validateBoundingBox(south: south, west: west, north: north, east: east)
        
        // 2. Query preparation
        let query = buildOverpassQuery(south: south, west: west, north: north, east: east)
        var request = URLRequest(url: apiEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("MyOfflineMapApp/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [URLQueryItem(name: "data", value: query)]
        request.httpBody = bodyComponents.query?.data(using: .utf8)
        
        // 3. Execution
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw TrailDownloaderError.networkError(error.localizedDescription)
        }
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8)
            throw TrailDownloaderError.httpError(statusCode: httpResponse.statusCode, responseBody: errorText)
        }
        
        // 4. GeoJSON conversion
        let geoJSONData = try converter.convert(overpassData: data)
        
        // 5. Local storage in Application Support/Trails/<region>.geojson
        let trailsDir = try getTrailsDirectory()
        let safeName = sanitizeRegionName(regionName)
        let destinationURL = trailsDir.appendingPathComponent("\(safeName).geojson")
        
        do {
            try geoJSONData.write(to: destinationURL, options: .atomic)
            
            // Mark file as excluded from iCloud/iTunes backup
            var rv = URLResourceValues()
            rv.isExcludedFromBackup = true
            var mutableURL = destinationURL
            try mutableURL.setResourceValues(rv)
            
            #if canImport(Darwin)
            var attrVal: [UInt8] = Array("com.apple.backupd\0".utf8)
            setxattr(mutableURL.path, "com.apple.metadata:com_apple_backup_excludeItem", &attrVal, attrVal.count, 0, 0)
            #endif
        } catch {
            throw TrailDownloaderError.storageError("Failed to write GeoJSON file: \(error.localizedDescription)")
        }
        
        return destinationURL
    }
    
    /// Lists all downloaded regional trail GeoJSON files.
    public func listDownloadedRegions() -> [URL] {
        guard let trailsDir = try? getTrailsDirectory() else { return [] }
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: trailsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isExcludedFromBackupKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }
        
        return fileURLs.filter { $0.pathExtension.lowercased() == "geojson" }
            .sorted { (u1, u2) -> Bool in
                let d1 = (try? u1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let d2 = (try? u2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return d1 > d2
            }
    }
    
    /// Deletes a downloaded trail region by filename or region name.
    public func deleteDownloadedRegion(named name: String) throws {
        let trailsDir = try getTrailsDirectory()
        let trailsDirPath = trailsDir.standardizedFileURL.path
        let safeTrailsPrefix = trailsDirPath.hasSuffix("/") ? trailsDirPath : trailsDirPath + "/"
        
        let candidateName = name.hasSuffix(".geojson") ? name : "\(name).geojson"
        let candidateURL = trailsDir.appendingPathComponent(candidateName)
        guard candidateURL.standardizedFileURL.path.hasPrefix(safeTrailsPrefix) &&
              candidateURL.standardizedFileURL.path.hasPrefix(trailsDir.standardizedFileURL.path) else {
            throw TrailDownloaderError.storageError("Invalid region path traversal")
        }
        
        let strippedName = name.hasSuffix(".geojson") ? String(name.dropLast(8)) : name
        let safeName = sanitizeRegionName(strippedName)
        let fileURL = trailsDir.appendingPathComponent("\(safeName).geojson")
        
        guard fileURL.standardizedFileURL.path.hasPrefix(safeTrailsPrefix) &&
              fileURL.standardizedFileURL.path.hasPrefix(trailsDir.standardizedFileURL.path) else {
            throw TrailDownloaderError.storageError("Invalid region path traversal")
        }
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw TrailDownloaderError.regionNotFound(name)
        }
        
        try fileManager.removeItem(at: fileURL)
    }
    
    /// Deletes a downloaded trail region at the given URL.
    public func deleteDownloadedRegion(at url: URL) throws {
        let trailsDir = try getTrailsDirectory()
        let trailsDirPath = trailsDir.standardizedFileURL.path
        let safeTrailsPrefix = trailsDirPath.hasSuffix("/") ? trailsDirPath : trailsDirPath + "/"
        
        guard url.standardizedFileURL.path.hasPrefix(safeTrailsPrefix) &&
              url.standardizedFileURL.path.hasPrefix(trailsDir.standardizedFileURL.path) else {
            throw TrailDownloaderError.storageError("Attempted deletion of file outside Trails directory")
        }
        guard fileManager.fileExists(atPath: url.path) else {
            throw TrailDownloaderError.regionNotFound(url.lastPathComponent)
        }
        try fileManager.removeItem(at: url)
    }
}
