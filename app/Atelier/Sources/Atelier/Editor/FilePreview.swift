import AppKit
import SwiftUI
import WebKit

nonisolated enum FilePreviewKind: Equatable, Sendable {
    case markdown
    case html
}

nonisolated enum FilePreviewPolicy {
    static func kind(for url: URL) -> FilePreviewKind? {
        switch url.pathExtension.lowercased() {
        case "md":
            .markdown
        case "html":
            .html
        default:
            nil
        }
    }

    static func showsPreviewByDefault(for url: URL) -> Bool {
        kind(for: url) == .html
    }
}

nonisolated enum HTMLFilePreviewPolicy {
    static let allowsContentJavaScript = true

    static func readAccessURL(for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent().standardizedFileURL
    }
}

struct FileRenderedPreview: View {
    let kind: FilePreviewKind
    let content: FileContent
    let fileURL: URL
    let isActive: Bool

    @ViewBuilder
    var body: some View {
        switch content {
        case .text(let source):
            switch kind {
            case .markdown:
                if isActive {
                    ScrollView {
                        AgentMarkdownView(source: source)
                            .padding(AtelierMetrics.spaceXL)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.editor)
                } else {
                    Color.clear
                }
            case .html:
                HTMLFilePreview(
                    sourceVersion: source,
                    fileURL: fileURL,
                    isActive: isActive
                )
            }
        case .loading:
            ProgressView("Loading preview...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            AtelierEmptyState(
                systemImage: "eye.slash",
                title: "Preview Unavailable",
                message: content.displayText
            )
        }
    }
}

private struct HTMLFilePreview: NSViewRepresentable {
    @Environment(\.atelierZoomScale) private var scale
    @Environment(\.colorScheme) private var colorScheme

    let sourceVersion: String
    let fileURL: URL
    let isActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript =
            HTMLFilePreviewPolicy.allowsContentJavaScript

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = AppKitThemeAdapter.editor(
            usesDarkAppearance: colorScheme == .dark
        )
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let usesDarkAppearance = colorScheme == .dark
        if context.coordinator.usesDarkAppearance != usesDarkAppearance {
            context.coordinator.usesDarkAppearance = usesDarkAppearance
            webView.underPageBackgroundColor = AppKitThemeAdapter.editor(
                usesDarkAppearance: usesDarkAppearance
            )
        }
        if context.coordinator.scale != scale {
            context.coordinator.scale = scale
            webView.pageZoom = scale
        }
        guard isActive else { return }
        guard context.coordinator.sourceVersion != sourceVersion
                || context.coordinator.fileURL != fileURL else { return }
        context.coordinator.sourceVersion = sourceVersion
        context.coordinator.fileURL = fileURL
        webView.loadFileURL(
            fileURL,
            allowingReadAccessTo: HTMLFilePreviewPolicy.readAccessURL(for: fileURL)
        )
    }

    final class Coordinator {
        var sourceVersion: String?
        var fileURL: URL?
        var scale: CGFloat = 0
        var usesDarkAppearance: Bool?
    }
}
