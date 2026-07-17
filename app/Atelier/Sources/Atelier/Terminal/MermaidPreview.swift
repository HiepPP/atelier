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

    static func widthBucket(containerWidth: CGFloat) -> CGFloat {
        let width = targetWidth(containerWidth: containerWidth)
        if width <= 480 { return 480 }
        if width <= 720 { return 720 }
        return 960
    }
}

@MainActor
protocol MermaidImageRendering: AnyObject {
    func render(source: String, width: CGFloat) async throws -> Data
}

@MainActor
final class MermaidImageCache {
    struct Key: Hashable {
        let source: String
        let width: Int
    }

    static let shared = MermaidImageCache()

    private(set) var entryCount = 0
    private(set) var inFlightCount = 0
    private let capacity: Int
    private let maximumInFlight: Int
    private let renderer: any MermaidImageRendering
    private var images: [Key: NSImage] = [:]
    private var accessOrder: [Key] = []
    private var inFlight: [Key: InFlightRender] = [:]
    private var inFlightOrder: [Key] = []
    private var serialTail: Task<Void, Never>?

    private struct InFlightRender {
        let token: UUID
        let task: Task<NSImage, any Error>
    }

    init(
        capacity: Int = 16,
        maximumInFlight: Int = 4,
        renderer: (any MermaidImageRendering)? = nil
    ) {
        self.capacity = max(1, capacity)
        self.maximumInFlight = max(1, maximumInFlight)
        self.renderer = renderer ?? MermaidImageRenderer()
    }

    func image(source: String, width: CGFloat) async throws -> NSImage {
        let key = Key(source: source, width: Int(width.rounded()))
        if let image = images[key] {
            touch(key)
            return image
        }
        if let render = inFlight[key] {
            return try await render.task.value
        }

        while inFlight.count >= maximumInFlight, let obsolete = inFlightOrder.first {
            cancelInFlight(obsolete)
        }

        let token = UUID()
        let predecessor = serialTail
        let renderer = self.renderer
        let task = Task { @MainActor in
            if let predecessor {
                await predecessor.value
            }
            try Task.checkCancellation()
            let data = try await renderer.render(source: source, width: width)
            try Task.checkCancellation()
            guard let image = NSImage(data: data) else {
                throw MermaidImageRendererError.imageEncodingFailed
            }
            return image
        }
        inFlight[key] = InFlightRender(token: token, task: task)
        inFlightOrder.append(key)
        inFlightCount = inFlight.count
        serialTail = Task { @MainActor in
            _ = await task.result
        }
        do {
            let image = try await task.value
            if inFlight[key]?.token == token {
                removeInFlight(key)
                insert(image, for: key)
            }
            return image
        } catch {
            if inFlight[key]?.token == token {
                removeInFlight(key)
            }
            throw error
        }
    }

    func removeAll() {
        for render in inFlight.values {
            render.task.cancel()
        }
        inFlight.removeAll(keepingCapacity: false)
        inFlightOrder.removeAll(keepingCapacity: false)
        inFlightCount = 0
        serialTail?.cancel()
        serialTail = nil
        images.removeAll(keepingCapacity: false)
        accessOrder.removeAll(keepingCapacity: false)
        entryCount = 0
    }

    private func insert(_ image: NSImage, for key: Key) {
        images[key] = image
        touch(key)
        while images.count > capacity, let oldest = accessOrder.first {
            accessOrder.removeFirst()
            images[oldest] = nil
        }
        entryCount = images.count
    }

    private func touch(_ key: Key) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    private func cancelInFlight(_ key: Key) {
        inFlight[key]?.task.cancel()
        removeInFlight(key)
    }

    private func removeInFlight(_ key: Key) {
        inFlight[key] = nil
        inFlightOrder.removeAll { $0 == key }
        inFlightCount = inFlight.count
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

extension MermaidImageRenderer: MermaidImageRendering {}
