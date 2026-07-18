import AppKit
import SwiftUI

struct ImageViewer: View {
    let data: Data
    let name: String

    var body: some View {
        if let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .shadow(color: AtelierTheme.shadowSoft, radius: AtelierMetrics.spaceS)
                .padding(AtelierMetrics.space2XL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AtelierTheme.canvas)
                .accessibilityLabel(name)
        } else {
            ContentUnavailableView(
                "Could Not Preview Image",
                systemImage: "photo.badge.exclamationmark",
                description: Text("The image data could not be decoded.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AtelierTheme.editor)
        }
    }
}
