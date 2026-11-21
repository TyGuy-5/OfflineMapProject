import Foundation

/// Errors thrown by TrailManager.
public enum TrailManagerError: LocalizedError, Equatable {
    case directoryCreationFailed(String)
    case fileNotFound(String)
    case invalidFileType(String)
    case pathTraversalDetected(String)
    case importFailed(String)
    case deletionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let message):
            return "Failed to create trails directory: \(message)"
        case .fileNotFound(let path):
            return "Trail file not found at: \(path)"
        case .invalidFileType(let ext):
            return "Invalid file type '.\(ext)'. Only .gpx files are supported."
        case .pathTraversalDetected(let path):
            return "Security violation: Path traversal detected for '\(path)'."
        case .importFailed(let message):
            return "Failed to import GPX trail: \(message)"
        case .deletionFailed(let message):
            return "Failed to delete trail: \(message)"
        }
    }
}

/// Service managing local storage, directory scanning, and importing of GPX trail files in Documents/Trails/.
/// Supports SwiftUI .fileImporter with security-scoped URL access, defensive path traversal protection,
/// and GeoJSON export for immediate MapLibre overlay rendering via TrailOverlayManager.
@MainActor
public class TrailManager: ObservableObject {
    
    // MARK: - Published State
    
    @Published public var importedTrails: [GPXTrack] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    
    // MARK: - Properties
    
    public let trailsDirectory: URL
    public let parser: GPXParser
    
    // MARK: - Initialization
    
    /// Initializes TrailManager.
    /// - Parameters:
    ///   - baseDirectory: Custom base directory for hermetic unit testing. If nil, defaults to Documents/Trails/.
    ///   - parser: The GPXParser instance to use for XML decoding.
    ///   - autoScan: If true, initiates an asynchronous scan of the trails directory on initialization.
    public init(
        baseDirectory: URL? = nil,
        parser: GPXParser = GPXParser(),
        autoScan: Bool = false
    ) {
        self.parser = parser
        if let base = baseDirectory {
            self.trailsDirectory = base
        } else {
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.trailsDirectory = documentsURL.appendingPathComponent("Trails", isDirectory: true)
        }
        
        createTrailsDirectoryIfNeeded()
        
        if autoScan {
            Task {
                await self.reload()
            }
        }
    }
    
    // MARK: - Directory Management
    
    /// Ensures that the local Trails directory exists. Creates it with intermediate directories if missing.
    public func createTrailsDirectoryIfNeeded() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: trailsDirectory.path) {
            try? fm.createDirectory(at: trailsDirectory, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    // MARK: - Local Scanner & Interface Contracts
    
    /// Scans the local Trails directory for all case-insensitive `.gpx` files and parses them into GPXTracks.
    /// Fulfills PROJECT.md § Interface Contracts: `func scanDocumentsDirectory() throws -> [GPXTrack]`
    @discardableResult
    public func scanDocumentsDirectory() throws -> [GPXTrack] {
        isLoading = true
        defer { isLoading = false }
        
        createTrailsDirectoryIfNeeded()
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: trailsDirectory.path) else {
            self.importedTrails = []
            return []
        }
        
        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(
                at: trailsDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw TrailManagerError.directoryCreationFailed(error.localizedDescription)
        }
        
        var tracks: [GPXTrack] = []
        for fileURL in contents {
            guard fileURL.pathExtension.lowercased() == "gpx" else {
                continue
            }
            
            do {
                let track = try parser.parse(fileURL: fileURL)
                tracks.append(track)
                // Cache GeoJSON for immediate overlay rendering
                _ = try? exportGeoJSON(for: track)
            } catch {
                print("Warning: Failed to parse GPX at \(fileURL.lastPathComponent): \(error)")
            }
        }
        
        tracks.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.importedTrails = tracks
        return tracks
    }
    
    /// Asynchronous scanner forwarding to `scanDocumentsDirectory()`.
    @discardableResult
    public func scanTrails() async throws -> [GPXTrack] {
        return try scanDocumentsDirectory()
    }
    
    /// Reloads the local trails list asynchronously, updating published state and error messages.
    public func reload() async {
        do {
            _ = try await scanTrails()
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Security-Scoped File Importer & Interface Contracts
    
    /// Synchronously imports a GPX file from an external source into `Documents/Trails/`.
    /// Fulfills PROJECT.md § Interface Contracts: `func importFile(from url: URL) throws -> GPXTrack`
    @discardableResult
    public func importFile(from sourceURL: URL) throws -> GPXTrack {
        let isSecurityScoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // Defensive check against path traversal and percent-encoded traversal in source filename and path
        let rawFilename = sourceURL.lastPathComponent
        let rawPath = sourceURL.path
        let standardizedPath = sourceURL.standardizedFileURL.path
        
        var decodedFilename = rawFilename
        while let next = decodedFilename.removingPercentEncoding, next != decodedFilename {
            decodedFilename = next
        }
        var decodedRawPath = rawPath
        while let next = decodedRawPath.removingPercentEncoding, next != decodedRawPath {
            decodedRawPath = next
        }
        var decodedStandardizedPath = standardizedPath
        while let next = decodedStandardizedPath.removingPercentEncoding, next != decodedStandardizedPath {
            decodedStandardizedPath = next
        }
        
        let lowerRaw = rawFilename.lowercased()
        let lowerDecoded = decodedFilename.lowercased()
        let lowerRawPath = rawPath.lowercased()
        let lowerDecodedRawPath = decodedRawPath.lowercased()
        let lowerStdPath = standardizedPath.lowercased()
        let lowerDecodedStdPath = decodedStandardizedPath.lowercased()
        
        let hasPercentTraversal = lowerRaw.contains("%2e") || lowerRaw.contains("%2f") || lowerRaw.contains("%5c") || lowerRaw.contains("%00") ||
                                  lowerRaw.contains("%25") ||
                                  lowerDecoded.contains("%2e") || lowerDecoded.contains("%2f") || lowerDecoded.contains("%5c") || lowerDecoded.contains("%00") ||
                                  lowerRawPath.contains("%2e") || lowerRawPath.contains("%2f") || lowerRawPath.contains("%5c") || lowerRawPath.contains("%00") ||
                                  lowerRawPath.contains("%25") ||
                                  lowerDecodedRawPath.contains("%2e") || lowerDecodedRawPath.contains("%2f") || lowerDecodedRawPath.contains("%5c") || lowerDecodedRawPath.contains("%00") ||
                                  lowerStdPath.contains("%2e") || lowerStdPath.contains("%2f") || lowerStdPath.contains("%5c") || lowerStdPath.contains("%00") ||
                                  lowerStdPath.contains("%25") ||
                                  lowerDecodedStdPath.contains("%2e") || lowerDecodedStdPath.contains("%2f") || lowerDecodedStdPath.contains("%5c") || lowerDecodedStdPath.contains("%00")
        
        if rawFilename.contains("..") || rawFilename.contains("/") || rawFilename.contains("\\") || rawFilename.contains("\0") ||
           decodedFilename.contains("..") || decodedFilename.contains("/") || decodedFilename.contains("\\") || decodedFilename.contains("\0") ||
           rawPath.contains("..") || decodedRawPath.contains("..") ||
           standardizedPath.contains("..") || decodedStandardizedPath.contains("..") ||
           rawFilename.rangeOfCharacter(from: CharacterSet.controlCharacters) != nil ||
           decodedFilename.rangeOfCharacter(from: CharacterSet.controlCharacters) != nil ||
           hasPercentTraversal {
            throw TrailManagerError.pathTraversalDetected(sourceURL.path)
        }
        
        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "gpx" else {
            throw TrailManagerError.invalidFileType(sourceURL.pathExtension)
        }
        
        createTrailsDirectoryIfNeeded()
        
        let sanitizedFilename = sanitizeFilename(rawFilename)
        let destinationURL = trailsDirectory.appendingPathComponent(sanitizedFilename).standardizedFileURL
        try validatePathSafety(for: destinationURL)
        
        let fm = FileManager.default
        if fm.fileExists(atPath: destinationURL.path) {
            try? fm.removeItem(at: destinationURL)
        }
        
        do {
            try fm.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw TrailManagerError.importFailed(error.localizedDescription)
        }
        
        let track: GPXTrack
        do {
            track = try parser.parse(fileURL: destinationURL)
            _ = try? exportGeoJSON(for: track)
        } catch {
            // Clean up destination file on parse failure so orphaned corrupted files do not persist
            try? fm.removeItem(at: destinationURL)
            throw error
        }
        
        if let idx = importedTrails.firstIndex(where: { $0.fileURL?.standardizedFileURL == destinationURL || $0.id == track.id }) {
            importedTrails[idx] = track
        } else {
            importedTrails.append(track)
        }
        importedTrails.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        
        return track
    }
    
    /// Asynchronous importer forwarding to `importFile(from:)`.
    @discardableResult
    public func importTrail(from sourceURL: URL) async throws -> GPXTrack {
        return try importFile(from: sourceURL)
    }
    
    /// Imports multiple external GPX files sequentially.
    @discardableResult
    public func importTrails(from sourceURLs: [URL]) async throws -> [GPXTrack] {
        var results: [GPXTrack] = []
        for url in sourceURLs {
            let track = try await importTrail(from: url)
            results.append(track)
        }
        return results
    }
    
    // MARK: - Deletion & Trail Removal
    
    /// Deletes the specified GPXTrack and its underlying `.gpx` and cached `.geojson` files.
    public func deleteTrail(_ track: GPXTrack) async throws {
        if let fileURL = track.fileURL {
            try await deleteTrail(at: fileURL)
        }
        importedTrails.removeAll { $0.id == track.id }
    }
    
    /// Deletes a trail file by filename within the local trails directory.
    public func deleteTrail(named filename: String) async throws {
        var decoded = filename
        while let next = decoded.removingPercentEncoding, next != decoded {
            decoded = next
        }
        let lower = filename.lowercased()
        let lowerDecoded = decoded.lowercased()
        let hasPercentTraversal = lower.contains("%2e") || lower.contains("%2f") || lower.contains("%5c") || lower.contains("%00") ||
                                  lower.contains("%25") ||
                                  lowerDecoded.contains("%2e") || lowerDecoded.contains("%2f") || lowerDecoded.contains("%5c") || lowerDecoded.contains("%00")
        
        if filename.contains("..") || filename.contains("/") || filename.contains("\\") || filename.contains("\0") ||
           decoded.contains("..") || decoded.contains("/") || decoded.contains("\\") || decoded.contains("\0") ||
           filename.rangeOfCharacter(from: CharacterSet.controlCharacters) != nil ||
           decoded.rangeOfCharacter(from: CharacterSet.controlCharacters) != nil ||
           hasPercentTraversal {
            throw TrailManagerError.pathTraversalDetected(filename)
        }
        let targetURL = trailsDirectory.appendingPathComponent(filename).standardizedFileURL
        try await deleteTrail(at: targetURL)
    }
    
    /// Deletes a trail file at the specified URL after verifying path containment.
    public func deleteTrail(at fileURL: URL) async throws {
        let standardized = fileURL.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath()
        try validatePathSafety(for: standardized)
        try validatePathSafety(for: resolved)
        
        let fm = FileManager.default
        if fm.fileExists(atPath: standardized.path) {
            do {
                try fm.removeItem(at: standardized)
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
                // Already removed; idempotent success
            } catch {
                throw TrailManagerError.deletionFailed(error.localizedDescription)
            }
        } else if fm.fileExists(atPath: resolved.path) {
            do {
                try fm.removeItem(at: resolved)
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
                // Already removed; idempotent success
            } catch {
                throw TrailManagerError.deletionFailed(error.localizedDescription)
            }
        }
        
        // Remove cached GeoJSON if present (with containment validation)
        let geoJSONURL = standardized.deletingPathExtension().appendingPathExtension("geojson")
        if (try? validatePathSafety(for: geoJSONURL)) != nil, fm.fileExists(atPath: geoJSONURL.path) {
            try? fm.removeItem(at: geoJSONURL)
        }
        let resolvedGeoJSONURL = resolved.deletingPathExtension().appendingPathExtension("geojson")
        if (try? validatePathSafety(for: resolvedGeoJSONURL)) != nil, fm.fileExists(atPath: resolvedGeoJSONURL.path) {
            try? fm.removeItem(at: resolvedGeoJSONURL)
        }
        
        importedTrails.removeAll {
            guard let itemURL = $0.fileURL else { return false }
            return itemURL.standardizedFileURL == standardized ||
                   itemURL.standardizedFileURL.resolvingSymlinksInPath() == resolved ||
                   itemURL.standardizedFileURL.path == standardized.path ||
                   itemURL.standardizedFileURL.resolvingSymlinksInPath().path == resolved.path
        }
    }
    
    // MARK: - GeoJSON Export for Overlay Rendering
    
    /// Exports the given GPXTrack to a standardized GeoJSON file in the trails directory.
    @discardableResult
    public func exportGeoJSON(for track: GPXTrack) throws -> URL {
        createTrailsDirectoryIfNeeded()
        let baseName: String
        if let url = track.fileURL {
            baseName = url.deletingPathExtension().lastPathComponent
        } else {
            baseName = sanitizeFilename(track.name).replacingOccurrences(of: ".gpx", with: "")
        }
        
        let geoJSONURL = trailsDirectory.appendingPathComponent("\(baseName).geojson").standardizedFileURL
        try validatePathSafety(for: geoJSONURL)
        
        let data = try track.toGeoJSONData()
        try data.write(to: geoJSONURL, options: .atomic)
        return geoJSONURL
    }
    
    /// Returns an array of file URLs for all currently imported trails exported as GeoJSON.
    /// Can be passed directly to `TrailOverlayManager.shared.applyTrailOverlay(to:geoJSONURLs:)`.
    public func allTrailGeoJSONURLs() -> [URL] {
        createTrailsDirectoryIfNeeded()
        var urls: [URL] = []
        for track in importedTrails {
            if let url = try? exportGeoJSON(for: track) {
                urls.append(url)
            }
        }
        return urls
    }
    
    // MARK: - Defensive Path Traversal Protection
    
    /// Verifies that the destination or target URL is strictly contained within the Trails directory.
    public func validatePathSafety(for url: URL) throws {
        let standardizedTarget = url.standardizedFileURL.path
        let safePrefix = trailsDirectory.standardizedFileURL.path + "/"
        
        let resolvedTarget = url.standardizedFileURL.resolvingSymlinksInPath().path
        let safeResolvedPrefix = trailsDirectory.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        
        guard standardizedTarget.hasPrefix(safePrefix) && resolvedTarget.hasPrefix(safeResolvedPrefix) else {
            throw TrailManagerError.pathTraversalDetected(url.path)
        }
    }
    
    /// Sanitizes an input filename by stripping control characters, traversal markers, and leading slashes.
    public func sanitizeFilename(_ raw: String) -> String {
        var decoded = raw
        while let next = decoded.removingPercentEncoding, next != decoded {
            decoded = next
        }
        var cleaned = decoded
        cleaned = cleaned.components(separatedBy: CharacterSet.controlCharacters).joined()
        cleaned = cleaned.replacingOccurrences(of: "%25", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "%2e", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "%2f", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "%5c", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "%00", with: "", options: .caseInsensitive)
        cleaned = cleaned.replacingOccurrences(of: "../", with: "")
        cleaned = cleaned.replacingOccurrences(of: "..\\", with: "")
        cleaned = cleaned.replacingOccurrences(of: "..", with: "")
        while cleaned.hasPrefix("/") || cleaned.hasPrefix("\\") {
            cleaned.removeFirst()
        }
        if let last = cleaned.components(separatedBy: "/").last, !last.isEmpty {
            cleaned = last
        }
        if let last = cleaned.components(separatedBy: "\\").last, !last.isEmpty {
            cleaned = last
        }
        cleaned = cleaned.replacingOccurrences(of: "..", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\0", with: "")
        if cleaned.isEmpty || cleaned == ".gpx" || cleaned == "." {
            cleaned = "imported_trail.gpx"
        }
        if !cleaned.lowercased().hasSuffix(".gpx") {
            cleaned += ".gpx"
        }
        return cleaned
    }
}
