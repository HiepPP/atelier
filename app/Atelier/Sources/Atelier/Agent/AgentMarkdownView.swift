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
        let footnoteSignature: String
    }

    private static let cacheLimit = 512
    private static let colorTokenExpression = try? NSRegularExpression(
        pattern: "(?<![0-9A-Za-z])#(?:[0-9A-Fa-f]{8}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{3})(?![0-9A-Za-z])"
    )
    private static let footnoteReferenceExpression = try? NSRegularExpression(
        pattern: "\\[\\^([^\\]\\s]+)\\]"
    )
    private static var cache: [CacheKey: AttributedString] = [:]
    private static var cacheOrder: [CacheKey] = []

    static func attributedString(
        _ content: String,
        showsColorSwatches: Bool = false,
        footnoteNumbers: [String: Int] = [:]
    ) -> AttributedString {
        cachedAttributedString(
            content,
            kind: .markdown,
            showsColorSwatches: showsColorSwatches,
            footnoteNumbers: footnoteNumbers
        )
    }

    static func plainAttributedString(
        _ content: String,
        showsColorSwatches: Bool
    ) -> AttributedString {
        cachedAttributedString(
            content,
            kind: .plain,
            showsColorSwatches: showsColorSwatches,
            footnoteNumbers: [:]
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
        showsColorSwatches: Bool,
        footnoteNumbers: [String: Int]
    ) -> AttributedString {
        let footnoteSignature = footnoteNumbers
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: "|")
        let key = CacheKey(
            content: content,
            kind: kind,
            showsColorSwatches: showsColorSwatches,
            footnoteSignature: footnoteSignature
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
                // Mono face only, matching the native builder. Any fill turns a
                // code-heavy paragraph into a mosaic of blocks.
                attributed[range].foregroundColor = Color.primary
            }
        case .plain:
            attributed = AttributedString(content)
        }

        if showsColorSwatches {
            attributed = addingColorSwatches(to: attributed)
        }
        if !footnoteNumbers.isEmpty {
            attributed = addingFootnoteReferences(
                to: attributed,
                numbers: footnoteNumbers
            )
        }
        storeCached(key, attributed)
        return attributed
    }

    private static func addingFootnoteReferences(
        to attributed: AttributedString,
        numbers: [String: Int]
    ) -> AttributedString {
        guard let footnoteReferenceExpression else { return attributed }
        var decorated = attributed
        let rendered = String(decorated.characters)
        let fullRange = NSRange(rendered.startIndex..<rendered.endIndex, in: rendered)
        let matches = footnoteReferenceExpression.matches(in: rendered, range: fullRange)

        for match in matches.reversed() {
            guard let idRange = Range(match.range(at: 1), in: rendered),
                  let number = numbers[String(rendered[idRange])],
                  let sourceRange = Range(match.range, in: rendered),
                  let lower = AttributedString.Index(sourceRange.lowerBound, within: decorated),
                  let upper = AttributedString.Index(sourceRange.upperBound, within: decorated) else {
                continue
            }
            var reference = AttributedString(String(number))
            reference.foregroundColor = AtelierTheme.accent
            reference.font = .system(size: AtelierTypography.micro, weight: .semibold)
            reference.baselineOffset = 4
            decorated.replaceSubrange(lower..<upper, with: reference)
        }
        return decorated
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

nonisolated enum MarkdownCalloutKind: String, CaseIterable, Equatable, Sendable {
    case note = "NOTE"
    case tip = "TIP"
    case important = "IMPORTANT"
    case warning = "WARNING"
    case caution = "CAUTION"

    var glyph: String {
        switch self {
        case .note: "\u{2139}"
        case .tip: "\u{2726}"
        case .important: "!"
        case .warning: "\u{26A0}"
        case .caution: "\u{25C6}"
        }
    }

    @MainActor
    var color: NSColor {
        switch self {
        case .note, .important: AppKitThemeAdapter.accent
        case .tip: AppKitThemeAdapter.gitAdded
        case .warning: AppKitThemeAdapter.gitModified
        case .caution: AppKitThemeAdapter.gitDeleted
        }
    }

}

nonisolated enum MarkdownColumnAlignment: Equatable, Sendable {
    case left
    case center
    case right
}

nonisolated struct MarkdownFootnote: Equatable, Sendable {
    let id: String
    let number: Int
    let text: String
}

nonisolated enum MarkdownFootnotePolicy {
    private static let definitionExpression = try? NSRegularExpression(
        pattern: "^\\[\\^([^\\]\\s]+)\\]:\\s*(.+)$"
    )
    private static let referenceExpression = try? NSRegularExpression(
        pattern: "\\[\\^([^\\]\\s]+)\\]"
    )

    static func definition(from line: String) -> (id: String, text: String)? {
        guard let definitionExpression else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = definitionExpression.firstMatch(in: line, range: range),
              let idRange = Range(match.range(at: 1), in: line),
              let textRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        return (String(line[idRange]), String(line[textRange]))
    }

    static func notes(
        in blocks: [AgentMarkdownBlock],
        definitions: [String: String]
    ) -> [MarkdownFootnote] {
        guard let referenceExpression, !definitions.isEmpty else { return [] }
        var seen: Set<String> = []
        var ordered: [MarkdownFootnote] = []
        for block in blocks {
            let sources: [String]
            if case .table(let headers, _, let rows) = block {
                sources = headers + rows.flatMap { $0 }
            } else if let source = AgentMarkdownBlock.inlineSource(for: block) {
                sources = [source]
            } else {
                sources = []
            }
            for source in sources {
                let range = NSRange(source.startIndex..<source.endIndex, in: source)
                for match in referenceExpression.matches(in: source, range: range) {
                    guard let idRange = Range(match.range(at: 1), in: source) else { continue }
                    let id = String(source[idRange])
                    guard !seen.contains(id), let text = definitions[id] else { continue }
                    seen.insert(id)
                    ordered.append(
                        MarkdownFootnote(id: id, number: ordered.count + 1, text: text)
                    )
                }
            }
        }
        return ordered
    }

    static func numberMap(in blocks: [AgentMarkdownBlock]) -> [String: Int] {
        guard let notesBlock = blocks.first(where: {
            if case .footnotes = $0 { return true }
            return false
        }), case .footnotes(let notes) = notesBlock else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0.number) })
    }

    static func resolvedReferences(
        in content: String,
        numbers: [String: Int]
    ) -> [(sourceRange: NSRange, number: Int)] {
        guard let referenceExpression, !numbers.isEmpty else { return [] }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        return referenceExpression.matches(in: content, range: range).compactMap {
            match in
            guard let idRange = Range(match.range(at: 1), in: content),
                  let number = numbers[String(content[idRange])] else {
                return nil
            }
            return (match.range, number)
        }
    }
}

nonisolated enum MarkdownImageFigurePolicy {
    static func parse(_ line: String) -> (altText: String, urlText: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("!["),
              let closeAlt = trimmed.firstIndex(of: "]"),
              trimmed.index(after: closeAlt) < trimmed.endIndex,
              trimmed[trimmed.index(after: closeAlt)] == "(",
              trimmed.last == ")" else {
            return nil
        }
        let altStart = trimmed.index(trimmed.startIndex, offsetBy: 2)
        let urlStart = trimmed.index(closeAlt, offsetBy: 2)
        let urlEnd = trimmed.index(before: trimmed.endIndex)
        let alt = String(trimmed[altStart..<closeAlt])
        let url = String(trimmed[urlStart..<urlEnd])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        return (alt, url)
    }

    static func localURL(urlText: String, directoryURL: URL?) -> URL? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let components = URLComponents(string: trimmed),
           let scheme = components.scheme,
           !scheme.isEmpty {
            guard scheme.lowercased() == "file" else { return nil }
            return components.url?.standardizedFileURL
        }
        let decoded = trimmed.removingPercentEncoding ?? trimmed
        if decoded.hasPrefix("/") {
            return URL(fileURLWithPath: decoded).standardizedFileURL
        }
        guard let directoryURL else { return nil }
        return directoryURL
            .appendingPathComponent(decoded)
            .standardizedFileURL
    }
}

nonisolated enum MarkdownTableAlignmentPolicy {
    static func numericMajorityColumns(
        headers: [String],
        rows: [[String]]
    ) -> Set<Int> {
        Set(headers.indices.filter { columnIndex in
            let values = rows.compactMap { row -> String? in
                guard row.indices.contains(columnIndex) else { return nil }
                let value = row[columnIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            guard !values.isEmpty else { return false }
            let numericCount = values.filter(isNumeric).count
            return numericCount * 2 > values.count
        })
    }

    private static func isNumeric(_ value: String) -> Bool {
        let normalized = value
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "$% "))
        return Double(normalized) != nil
    }
}

/// Shared front-matter card geometry. The key column is sized from the widest key
/// the document actually holds, so a deep dotted path such as
/// `colors.text.sidebar-primary-foreground` stays on one line instead of wrapping
/// mid-word. Bounded at both ends so a short-key document does not waste the
/// measure and a pathological key cannot starve the value column.
nonisolated enum MarkdownFrontMatterLayout {
    static let minimumKeyPercentage: CGFloat = 22
    static let maximumKeyPercentage: CGFloat = 48

    /// The table resolves its percentages against the real text container, which is
    /// narrower than the nominal measure whenever the window cannot grant the full
    /// measure. The document is built before layout, so the container width is not
    /// known here. Reserve headroom for that gap, or the widest key computes a share
    /// that fits the nominal measure and still wraps on screen.
    static let containerHeadroom: CGFloat = 0.88

    static func keyColumnPercentage(
        longestKeyWidth: CGFloat,
        horizontalPadding: CGFloat,
        measure: CGFloat
    ) -> CGFloat {
        guard measure > 0, longestKeyWidth > 0 else { return minimumKeyPercentage }
        let assumedContainer = measure * containerHeadroom
        let needed = (longestKeyWidth + horizontalPadding) / assumedContainer * 100
        return min(maximumKeyPercentage, max(minimumKeyPercentage, needed))
    }
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
    let sourceDirectoryURL: URL?
    let blocks: [AgentMarkdownBlock]
    let outline: [MarkdownOutlineEntry]
    /// Pre-parsed inline runs aligned with `blocks` (nil for non-text blocks).
    let inlineRuns: [AttributedString?]

    static let empty = ParsedMarkdownDocument(
        source: "",
        sourceDirectoryURL: nil,
        blocks: [],
        outline: [],
        inlineRuns: []
    )

    init(source: String, sourceDirectoryURL: URL? = nil) {
        self.source = source
        self.sourceDirectoryURL = sourceDirectoryURL
        let blocks = AgentMarkdownBlock.parse(source)
        self.blocks = blocks
        self.outline = AgentMarkdownBlock.outline(from: blocks)
        self.inlineRuns = Self.makeInlineRuns(for: blocks)
    }

    init(
        source: String,
        sourceDirectoryURL: URL? = nil,
        blocks: [AgentMarkdownBlock]
    ) {
        self.source = source
        self.sourceDirectoryURL = sourceDirectoryURL
        self.blocks = blocks
        self.outline = AgentMarkdownBlock.outline(from: blocks)
        self.inlineRuns = Self.makeInlineRuns(for: blocks)
    }

    init(
        source: String,
        sourceDirectoryURL: URL? = nil,
        blocks: [AgentMarkdownBlock],
        outline: [MarkdownOutlineEntry],
        inlineRuns: [AttributedString?] = []
    ) {
        self.source = source
        self.sourceDirectoryURL = sourceDirectoryURL
        self.blocks = blocks
        self.outline = outline
        self.inlineRuns = inlineRuns
    }

    private static func makeInlineRuns(for blocks: [AgentMarkdownBlock]) -> [AttributedString?] {
        let footnoteNumbers = MarkdownFootnotePolicy.numberMap(in: blocks)
        return blocks.map { block -> AttributedString? in
            guard let text = AgentMarkdownBlock.inlineSource(for: block) else { return nil }
            return AgentMarkdownInlinePolicy.attributedString(
                text,
                showsColorSwatches: true,
                footnoteNumbers: footnoteNumbers
            )
        }
    }
}

/// One rendered heading and its vertical offset inside the transcript surface.
/// The response panel maps a scroll position to a section title with these.
nonisolated struct MarkdownTranscriptHeading: Equatable, Sendable {
    let title: String
    let y: CGFloat
}

struct AgentMarkdownView: View, Equatable {
    let source: String
    let bodyFontSize: CGFloat
    let presentation: AgentMarkdownPresentation
    let blocks: [AgentMarkdownBlock]?
    let inlineRuns: [AttributedString?]?
    let onHeadingLayout: ([MarkdownTranscriptHeading]) -> Void

    /// Bumped when an async figure changes the rendered height, so SwiftUI
    /// measures the native surface again.
    @State private var contentRevision = 0

    init(
        source: String,
        bodyFontSize: CGFloat = AtelierTypography.body,
        presentation: AgentMarkdownPresentation = .transcript,
        blocks: [AgentMarkdownBlock]? = nil,
        inlineRuns: [AttributedString?]? = nil,
        onHeadingLayout: @escaping ([MarkdownTranscriptHeading]) -> Void = { _ in }
    ) {
        self.source = source
        self.bodyFontSize = bodyFontSize
        self.presentation = presentation
        self.blocks = blocks
        self.inlineRuns = inlineRuns
        self.onHeadingLayout = onHeadingLayout
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

    /// `bodyFontSize` is a caller override on top of the mode's own base size.
    private var fontScale: CGFloat {
        let base = presentation == .document
            ? AtelierTypography.editorSize
            : AtelierTypography.body
        guard base > 0, bodyFontSize > 0 else { return 1 }
        return bodyFontSize / base
    }

    var body: some View {
        MarkdownTranscriptTextView(
            source: source,
            blocks: blocks,
            presentation: presentation,
            fontScale: fontScale,
            contentRevision: contentRevision,
            onContentHeightChange: { contentRevision &+= 1 },
            onHeadingLayout: onHeadingLayout
        )
        .frame(maxWidth: proseMaxWidth, alignment: .leading)
    }
}

/// One native surface per Markdown source. It sizes itself to its content so the
/// host scroll view keeps ownership of scrolling: no nested scroll view, and one
/// selection that runs across every block.
private struct MarkdownTranscriptTextView: NSViewRepresentable {
    @Environment(\.atelierZoomScale) private var scale
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    let source: String
    let blocks: [AgentMarkdownBlock]?
    let presentation: AgentMarkdownPresentation
    let fontScale: CGFloat
    /// Read only to re-run layout after an async figure changed the height.
    let contentRevision: Int
    let onContentHeightChange: () -> Void
    let onHeadingLayout: ([MarkdownTranscriptHeading]) -> Void

    func makeCoordinator() -> MarkdownTranscriptCoordinator {
        MarkdownTranscriptCoordinator()
    }

    func makeNSView(context: Context) -> NSTextView {
        let textView = MarkdownTranscriptCoordinator.makeTextView()
        textView.delegate = context.coordinator
        context.coordinator.attach(textView: textView)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.update(
            source: source,
            blocks: blocks,
            presentation: presentation,
            scale: scale * fontScale,
            displayScale: displayScale,
            usesDarkAppearance: colorScheme == .dark,
            openURL: openURL,
            onContentHeightChange: onContentHeightChange,
            onHeadingLayout: onHeadingLayout
        )
    }

    /// A fill representable without this collapses to its child fitting height.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSTextView,
        context: Context
    ) -> CGSize? {
        var width = proposal.width ?? .nan
        if !(width.isFinite && width >= 1) {
            width = nsView.bounds.width
        }
        if !(width.isFinite && width >= 1) {
            width = presentation == .document
                ? AtelierMetrics.documentMaxWidth
                : AtelierMetrics.transcriptMaxWidth
        }
        guard width.isFinite, width >= 1 else { return nil }
        return CGSize(
            width: width,
            height: context.coordinator.height(forWidth: width)
        )
    }

    static func dismantleNSView(
        _ nsView: NSTextView,
        coordinator: MarkdownTranscriptCoordinator
    ) {
        coordinator.stop()
    }
}

@MainActor
final class MarkdownTranscriptCoordinator: NSObject, NSTextViewDelegate {
    private static let highlightService = SyntaxHighlightService()

    private weak var textView: NSTextView?
    private var codeBlocks: [MarkdownCodeBlockRegion] = []
    private var imageFigures: [MarkdownImageFigureRegion] = []
    private var mermaidFigures: [MarkdownMermaidFigureRegion] = []
    private var codeCopyControls: [String: NSHostingView<MarkdownCodeCopyControl>] = [:]
    private var mermaidControls: [String: NSHostingView<MarkdownMermaidSourceControl>] = [:]
    private let mermaidExpansion = MarkdownMermaidSourceExpansion()
    private var hasPendingOverlaySync = false
    private var renderedSource: String?
    private var renderedPresentation: AgentMarkdownPresentation?
    private var renderedScale: CGFloat = 0
    private var renderedDisplayScale: CGFloat = 0
    private var renderedDarkAppearance: Bool?
    private var openURL: OpenURLAction?
    private var onContentHeightChange: () -> Void = {}
    private var onHeadingLayout: ([MarkdownTranscriptHeading]) -> Void = { _ in }
    private var headings: [MarkdownAttributedHeading] = []
    private var reportedHeadings: [MarkdownTranscriptHeading] = []
    private var contentGeneration = 0
    private var measuredGeneration = -1
    private var measuredWidth: CGFloat = 0
    private var measuredHeight: CGFloat = 0
    private var highlightGeneration = 0
    private var highlightTask: Task<Void, Never>?
    private var imageGeneration = 0
    private var imageTask: Task<Void, Never>?
    private var mermaidGeneration = 0
    private var mermaidTask: Task<Void, Never>?

    /// Bare text view with no scroll view: the host scroll view owns scrolling.
    static func makeTextView() -> NSTextView {
        let textStorage = NSTextStorage()
        let layoutManager = MarkdownPreviewLayoutManager(metrics: .current)
        // Self-sizing needs a complete used rect, so keep layout contiguous.
        layoutManager.allowsNonContiguousLayout = false
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            containerSize: NSSize(
                width: 0,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let textView = MarkdownPreviewTextView(
            frame: .zero,
            textContainer: textContainer
        )
        textView.textContainerInset = .zero
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.usesFindBar = false
        textView.allowsUndo = false
        textView.drawsBackground = false
        textView.selectedTextAttributes = [
            .backgroundColor: AppKitThemeAdapter.selection
        ]
        textView.linkTextAttributes = [
            .foregroundColor: AppKitThemeAdapter.accent,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .underlineColor: MarkdownLinkStylePolicy.normalUnderlineColor
        ]
        textView.setAccessibilityLabel("Answer")
        return textView
    }

    func attach(textView: NSTextView) {
        self.textView = textView
    }

    func update(
        source: String,
        blocks: [AgentMarkdownBlock]?,
        presentation: AgentMarkdownPresentation,
        scale: CGFloat,
        displayScale: CGFloat,
        usesDarkAppearance: Bool,
        openURL: OpenURLAction?,
        onContentHeightChange: @escaping () -> Void,
        onHeadingLayout: @escaping ([MarkdownTranscriptHeading]) -> Void
    ) {
        self.openURL = openURL
        self.onContentHeightChange = onContentHeightChange
        self.onHeadingLayout = onHeadingLayout
        let needsRender = renderedSource != source
            || renderedPresentation != presentation
            || renderedScale != scale
            || renderedDisplayScale != displayScale
            || renderedDarkAppearance != usesDarkAppearance
        guard needsRender else { return }
        renderedSource = source
        renderedPresentation = presentation
        renderedScale = scale
        renderedDisplayScale = displayScale
        renderedDarkAppearance = usesDarkAppearance

        let parsed: ParsedMarkdownDocument
        if let blocks {
            parsed = ParsedMarkdownDocument(source: source, blocks: blocks)
        } else {
            parsed = ParsedMarkdownDocument(source: source)
        }
        let rendered = MarkdownAttributedDocumentBuilder.build(
            document: parsed,
            scale: scale,
            displayScale: displayScale,
            usesDarkAppearance: usesDarkAppearance,
            presentation: presentation
        )
        apply(rendered)
        scheduleHighlights(
            rendered.codeHighlights,
            usesDarkAppearance: usesDarkAppearance
        )
        scheduleImageLoads(rendered.imageFigures)
        scheduleMermaidRenders(rendered.mermaidFigures)
    }

    func stop() {
        highlightGeneration += 1
        highlightTask?.cancel()
        highlightTask = nil
        imageGeneration += 1
        imageTask?.cancel()
        imageTask = nil
        mermaidGeneration += 1
        mermaidTask?.cancel()
        mermaidTask = nil
        removeOverlayControls()
        codeBlocks = []
        imageFigures = []
        mermaidFigures = []
        mermaidExpansion.reset()
        headings = []
        reportedHeadings = []
        textView = nil
        openURL = nil
        onContentHeightChange = {}
        onHeadingLayout = { _ in }
    }

    /// Content height for a proposed width, measured from the used rect.
    func height(forWidth width: CGFloat) -> CGFloat {
        guard let textView,
              let textContainer = textView.textContainer,
              let layoutManager = textView.layoutManager else {
            return 0
        }
        let target = max(1, width)
        if measuredGeneration == contentGeneration,
           abs(measuredWidth - target) < 0.5 {
            return measuredHeight
        }
        if abs(textView.frame.width - target) > 0.5 {
            textView.setFrameSize(
                NSSize(width: target, height: max(1, textView.frame.height))
            )
        }
        layoutManager.ensureLayout(for: textContainer)
        let height = max(
            1,
            layoutManager.usedRect(for: textContainer).maxY.rounded(.up)
        )
        measuredWidth = target
        measuredHeight = height
        measuredGeneration = contentGeneration
        // Overlay frames need finished layout, and this runs inside one. Place
        // them on the next runloop instead of during the measurement pass.
        scheduleOverlaySync()
        publishHeadingLayout(layoutManager: layoutManager, textContainer: textContainer)
        return height
    }

    /// Heading offsets are only valid after layout, so they are read here and
    /// published on the next runloop. Writing view state inside this measurement
    /// pass would mutate during AppKit layout.
    private func publishHeadingLayout(
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) {
        guard let textStorage = textView?.textStorage else { return }
        let rows = headings.compactMap { heading -> MarkdownTranscriptHeading? in
            guard NSMaxRange(heading.range) <= textStorage.length,
                  heading.range.length > 0 else { return nil }
            let title = textStorage.attributedSubstring(from: heading.range)
                .string
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: heading.range,
                actualCharacterRange: nil
            )
            let rect = layoutManager.boundingRect(
                forGlyphRange: glyphRange,
                in: textContainer
            )
            return MarkdownTranscriptHeading(title: title, y: rect.minY)
        }
        guard rows != reportedHeadings else { return }
        reportedHeadings = rows
        let publish = onHeadingLayout
        Task { @MainActor in
            publish(rows)
        }
    }

    func textView(
        _ textView: NSTextView,
        clickedOnLink link: Any,
        at charIndex: Int
    ) -> Bool {
        let url = (link as? URL)
            ?? (link as? String).flatMap { URL(string: $0) }
        guard let url, let openURL else { return false }
        openURL(url)
        return true
    }

    private func measure(_ presentation: AgentMarkdownPresentation) -> CGFloat {
        presentation == .document
            ? AtelierMetrics.documentMaxWidth
            : AtelierMetrics.transcriptMaxWidth
    }

    /// Figure width for the current host. A sidecar panel is far narrower than
    /// the mode measure, so a figure has to shrink instead of overflowing it.
    private func figureMeasure() -> CGFloat {
        let mode = measure(renderedPresentation ?? .transcript)
        guard let containerWidth = textView?.textContainer?.size.width,
              containerWidth >= 1 else {
            return mode
        }
        return min(mode, containerWidth)
    }

    private func apply(_ document: MarkdownAttributedDocument) {
        guard let textView,
              let textStorage = textView.textStorage else { return }
        codeBlocks = document.codeBlocks
        imageFigures = document.imageFigures
        mermaidFigures = document.mermaidFigures
        headings = document.headings
        reportedHeadings = []
        mermaidExpansion.reset()
        let validIDs = Set(codeBlocks.map(\.id)).union(mermaidFigures.map(\.id))
        for id in codeCopyControls.keys.filter({ !validIDs.contains($0) }) {
            codeCopyControls[id]?.removeFromSuperview()
            codeCopyControls[id] = nil
        }
        for id in mermaidControls.keys.filter({ !validIDs.contains($0) }) {
            mermaidControls[id]?.removeFromSuperview()
            mermaidControls[id] = nil
        }
        textStorage.setAttributedString(document.attributedString)
        (textView as? MarkdownPreviewTextView)?.resetHoveredLink()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        contentGeneration &+= 1
        scheduleOverlaySync()
    }

    /// Every block is materialized here, so there is no visible-range filter:
    /// one response card holds a handful of code blocks and figures.
    private func syncOverlayControls() {
        guard let textView else {
            removeOverlayControls()
            return
        }
        for block in codeBlocks {
            let control: NSHostingView<MarkdownCodeCopyControl>
            if let existing = codeCopyControls[block.id] {
                control = existing
            } else {
                let created = NSHostingView(
                    rootView: MarkdownCodeCopyControl(source: block.source)
                )
                textView.addSubview(created)
                codeCopyControls[block.id] = created
                control = created
            }
            place(control, over: block.headerRange, anchor: .centered)
        }
        for figure in mermaidFigures {
            let control: NSHostingView<MarkdownMermaidSourceControl>
            if let existing = mermaidControls[figure.id] {
                control = existing
            } else {
                let created = NSHostingView(
                    rootView: mermaidSourceControl(for: figure)
                )
                textView.addSubview(created)
                mermaidControls[figure.id] = created
                control = created
            }
            place(control, over: figure.range, anchor: .top)
        }
    }

    private func scheduleOverlaySync() {
        guard !hasPendingOverlaySync else { return }
        hasPendingOverlaySync = true
        Task { @MainActor [weak self] in
            self?.hasPendingOverlaySync = false
            self?.syncOverlayControls()
        }
    }

    private func place(
        _ control: NSView,
        over range: NSRange,
        anchor: MarkdownOverlayAnchor
    ) {
        guard let textView,
              let frame = MarkdownOverlayControlLayout.frame(
                  for: range,
                  size: control.fittingSize,
                  anchor: anchor,
                  in: textView,
                  host: textView
              ) else {
            return
        }
        control.frame = frame
    }

    private func removeOverlayControls() {
        for control in codeCopyControls.values {
            control.removeFromSuperview()
        }
        codeCopyControls.removeAll(keepingCapacity: true)
        for control in mermaidControls.values {
            control.removeFromSuperview()
        }
        mermaidControls.removeAll(keepingCapacity: true)
    }

    private func mermaidSourceControl(
        for figure: MarkdownMermaidFigureRegion
    ) -> MarkdownMermaidSourceControl {
        MarkdownMermaidSourceControl(
            isExpanded: mermaidExpansion.isExpanded(figure.id)
        ) { [weak self] in
            self?.toggleMermaidSource(id: figure.id)
        }
    }

    private func toggleMermaidSource(id: String) {
        guard let textView,
              let textStorage = textView.textStorage,
              let figure = mermaidFigures.first(where: { $0.id == id }),
              let presentation = renderedPresentation else {
            return
        }
        guard let edit = mermaidExpansion.toggle(
            figure: figure,
            in: textStorage,
            scale: renderedScale,
            displayScale: renderedDisplayScale,
            presentation: presentation
        ) else {
            return
        }
        shiftRegions(after: edit.location, by: edit.delta)
        for figure in mermaidFigures {
            mermaidControls[figure.id]?.rootView = mermaidSourceControl(
                for: figure
            )
        }
        noteContentHeightChanged()
    }

    /// An in-place storage edit moves every later range, so the stored regions
    /// have to follow it instead of being rebuilt.
    private func shiftRegions(after location: Int, by delta: Int) {
        guard delta != 0 else { return }
        codeBlocks = codeBlocks.map {
            MarkdownCodeBlockRegion(
                id: $0.id,
                headerRange: MarkdownRegionShift.shifted(
                    $0.headerRange,
                    after: location,
                    by: delta
                ),
                sourceRange: MarkdownRegionShift.shifted(
                    $0.sourceRange,
                    after: location,
                    by: delta
                ),
                source: $0.source,
                usesGeneratedLineNumbers: $0.usesGeneratedLineNumbers
            )
        }
        imageFigures = imageFigures.map {
            MarkdownImageFigureRegion(
                id: $0.id,
                url: $0.url,
                attachment: $0.attachment,
                range: MarkdownRegionShift.shifted(
                    $0.range,
                    after: location,
                    by: delta
                )
            )
        }
        mermaidFigures = mermaidFigures.map {
            MarkdownMermaidFigureRegion(
                id: $0.id,
                source: $0.source,
                attachment: $0.attachment,
                range: MarkdownRegionShift.shifted(
                    $0.range,
                    after: location,
                    by: delta
                )
            )
        }
    }

    /// A load started before a toggle carries the range it was scheduled with,
    /// so resolve the current range by id instead of trusting the captured one.
    private func currentRange(for figure: MarkdownImageFigureRegion) -> NSRange {
        imageFigures.first { $0.id == figure.id }?.range ?? figure.range
    }

    private func currentRange(for figure: MarkdownMermaidFigureRegion) -> NSRange {
        mermaidFigures.first { $0.id == figure.id }?.range ?? figure.range
    }

    /// Height changed outside a SwiftUI update, so ask for a new measurement on
    /// the next runloop. Never mutate view state inside this layout pass.
    private func noteContentHeightChanged() {
        contentGeneration &+= 1
        let notify = onContentHeightChange
        Task { @MainActor in
            notify()
        }
    }

    private func scheduleHighlights(
        _ requests: [MarkdownCodeHighlightRequest],
        usesDarkAppearance: Bool
    ) {
        highlightGeneration += 1
        let generation = highlightGeneration
        highlightTask?.cancel()
        highlightTask = nil
        guard !requests.isEmpty else { return }
        highlightTask = Task { [weak self] in
            await Task.yield()
            for request in requests {
                guard !Task.isCancelled else { return }
                do {
                    let highlighted = try await Self.highlightService
                        .highlightPreservingWhitespace(
                            request.source,
                            languageName: request.languageName,
                            usesDarkAppearance: usesDarkAppearance
                        )
                    guard !Task.isCancelled else { return }
                    self?.applyHighlight(
                        highlighted,
                        to: request.range,
                        generation: generation
                    )
                } catch {
                    guard !(error is CancellationError) else { return }
                }
            }
        }
    }

    private func applyHighlight(
        _ highlighted: AttributedString,
        to targetRange: NSRange,
        generation: Int
    ) {
        guard generation == highlightGeneration,
              let textStorage = textView?.textStorage,
              NSMaxRange(targetRange) <= textStorage.length else { return }
        let native = NSAttributedString(highlighted)
        textStorage.beginEditing()
        native.enumerateAttribute(
            .foregroundColor,
            in: NSRange(location: 0, length: native.length)
        ) { value, range, _ in
            guard let value, range.location < targetRange.length else { return }
            let availableLength = targetRange.length - range.location
            let destination = NSRange(
                location: targetRange.location + range.location,
                length: min(range.length, availableLength)
            )
            guard destination.length > 0,
                  NSMaxRange(destination) <= NSMaxRange(targetRange) else {
                return
            }
            textStorage.addAttribute(
                .foregroundColor,
                value: value,
                range: destination
            )
        }
        textStorage.endEditing()
    }

    private func scheduleImageLoads(
        _ figures: [MarkdownImageFigureRegion]
    ) {
        imageGeneration += 1
        let generation = imageGeneration
        imageTask?.cancel()
        imageTask = nil
        guard !figures.isEmpty else { return }
        imageTask = Task { [weak self] in
            for figure in figures {
                guard !Task.isCancelled else { return }
                guard let decoded = await MarkdownLocalImageLoader.load(
                    figure.url
                ) else {
                    continue
                }
                guard !Task.isCancelled else { return }
                self?.applyImage(
                    decoded,
                    to: figure,
                    generation: generation
                )
            }
        }
    }

    private func applyImage(
        _ decoded: MarkdownDecodedImage,
        to figure: MarkdownImageFigureRegion,
        generation: Int
    ) {
        guard generation == imageGeneration else { return }
        let bounds = MarkdownImageFigureLayout.fittedBounds(
            pixelWidth: decoded.width,
            pixelHeight: decoded.height,
            measure: figureMeasure()
        )
        applyFigure(
            image: MarkdownImageFigureRenderer.image(
                size: bounds.size,
                content: decoded.cgImage()
            ),
            bounds: bounds,
            attachment: figure.attachment,
            range: currentRange(for: figure)
        )
    }

    private func scheduleMermaidRenders(
        _ figures: [MarkdownMermaidFigureRegion]
    ) {
        mermaidGeneration += 1
        let generation = mermaidGeneration
        mermaidTask?.cancel()
        mermaidTask = nil
        guard !figures.isEmpty else { return }
        let width = MarkdownMermaidFigureLayout.renderWidth(
            measure: figureMeasure()
        )
        mermaidTask = Task { @MainActor [weak self] in
            for figure in figures {
                guard !Task.isCancelled else { return }
                do {
                    let rendered = try await MermaidImageCache.shared.image(
                        source: figure.source,
                        width: width
                    )
                    guard !Task.isCancelled else { return }
                    self?.applyMermaid(
                        rendered,
                        to: figure,
                        generation: generation
                    )
                } catch is CancellationError {
                    // An evicted queue slot is not a render failure: keep the
                    // placeholder so a later pass can still draw the diagram.
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.applyMermaidFailure(
                        to: figure,
                        generation: generation
                    )
                }
            }
        }
    }

    private func applyMermaid(
        _ rendered: NSImage,
        to figure: MarkdownMermaidFigureRegion,
        generation: Int
    ) {
        guard generation == mermaidGeneration else { return }
        let bounds = MarkdownMermaidFigureLayout.fittedBounds(
            imageSize: rendered.size,
            measure: figureMeasure()
        )
        applyFigure(
            image: MarkdownImageFigureRenderer.image(
                size: bounds.size,
                content: rendered.cgImage(
                    forProposedRect: nil,
                    context: nil,
                    hints: nil
                )
            ),
            bounds: bounds,
            attachment: figure.attachment,
            range: currentRange(for: figure)
        )
    }

    private func applyMermaidFailure(
        to figure: MarkdownMermaidFigureRegion,
        generation: Int
    ) {
        guard generation == mermaidGeneration else { return }
        let bounds = MarkdownMermaidFigureLayout.fittedBounds(
            imageSize: figure.attachment.bounds.size,
            measure: figureMeasure()
        )
        applyFigure(
            image: MarkdownImageFigureRenderer.image(
                size: bounds.size,
                content: nil,
                message: MarkdownMermaidFigureLayout.failureMessage
            ),
            bounds: bounds,
            attachment: figure.attachment,
            range: currentRange(for: figure)
        )
    }

    private func applyFigure(
        image: NSImage,
        bounds: NSRect,
        attachment: NSTextAttachment,
        range: NSRange
    ) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textStorage = textView.textStorage,
              NSMaxRange(range) <= textStorage.length else {
            return
        }
        attachment.image = image
        attachment.bounds = bounds
        layoutManager.invalidateLayout(
            forCharacterRange: range,
            actualCharacterRange: nil
        )
        layoutManager.invalidateDisplay(forCharacterRange: range)
        textView.needsDisplay = true
        noteContentHeightChanged()
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

nonisolated struct MarkdownFrontMatterEntry: Equatable, Sendable {
    let key: String
    let value: String
}

/// Leading YAML front matter recognized as one metadata block. Deliberately strict:
/// anything that is not `key: value`, a `- item` continuation, or a blank line falls
/// back to normal block parsing so a plain `---` divider keeps its meaning.
nonisolated enum MarkdownFrontMatterPolicy {
    /// Bounds the scan for the closing marker so a stray `---` cannot make the
    /// parser read a whole document. Real front matter is routinely long: a design
    /// system catalog reaches 186 lines, and the old 64-line bound made it fall back
    /// to block parsing, where the opening `---` became a divider and every
    /// `key: value` line was joined into one run-on paragraph.
    static let maximumLineCount = 512
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
        // YAML allows a quoted key, and a numeric one has to be quoted: `"2": "border-2"`.
        // Strip the quotes before the charset check, exactly as values are unquoted.
        let key = unquoted(String(line[..<separator]))
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
    case unorderedItem(depth: Int, content: String)
    case orderedItem(number: Int, depth: Int, content: String)
    case taskItem(isCompleted: Bool, depth: Int, content: String)
    case quote(String)
    case callout(kind: MarkdownCalloutKind, content: String)
    case code(language: String?, content: String)
    case mermaid(String)
    case invalidMermaid(source: String, error: String)
    case table(
        headers: [String],
        alignments: [MarkdownColumnAlignment],
        rows: [[String]]
    )
    case image(altText: String, urlText: String)
    case footnotes([MarkdownFootnote])
    case divider

    static func blockAnchorID(_ index: Int) -> String {
        "md-block-\(index)"
    }

    static func inlineSource(for block: Self) -> String? {
        switch block {
        case .heading(_, let content),
                .paragraph(let content),
                .unorderedItem(_, let content),
                .orderedItem(_, _, let content),
                .taskItem(_, _, let content),
                .quote(let content),
                .callout(_, let content):
            content
        case .frontMatter, .code, .mermaid, .invalidMermaid, .table,
                .image, .footnotes, .divider:
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
        var footnoteDefinitions: [String: String] = [:]
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
            case .unorderedItem(let depth, let content):
                blocks[index] = .unorderedItem(
                    depth: depth,
                    content: joined(content, text)
                )
            case .orderedItem(let number, let depth, let content):
                blocks[index] = .orderedItem(
                    number: number,
                    depth: depth,
                    content: joined(content, text)
                )
            case .taskItem(let isCompleted, let depth, let content):
                blocks[index] = .taskItem(
                    isCompleted: isCompleted,
                    depth: depth,
                    content: joined(content, text)
                )
            case .quote(let content):
                blocks[index] = .quote(joined(content, text))
            case .callout(let kind, let content):
                blocks[index] = .callout(
                    kind: kind,
                    content: joined(content, text)
                )
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
            let leadingSpaces = line.prefix { $0 == " " }.count
            let listDepth = min(3, leadingSpaces / 2)

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
               let alignments = tableAlignments(
                   from: lines[lineIndex + 1],
                   columnCount: headers.count
               ) {
                flushParagraph()
                var rows: [[String]] = []
                lineIndex += 2
                while lineIndex < lines.count,
                      let row = tableRow(from: lines[lineIndex]),
                      tableAlignments(
                          from: lines[lineIndex],
                          columnCount: headers.count
                      ) == nil {
                    rows.append(normalizedTableRow(row, columnCount: headers.count))
                    lineIndex += 1
                }
                blocks.append(
                    .table(
                        headers: headers,
                        alignments: alignments,
                        rows: rows
                    )
                )
                continuationIndex = nil
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                continuationIndex = nil
                lineIndex += 1
                continue
            }

            if let definition = MarkdownFootnotePolicy.definition(from: trimmed) {
                flushParagraph()
                if footnoteDefinitions[definition.id] == nil {
                    footnoteDefinitions[definition.id] = definition.text
                }
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

            if let figure = MarkdownImageFigurePolicy.parse(trimmed) {
                flushParagraph()
                blocks.append(
                    .image(
                        altText: figure.altText,
                        urlText: figure.urlText
                    )
                )
                continuationIndex = nil
                lineIndex += 1
                continue
            }

            if let task = taskItem(from: trimmed) {
                flushParagraph()
                blocks.append(.taskItem(
                    isCompleted: task.isCompleted,
                    depth: listDepth,
                    content: task.content
                ))
                continuationIndex = blocks.count - 1
                lineIndex += 1
                continue
            }

            if let content = prefixedContent(in: trimmed, prefixes: ["- ", "* ", "+ "]) {
                flushParagraph()
                blocks.append(.unorderedItem(depth: listDepth, content: content))
                continuationIndex = blocks.count - 1
                lineIndex += 1
                continue
            }

            if let item = orderedItem(from: trimmed) {
                flushParagraph()
                blocks.append(
                    .orderedItem(
                        number: item.number,
                        depth: listDepth,
                        content: item.content
                    )
                )
                continuationIndex = blocks.count - 1
                lineIndex += 1
                continue
            }

            if let kind = calloutKind(from: trimmed) {
                flushParagraph()
                var contentLines: [String] = []
                lineIndex += 1
                while lineIndex < lines.count {
                    let quoted = lines[lineIndex]
                        .trimmingCharacters(in: .whitespaces)
                    if quoted == ">" {
                        contentLines.append("")
                    } else if let content = prefixedContent(
                        in: quoted,
                        prefixes: ["> "]
                    ) {
                        contentLines.append(content)
                    } else {
                        break
                    }
                    lineIndex += 1
                }
                blocks.append(
                    .callout(
                        kind: kind,
                        content: contentLines.joined(separator: " ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
                continuationIndex = nil
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
        let notes = MarkdownFootnotePolicy.notes(
            in: blocks,
            definitions: footnoteDefinitions
        )
        if !notes.isEmpty {
            blocks.append(.footnotes(notes))
        }
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

    private static func tableAlignments(
        from line: String,
        columnCount: Int
    ) -> [MarkdownColumnAlignment]? {
        guard let cells = tableRow(from: line), cells.count == columnCount else { return nil }
        var alignments: [MarkdownColumnAlignment] = []
        for cell in cells {
            let marker = cell.trimmingCharacters(in: .whitespaces)
            let hasLeadingColon = marker.hasPrefix(":")
            let hasTrailingColon = marker.hasSuffix(":")
            let dashes = marker.filter { $0 == "-" }.count
            let minimumDashes = hasLeadingColon && hasTrailingColon
                ? 1
                : (hasLeadingColon || hasTrailingColon ? 2 : 3)
            guard marker.count >= 3,
                  dashes >= minimumDashes,
                  marker.allSatisfy({ $0 == "-" || $0 == ":" }) else {
                return nil
            }
            if hasLeadingColon, hasTrailingColon {
                alignments.append(.center)
            } else if hasTrailingColon {
                alignments.append(.right)
            } else {
                alignments.append(.left)
            }
        }
        return alignments
    }

    private static func calloutKind(from line: String) -> MarkdownCalloutKind? {
        guard line.hasPrefix("> [!"), line.hasSuffix("]") else { return nil }
        let start = line.index(line.startIndex, offsetBy: 4)
        let end = line.index(before: line.endIndex)
        return MarkdownCalloutKind(rawValue: String(line[start..<end]).uppercased())
    }

    private static func normalizedTableRow(_ row: [String], columnCount: Int) -> [String] {
        var normalized = Array(row.prefix(columnCount))
        if normalized.count < columnCount {
            normalized.append(contentsOf: repeatElement("", count: columnCount - normalized.count))
        }
        return normalized
    }
}
