
import Foundation
import CoreLocation
import SwiftUI

@main
struct DebugRunner {
    @MainActor
    static func main() async {
        let view = ContentView()
        print("Before view.appMode:", view.appMode)
        print("Before view.viewModel.appMode:", view.viewModel.appMode)
        view.appMode = .navigation
        print("After view.appMode:", view.appMode)
        print("After view.viewModel.appMode:", view.viewModel.appMode)
    }
}
