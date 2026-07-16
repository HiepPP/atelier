import KeyboardShortcuts
import Luminare
import Pow
import SwiftUI
import SwiftUIIntrospect
import SwiftUIX

extension KeyboardShortcuts.Name {
    static let compatibilitySpike = Self("compatibilitySpike")
}

struct CompatibilityView: View {
    var body: some View {
        LuminareSection {
            TextView("SwiftUIX")
                .editable(false)
                .introspect(.scrollView, on: .macOS(.v26)) { _ in }
                .changeEffect(.shake, value: 0)

            KeyboardShortcuts.Recorder(
                "KeyboardShortcuts:",
                name: .compatibilitySpike
            )
        }
    }
}

_ = CompatibilityView()
print("Atelier library compatibility passed")
