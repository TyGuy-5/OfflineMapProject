import Foundation

struct OfflineDataManager {
    static func prepareIfNeeded() throws {
        print("Data manager initialized.")
    }
    
    static func url(for filename: String) -> URL {
        #if targetEnvironment(simulator)
        // Simulator shortcut: Read directly from the external drive to save 25GB of copying!
        let basePath = "/Volumes/Extended Hard Drive 1Tb (Mac Mini M4)/OfflineMapProject/MyOfflineMapApp/Sources/Assets/"
        return URL(fileURLWithPath: basePath + filename)
        #else
        return Bundle.main.url(forResource: filename, withExtension: nil)!
        #endif
    }
}
