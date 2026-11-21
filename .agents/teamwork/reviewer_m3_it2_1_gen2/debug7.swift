
import Foundation
import CoreLocation
import SwiftUI

struct MyView: View {
    @StateObject var vm: NavigationViewModel
    init(vm: NavigationViewModel? = nil) {
        let resolved = vm ?? NavigationViewModel()
        _vm = StateObject(wrappedValue: resolved)
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
    }
}
