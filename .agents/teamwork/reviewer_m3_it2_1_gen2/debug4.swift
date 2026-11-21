
import Foundation
import CoreLocation
import SwiftUI

@main
struct DebugRunner {
    @MainActor
    static func main() async {
        let vm = NavigationViewModel()
        let stateObj1 = StateObject(wrappedValue: vm)
        print("Explicit vm id 1:", ObjectIdentifier(stateObj1.wrappedValue))
        print("Explicit vm id 2:", ObjectIdentifier(stateObj1.wrappedValue))

        let stateObj2 = StateObject(wrappedValue: NavigationViewModel())
        print("Inline closure id 1:", ObjectIdentifier(stateObj2.wrappedValue))
        print("Inline closure id 2:", ObjectIdentifier(stateObj2.wrappedValue))

        let precreated = NavigationViewModel()
        let stateObj3 = StateObject(wrappedValue: precreated)
        print("Precreated id 1:", ObjectIdentifier(stateObj3.wrappedValue))
        print("Precreated id 2:", ObjectIdentifier(stateObj3.wrappedValue))
    }
}
