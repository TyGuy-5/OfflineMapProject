
import Foundation
import CoreLocation
import SwiftUI

@main
struct DebugRunner {
    @MainActor
    static func main() async {
        let view = ContentView()
        view.searchCategory("Gas")
        print("destinationText:", view.destinationText)
        print("isProgrammaticTextChange:", view.isProgrammaticTextChange)
    }
}
