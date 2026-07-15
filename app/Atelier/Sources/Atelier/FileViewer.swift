import SwiftUI
import AppKit

struct FileViewer: NSViewRepresentable {
    let content: FileContent

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
        textView.textColor = AtelierNativePalette.foreground
        textView.backgroundColor = AtelierNativePalette.code
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.textContainer?.lineFragmentPadding = 0
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = AtelierNativePalette.code
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.textColor = AtelierNativePalette.foreground
        textView.backgroundColor = AtelierNativePalette.code
        scrollView.backgroundColor = AtelierNativePalette.code
        guard textView.string != content.displayText else { return }
        textView.string = content.displayText
        textView.scrollToBeginningOfDocument(nil)
    }
}
