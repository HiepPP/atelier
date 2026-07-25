import AppKit
import SwiftUI

nonisolated enum AgentCodeBlockPolicy {
    static let displayLimit = 8_000

    static func displayedContent(_ source: String) -> String {
        guard source.count > displayLimit else { return source }
        return String(source.prefix(displayLimit)) + "\n..."
    }

    static func copiedContent(_ source: String) -> String {
        source
    }
}

nonisolated enum AgentCodeHighlightPolicy {
    static func languageName(for markdownLanguage: String?) -> String? {
        guard let markdownLanguage else { return nil }
        let normalized = markdownLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "js", "jsx", "mjs", "cjs", "javascript": return "javaScript"
        case "ts", "tsx", "mts", "cts", "typescript": return "typeScript"
        case "cpp", "c++", "cplusplus": return "cPlusPlus"
        case "cs", "c#", "csharp": return "cSharp"
        case "objc", "objective-c", "objectivec": return "objectiveC"
        case "graphql", "gql": return "graphQL"
        case "postgres", "postgresql": return "postgreSQL"
        case "proto", "protobuf": return "protocolBuffers"
        case "sh", "zsh": return "bash"
        case "md": return "markdown"
        case "text", "txt": return "plaintext"
        case "yml": return "yaml"
        default: return normalized.isEmpty ? nil : normalized
        }
    }
}

enum AgentMarkdownInlinePolicy {
    private enum ContentKind: Hashable {
        case markdown
        case plain
    }

    private struct CacheKey: Hashable {
        let content: String
        let kind: ContentKind
        let showsColorSwatches: Bool
    }

    private static let cacheLimit = 512
    private static let colorTokenExpression = try? NSRegularExpression(
        pattern: "(?<![0-9A-Za-z])#(?:[0-9A-Fa-f]{8}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{3})(?![0-9A-Za-z])"
    )
    private static var cache: [CacheKey: AttributedString] = [:]
    private static var cacheOrder: [CacheKey] = []

    /// Whole-cell / whole-span inline code only. Used to draw one continuous accent
    /// chip so soft-wrapped paths do not zebra per line fragment.
    static func pureCodeContent(_ markdown: String) -> String? {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              trimmed.first == "`",
              trimmed.last == "`" else {
            return nil
        }
        let inner = String(trimmed.dropFirst().dropLast())
        // Reject multi-span or empty payloads; nested fences belong to block parsing.
        guard !inner.isEmpty, !inner.contains("`") else { return nil }
        return inner
    }

    static func attributedString(
        _ content: String,
        showsColorSwatches: Bool = false
    ) -> AttributedString {
        cachedAttributedString(
            content,
            kind: .markdown,
            showsColorSwatches: showsColorSwatches
        )
    }

    static func plainAttributedString(
        _ content: String,
        showsColorSwatches: Bool
    ) -> AttributedString {
        cachedAttributedString(
            content,
            kind: .plain,
            showsColorSwatches: showsColorSwatches
        )
    }

    static func addingColorSwatches(to attributed: AttributedString) -> AttributedString {
        guard let colorTokenExpression else { return attributed }
        var decorated = attributed
        let rendered = String(decorated.characters)
        let fullRange = NSRange(rendered.startIndex..<rendered.endIndex, in: rendered)
        let matches = colorTokenExpression.matches(in: rendered, range: fullRange)

        for match in matches.reversed() {
            guard let stringRange = Range(match.range, in: rendered),
                  let insertionIndex = AttributedString.Index(
                      stringRange.lowerBound,
                      within: decorated
                  ),
                  let color = color(for: String(rendered[stringRange])) else {
                continue
            }
            var swatch = AttributedString("\u{25A0}")
            swatch.foregroundColor = color
            swatch.font = .system(size: AtelierTypography.editorSize)
            decorated.insert(swatch, at: insertionIndex)
        }
        return decorated
    }

    private static func cachedAttributedString(
        _ content: String,
        kind: ContentKind,
        showsColorSwatches: Bool
    ) -> AttributedString {
        let key = CacheKey(
            content: content,
            kind: kind,
            showsColorSwatches: showsColorSwatches
        )
        if let cached = cache[key] {
            return cached
        }

        var attributed: AttributedString
        switch kind {
        case .markdown:
            let options = AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
            attributed = (try? AttributedString(markdown: content, options: options))
                ?? AttributedString(content)
            let codeRanges = attributed.runs.compactMap { run in
                run.inlinePresentationIntent?.contains(.code) == true ? run.range : nil
            }
            for range in codeRanges {
                attributed[range].foregroundColor = AtelierTheme.accent
                // Short mixed-prose chips stay filled. Pure soft-wrapped code in tables
                // uses `pureCodeContent` + a View-level chip so fills do not zebra.
                attributed[range].backgroundColor = AtelierTheme.accent.opacity(0.12)
            }
        case .plain:
            attributed = AttributedString(content)
        }

        if showsColorSwatches {
            attributed = addingColorSwatches(to: attributed)
        }
        storeCached(key, attributed)
        return attributed
    }

    private static func color(for token: String) -> Color? {
        guard token.first == "#" else { return nil }
        let hex = token.dropFirst()
        let expanded: String
        switch hex.count {
        case 3:
            expanded = doubled(hex) + "FF"
        case 4:
            expanded = doubled(hex)
        case 6:
            expanded = String(hex) + "FF"
        case 8:
            expanded = String(hex)
        default:
            return nil
        }
        guard let rgba = UInt32(expanded, radix: 16) else { return nil }
        return Color(
            .sRGB,
            red: Double((rgba >> 24) & 0xFF) / 255,
            green: Double((rgba >> 16) & 0xFF) / 255,
            blue: Double((rgba >> 8) & 0xFF) / 255,
            opacity: Double(rgba & 0xFF) / 255
        )
    }

    private static func doubled(_ hex: Substring) -> String {
        hex.reduce(into: "") { result, digit in
            result.append(digit)
            result.append(digit)
        }
    }

    private static func storeCached(_ key: CacheKey, _ value: AttributedString) {
        if cache[key] == nil {
            cacheOrder.append(key)
        }
        cache[key] = value
        while cacheOrder.count > cacheLimit {
            let evicted = cacheOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }
}

nonisolated enum MermaidResponsePresentationPolicy {
    enum DisplayState: Equatable, Sendable {
        case loading
        case rendered
        case failed(String)
    }

    static func showsSource(userRequested: Bool, hasRenderError: Bool) -> Bool {
        userRequested || hasRenderError
    }

    static func displayState(hasImage: Bool, error: String?) -> DisplayState {
        if let error { return .failed(error) }
        return hasImage ? .rendered : .loading
    }
}

/// Shared pull-quote geometry for both Markdown surfaces.
nonisolated enum MarkdownQuoteLayout {
    static let barWidth: CGFloat = 3
    static let leadingInset: CGFloat = 5
    static let indent: CGFloat = 20
}

/// Shared front-matter card geometry.
nonisolated enum MarkdownFrontMatterLayout {
    static let keyColumnWidth: CGFloat = 132
    static let keyColumnPercentage: CGFloat = 26
}

/// Layout and type treatment for Markdown surfaces.
/// - `transcript`: compact agent responses
/// - `document`: file-preview reading layout
nonisolated enum AgentMarkdownPresentation: Equatable, Sendable {
    case transcript
    case document
}

enum MarkdownDocumentCoordinateSpace {
    nonisolated static let name = "atelier.markdown.document"
}

nonisolated struct MarkdownOutlineEntry: Equatable, Identifiable, Sendable {
    let id: String
    let level: Int
    let title: String
}

/// Maps document scroll position to the outline entry that owns the viewport.
nonisolated enum MarkdownOutlineSyncPolicy {
    static let viewportLead: CGFloat = 64
    /// Ignore sub-pixel offset thrash while still catching section boundaries.
    static let offsetQuantization: CGFloat = 0.5

    static func quantizeOffset(_ value: CGFloat) -> CGFloat {
        (value / offsetQuantization).rounded() * offsetQuantization
    }

    static func activeOutlineID(
        entries: [MarkdownOutlineEntry],
        offsets: [String: CGFloat],
        contentOffsetY: CGFloat,
        lead: CGFloat = viewportLead
    ) -> String? {
        guard !entries.isEmpty else { return nil }
        let threshold = max(0, contentOffsetY) + lead
        var active: String?
        for entry in entries {
            guard let y = offsets[entry.id] else { continue }
            if y <= threshold {
                active = entry.id
            } else if active != nil {
                break
            }
        }
        return active ?? entries.first?.id
    }

    /// Nearest already-measured heading at or before `targetID` (for LazyVStack materialization).
    static func nearestMeasuredID(
        targetID: String,
        entries: [MarkdownOutlineEntry],
        offsets: [String: CGFloat]
    ) -> String? {
        var nearest: String?
        for entry in entries {
            if offsets[entry.id] != nil {
                nearest = entry.id
            }
            if entry.id == targetID {
                return nearest
            }
        }
        return nearest
    }

    static func clampedContentOffset(
        targetY: CGFloat,
        viewportHeight: CGFloat,
        contentHeight: CGFloat
    ) -> CGFloat {
        let maxOrigin = max(0, contentHeight - max(viewportHeight, 1))
        return min(max(0, targetY), maxOrigin)
    }
}

/// Class-backed heading offsets. Mutations do not invalidate SwiftUI views.
final class MarkdownHeadingOffsetStore: @unchecked Sendable {
    private let lock = NSLock()
    private var map: [String: CGFloat] = [:]
    private var contentOffsetY: CGFloat = 0
    private var suppressSyncUntil: Date?

    func reset() {
        lock.lock()
        map.removeAll(keepingCapacity: true)
        contentOffsetY = 0
        suppressSyncUntil = nil
        lock.unlock()
    }

    func setContentOffset(_ y: CGFloat) {
        lock.lock()
        contentOffsetY = y
        lock.unlock()
    }

    func setSuppressSyncUntil(_ date: Date?) {
        lock.lock()
        suppressSyncUntil = date
        lock.unlock()
    }

    @discardableResult
    func setOffset(id: String, y: CGFloat) -> Bool {
        let quantized = MarkdownOutlineSyncPolicy.quantizeOffset(y)
        lock.lock()
        defer { lock.unlock() }
        if let old = map[id], abs(old - quantized) < 0.25 {
            return false
        }
        map[id] = quantized
        return true
    }

    func offset(for id: String) -> CGFloat? {
        lock.lock()
        defer { lock.unlock() }
        return map[id]
    }

    func snapshotOffsets() -> [String: CGFloat] {
        lock.lock()
        defer { lock.unlock() }
        return map
    }

    func activeOutlineID(entries: [MarkdownOutlineEntry]) -> String? {
        lock.lock()
        let snapshot = map
        let offsetY = contentOffsetY
        lock.unlock()
        return MarkdownOutlineSyncPolicy.activeOutlineID(
            entries: entries,
            offsets: snapshot,
            contentOffsetY: offsetY
        )
    }

    var currentContentOffsetY: CGFloat {
        lock.lock()
        defer { lock.unlock() }
        return contentOffsetY
    }

    var isSyncSuppressed: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let suppressSyncUntil else { return false }
        return Date() < suppressSyncUntil
    }
}

/// Weak AppKit handle for reliable outline jumps (SwiftUI scrollTo is flaky with LazyVStack).
final class MarkdownDocumentScrollSurface: @unchecked Sendable {
    weak var scrollView: NSScrollView?

    @discardableResult
    func scrollToContentY(_ y: CGFloat, animated: Bool, duration: TimeInterval) -> Bool {
        guard let scrollView,
              let documentView = scrollView.documentView else { return false }
        let clipView = scrollView.contentView
        let targetY = MarkdownOutlineSyncPolicy.clampedContentOffset(
            targetY: y,
            viewportHeight: clipView.bounds.height,
            contentHeight: documentView.frame.height
        )
        var origin = clipView.bounds.origin
        guard abs(origin.y - targetY) > 0.5 else {
            scrollView.reflectScrolledClipView(clipView)
            return true
        }
        origin.y = targetY
        if animated, duration > 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.allowsImplicitAnimation = true
                clipView.animator().setBoundsOrigin(origin)
                scrollView.reflectScrolledClipView(clipView)
            }
        } else {
            clipView.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(clipView)
        }
        return true
    }
}

private struct MarkdownHeadingOffsetStoreKey: EnvironmentKey {
    static let defaultValue: MarkdownHeadingOffsetStore? = nil
}

extension EnvironmentValues {
    var markdownHeadingOffsetStore: MarkdownHeadingOffsetStore? {
        get { self[MarkdownHeadingOffsetStoreKey.self] }
        set { self[MarkdownHeadingOffsetStoreKey.self] = newValue }
    }
}

/// One-shot parse shared by document layout, outline, and block rendering.
struct ParsedMarkdownDocument: Equatable {
    let source: String
    let blocks: [AgentMarkdownBlock]
    let outline: [MarkdownOutlineEntry]
    /// Pre-parsed inline runs aligned with `blocks` (nil for non-text blocks).
    let inlineRuns: [AttributedString?]

    static let empty = ParsedMarkdownDocument(
        source: "",
        blocks: [],
        outline: [],
        inlineRuns: []
    )

    init(source: String) {
        self.source = source
        let blocks = AgentMarkdownBlock.parse(source)
        self.blocks = blocks
        self.outline = AgentMarkdownBlock.outline(from: blocks)
        self.inlineRuns = Self.makeInlineRuns(for: blocks)
    }

    init(source: String, blocks: [AgentMarkdownBlock]) {
        self.source = source
        self.blocks = blocks
        self.outline = AgentMarkdownBlock.outline(from: blocks)
        self.inlineRuns = Self.makeInlineRuns(for: blocks)
    }

    init(
        source: String,
        blocks: [AgentMarkdownBlock],
        outline: [MarkdownOutlineEntry],
        inlineRuns: [AttributedString?] = []
    ) {
        self.source = source
        self.blocks = blocks
        self.outline = outline
        self.inlineRuns = inlineRuns
    }

    private static func makeInlineRuns(for blocks: [AgentMarkdownBlock]) -> [AttributedString?] {
        blocks.map { block in
            guard let text = AgentMarkdownBlock.inlineSource(for: block) else { return nil }
            return AgentMarkdownInlinePolicy.attributedString(
                text,
                showsColorSwatches: true
            )
        }
    }
}

struct AgentMarkdownView: View, Equatable {
    let source: String
    let bodyFontSize: CGFloat
    let presentation: AgentMarkdownPresentation
    let blocks: [AgentMarkdownBlock]?
    let inlineRuns: [AttributedString?]?

    @Environment(\.markdownHeadingOffsetStore) private var headingOffsetStore

    init(
        source: String,
        bodyFontSize: CGFloat = AtelierTypography.body,
        presentation: AgentMarkdownPresentation = .transcript,
        blocks: [AgentMarkdownBlock]? = nil,
        inlineRuns: [AttributedString?]? = nil
    ) {
        self.source = source
        self.bodyFontSize = bodyFontSize
        self.presentation = presentation
        self.blocks = blocks
        self.inlineRuns = inlineRuns
    }

    static func == (lhs: AgentMarkdownView, rhs: AgentMarkdownView) -> Bool {
        // Source identity is enough: blocks/inlines are derived for the same source.
        lhs.source == rhs.source
            && lhs.bodyFontSize == rhs.bodyFontSize
            && lhs.presentation == rhs.presentation
    }

    private var proseMaxWidth: CGFloat {
        presentation == .document
            ? AtelierMetrics.documentMaxWidth
            : AtelierMetrics.transcriptMaxWidth
    }

    private var proseLineSpacing: CGFloat {
        presentation == .document ? AtelierMetrics.spaceS : AtelierMetrics.spaceXS
    }

    private var resolvedBlocks: [AgentMarkdownBlock] {
        blocks ?? AgentMarkdownBlock.parse(source)
    }

    var body: some View {
        let resolved = resolvedBlocks
        Group {
            if presentation == .document {
                // Always lazy: eager VStack made free scroll hitch on medium/large files.
                // Outline jump uses AppKit offset + materialize retries instead.
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    blockStack(resolved)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    blockStack(resolved)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockStack(_ blocks: [AgentMarkdownBlock]) -> some View {
        ForEach(blocks.indices, id: \.self) { index in
            let block = blocks[index]
            let anchorID = AgentMarkdownBlock.blockAnchorID(index)
            blockView(block, index: index)
                .padding(.top, blockTopSpacing(for: block, at: index))
                .id(anchorID)
                .modifier(
                    MarkdownHeadingOffsetReporter(
                        isEnabled: presentation == .document && {
                            if case .heading = block { return true }
                            return false
                        }(),
                        anchorID: anchorID,
                        store: headingOffsetStore
                    )
                )
        }
    }

    @ViewBuilder
    private func blockView(_ block: AgentMarkdownBlock, index: Int) -> some View {
        switch block {
        case .frontMatter(let entries):
            frontMatter(entries)
        case .heading(let level, let content):
            heading(level: level, content: content, index: index)
        case .paragraph(let content):
            inlineText(content, index: index)
                .atelierFont(size: bodyFontSize)
                .lineSpacing(proseLineSpacing)
                .frame(maxWidth: proseMaxWidth, alignment: .leading)
        case .unorderedItem(let content):
            listRow(marker: .bullet, content: content, index: index)
                .frame(maxWidth: proseMaxWidth, alignment: .leading)
        case .orderedItem(let number, let content):
            listRow(marker: .number(number), content: content, index: index)
                .frame(maxWidth: proseMaxWidth, alignment: .leading)
        case .taskItem(let isCompleted, let content):
            listRow(
                marker: .task(isCompleted),
                content: content,
                index: index,
                isStruck: isCompleted
            )
            .frame(maxWidth: proseMaxWidth, alignment: .leading)
        case .quote(let content):
            HStack(alignment: .top, spacing: AtelierMetrics.spaceL) {
                Rectangle()
                    .fill(AtelierTheme.accent.opacity(0.62))
                    .frame(width: MarkdownQuoteLayout.barWidth)
                    .accessibilityHidden(true)
                inlineText(content, index: index)
                    .italic()
                    .atelierFont(size: bodyFontSize, design: .serif)
                    .lineSpacing(proseLineSpacing)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, AtelierMetrics.spaceXS)
            .frame(maxWidth: proseMaxWidth, alignment: .leading)
        case .code(let language, let content):
            codeBlock(language: language, content: content)
        case .mermaid(let source):
            MermaidResponseCard(source: source)
        case .invalidMermaid(let source, let error):
            MermaidResponseCard(source: source, parseError: error)
        case .table(let headers, let rows):
            table(headers: headers, rows: rows)
        case .divider:
            HStack(spacing: 0) {
                Rectangle()
                    .fill(AtelierTheme.accent.opacity(0.72))
                    .frame(width: AtelierMetrics.space2XL, height: AtelierTheme.strokeFocus)
                Rectangle()
                    .fill(AtelierTheme.border)
                    .frame(height: AtelierTheme.strokeHairline)
            }
            .frame(maxWidth: proseMaxWidth)
        }
    }

    private func heading(level: Int, content: String, index: Int) -> some View {
        VStack(alignment: .leading, spacing: level <= 2 ? AtelierMetrics.spaceS : 0) {
            inlineText(content, index: index)
                .atelierFont(
                    size: headingSize(level),
                    weight: headingWeight(level),
                    design: headingDesign(level)
                )
                .tracking(level == 1 ? -0.6 : (level == 2 ? -0.3 : -0.15))
                .foregroundStyle(level >= 4 ? .secondary : .primary)
                .accessibilityAddTraits(.isHeader)

            if level <= 2 {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(AtelierTheme.accent.opacity(level == 1 ? 0.9 : 0.62))
                        .frame(
                            width: level == 1 ? AtelierMetrics.space2XL : AtelierMetrics.spaceL,
                            height: AtelierTheme.strokeFocus
                        )
                    Rectangle()
                        .fill(AtelierTheme.border)
                        .frame(height: AtelierTheme.strokeHairline)
                }
                .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: proseMaxWidth, alignment: .leading)
        .padding(.top, presentation == .document && level <= 2 ? AtelierMetrics.spaceXS : 0)
    }

    /// Reports heading Y into a class store without PreferenceKey invalidation storms.
    private struct MarkdownHeadingOffsetReporter: ViewModifier {
        let isEnabled: Bool
        let anchorID: String
        let store: MarkdownHeadingOffsetStore?

        func body(content: Content) -> some View {
            if isEnabled, store != nil {
                content
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.frame(in: .named(MarkdownDocumentCoordinateSpace.name)).minY
                    } action: { _, minY in
                        store?.setOffset(id: anchorID, y: minY)
                    }
            } else {
                content
            }
        }
    }

    private func codeBlock(language: String?, content: String) -> some View {
        let bounded = AgentCodeBlockPolicy.displayedContent(content)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AtelierMetrics.spaceS) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                    .foregroundStyle(AtelierTheme.accent)
                    .accessibilityHidden(true)
                Text(language?.uppercased() ?? "CODE")
                    .atelierFont(
                        size: AtelierTypography.micro,
                        weight: .semibold,
                        design: .monospaced
                    )
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Spacer()
                MarkdownCopyButton(
                    source: AgentCodeBlockPolicy.copiedContent(content),
                    label: "Copy code"
                )
            }
            .padding(.horizontal, AtelierMetrics.spaceS)
            .frame(height: AtelierMetrics.fieldHeight)
            .background(AtelierTheme.raised)

            MarkdownHighlightedCodeText(
                content: bounded,
                languageName: AgentCodeHighlightPolicy.languageName(for: language),
                showsColorSwatches: presentation == .document
            )
            .padding(AtelierMetrics.spaceS)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .atelierCard()
    }

    @ViewBuilder
    private func table(headers: [String], rows: [[String]]) -> some View {
        if headers.count <= 3 {
            tableGrid(headers: headers, rows: rows, isFlexible: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                tableGrid(headers: headers, rows: rows, isFlexible: false)
            }
            .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.panel)
        }
    }

    private func tableGrid(
        headers: [String],
        rows: [[String]],
        isFlexible: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(headers.indices, id: \.self) { index in
                    tableCell(
                        headers[index],
                        isHeader: true,
                        isFlexible: isFlexible
                    )
                }
            }
            .background(AtelierTheme.accent.opacity(0.08))
            ForEach(rows.indices, id: \.self) { rowIndex in
                Divider()
                HStack(spacing: 0) {
                    ForEach(headers.indices, id: \.self) { columnIndex in
                        let value = rows[rowIndex].indices.contains(columnIndex)
                            ? rows[rowIndex][columnIndex]
                            : ""
                        tableCell(
                            value,
                            isHeader: false,
                            isFlexible: isFlexible
                        )
                    }
                }
                .background(
                    rowIndex.isMultiple(of: 2)
                        ? Color.clear
                        : AtelierTheme.raised.opacity(0.22)
                )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: AtelierTheme.controlRadius)
                .stroke(AtelierTheme.border, lineWidth: AtelierTheme.strokeControl)
        }
        .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
    }

    @ViewBuilder
    private func tableCell(
        _ value: String,
        isHeader: Bool,
        isFlexible: Bool
    ) -> some View {
        // Pure `code` cells use one View-level chip so soft-wrapped paths keep a
        // continuous fill. AttributedString.backgroundColor paints per line and
        // zebra-stripes multi-line skill paths in Markdown preview tables.
        let cell = Group {
            if let code = AgentMarkdownInlinePolicy.pureCodeContent(value) {
                Text(
                    AgentMarkdownInlinePolicy.plainAttributedString(
                        code,
                        showsColorSwatches: presentation == .document
                    )
                )
                    .atelierFont(
                        size: AtelierTypography.label,
                        weight: isHeader ? .semibold : .regular,
                        design: .monospaced
                    )
                    .foregroundStyle(AtelierTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, AtelierMetrics.spaceXS)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(AtelierTheme.accent.opacity(0.12))
                    )
            } else {
                Text(
                    AgentMarkdownInlinePolicy.attributedString(
                        value,
                        showsColorSwatches: presentation == .document
                    )
                )
                    .atelierFont(
                        size: AtelierTypography.label,
                        weight: isHeader ? .semibold : .regular
                    )
                    .tracking(isHeader ? 0.4 : 0)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, AtelierMetrics.spaceM)
        .padding(.vertical, AtelierMetrics.spaceS)

        if isFlexible {
            cell
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            cell
                .frame(width: 240, alignment: .leading)
        }
    }

    private func listRow(
        marker: MarkdownListMarker,
        content: String,
        index: Int,
        isStruck: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: AtelierMetrics.spaceM) {
            listMarker(marker)
                .frame(width: AtelierMetrics.spaceL, height: bodyFontSize + proseLineSpacing)
            inlineText(content, index: index)
                .strikethrough(isStruck, color: .secondary)
                .atelierFont(size: bodyFontSize)
                .lineSpacing(proseLineSpacing)
                .foregroundStyle(isStruck ? Color.secondary : Color.primary)
        }
        .accessibilityElement(children: .combine)
    }

    private func frontMatter(_ entries: [MarkdownFrontMatterEntry]) -> some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
            ForEach(entries.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: AtelierMetrics.spaceM) {
                    Text(verbatim: entries[index].key)
                        .atelierFont(
                            size: AtelierTypography.micro,
                            weight: .semibold,
                            design: .monospaced
                        )
                        .foregroundStyle(AtelierTheme.accent)
                        .frame(
                            width: MarkdownFrontMatterLayout.keyColumnWidth,
                            alignment: .leading
                        )
                    Text(verbatim: entries[index].value)
                        .atelierFont(size: AtelierTypography.label)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(AtelierMetrics.spaceM)
        .frame(maxWidth: proseMaxWidth, alignment: .leading)
        .atelierCard(fill: AtelierTheme.raised.opacity(0.32))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Front matter")
    }

    @ViewBuilder
    private func listMarker(_ marker: MarkdownListMarker) -> some View {
        switch marker {
        case .bullet:
            Circle()
                .fill(AtelierTheme.accent.opacity(0.82))
                .frame(width: 5, height: 5)
                .padding(.top, bodyFontSize * 0.46)
                .accessibilityHidden(true)
        case .number(let number):
            Text("\(number).")
                .atelierFont(size: AtelierTypography.label, weight: .semibold, design: .monospaced)
                .foregroundStyle(AtelierTheme.accent)
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .task(let isCompleted):
            Image(systemName: isCompleted ? "checkmark.square.fill" : "square")
                .atelierFont(size: AtelierTypography.uiSize, weight: .medium)
                .foregroundStyle(isCompleted ? AtelierTheme.accent : .secondary)
                .accessibilityLabel(isCompleted ? "Completed" : "Not completed")
        }
    }

    private func inlineText(_ content: String, index: Int) -> Text {
        if let inlineRuns,
           inlineRuns.indices.contains(index),
           let precomputed = inlineRuns[index] {
            return Text(precomputed)
        }
        return Text(
            AgentMarkdownInlinePolicy.attributedString(
                content,
                showsColorSwatches: presentation == .document
            )
        )
    }

    private func headingSize(_ level: Int) -> CGFloat {
        if presentation == .document {
            return switch level {
            case 1: max(28, bodyFontSize * 1.85)
            case 2: max(22, bodyFontSize * 1.45)
            case 3: max(AtelierTypography.headline, bodyFontSize * 1.18)
            default: max(AtelierTypography.uiSize, bodyFontSize)
            }
        }
        return switch level {
        case 1: max(AtelierTypography.display, bodyFontSize * 1.8)
        case 2: max(AtelierTypography.title, bodyFontSize * 1.45)
        case 3: max(AtelierTypography.headline, bodyFontSize * 1.2)
        default: max(AtelierTypography.uiSize, bodyFontSize)
        }
    }

    private func headingWeight(_ level: Int) -> Font.Weight {
        if presentation == .document {
            return level <= 2 ? .semibold : .medium
        }
        return level <= 2 ? .bold : .semibold
    }

    private func headingDesign(_ level: Int) -> Font.Design {
        if presentation == .document, level <= 2 {
            return .serif
        }
        return .default
    }

    private func blockTopSpacing(for block: AgentMarkdownBlock, at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        let documentBoost: CGFloat = presentation == .document ? AtelierMetrics.spaceS : 0
        return switch block {
        case .heading(let level, _):
            (level <= 2 ? AtelierMetrics.space2XL : AtelierMetrics.spaceXL) + documentBoost
        case .frontMatter:
            AtelierMetrics.spaceL
        case .code, .mermaid, .invalidMermaid, .table, .quote, .divider:
            AtelierMetrics.spaceL + (presentation == .document ? AtelierMetrics.spaceXS : 0)
        case .paragraph:
            AtelierMetrics.spaceM + documentBoost * 0.5
        case .unorderedItem, .orderedItem, .taskItem:
            presentation == .document ? AtelierMetrics.spaceS + 2 : AtelierMetrics.spaceS
        }
    }
}

/// Icon-only copy control shared by both Markdown surfaces. Confirms with a
/// checkmark, then restores itself; no owner state changes, no document rebuild.
struct MarkdownCopyButton: View {
    let source: String
    let label: String

    @State private var didCopy = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(source, forType: .string)
            didCopy = true
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .frame(width: AtelierMetrics.regularIconSize)
        }
        .buttonStyle(AtelierGhostButtonStyle(tint: didCopy ? AtelierTheme.accent : .primary))
        .accessibilityLabel(label)
        .help(label)
        .task(id: didCopy) {
            guard didCopy else { return }
            try? await Task.sleep(for: .milliseconds(1_100))
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }
}

private struct MarkdownHighlightedCodeText: View {
    private struct Request: Hashable {
        let content: String
        let languageName: String?
        let usesDarkAppearance: Bool
        let showsColorSwatches: Bool
    }

    private static let highlightService = SyntaxHighlightService()

    @Environment(\.colorScheme) private var colorScheme
    @State private var highlightedContent: AttributedString?

    let content: String
    let languageName: String?
    let showsColorSwatches: Bool

    var body: some View {
        Text(
            highlightedContent
                ?? AgentMarkdownInlinePolicy.plainAttributedString(
                    content,
                    showsColorSwatches: showsColorSwatches
                )
        )
            .atelierFont(size: AtelierTypography.label, design: .monospaced)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .task(id: request) {
                highlightedContent = nil
                // Yield so scroll/layout can finish before syntax work.
                await Task.yield()
                guard !Task.isCancelled else { return }
                do {
                    let result = try await Self.highlightService.highlightPreservingWhitespace(
                        content,
                        languageName: languageName,
                        usesDarkAppearance: request.usesDarkAppearance
                    )
                    guard !Task.isCancelled else { return }
                    highlightedContent = showsColorSwatches
                        ? AgentMarkdownInlinePolicy.addingColorSwatches(to: result)
                        : result
                } catch {
                    guard !Task.isCancelled else { return }
                    highlightedContent = nil
                }
            }
    }

    private var request: Request {
        Request(
            content: content,
            languageName: languageName,
            usesDarkAppearance: colorScheme == .dark,
            showsColorSwatches: showsColorSwatches
        )
    }
}

private enum MarkdownListMarker {
    case bullet
    case number(Int)
    case task(Bool)
}

struct MermaidResponseCard: View {
    let source: String
    let parseError: String?

    @State private var image: NSImage?
    @State private var imageSource: String?
    @State private var renderError: String?
    @State private var showsSource = false
    @State private var containerWidth: CGFloat = 480
    @State private var isRendering = false

    init(source: String, parseError: String? = nil) {
        self.source = source
        self.parseError = parseError
    }

    private var renderWidth: CGFloat {
        MermaidRenderingPolicy.widthBucket(containerWidth: containerWidth)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            HStack(spacing: AtelierMetrics.spaceS) {
                Label("Mermaid", systemImage: "point.3.connected.trianglepath.dotted")
                    .atelierFont(
                        size: AtelierTypography.caption,
                        weight: .semibold,
                        design: .monospaced
                    )
                    .foregroundStyle(AtelierTheme.accent)
                Spacer()
                Button(showsSource ? "Hide source" : "View source") {
                    showsSource.toggle()
                }
                .buttonStyle(AtelierGhostButtonStyle())
                .accessibilityLabel(showsSource ? "Hide Mermaid source" : "View Mermaid source")
            }

            switch MermaidResponsePresentationPolicy.displayState(
                hasImage: image != nil,
                error: parseError ?? renderError
            ) {
            case .rendered:
                if let image {
                    ZStack(alignment: .topTrailing) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isRendering {
                            ProgressView()
                                .controlSize(.small)
                                .padding(AtelierMetrics.spaceS)
                                .background(.regularMaterial)
                                .clipShape(Circle())
                        }
                    }
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .atelierFont(size: AtelierTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }

            if MermaidResponsePresentationPolicy.showsSource(
                userRequested: showsSource,
                hasRenderError: parseError != nil || renderError != nil
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("MERMAID SOURCE")
                            .atelierFont(
                                size: AtelierTypography.micro,
                                weight: .semibold,
                                design: .monospaced
                            )
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        Spacer()
                        MarkdownCopyButton(
                            source: source,
                            label: "Copy Mermaid source"
                        )
                    }
                    .padding(.horizontal, AtelierMetrics.spaceS)
                    .frame(height: AtelierMetrics.fieldHeight)
                    .background(AtelierTheme.raised)

                    Text(source)
                        .atelierFont(size: AtelierTypography.label, design: .monospaced)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AtelierMetrics.spaceM)
                }
                .background(AtelierTheme.editor)
                .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
            }
        }
        .padding(AtelierMetrics.spaceM)
        .atelierCard()
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { containerWidth = max(1, geometry.size.width) }
                    .onChange(of: geometry.size.width) { _, width in
                        // Defer off the layout pass: mutating state synchronously here
                        // re-enters AppKit layout and can trap during window zoom.
                        Task { @MainActor in
                            containerWidth = max(1, width)
                        }
                    }
            }
        }
        .task(id: MermaidRenderRequest(
            source: source,
            width: Int(renderWidth),
            parseError: parseError
        )) {
            guard parseError == nil else {
                image = nil
                imageSource = nil
                renderError = nil
                isRendering = false
                return
            }
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
            }
            if imageSource != source {
                image = nil
                imageSource = nil
            }
            renderError = nil
            isRendering = true
            defer { isRendering = false }
            do {
                let rendered = try await MermaidImageCache.shared.image(
                    source: source,
                    width: renderWidth
                )
                guard !Task.isCancelled else { return }
                image = rendered
                imageSource = source
            } catch {
                guard !Task.isCancelled else { return }
                renderError = "Mermaid syntax could not be rendered. Source is shown below."
            }
        }
    }
}

private struct MermaidRenderRequest: Hashable {
    let source: String
    let width: Int
    let parseError: String?
}

nonisolated struct MarkdownFrontMatterEntry: Equatable, Sendable {
    let key: String
    let value: String
}

/// Leading YAML front matter recognized as one metadata block. Deliberately strict:
/// anything that is not `key: value`, a `- item` continuation, or a blank line falls
/// back to normal block parsing so a plain `---` divider keeps its meaning.
nonisolated enum MarkdownFrontMatterPolicy {
    static let maximumLineCount = 64
    static let maximumKeyLength = 48

    static func parse(
        _ lines: [String]
    ) -> (entries: [MarkdownFrontMatterEntry], endIndex: Int)? {
        guard let opening = lines.first,
              opening.trimmingCharacters(in: .whitespaces) == "---" else { return nil }
        var entries: [MarkdownFrontMatterEntry] = []
        var parents: [(indent: Int, key: String)] = []
        var index = 1
        let limit = min(lines.count, maximumLineCount + 1)

        while index < limit {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" || trimmed == "..." {
                return entries.isEmpty ? nil : (entries, index + 1)
            }
            if trimmed.isEmpty {
                index += 1
                continue
            }
            let indent = line.prefix { $0 == " " || $0 == "\t" }.count

            if let item = listItem(trimmed) {
                guard !parents.isEmpty else { return nil }
                append(item, to: keyPath(parents), in: &entries)
                index += 1
                continue
            }

            guard let field = field(trimmed) else { return nil }
            while let parent = parents.last, parent.indent >= indent {
                parents.removeLast()
            }
            parents.append((indent, field.key))
            if !field.value.isEmpty {
                entries.append(
                    MarkdownFrontMatterEntry(key: keyPath(parents), value: field.value)
                )
            }
            index += 1
        }
        return nil
    }

    private static func keyPath(_ parents: [(indent: Int, key: String)]) -> String {
        parents.map(\.key).joined(separator: ".")
    }

    private static func append(
        _ value: String,
        to key: String,
        in entries: inout [MarkdownFrontMatterEntry]
    ) {
        if let last = entries.indices.last, entries[last].key == key {
            entries[last] = MarkdownFrontMatterEntry(
                key: key,
                value: entries[last].value.isEmpty
                    ? value
                    : entries[last].value + ", " + value
            )
        } else {
            entries.append(MarkdownFrontMatterEntry(key: key, value: value))
        }
    }

    private static func listItem(_ line: String) -> String? {
        guard line.hasPrefix("- ") else { return nil }
        let value = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : unquoted(value)
    }

    private static func field(_ line: String) -> (key: String, value: String)? {
        guard let separator = line.firstIndex(of: ":") else { return nil }
        let key = String(line[..<separator])
        guard !key.isEmpty,
              key.count <= maximumKeyLength,
              key.allSatisfy({ $0.isLetter || $0.isNumber || "_-.".contains($0) }) else {
            return nil
        }
        let value = line[line.index(after: separator)...]
            .trimmingCharacters(in: .whitespaces)
        return (key, unquoted(value))
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              first == "\"" || first == "'",
              value.last == first else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}

nonisolated enum AgentMarkdownBlock: Equatable, Sendable {
    case frontMatter([MarkdownFrontMatterEntry])
    case heading(level: Int, content: String)
    case paragraph(String)
    case unorderedItem(String)
    case orderedItem(number: Int, content: String)
    case taskItem(isCompleted: Bool, content: String)
    case quote(String)
    case code(language: String?, content: String)
    case mermaid(String)
    case invalidMermaid(source: String, error: String)
    case table(headers: [String], rows: [[String]])
    case divider

    static func blockAnchorID(_ index: Int) -> String {
        "md-block-\(index)"
    }

    static func inlineSource(for block: Self) -> String? {
        switch block {
        case .heading(_, let content),
                .paragraph(let content),
                .unorderedItem(let content),
                .orderedItem(_, let content),
                .taskItem(_, let content),
                .quote(let content):
            content
        case .frontMatter, .code, .mermaid, .invalidMermaid, .table, .divider:
            nil
        }
    }

    static func outline(from source: String) -> [MarkdownOutlineEntry] {
        outline(from: parse(source))
    }

    static func outline(from blocks: [Self]) -> [MarkdownOutlineEntry] {
        blocks.enumerated().compactMap { index, block in
            guard case .heading(let level, let content) = block else { return nil }
            let title = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return MarkdownOutlineEntry(
                id: blockAnchorID(index),
                level: level,
                title: title
            )
        }
    }

    static func parse(_ source: String) -> [Self] {
        var blocks: [Self] = []
        var paragraph: [String] = []
        var fencedLines: [String] = []
        var fenceMarker: String?
        var fenceLanguage: String?
        // Index of the list item or quote that a following plain line continues
        // (Markdown lazy continuation). Reset by a blank line or any new block.
        var continuationIndex: Int?

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll(keepingCapacity: true)
        }

        func appendContinuation(_ text: String, at index: Int) -> Bool {
            guard blocks.indices.contains(index), !text.isEmpty else { return false }
            switch blocks[index] {
            case .unorderedItem(let content):
                blocks[index] = .unorderedItem(joined(content, text))
            case .orderedItem(let number, let content):
                blocks[index] = .orderedItem(
                    number: number,
                    content: joined(content, text)
                )
            case .taskItem(let isCompleted, let content):
                blocks[index] = .taskItem(
                    isCompleted: isCompleted,
                    content: joined(content, text)
                )
            case .quote(let content):
                blocks[index] = .quote(joined(content, text))
            default:
                return false
            }
            return true
        }

        func flushFence(isClosed: Bool) {
            let content = fencedLines.joined(separator: "\n")
            if fenceLanguage?.lowercased() == "mermaid" {
                if !isClosed {
                    blocks.append(.invalidMermaid(
                        source: content,
                        error: "Mermaid block is missing its closing fence. Source is shown below."
                    ))
                } else if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.invalidMermaid(
                        source: content,
                        error: "Mermaid block is empty. Source is shown below."
                    ))
                } else {
                    blocks.append(.mermaid(content))
                }
            } else {
                blocks.append(.code(language: fenceLanguage, content: content))
            }
            fencedLines.removeAll(keepingCapacity: true)
            fenceMarker = nil
            fenceLanguage = nil
        }

        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var lineIndex = 0
        if let matter = MarkdownFrontMatterPolicy.parse(lines) {
            blocks.append(.frontMatter(matter.entries))
            lineIndex = matter.endIndex
        }
        while lineIndex < lines.count {
            let line = lines[lineIndex]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fenceMarker {
                if isFenceClosing(trimmed, marker: fenceMarker) {
                    flushFence(isClosed: true)
                } else {
                    fencedLines.append(line)
                }
                lineIndex += 1
                continue
            }

            if let opening = fenceOpening(trimmed) {
                flushParagraph()
                continuationIndex = nil
                fenceMarker = opening.marker
                fenceLanguage = opening.language
                lineIndex += 1
                continue
            }

            if lineIndex + 1 < lines.count,
               let headers = tableRow(from: trimmed),
               isTableDivider(lines[lineIndex + 1], columnCount: headers.count) {
                flushParagraph()
                var rows: [[String]] = []
                lineIndex += 2
                while lineIndex < lines.count,
                      let row = tableRow(from: lines[lineIndex]),
                      !isTableDivider(lines[lineIndex], columnCount: headers.count) {
                    rows.append(normalizedTableRow(row, columnCount: headers.count))
                    lineIndex += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continuationIndex = nil
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continuationIndex = nil
                lineIndex += 1
                continue
            }

            if isDivider(trimmed) {
                flushParagraph()
                blocks.append(.divider)
                continuationIndex = nil
                lineIndex += 1
                continue
            }

            if let heading = heading(from: trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, content: heading.content))
                continuationIndex = nil
                lineIndex += 1
                continue
            }

            if let task = taskItem(from: trimmed) {
                flushParagraph()
                blocks.append(.taskItem(
                    isCompleted: task.isCompleted,
                    content: task.content
                ))
                continuationIndex = blocks.count - 1
                lineIndex += 1
                continue
            }

            if let content = prefixedContent(in: trimmed, prefixes: ["- ", "* ", "+ "]) {
                flushParagraph()
                blocks.append(.unorderedItem(content))
                continuationIndex = blocks.count - 1
                lineIndex += 1
                continue
            }

            if let item = orderedItem(from: trimmed) {
                flushParagraph()
                blocks.append(.orderedItem(number: item.number, content: item.content))
                continuationIndex = blocks.count - 1
                lineIndex += 1
                continue
            }

            if let content = prefixedContent(in: trimmed, prefixes: ["> "]) {
                // Consecutive quote lines are one pull-quote, not one block per line.
                if let index = continuationIndex,
                   case .quote = blocks[index],
                   appendContinuation(content, at: index) {
                    lineIndex += 1
                    continue
                }
                flushParagraph()
                blocks.append(.quote(content))
                continuationIndex = blocks.count - 1
                lineIndex += 1
                continue
            }

            // Wrapped source line for the list item or quote right above it.
            if paragraph.isEmpty,
               let index = continuationIndex,
               appendContinuation(trimmed, at: index) {
                lineIndex += 1
                continue
            }

            paragraph.append(trimmed)
            continuationIndex = nil
            lineIndex += 1
        }

        if fenceMarker != nil || !fencedLines.isEmpty {
            flushFence(isClosed: false)
        }
        flushParagraph()
        return blocks
    }

    private static func joined(_ content: String, _ continuation: String) -> String {
        content.isEmpty ? continuation : content + " " + continuation
    }

    private static func fenceOpening(_ line: String) -> (marker: String, language: String?)? {
        guard let markerCharacter = line.first, markerCharacter == "`" || markerCharacter == "~" else {
            return nil
        }
        let markerLength = line.prefix(while: { $0 == markerCharacter }).count
        guard markerLength >= 3 else { return nil }
        let marker = String(repeating: markerCharacter, count: markerLength)
        let language = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        return (marker, language.isEmpty ? nil : language)
    }

    private static func isFenceClosing(_ line: String, marker: String) -> Bool {
        guard let markerCharacter = marker.first,
              line.count >= marker.count,
              line.allSatisfy({ $0 == markerCharacter }) else {
            return false
        }
        return true
    }

    private static func heading(from line: String) -> (level: Int, content: String)? {
        let level = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level), line.dropFirst(level).first == " " else { return nil }
        return (level, String(line.dropFirst(level + 1)))
    }

    private static func orderedItem(from line: String) -> (number: Int, content: String)? {
        guard let delimiter = line.firstIndex(of: ".") else { return nil }
        let numberText = line[..<delimiter]
        let contentStart = line.index(after: delimiter)
        guard !numberText.isEmpty,
              numberText.allSatisfy(\.isNumber),
              contentStart < line.endIndex,
              line[contentStart] == " ",
              let number = Int(numberText) else {
            return nil
        }
        return (number, String(line[line.index(after: contentStart)...]))
    }

    private static func taskItem(from line: String) -> (isCompleted: Bool, content: String)? {
        let markers = [
            ("- [ ] ", false), ("* [ ] ", false), ("+ [ ] ", false),
            ("- [x] ", true), ("* [x] ", true), ("+ [x] ", true),
            ("- [X] ", true), ("* [X] ", true), ("+ [X] ", true)
        ]
        guard let marker = markers.first(where: { line.hasPrefix($0.0) }) else { return nil }
        return (marker.1, String(line.dropFirst(marker.0.count)))
    }

    private static func prefixedContent(in line: String, prefixes: [String]) -> String? {
        guard let prefix = prefixes.first(where: line.hasPrefix) else { return nil }
        return String(line.dropFirst(prefix.count))
    }

    private static func isDivider(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        let characters = line.filter { !$0.isWhitespace }
        guard characters.count >= 3, let first = characters.first, "-_*".contains(first) else {
            return false
        }
        return characters.allSatisfy { $0 == first }
    }

    private static func tableRow(from line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        var cells = trimmed.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if trimmed.hasPrefix("|") { cells.removeFirst() }
        if trimmed.hasSuffix("|") { cells.removeLast() }
        return cells.isEmpty ? nil : cells
    }

    private static func isTableDivider(_ line: String, columnCount: Int) -> Bool {
        guard let cells = tableRow(from: line), cells.count == columnCount else { return false }
        return cells.allSatisfy { cell in
            let marker = cell.trimmingCharacters(in: .whitespaces)
            let dashes = marker.filter { $0 == "-" }.count
            return dashes >= 3 && marker.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func normalizedTableRow(_ row: [String], columnCount: Int) -> [String] {
        var normalized = Array(row.prefix(columnCount))
        if normalized.count < columnCount {
            normalized.append(contentsOf: repeatElement("", count: columnCount - normalized.count))
        }
        return normalized
    }
}
