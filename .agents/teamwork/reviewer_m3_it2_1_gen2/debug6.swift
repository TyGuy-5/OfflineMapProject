
import Foundation
import CoreLocation
import SwiftUI

struct MyView: View {
    @StateObject var vm: NavigationViewModel
    init(vm: NavigationViewModel? = nil) {
        _vm = StateObject(wrappedValue: vm ?? NavigationViewModel())
    }
    var body: some View { EmptyView() }
}

@main
struct DebugRunner {
    @MainActor
    static func main() async {
        let v = MyView()
        print("v.vm 1:", ObjectIdentifier(v.vm))
        print("v.vm 2:", ObjectIdentifier(v.vm))

        let vm = NavigationViewModel()
        let v2 = MyView(vm: vm)
        print("v2.vm 1:", ObjectIdentifier(v2.vm))
        print("v2.vm 2:", ObjectIdentifier(v2.vm))
    }
}
