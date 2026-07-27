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
                MarkdownFileDocumentView(
                    source: source,
                    sourceDirectoryURL: fileURL.deletingLastPathComponent()
                )
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

struct MarkdownFileTabView: View {
    let file: EditorSession
    let isActive: Bool
    let showsPreview: Bool
    let onEdit: () -> Void

    @State private var document: ParsedMarkdownDocument = .empty
    @State private var selectedOutlineID: String?
    @State private var containerWidth: CGFloat = 0
    @State private var sourceHeadingLines: [String: Int] = [:]
    @State private var jumpGeneration = 0
    @State private var previewJumpRequest: MarkdownPreviewJumpRequest?
    @State private var sourceRevealRequest: FileViewerRevealRequest?
    @State private var readingProgress: CGFloat = 0

    private var source: String {
        guard case .text(let source) = file.content else { return "" }
        return source
    }

    private var showsOutline: Bool {
        MarkdownFileDocumentPolicy.showsOutline(
            headingCount: document.outline.count,
            containerWidth: containerWidth
        )
    }

    /// Only cover a loaded, genuinely empty document; loading must not flash the state.
    private var showsEmptyPreview: Bool {
        guard case .text = file.content else { return false }
        return document.blocks.isEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                FileViewer(
                    content: file.content,
                    fileURL: file.document.url,
                    isActive: isActive && !showsPreview,
                    isWordWrapEnabled: file.isWordWrapEnabled,
                    surfaceOwner: file,
                    revealRequest: sourceRevealRequest,
                    onEdit: onEdit
                )
                .opacity(showsPreview ? 0 : 1)
                .allowsHitTesting(!showsPreview)
                .accessibilityHidden(showsPreview)
                .zIndex(0)

                MarkdownSelectableDocumentView(
                    document: document,
                    isActive: isActive && showsPreview,
                    jumpRequest: previewJumpRequest,
                    selectedOutlineID: $selectedOutlineID,
                    readingProgress: $readingProgress
                )
                .opacity(showsPreview ? 1 : 0)
                .allowsHitTesting(showsPreview)
                .accessibilityHidden(!showsPreview)
                .zIndex(1)

                if showsPreview, showsEmptyPreview {
                    MarkdownEmptyPreview()
                        .zIndex(2)
                }
            }

            if showsOutline {
                MarkdownDocumentOutline(
                    entries: document.outline,
                    selectedID: selectedOutlineID,
                    readingProgress: readingProgress,
                    onSelect: jumpToOutlineEntry
                )
            }
        }
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
            document = ParsedMarkdownDocument(
                source: newSource,
                sourceDirectoryURL: file.document.url.deletingLastPathComponent()
            )
            sourceHeadingLines = MarkdownSourceOutlinePolicy.lineNumberByOutlineID(
                source: newSource,
                entries: document.outline
            )
            if !document.outline.contains(where: { $0.id == selectedOutlineID }) {
                selectedOutlineID = document.outline.first?.id
            }
        }
        .onChange(of: file.navigationRevealRequest, initial: true) { _, request in
            guard let request else { return }
            jumpGeneration &+= 1
            sourceRevealRequest = FileViewerRevealRequest(
                line: request.line,
                generation: jumpGeneration
            )
        }
    }

    private func jumpToOutlineEntry(_ entry: MarkdownOutlineEntry) {
        selectedOutlineID = entry.id
        jumpGeneration += 1
        previewJumpRequest = MarkdownPreviewJumpRequest(
            outlineID: entry.id,
            generation: jumpGeneration
        )
        if let line = sourceHeadingLines[entry.id] {
            sourceRevealRequest = FileViewerRevealRequest(
                line: line,
                generation: jumpGeneration
            )
        }
    }
}

private struct MarkdownFileDocumentView: View {
    let source: String
    let sourceDirectoryURL: URL

    @State private var document: ParsedMarkdownDocument = .empty
    @State private var selectedOutlineID: String?
    @State private var containerWidth: CGFloat = 0
    @State private var jumpGeneration = 0
    @State private var jumpRequest: MarkdownPreviewJumpRequest?
    @State private var readingProgress: CGFloat = 0

    private var showsOutline: Bool {
        MarkdownFileDocumentPolicy.showsOutline(
            headingCount: document.outline.count,
            containerWidth: containerWidth
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack {
                MarkdownSelectableDocumentView(
                    document: document,
                    isActive: true,
                    jumpRequest: jumpRequest,
                    selectedOutlineID: $selectedOutlineID,
                    readingProgress: $readingProgress
                )
                if document.blocks.isEmpty {
                    MarkdownEmptyPreview()
                }
            }
            if showsOutline {
                MarkdownDocumentOutline(
                    entries: document.outline,
                    selectedID: selectedOutlineID,
                    readingProgress: readingProgress,
                    onSelect: jumpToOutlineEntry
                )
            }
        }
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
            document = ParsedMarkdownDocument(
                source: newSource,
                sourceDirectoryURL: sourceDirectoryURL
            )
            selectedOutlineID = document.outline.first?.id
        }
    }

    private func jumpToOutlineEntry(_ entry: MarkdownOutlineEntry) {
        selectedOutlineID = entry.id
        jumpGeneration += 1
        jumpRequest = MarkdownPreviewJumpRequest(
            outlineID: entry.id,
            generation: jumpGeneration
        )
    }
}

/// Quiet cover for an empty parsed document. The native text view stays mounted behind it.
private struct MarkdownEmptyPreview: View {
    var body: some View {
        AtelierEmptyState(
            systemImage: "doc.richtext",
            title: "Nothing to Preview",
            message: "This Markdown file has no rendered content yet."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AtelierTheme.editor)
    }
}

nonisolated enum MarkdownSourceOutlinePolicy {
    static func lineNumberByOutlineID(
        source: String,
        entries: [MarkdownOutlineEntry]
    ) -> [String: Int] {
        guard !entries.isEmpty else { return [:] }
        let lines = source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).map(String.init)
        var result: [String: Int] = [:]
        var entryIndex = 0
        var fence: (character: Character, length: Int)?

        for (lineIndex, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let activeFence = fence {
                let markerLength = trimmed.prefix {
                    $0 == activeFence.character
                }.count
                if markerLength >= activeFence.length,
                   trimmed.allSatisfy({ $0 == activeFence.character }) {
                    fence = nil
                }
                continue
            }

            if let marker = trimmed.first,
               marker == "`" || marker == "~" {
                let markerLength = trimmed.prefix { $0 == marker }.count
                if markerLength >= 3 {
                    fence = (marker, markerLength)
                    continue
                }
            }

            let level = trimmed.prefix { $0 == "#" }.count
            guard (1...6).contains(level),
                  trimmed.dropFirst(level).first == " " else { continue }
            let title = trimmed.dropFirst(level + 1)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, entryIndex < entries.count else { continue }
            result[entries[entryIndex].id] = lineIndex + 1
            entryIndex += 1
        }
        return result
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
    let readingProgress: CGFloat
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
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(AtelierTheme.border)
                        .frame(width: AtelierTheme.strokeHairline)
                    Rectangle()
                        .fill(AtelierTheme.accent)
                        .frame(
                            width: 1,
                            height: geometry.size.height
                                * min(1, max(0, readingProgress))
                        )
                }
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
        }
        // Whole rail claims pointer so AppKit text cursors cannot bleed in.
        .contentShape(Rectangle())
        .atelierPointerCursor()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Document outline")
    }
}

private enum MarkdownOutlineRowLayout {
    static let indicatorWidth: CGFloat = 2
    static let indicatorHeight: CGFloat = 14
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
                .foregroundStyle(labelStyle)
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
                .overlay(alignment: .leading) {
                    // Static marker: never animate the rail during passive scroll.
                    Capsule(style: .continuous)
                        .fill(AtelierTheme.accent)
                        .frame(
                            width: MarkdownOutlineRowLayout.indicatorWidth,
                            height: MarkdownOutlineRowLayout.indicatorHeight
                        )
                        .padding(.leading, AtelierMetrics.spaceXS)
                        .opacity(isSelected ? 1 : 0)
                        .accessibilityHidden(true)
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

    private var labelStyle: Color {
        if isSelected {
            AtelierTheme.accent
        } else if isHovering {
            Color.primary
        } else {
            Color.secondary
        }
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
