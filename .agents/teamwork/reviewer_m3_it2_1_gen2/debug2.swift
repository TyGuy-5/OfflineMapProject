
import Foundation
import CoreLocation
import SwiftUI

@main
struct DebugRunner {
    @MainActor
    static func main() async {
        let vm = NavigationViewModel()
        let view = ContentView(viewModel: vm)
        print("Before view.appMode:", view.appMode)
        print("Before vm.appMode:", vm.appMode)
        view.appMode = .navigation
        print("After view.appMode:", view.appMode)
        print("After vm.appMode:", vm.appMode)
    }
}
