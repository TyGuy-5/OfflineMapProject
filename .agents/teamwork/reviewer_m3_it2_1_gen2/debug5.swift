
import Foundation
import CoreLocation
import SwiftUI

@main
struct DebugRunner {
    @MainActor
    static func main() async {
        let view = ContentView()
        print("wrappedValue 1:", ObjectIdentifier(view._viewModel.wrappedValue))
        print("wrappedValue 2:", ObjectIdentifier(view._viewModel.wrappedValue))
        print("viewModel 1:", ObjectIdentifier(view.viewModel))
        print("viewModel 2:", ObjectIdentifier(view.viewModel))
    }
}
