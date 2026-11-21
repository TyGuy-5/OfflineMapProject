
import Foundation
import CoreLocation
import SwiftUI

@main
struct DebugRunner {
    @MainActor
    static func main() async {
        let view = ContentView()
        print("Id 1:", ObjectIdentifier(view.viewModel))
        print("Id 2:", ObjectIdentifier(view.viewModel))
    }
}
