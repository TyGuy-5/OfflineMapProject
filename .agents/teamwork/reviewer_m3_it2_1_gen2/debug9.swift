
import Foundation
import CoreLocation
import SwiftUI

@main
struct DebugRunner {
    @MainActor
    static func main() async {
        let vm = NavigationViewModel()
        let view = ContentView(viewModel: vm)
        view.searchCategory("Gas")
        print("destinationText:", view.destinationText)
        print("isProgrammaticTextChange:", view.isProgrammaticTextChange)
    }
}
