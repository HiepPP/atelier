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
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AtelierTheme.editor)
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
