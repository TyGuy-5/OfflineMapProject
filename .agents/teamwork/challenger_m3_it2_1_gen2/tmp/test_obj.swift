
import Foundation
import SwiftUI

@main
struct TestObjId {
    @MainActor
    static func main() {
        let view = ContentView()
        print("Id 1:", ObjectIdentifier(view.viewModel))
        print("Id 2:", ObjectIdentifier(view.viewModel))
        view.isHudMode = true
        print("view.isHudMode:", view.isHudMode)
        print("view.viewModel.isHudMode:", view.viewModel.isHudMode)

        let vm = NavigationViewModel()
        let view2 = ContentView(viewModel: vm)
        print("view2 Id 1:", ObjectIdentifier(view2.viewModel))
        print("view2 Id 2:", ObjectIdentifier(view2.viewModel))
        view2.isHudMode = true
        print("view2.isHudMode:", view2.isHudMode)
        print("vm.isHudMode:", vm.isHudMode)
    }
}
