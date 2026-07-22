import AppKit
import SwiftUI
import WebKit
@_spi(Advanced) import SwiftUIIntrospect

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
        kind(for: url) != nil
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
                    MarkdownFileDocumentView(source: source)
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

private struct MarkdownFileDocumentView: View {
    let source: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Cheap empty seed: never parse inside `State(initialValue:)` because parent
    /// body re-evaluation re-runs view init even when state storage is preserved.
    @State private var document: ParsedMarkdownDocument = .empty
    @State private var selectedOutlineID: String?
    @State private var containerWidth: CGFloat = 0
    /// Class store: heading Y updates do not invalidate the document tree.
    @State private var headingOffsets = MarkdownHeadingOffsetStore()
    @State private var documentScrollSurface = MarkdownDocumentScrollSurface()
    @State private var outlineJumpTask: Task<Void, Never>?

    private var showsOutline: Bool {
        MarkdownFileDocumentPolicy.showsOutline(
            headingCount: document.outline.count,
            containerWidth: containerWidth
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                documentScroll
                if showsOutline {
                    MarkdownDocumentOutline(
                        entries: document.outline,
                        selectedID: selectedOutlineID
                    ) { entry in
                        jumpToOutlineEntry(entry, proxy: proxy)
                    }
                }
            }
        }
        .environment(\.markdownHeadingOffsetStore, headingOffsets)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        Task { @MainActor in
                            containerWidth = geometry.size.width
                        }
                    }
                    .onChange(of: geometry.size.width) { _, width in
                        Task { @MainActor in
                            containerWidth = width
                        }
                    }
            }
        }
        .onChange(of: source, initial: true) { _, newSource in
            guard document.source != newSource else { return }
            outlineJumpTask?.cancel()
            outlineJumpTask = nil
            document = ParsedMarkdownDocument(source: newSource)
            headingOffsets.reset()
            selectedOutlineID = document.outline.first?.id
        }
        .task(id: document.source) {
            // Catch lazy-loaded heading measurements after first layout without scroll.
            guard !document.source.isEmpty else { return }
            for delayMs in [32, 120, 320] {
                try? await Task.sleep(for: .milliseconds(delayMs))
                guard !Task.isCancelled else { return }
                syncOutlineSelection(contentOffsetY: headingOffsets.currentContentOffsetY)
            }
        }
        .onDisappear {
            outlineJumpTask?.cancel()
            outlineJumpTask = nil
        }
    }

    private var documentScroll: some View {
        ScrollView {
            HStack(spacing: 0) {
                Spacer(minLength: AtelierMetrics.spaceL)
                AgentMarkdownView(
                    source: document.source,
                    bodyFontSize: AtelierTypography.editorSize,
                    presentation: .document,
                    blocks: document.blocks,
                    inlineRuns: document.inlineRuns
                )
                .equatable()
                .frame(maxWidth: AtelierMetrics.documentMaxWidth, alignment: .leading)
                .padding(.vertical, AtelierMetrics.space2XL)
                Spacer(minLength: AtelierMetrics.spaceL)
            }
            .padding(.horizontal, AtelierMetrics.spaceXL)
            .frame(maxWidth: .infinity, alignment: .center)
            .coordinateSpace(name: MarkdownDocumentCoordinateSpace.name)
        }
        .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.editor)
        .introspect(.scrollView, on: .macOS(.v26)) { scrollView in
            documentScrollSurface.scrollView = scrollView
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            // Coarser than heading store quantize: fewer selection passes while scrolling.
            MarkdownOutlineSyncPolicy.quantizeOffset(geometry.contentOffset.y / 4) * 4
        } action: { oldOffset, newOffset in
            guard oldOffset != newOffset else { return }
            syncOutlineSelection(contentOffsetY: newOffset)
        }
    }

    private func jumpToOutlineEntry(_ entry: MarkdownOutlineEntry, proxy: ScrollViewProxy) {
        selectedOutlineID = entry.id
        // Suppress passive selection rewrites while the jump settles.
        headingOffsets.setSuppressSyncUntil(Date().addingTimeInterval(0.55))
        outlineJumpTask?.cancel()

        let animated = !reduceMotion
        let duration = TimeInterval(AtelierMotionTokens.standard)

        // Fast path: heading already measured — drive NSScrollView directly.
        if let y = headingOffsets.offset(for: entry.id),
           documentScrollSurface.scrollToContentY(y, animated: animated, duration: duration) {
            headingOffsets.setContentOffset(y)
            return
        }

        // Slow path: LazyVStack may not have built the target yet.
        // 1) Jump near a measured predecessor to force materialization.
        // 2) Retry SwiftUI scrollTo + AppKit settle.
        let priorID = MarkdownOutlineSyncPolicy.nearestMeasuredID(
            targetID: entry.id,
            entries: document.outline,
            offsets: headingOffsets.snapshotOffsets()
        )

        outlineJumpTask = Task { @MainActor in
            if let priorID, priorID != entry.id {
                var seed = Transaction()
                seed.disablesAnimations = true
                withTransaction(seed) {
                    proxy.scrollTo(priorID, anchor: .top)
                }
                try? await Task.sleep(for: .milliseconds(24))
                guard !Task.isCancelled else { return }
            }

            for (attempt, delayMs) in [0, 24, 72, 160, 320].enumerated() {
                guard !Task.isCancelled else { return }
                if delayMs > 0 {
                    try? await Task.sleep(for: .milliseconds(delayMs))
                    guard !Task.isCancelled else { return }
                }

                if let y = headingOffsets.offset(for: entry.id),
                   documentScrollSurface.scrollToContentY(
                    y,
                    animated: animated && attempt == 0,
                    duration: duration
                   ) {
                    headingOffsets.setContentOffset(y)
                    return
                }

                if animated, attempt == 0 {
                    withAnimation(.easeOut(duration: duration)) {
                        proxy.scrollTo(entry.id, anchor: .top)
                    }
                } else {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(entry.id, anchor: .top)
                    }
                }
            }
        }
    }

    private func syncOutlineSelection(contentOffsetY: CGFloat) {
        guard !headingOffsets.isSyncSuppressed else { return }
        headingOffsets.setContentOffset(contentOffsetY)
        let active = headingOffsets.activeOutlineID(entries: document.outline)
        if selectedOutlineID != active {
            selectedOutlineID = active
        }
    }
}

enum MarkdownFileDocumentPolicy {
    static func showsOutline(headingCount: Int, containerWidth: CGFloat) -> Bool {
        guard headingCount >= 2, containerWidth > 0 else { return false }
        let required =
            AtelierMetrics.documentMaxWidth
            + AtelierMetrics.markdownOutlineWidth
            + AtelierMetrics.space2XL * 2
        return containerWidth >= required
    }
}

private struct MarkdownDocumentOutline: View {
    let entries: [MarkdownOutlineEntry]
    let selectedID: String?
    let onSelect: (MarkdownOutlineEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("On This Page")
                .atelierFont(size: AtelierTypography.micro, weight: .semibold)
                .foregroundStyle(.secondary)
                .tracking(0.7)
                .textCase(.uppercase)
                .padding(.horizontal, AtelierMetrics.spaceM)
                .padding(.top, AtelierMetrics.spaceL)
                .padding(.bottom, AtelierMetrics.spaceS)
                .accessibilityAddTraits(.isHeader)

            ScrollView {
                // Outline lists are small; eager VStack avoids lazy recycling jank.
                // Do not auto-scroll this rail during document scroll — that fights freewheel.
                VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
                    ForEach(entries) { entry in
                        MarkdownOutlineRow(
                            entry: entry,
                            isSelected: selectedID == entry.id,
                            onSelect: { onSelect(entry) }
                        )
                        .equatable()
                        .id(entry.id)
                    }
                }
                .padding(.bottom, AtelierMetrics.spaceL)
            }
            .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.panel)
        }
        .frame(width: AtelierMetrics.markdownOutlineWidth)
        .background(AtelierTheme.panel.opacity(0.72))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(width: AtelierTheme.strokeHairline)
        }
        // Whole rail claims pointer so AppKit text cursors cannot bleed in.
        .contentShape(Rectangle())
        .atelierPointerCursor()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Document outline")
    }
}

private struct MarkdownOutlineRow: View, Equatable {
    let entry: MarkdownOutlineEntry
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovering = false

    static func == (lhs: MarkdownOutlineRow, rhs: MarkdownOutlineRow) -> Bool {
        lhs.entry == rhs.entry && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Button(action: onSelect) {
            Text(verbatim: entry.title)
                .atelierFont(
                    size: entry.level <= 2
                        ? AtelierTypography.caption
                        : AtelierTypography.micro,
                    weight: entry.level == 1 ? .semibold : .regular
                )
                .foregroundStyle(isSelected ? AtelierTheme.accent : .secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .padding(.leading, outlineIndent(for: entry.level))
                .padding(.vertical, AtelierMetrics.spaceXS)
                .padding(.horizontal, AtelierMetrics.spaceM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .background {
                    RoundedRectangle(
                        cornerRadius: AtelierTheme.rowRadius,
                        style: .continuous
                    )
                    .fill(rowFill)
                    .padding(.horizontal, AtelierMetrics.spaceXS)
                }
        }
        .buttonStyle(.plain)
        .atelierPointerCursor()
        .onHover { hovering in
            isHovering = hovering
            // Force AppKit cursor: NSTextView under preview can otherwise keep I-beam.
            if hovering {
                NSCursor.pointingHand.set()
            }
        }
        .accessibilityLabel("Jump to \(entry.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowFill: Color {
        if isSelected {
            AtelierTheme.accent.opacity(0.10)
        } else if isHovering {
            AtelierTheme.hoverFill
        } else {
            Color.clear
        }
    }

    private func outlineIndent(for level: Int) -> CGFloat {
        CGFloat(max(0, min(level, 4) - 1)) * AtelierMetrics.spaceS
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
