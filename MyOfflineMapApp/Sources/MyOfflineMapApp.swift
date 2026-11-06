import SwiftUI
import MapLibre

@main
struct MyOfflineMapApp: App {
    init() {
        MLNLoggingConfiguration.shared.loggingLevel = .fault
        MLNLoggingConfiguration.shared.handler = { level, filePath, line, message in
            print("[MapLibre \(level.rawValue)] \(message)")
        }
        try? OfflineDataManager.prepareIfNeeded()
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
