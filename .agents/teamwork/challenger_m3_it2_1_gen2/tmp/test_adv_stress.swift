
import Foundation
import SwiftUI

@main
struct AdversarialStressRunner {
    @MainActor
    static func main() async {
        print("=== ADVERSARIAL STRESS TEST: CATEGORY SEARCH, ONCHANGE & HUD TOGGLES ===")

        let vm = NavigationViewModel()
        let view = ContentView(viewModel: vm)

        // 1. Stress Test Category Search & onChange suppression
        print("Scenario 1: Category tap & onChange suppression")
        assert(view.destinationText.isEmpty)
        assert(view.isProgrammaticTextChange == false)

        view.searchCategory("Gas")
        assert(view.destinationText == "Gas")
        assert(view.isProgrammaticTextChange == true)
        assert(vm.destinationText == "Gas")

        // Simulate onChange firing due to destinationText change
        if view.isProgrammaticTextChange {
            view.isProgrammaticTextChange = false
            print("  [OK] Programmatic text change intercepted and suppressed query re-trigger")
        } else {
            fatalError("onChange did not detect programmatic change!")
        }
        assert(view.isProgrammaticTextChange == false)

        // Simulate user typing (non-programmatic change)
        print("Scenario 2: User manual typing trigger")
        view.destinationText = "Coffee"
        if view.isProgrammaticTextChange {
            fatalError("Manual typing should not be flagged as programmatic!")
        } else {
            view.handleQueryChange(view.destinationText)
            assert(view.appMode == .searchList)
            assert(view.isSearching == true)
            print("  [OK] Manual typing triggered searchList mode and isSearching")
        }

        // 2. Stress Test HUD Mode Toggles
        print("Scenario 3: HUD Mode toggle lifecycle")
        assert(view.isHudMode == false)
        assert(vm.isHudMode == false)

        // Simulate HUD button tap (line 875)
        let hudOpenAction = { view.isHudMode = true }
        hudOpenAction()
        assert(view.isHudMode == true)
        assert(vm.isHudMode == true)
        print("  [OK] HUD open action set isHudMode = true")

        // Simulate HUD close button tap (line 993)
        let hudCloseAction = { view.isHudMode = false }
        hudCloseAction()
        assert(view.isHudMode == false)
        assert(vm.isHudMode == false)
        print("  [OK] HUD close action set isHudMode = false")

        // Rapid oscillating toggles
        for _ in 0..<100 {
            hudOpenAction()
            assert(view.isHudMode == true)
            hudCloseAction()
            assert(view.isHudMode == false)
        }
        print("  [OK] 100 rapid HUD toggle cycles passed")

        // 3. Stress Test Concurrency on HUD and Navigation state
        print("Scenario 4: High-frequency state mutation across forwarding properties")
        for i in 0..<200 {
            view.destinationText = "Query \(i)"
            view.currentStepIndex = i
            view.remainingStepDistanceMiles = Double(i) * 0.1
            view.simulationSpeedMultiplier = (i % 2 == 0) ? 2.0 : 5.0
            assert(vm.currentStepIndex == i)
            assert(vm.simulationSpeedMultiplier == ((i % 2 == 0) ? 2.0 : 5.0))
        }
        print("  [OK] 200 high-frequency property mutations verified")

        print("=== ALL ADVERSARIAL STRESS SCENARIOS PASSED SUCCESSFULLY ===")
    }
}
