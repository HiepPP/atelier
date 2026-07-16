import Luminare
import SwiftUI

struct LuminareCompatibilityPreview: View {
    var body: some View {
        LuminareSection {
            VStack(spacing: 8) {
                Button("Compact") {}
                    .buttonStyle(.luminareCompact)

                Button("Prominent") {}
                    .buttonStyle(.luminareProminent)
            }
            .padding(8)
        }
        .frame(width: 240)
    }
}

print("Luminare compatibility surfaces compiled")
