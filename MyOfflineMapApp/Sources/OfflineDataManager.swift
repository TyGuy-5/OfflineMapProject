import Foundation

private final class CacheStorage: @unchecked Sendable {
    private var storage = [String: URL]()
    private let lock = NSLock()

    func get(_ key: String) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func set(_ key: String, value: URL) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = value
    }

    func remove(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeValue(forKey: key)
    }
}

public struct OfflineDataManager {
    private static let cache = CacheStorage()

    public static func assetExists(at url: URL) -> Bool {
        let path = url.path
        if FileManager.default.fileExists(atPath: path) {
            return true
        }
        let spriteExtensions = [".json", ".png", "@2x.json", "@2x.png"]
        for ext in spriteExtensions {
            if FileManager.default.fileExists(atPath: path + ext) {
                return true
            }
        }
        return false
    }

    public static func prepareIfNeeded() throws {
        // Ensure Application Support directory exists and mark it as excluded from iCloud backup
        if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = appSupportURL
            try? mutableURL.setResourceValues(resourceValues)
        }
        // Exclude Documents directory from iCloud backup to avoid backing up multi-gigabyte offline data
        if let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: docsURL, withIntermediateDirectories: true)
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = docsURL
            try? mutableURL.setResourceValues(resourceValues)
        }
        print("OfflineDataManager initialized with backup exclusion configured.")
    }

    /// Resolves the URL for an offline data asset across external storage, Application Support, Documents, and App Bundle
    public static func url(for filename: String) -> URL {
        if let cached = cache.get(filename) {
            if assetExists(at: cached) {
                return cached
            }
            cache.remove(filename)
        }

        let resolvedURL: URL = {
            // 1. Application Support directory (standard on-device location for downloaded regions)
            if let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let fileInAppSupport = appSupportURL.appendingPathComponent(filename)
                if assetExists(at: fileInAppSupport) {
                    return fileInAppSupport
                }
            }

            // 2. Documents directory (for files imported via Files app, AirDrop, or iTunes File Sharing)
            if let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fileInDocs = documentsURL.appendingPathComponent(filename)
                if assetExists(at: fileInDocs) {
                    return fileInDocs
                }
            }

            // 3. Developer / test environment lookup via source tree (Simulator & macOS only)
            #if (targetEnvironment(simulator) || os(macOS)) && DEBUG
            let sourceURL = URL(fileURLWithPath: #filePath)
            let projectRoot = sourceURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            let devCandidates = [
                projectRoot.appendingPathComponent("data/\(filename)").path,
                projectRoot.appendingPathComponent("MyOfflineMapApp/Resources/\(filename)").path,
                projectRoot.appendingPathComponent(filename).path
            ]
            for path in devCandidates {
                let candidateURL = URL(fileURLWithPath: path)
                if assetExists(at: candidateURL) {
                    return candidateURL
                }
            }
            #endif

            // 4. Resources / App Bundle lookup
            let nsString = filename as NSString
            let name = nsString.deletingPathExtension
            let ext = nsString.pathExtension.isEmpty ? nil : nsString.pathExtension

            if let bundleURL = Bundle.main.url(forResource: name, withExtension: ext) {
                return bundleURL
            }
            if let bundleURL = Bundle.main.url(forResource: filename, withExtension: nil) {
                return bundleURL
            }
            if ext == nil, let jsonURL = Bundle.main.url(forResource: filename, withExtension: "json") {
                return jsonURL.deletingPathExtension()
            }

            #if targetEnvironment(simulator) || os(macOS)
            // 5. Workspace relative path (for local command-line / unit-test execution)
            let currentDir = FileManager.default.currentDirectoryPath
            let localCandidates = [
                URL(fileURLWithPath: currentDir).appendingPathComponent("data/\(filename)").path,
                URL(fileURLWithPath: currentDir).appendingPathComponent("MyOfflineMapApp/Resources/\(filename)").path,
                URL(fileURLWithPath: currentDir).appendingPathComponent(filename).path
            ]
            for path in localCandidates {
                let candidateURL = URL(fileURLWithPath: path)
                if assetExists(at: candidateURL) {
                    return candidateURL
                }
            }
            #endif

            // Safe fallback to Bundle URL
            return Bundle.main.bundleURL.appendingPathComponent(filename)
        }()

        if assetExists(at: resolvedURL) {
            cache.set(filename, value: resolvedURL)
        }

        return resolvedURL
    }

    /// Check available free disk space on device in gigabytes
    public static func availableFreeDiskSpaceGB() -> Double {
        if let systemAttributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeSpace = systemAttributes[.systemFreeSize] as? NSNumber {
            return freeSpace.doubleValue / (1024 * 1024 * 1024)
        }
        return 0.0
    }

    /// Atomically moves a downloaded or imported file into Application Support with backup exclusion
    public static func installOfflineAsset(from tempURL: URL, filename: String) throws {
        guard let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "OfflineDataManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Application Support directory unavailable"])
        }
        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        let destinationURL = appSupportURL.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            _ = try FileManager.default.replaceItemAt(destinationURL, withItemAt: tempURL)
        } else {
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        }

        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var mutableURL = destinationURL
        try mutableURL.setResourceValues(resourceValues)

        // Invalidate cache entry for this filename
        cache.remove(filename)
    }
}
