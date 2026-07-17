import AppKit
import WebKit

enum MermaidRenderingPolicy {
    private static let minimumWidth: CGFloat = 420
    private static let maximumWidth: CGFloat = 960

    static func targetWidth(containerWidth: CGFloat) -> CGFloat {
        let availableWidth = max(1, min(containerWidth, maximumWidth))
        let preferredWidth = max(minimumWidth, containerWidth * 0.9)
        return min(availableWidth, preferredWidth)
    }

    static func imageColumns(
        imageWidth: CGFloat,
        terminalWidth: CGFloat,
        terminalColumns: Int
    ) -> Int {
        guard terminalWidth > 0, terminalColumns > 0 else { return 1 }
        let cellWidth = terminalWidth / CGFloat(terminalColumns)
        let columns = Int(ceil(min(imageWidth, terminalWidth) / cellWidth))
        return min(max(1, columns), terminalColumns)
    }
}

enum MermaidImageRendererError: LocalizedError {
    case missingResources
    case invalidResult
    case imageEncodingFailed

    var errorDescription: String? {
        switch self {
        case .missingResources:
            "Mermaid resources are unavailable."
        case .invalidResult:
            "Mermaid returned an invalid diagram size."
        case .imageEncodingFailed:
            "Mermaid diagram could not be encoded as PNG."
        }
    }
}

@MainActor
final class MermaidImageRenderer: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var isLoaded = false
    private var loadContinuations: [CheckedContinuation<Void, any Error>] = []

    override init() {
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 960, height: 640),
            configuration: configuration
        )
        super.init()
        webView.navigationDelegate = self
        webView.underPageBackgroundColor = .clear
        webView.setValue(false, forKey: "drawsBackground")

        if let documentURL = Self.documentURL,
           let mermaidResourceURL = Self.mermaidResourceURL {
            webView.loadFileURL(documentURL, allowingReadAccessTo: mermaidResourceURL)
        } else {
            isLoaded = true
        }
    }

    func render(source: String, width: CGFloat) async throws -> Data {
        guard Self.documentURL != nil, Self.mermaidResourceURL != nil else {
            throw MermaidImageRendererError.missingResources
        }
        try await waitUntilLoaded()

        let renderWidth = min(max(width, 1), 960)
        webView.setFrameSize(CGSize(width: renderWidth, height: 1_200))
        let result = try await webView.callAsyncJavaScript(
            "return await renderMermaidForSnapshot(source);",
            arguments: ["source": source],
            in: nil,
            contentWorld: .page
        )
        guard let metrics = result as? [String: Any],
              let rawHeight = metrics["height"] as? Double else {
            throw MermaidImageRendererError.invalidResult
        }

        let renderHeight = min(max(CGFloat(rawHeight), 160), 1_200)
        webView.setFrameSize(CGSize(width: renderWidth, height: renderHeight))
        await Task.yield()

        let snapshot = WKSnapshotConfiguration()
        snapshot.rect = webView.bounds
        let image = try await webView.takeSnapshot(configuration: snapshot)
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let png = representation.representation(using: .png, properties: [:]) else {
            throw MermaidImageRendererError.imageEncodingFailed
        }
        return png
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        isLoaded = true
        let continuations = loadContinuations
        loadContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: any Error
    ) {
        failLoading(with: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        failLoading(with: error)
    }

    private func waitUntilLoaded() async throws {
        if isLoaded { return }
        try await withCheckedThrowingContinuation { continuation in
            loadContinuations.append(continuation)
        }
    }

    private func failLoading(with error: any Error) {
        let continuations = loadContinuations
        loadContinuations.removeAll()
        continuations.forEach { $0.resume(throwing: error) }
    }

    private static let mermaidResourceURL = Bundle.module.resourceURL?
        .appendingPathComponent("Mermaid", isDirectory: true)
    private static let documentURL = Bundle.module.url(
        forResource: "viewer",
        withExtension: "html",
        subdirectory: "Mermaid"
    )
}
