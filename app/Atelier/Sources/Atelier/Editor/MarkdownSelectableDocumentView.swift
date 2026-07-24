import AppKit
import SwiftUI

nonisolated struct MarkdownPreviewJumpRequest: Equatable, Sendable {
    let outlineID: String
    let generation: Int
}

struct MarkdownAttributedHeading: Equatable {
    let id: String
    let range: NSRange
}

struct MarkdownCodeHighlightRequest: Equatable {
    let range: NSRange
    let source: String
    let languageName: String?
}

struct MarkdownAttributedDocument {
    let attributedString: NSAttributedString
    let headings: [MarkdownAttributedHeading]
    let codeHighlights: [MarkdownCodeHighlightRequest]

    static let empty = MarkdownAttributedDocument(
        attributedString: NSAttributedString(),
        headings: [],
        codeHighlights: []
    )
}

extension NSAttributedString.Key {
    nonisolated static let atelierInlineCode = NSAttributedString.Key(
        "app.atelier.markdown.inline-code"
    )
}

private enum MarkdownInlineCodeLayout {
    static let padding = NSSize(
        width: AtelierMetrics.spaceS,
        height: AtelierMetrics.spaceXS
    )
    static let outerMargin = AtelierMetrics.spaceXS
    static let horizontalReservation = padding.width + outerMargin
}

nonisolated final class MarkdownPreviewLayoutManager: NSLayoutManager {
    private let inlineCodePadding: NSSize
    private let inlineCodeHorizontalReservation: CGFloat

    init(inlineCodePadding: NSSize, inlineCodeHorizontalReservation: CGFloat) {
        self.inlineCodePadding = inlineCodePadding
        self.inlineCodeHorizontalReservation = inlineCodeHorizontalReservation
        super.init()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let textStorage else { return }
        let characterRange = characterRange(
            forGlyphRange: glyphsToShow,
            actualGlyphRange: nil
        )
        textStorage.enumerateAttribute(
            .atelierInlineCode,
            in: characterRange
        ) { value, range, _ in
            guard let color = value as? NSColor else { return }
            let codeGlyphRange = glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            enumerateLineFragments(forGlyphRange: codeGlyphRange) {
                _, _, textContainer, lineGlyphRange, _ in
                let visibleRange = NSIntersectionRange(
                    NSIntersectionRange(codeGlyphRange, lineGlyphRange),
                    glyphsToShow
                )
                guard visibleRange.length > 0 else { return }
                let backgroundRect = self.inlineCodeBackgroundRect(
                    for: self.boundingRect(
                        forGlyphRange: visibleRange,
                        in: textContainer
                    ),
                    at: origin,
                    includesTrailingReservation:
                        NSMaxRange(visibleRange) == NSMaxRange(codeGlyphRange)
                )
                color.setFill()
                backgroundRect.fill()
            }
        }
    }

    func inlineCodeBackgroundRect(
        for rect: NSRect,
        at origin: NSPoint,
        includesTrailingReservation: Bool
    ) -> NSRect {
        var contentRect = rect.offsetBy(dx: origin.x, dy: origin.y)
        if includesTrailingReservation {
            contentRect.size.width = max(
                0,
                contentRect.width - inlineCodeHorizontalReservation
            )
        }
        return contentRect.insetBy(
            dx: -inlineCodePadding.width,
            dy: -inlineCodePadding.height
        )
    }
}

@MainActor
enum MarkdownAttributedDocumentBuilder {
    private static let colorSwatchExpression = try? NSRegularExpression(
        pattern: "\u{25A0}(#(?:[0-9A-Fa-f]{8}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{3}))"
    )

    static func build(
        document: ParsedMarkdownDocument,
        scale: CGFloat,
        displayScale: CGFloat,
        usesDarkAppearance: Bool
    ) -> MarkdownAttributedDocument {
        let output = NSMutableAttributedString()
        var headings: [MarkdownAttributedHeading] = []
        var codeHighlights: [MarkdownCodeHighlightRequest] = []
        let bodySize = AtelierFontScaling.snapped(
            AtelierTypography.editorSize * scale,
            displayScale: displayScale
        )
        let bodyFont = NSFont.systemFont(ofSize: bodySize)
        let codeFont = AtelierTypography.codeFont(
            size: AtelierFontScaling.snapped(
                AtelierTypography.label * scale,
                displayScale: displayScale
            )
        )

        for (index, block) in document.blocks.enumerated() {
            switch block {
            case .heading(let level, let content):
                let start = output.length
                let font = headingFont(level: level, bodySize: bodySize)
                let paragraph = paragraphStyle(
                    lineSpacing: AtelierMetrics.spaceXS,
                    before: index == 0 ? 0 : headingTopSpacing(level: level),
                    after: level <= 2 ? AtelierMetrics.spaceS : AtelierMetrics.spaceXS
                )
                let text = inlineText(
                    content,
                    font: font,
                    foregroundColor: level >= 4
                        ? AppKitThemeAdapter.secondary
                        : AppKitThemeAdapter.foreground,
                    paragraphStyle: paragraph,
                    codeFont: codeFont
                )
                if level <= 2 {
                    text.addAttributes([
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                        .underlineColor: AppKitThemeAdapter.accent.withAlphaComponent(
                            level == 1 ? 0.9 : 0.62
                        )
                    ], range: NSRange(location: 0, length: text.length))
                }
                output.append(text)
                let headingLength = text.length
                output.append(NSAttributedString(string: "\n", attributes: [
                    .font: font,
                    .paragraphStyle: paragraph
                ]))

                let title = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    headings.append(
                        MarkdownAttributedHeading(
                            id: AgentMarkdownBlock.blockAnchorID(index),
                            range: NSRange(location: start, length: max(1, headingLength))
                        )
                    )
                }

            case .paragraph(let content):
                appendInlineParagraph(
                    content,
                    to: output,
                    font: bodyFont,
                    codeFont: codeFont,
                    paragraphStyle: paragraphStyle(
                        lineSpacing: AtelierMetrics.spaceS,
                        before: index == 0 ? 0 : AtelierMetrics.spaceM,
                        after: AtelierMetrics.spaceXS
                    )
                )

            case .unorderedItem(let content):
                appendListItem(
                    marker: "-",
                    content: content,
                    to: output,
                    bodyFont: bodyFont,
                    codeFont: codeFont
                )

            case .orderedItem(let number, let content):
                appendListItem(
                    marker: "\(number).",
                    content: content,
                    to: output,
                    bodyFont: bodyFont,
                    codeFont: codeFont
                )

            case .taskItem(let isCompleted, let content):
                appendListItem(
                    marker: isCompleted ? "[x]" : "[ ]",
                    content: content,
                    to: output,
                    bodyFont: bodyFont,
                    codeFont: codeFont
                )

            case .quote(let content):
                let paragraph = paragraphStyle(
                    lineSpacing: AtelierMetrics.spaceS,
                    before: AtelierMetrics.spaceL,
                    after: AtelierMetrics.spaceS,
                    firstLineHeadIndent: AtelierMetrics.spaceL,
                    headIndent: AtelierMetrics.spaceL,
                    tailIndent: -AtelierMetrics.spaceL
                )
                let prefix = NSAttributedString(string: "> ", attributes: [
                    .font: NSFont.systemFont(ofSize: bodySize, weight: .semibold),
                    .foregroundColor: AppKitThemeAdapter.accent,
                    .backgroundColor: AppKitThemeAdapter.raised,
                    .paragraphStyle: paragraph
                ])
                output.append(prefix)
                let quote = inlineText(
                    content,
                    font: serifFont(size: bodySize, weight: .medium),
                    foregroundColor: AppKitThemeAdapter.secondary,
                    paragraphStyle: paragraph,
                    codeFont: codeFont
                )
                quote.addAttribute(
                    .backgroundColor,
                    value: AppKitThemeAdapter.raised,
                    range: NSRange(location: 0, length: quote.length)
                )
                output.append(quote)
                output.append(NSAttributedString(string: "\n", attributes: [
                    .font: bodyFont,
                    .backgroundColor: AppKitThemeAdapter.raised,
                    .paragraphStyle: paragraph
                ]))

            case .code(let language, let content):
                appendCode(
                    language: language,
                    content: content,
                    to: output,
                    codeFont: codeFont,
                    codeHighlights: &codeHighlights
                )

            case .mermaid(let source):
                appendMermaid(
                    source: source,
                    error: nil,
                    to: output,
                    bodyFont: bodyFont,
                    codeFont: codeFont
                )

            case .invalidMermaid(let source, let error):
                appendMermaid(
                    source: source,
                    error: error,
                    to: output,
                    bodyFont: bodyFont,
                    codeFont: codeFont
                )

            case .table(let headers, let rows):
                appendTable(
                    headers: headers,
                    rows: rows,
                    to: output,
                    bodyFont: bodyFont,
                    codeFont: codeFont,
                    usesDarkAppearance: usesDarkAppearance
                )

            case .divider:
                let paragraph = paragraphStyle(
                    lineSpacing: 0,
                    before: AtelierMetrics.spaceL,
                    after: AtelierMetrics.spaceL
                )
                output.append(NSAttributedString(
                    string: String(repeating: "-", count: 48) + "\n",
                    attributes: [
                        .font: NSFont.systemFont(
                            ofSize: max(6, bodySize * 0.5),
                            weight: .medium
                        ),
                        .foregroundColor: AppKitThemeAdapter.border,
                        .paragraphStyle: paragraph
                    ]
                ))
            }
        }

        return MarkdownAttributedDocument(
            attributedString: NSAttributedString(attributedString: output),
            headings: headings,
            codeHighlights: codeHighlights
        )
    }

    private static func appendInlineParagraph(
        _ content: String,
        to output: NSMutableAttributedString,
        font: NSFont,
        codeFont: NSFont,
        paragraphStyle: NSParagraphStyle
    ) {
        output.append(
            inlineText(
                content,
                font: font,
                foregroundColor: AppKitThemeAdapter.foreground,
                paragraphStyle: paragraphStyle,
                codeFont: codeFont
            )
        )
        output.append(NSAttributedString(string: "\n", attributes: [
            .font: font,
            .paragraphStyle: paragraphStyle
        ]))
    }

    private static func appendListItem(
        marker: String,
        content: String,
        to output: NSMutableAttributedString,
        bodyFont: NSFont,
        codeFont: NSFont
    ) {
        let markerWidth = AtelierMetrics.space2XL
        let paragraph = paragraphStyle(
            lineSpacing: AtelierMetrics.spaceS,
            before: AtelierMetrics.spaceXS,
            after: AtelierMetrics.spaceXS,
            firstLineHeadIndent: 0,
            headIndent: markerWidth
        )
        output.append(NSAttributedString(string: marker + "\t", attributes: [
            .font: AtelierTypography.codeFont(size: bodyFont.pointSize * 0.86),
            .foregroundColor: AppKitThemeAdapter.accent,
            .paragraphStyle: paragraph
        ]))
        output.append(
            inlineText(
                content,
                font: bodyFont,
                foregroundColor: AppKitThemeAdapter.foreground,
                paragraphStyle: paragraph,
                codeFont: codeFont
            )
        )
        output.append(NSAttributedString(string: "\n", attributes: [
            .font: bodyFont,
            .paragraphStyle: paragraph
        ]))
    }

    private static func appendCode(
        language: String?,
        content: String,
        to output: NSMutableAttributedString,
        codeFont: NSFont,
        codeHighlights: inout [MarkdownCodeHighlightRequest]
    ) {
        let headerStyle = paragraphStyle(
            lineSpacing: 0,
            before: AtelierMetrics.spaceL,
            after: 0,
            firstLineHeadIndent: AtelierMetrics.spaceM,
            headIndent: AtelierMetrics.spaceM,
            tailIndent: -AtelierMetrics.spaceM
        )
        output.append(NSAttributedString(
            string: (language?.uppercased() ?? "CODE") + "\n",
            attributes: [
                .font: NSFont.monospacedSystemFont(
                    ofSize: AtelierTypography.micro,
                    weight: .semibold
                ),
                .foregroundColor: AppKitThemeAdapter.secondary,
                .backgroundColor: AppKitThemeAdapter.raised,
                .paragraphStyle: headerStyle
            ]
        ))

        let codeStyle = paragraphStyle(
            lineSpacing: AtelierMetrics.spaceXS,
            before: 0,
            after: 0,
            firstLineHeadIndent: AtelierMetrics.spaceM,
            headIndent: AtelierMetrics.spaceM,
            tailIndent: -AtelierMetrics.spaceM
        )
        let trailingCodeStyle = paragraphStyle(
            lineSpacing: AtelierMetrics.spaceXS,
            before: 0,
            after: AtelierMetrics.spaceL,
            firstLineHeadIndent: AtelierMetrics.spaceM,
            headIndent: AtelierMetrics.spaceM,
            tailIndent: -AtelierMetrics.spaceM
        )
        let source = content.isEmpty ? " " : content
        let range = NSRange(location: output.length, length: (source as NSString).length)
        let code = NSMutableAttributedString(string: source + "\n", attributes: [
            .font: codeFont,
            .foregroundColor: AppKitThemeAdapter.foreground,
            .backgroundColor: AppKitThemeAdapter.code,
            .paragraphStyle: codeStyle
        ])
        let lastBreak = (source as NSString).range(of: "\n", options: .backwards)
        let lastLineStart = lastBreak.location == NSNotFound ? 0 : NSMaxRange(lastBreak)
        code.addAttribute(
            .paragraphStyle,
            value: trailingCodeStyle,
            range: NSRange(
                location: lastLineStart,
                length: code.length - lastLineStart
            )
        )
        output.append(code)
        if !content.isEmpty {
            codeHighlights.append(
                MarkdownCodeHighlightRequest(
                    range: range,
                    source: content,
                    languageName: AgentCodeHighlightPolicy.languageName(for: language)
                )
            )
        }
    }

    private static func appendMermaid(
        source: String,
        error: String?,
        to output: NSMutableAttributedString,
        bodyFont: NSFont,
        codeFont: NSFont
    ) {
        let headerStyle = paragraphStyle(
            lineSpacing: 0,
            before: AtelierMetrics.spaceL,
            after: AtelierMetrics.spaceXS,
            firstLineHeadIndent: AtelierMetrics.spaceM,
            headIndent: AtelierMetrics.spaceM,
            tailIndent: -AtelierMetrics.spaceM
        )
        output.append(NSAttributedString(string: "MERMAID - SOURCE FALLBACK\n", attributes: [
            .font: NSFont.monospacedSystemFont(
                ofSize: AtelierTypography.micro,
                weight: .semibold
            ),
            .foregroundColor: AppKitThemeAdapter.accent,
            .backgroundColor: AppKitThemeAdapter.raised,
            .paragraphStyle: headerStyle
        ]))
        if let error {
            output.append(NSAttributedString(string: error + "\n", attributes: [
                .font: bodyFont,
                .foregroundColor: AppKitThemeAdapter.secondary,
                .backgroundColor: AppKitThemeAdapter.raised,
                .paragraphStyle: headerStyle
            ]))
        }
        let sourceStyle = paragraphStyle(
            lineSpacing: AtelierMetrics.spaceXS,
            before: 0,
            after: AtelierMetrics.spaceL,
            firstLineHeadIndent: AtelierMetrics.spaceM,
            headIndent: AtelierMetrics.spaceM,
            tailIndent: -AtelierMetrics.spaceM
        )
        output.append(NSAttributedString(string: source + "\n", attributes: [
            .font: codeFont,
            .foregroundColor: AppKitThemeAdapter.foreground,
            .backgroundColor: AppKitThemeAdapter.code,
            .paragraphStyle: sourceStyle
        ]))
    }

    private static func appendTable(
        headers: [String],
        rows: [[String]],
        to output: NSMutableAttributedString,
        bodyFont: NSFont,
        codeFont: NSFont,
        usesDarkAppearance: Bool
    ) {
        guard !headers.isEmpty else { return }
        let table = NSTextTable()
        table.numberOfColumns = headers.count
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        table.setContentWidth(100, type: .percentageValueType)
        let allRows = [headers] + rows
        let spacerStyle = paragraphStyle(
            lineSpacing: 0,
            before: AtelierMetrics.spaceL,
            after: 0
        )
        output.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 1),
            .paragraphStyle: spacerStyle
        ]))

        for (rowIndex, row) in allRows.enumerated() {
            for columnIndex in headers.indices {
                let block = NSTextTableBlock(
                    table: table,
                    startingRow: rowIndex,
                    rowSpan: 1,
                    startingColumn: columnIndex,
                    columnSpan: 1
                )
                block.setWidth(
                    AtelierTheme.strokeHairline,
                    type: .absoluteValueType,
                    for: .border
                )
                block.setBorderColor(AppKitThemeAdapter.border)
                block.setWidth(
                    AtelierMetrics.spaceS,
                    type: .absoluteValueType,
                    for: .padding
                )
                if rowIndex == 0 {
                    block.backgroundColor = AppKitThemeAdapter.accent.withAlphaComponent(
                        usesDarkAppearance ? 0.16 : 0.08
                    )
                } else if rowIndex.isMultiple(of: 2) {
                    block.backgroundColor = AppKitThemeAdapter.raised.withAlphaComponent(0.28)
                }

                let paragraph = paragraphStyle(
                    lineSpacing: AtelierMetrics.spaceXS,
                    before: 0,
                    after: 0
                )
                paragraph.textBlocks = [block]
                let value = row.indices.contains(columnIndex) ? row[columnIndex] : ""
                let font = rowIndex == 0
                    ? NSFont.systemFont(ofSize: bodyFont.pointSize * 0.86, weight: .semibold)
                    : NSFont.systemFont(ofSize: bodyFont.pointSize * 0.86)
                let cell = inlineText(
                    value,
                    font: font,
                    foregroundColor: AppKitThemeAdapter.foreground,
                    paragraphStyle: paragraph,
                    codeFont: codeFont
                )
                output.append(cell)
                output.append(NSAttributedString(string: "\n", attributes: [
                    .font: font,
                    .paragraphStyle: paragraph
                ]))
            }
        }
    }

    private static func inlineText(
        _ content: String,
        font: NSFont,
        foregroundColor: NSColor,
        paragraphStyle: NSParagraphStyle,
        codeFont: NSFont
    ) -> NSMutableAttributedString {
        let swiftValue = AgentMarkdownInlinePolicy.attributedString(
            content,
            showsColorSwatches: true
        )
        let output = NSMutableAttributedString(attributedString: NSAttributedString(swiftValue))
        let fullRange = NSRange(location: 0, length: output.length)
        guard fullRange.length > 0 else { return output }

        let nativeString = output.string as NSString
        var swatchColors: [(range: NSRange, color: NSColor)] = []
        let matches = colorSwatchExpression?.matches(
            in: output.string,
            range: fullRange
        ) ?? []
        for match in matches {
            let tokenRange = match.range(at: 1)
            guard tokenRange.location != NSNotFound,
                  let color = nativeColor(
                    for: nativeString.substring(with: tokenRange)
                  ) else {
                continue
            }
            swatchColors.append(
                (
                    NSRange(location: match.range.location, length: 1),
                    color
                )
            )
        }

        fillMissingAttribute(.font, value: font, in: output, range: fullRange)
        fillMissingAttribute(
            .foregroundColor,
            value: foregroundColor,
            in: output,
            range: fullRange
        )
        output.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

        var intentRuns: [(Int, NSRange)] = []
        output.enumerateAttribute(.inlinePresentationIntent, in: fullRange) { value, range, _ in
            let rawValue = (value as? NSNumber)?.intValue ?? (value as? Int ?? 0)
            if rawValue != 0 {
                intentRuns.append((rawValue, range))
            }
        }
        for (intent, range) in intentRuns {
            if intent & 4 != 0 {
                let backgroundColor = AppKitThemeAdapter.accent.withAlphaComponent(0.12)
                output.removeAttribute(.backgroundColor, range: range)
                output.addAttributes([
                    .font: codeFont,
                    .foregroundColor: AppKitThemeAdapter.accent,
                    .atelierInlineCode: backgroundColor
                ], range: range)
                if range.location > 0 {
                    output.addAttribute(
                        .kern,
                        value: MarkdownInlineCodeLayout.horizontalReservation,
                        range: nativeString.rangeOfComposedCharacterSequence(
                            at: range.location - 1
                        )
                    )
                }
                output.addAttribute(
                    .kern,
                    value: MarkdownInlineCodeLayout.horizontalReservation,
                    range: nativeString.rangeOfComposedCharacterSequence(
                        at: NSMaxRange(range) - 1
                    )
                )
                continue
            }
            var traits: NSFontDescriptor.SymbolicTraits = []
            if intent & 1 != 0 { traits.insert(.italic) }
            if intent & 2 != 0 { traits.insert(.bold) }
            if !traits.isEmpty {
                let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
                if let styledFont = NSFont(
                    descriptor: descriptor,
                    size: font.pointSize
                ) {
                    output.addAttribute(.font, value: styledFont, range: range)
                }
            }
        }
        for swatch in swatchColors {
            output.addAttribute(
                .foregroundColor,
                value: swatch.color,
                range: swatch.range
            )
        }
        return output
    }

    private static func nativeColor(for token: String) -> NSColor? {
        guard token.first == "#" else { return nil }
        let hex = token.dropFirst()
        let expanded: String
        switch hex.count {
        case 3:
            expanded = hex.reduce(into: "") { result, digit in
                result.append(digit)
                result.append(digit)
            } + "FF"
        case 4:
            expanded = hex.reduce(into: "") { result, digit in
                result.append(digit)
                result.append(digit)
            }
        case 6:
            expanded = String(hex) + "FF"
        case 8:
            expanded = String(hex)
        default:
            return nil
        }
        guard let rgba = UInt32(expanded, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((rgba >> 24) & 0xFF) / 255,
            green: CGFloat((rgba >> 16) & 0xFF) / 255,
            blue: CGFloat((rgba >> 8) & 0xFF) / 255,
            alpha: CGFloat(rgba & 0xFF) / 255
        )
    }

    private static func fillMissingAttribute(
        _ key: NSAttributedString.Key,
        value: Any,
        in output: NSMutableAttributedString,
        range: NSRange
    ) {
        var missing: [NSRange] = []
        output.enumerateAttribute(key, in: range) { current, currentRange, _ in
            if current == nil {
                missing.append(currentRange)
            }
        }
        for range in missing {
            output.addAttribute(key, value: value, range: range)
        }
    }

    private static func paragraphStyle(
        lineSpacing: CGFloat,
        before: CGFloat,
        after: CGFloat,
        firstLineHeadIndent: CGFloat = 0,
        headIndent: CGFloat = 0,
        tailIndent: CGFloat = 0
    ) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = lineSpacing
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.firstLineHeadIndent = firstLineHeadIndent
        style.headIndent = headIndent
        style.tailIndent = tailIndent
        return style
    }

    private static func headingFont(level: Int, bodySize: CGFloat) -> NSFont {
        let size: CGFloat = switch level {
        case 1: max(28, bodySize * 1.85)
        case 2: max(22, bodySize * 1.45)
        case 3: max(AtelierTypography.headline, bodySize * 1.18)
        default: max(AtelierTypography.uiSize, bodySize)
        }
        let weight: NSFont.Weight = level <= 2 ? .semibold : .medium
        return level <= 2
            ? serifFont(size: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
    }

    private static func serifFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    private static func headingTopSpacing(level: Int) -> CGFloat {
        level <= 2 ? AtelierMetrics.space2XL + AtelierMetrics.spaceS : AtelierMetrics.spaceXL
    }
}

struct MarkdownSelectableDocumentView: NSViewRepresentable {
    @Environment(\.atelierZoomScale) private var scale
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    let document: ParsedMarkdownDocument
    let isActive: Bool
    let jumpRequest: MarkdownPreviewJumpRequest?
    @Binding var selectedOutlineID: String?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = AppKitThemeAdapter.editor
        scrollView.scrollerStyle = .overlay
        scrollView.contentView.postsBoundsChangedNotifications = true

        let textStorage = NSTextStorage()
        let layoutManager = MarkdownPreviewLayoutManager(
            inlineCodePadding: MarkdownInlineCodeLayout.padding,
            inlineCodeHorizontalReservation:
                MarkdownInlineCodeLayout.horizontalReservation
        )
        layoutManager.allowsNonContiguousLayout = true
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(
            containerSize: NSSize(
                width: scrollView.contentSize.width,
                height: CGFloat.greatestFiniteMagnitude
            )
        )
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(
            frame: NSRect(origin: .zero, size: scrollView.contentSize),
            textContainer: textContainer
        )
        textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.allowsUndo = false
        textView.drawsBackground = true
        textView.backgroundColor = AppKitThemeAdapter.editor
        textView.insertionPointColor = AppKitThemeAdapter.accent
        textView.selectedTextAttributes = [
            .backgroundColor: AppKitThemeAdapter.selection
        ]
        textView.linkTextAttributes = [
            .foregroundColor: AppKitThemeAdapter.accent,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.setAccessibilityLabel("Markdown preview")
        scrollView.documentView = textView
        context.coordinator.attach(scrollView: scrollView, textView: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            document: document,
            scale: scale,
            displayScale: displayScale,
            usesDarkAppearance: colorScheme == .dark,
            isActive: isActive,
            jumpRequest: jumpRequest,
            onSelectedOutlineChange: { selectedOutlineID = $0 }
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSScrollView,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.frame.width,
            height: proposal.height ?? nsView.frame.height
        )
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        private static let highlightService = SyntaxHighlightService()

        private weak var scrollView: NSScrollView?
        private weak var textView: NSTextView?
        private var boundsObserver: NSObjectProtocol?
        private var renderedSource = ""
        private var renderedScale: CGFloat = 0
        private var renderedDisplayScale: CGFloat = 0
        private var renderedDarkAppearance: Bool?
        private var headings: [MarkdownAttributedHeading] = []
        private var appliedJumpRequest: MarkdownPreviewJumpRequest?
        private var lastReportedOutlineID: String?
        private var onSelectedOutlineChange: (String?) -> Void = { _ in }
        private var highlightGeneration = 0
        private var highlightTask: Task<Void, Never>?
        private var lastViewportWidth: CGFloat = 0
        private var isActive = false

        func attach(scrollView: NSScrollView, textView: NSTextView) {
            self.scrollView = scrollView
            self.textView = textView
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateTextInsets()
                    self?.syncActiveHeading()
                }
            }
        }

        func update(
            document: ParsedMarkdownDocument,
            scale: CGFloat,
            displayScale: CGFloat,
            usesDarkAppearance: Bool,
            isActive: Bool,
            jumpRequest: MarkdownPreviewJumpRequest?,
            onSelectedOutlineChange: @escaping (String?) -> Void
        ) {
            self.onSelectedOutlineChange = onSelectedOutlineChange
            updateActiveState(isActive)
            updateTextInsets()

            let needsRender =
                renderedSource != document.source
                || renderedScale != scale
                || renderedDisplayScale != displayScale
                || renderedDarkAppearance != usesDarkAppearance
            if needsRender {
                renderedSource = document.source
                renderedScale = scale
                renderedDisplayScale = displayScale
                renderedDarkAppearance = usesDarkAppearance
                let rendered = MarkdownAttributedDocumentBuilder.build(
                    document: document,
                    scale: scale,
                    displayScale: displayScale,
                    usesDarkAppearance: usesDarkAppearance
                )
                apply(rendered)
                scheduleHighlights(
                    rendered.codeHighlights,
                    usesDarkAppearance: usesDarkAppearance
                )
            }

            if appliedJumpRequest != jumpRequest {
                appliedJumpRequest = jumpRequest
                if let jumpRequest {
                    scrollToHeading(id: jumpRequest.outlineID)
                }
            }
        }

        func stop() {
            highlightGeneration += 1
            highlightTask?.cancel()
            highlightTask = nil
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            boundsObserver = nil
            textView = nil
            scrollView = nil
            onSelectedOutlineChange = { _ in }
        }

        private func updateActiveState(_ active: Bool) {
            let becameInactive = isActive && !active
            isActive = active
            guard let scrollView, let textView else { return }
            scrollView.isHidden = !active
            textView.isSelectable = active
            if becameInactive,
               let window = textView.window,
               let responder = window.firstResponder,
               responder === textView || (responder as? NSView)?.isDescendant(of: scrollView) == true {
                window.makeFirstResponder(nil)
            }
        }

        private func updateTextInsets() {
            guard let scrollView, let textView else { return }
            let width = scrollView.contentView.bounds.width
            guard width > 0, width != lastViewportWidth else { return }
            lastViewportWidth = width
            let horizontal = max(
                AtelierMetrics.spaceXL,
                (width - AtelierMetrics.documentMaxWidth) / 2
            )
            textView.textContainerInset = NSSize(
                width: horizontal,
                height: AtelierMetrics.space2XL
            )
        }

        private func apply(_ document: MarkdownAttributedDocument) {
            guard let scrollView,
                  let textView,
                  let textStorage = textView.textStorage else { return }
            let origin = scrollView.contentView.bounds.origin
            let selection = textView.selectedRange()
            headings = document.headings
            textStorage.setAttributedString(document.attributedString)
            let length = textStorage.length
            if selection.location <= length {
                textView.setSelectedRange(
                    NSRange(
                        location: selection.location,
                        length: min(selection.length, length - selection.location)
                    )
                )
            }
            if let textContainer = textView.textContainer {
                textView.layoutManager?.ensureLayout(for: textContainer)
            }
            let maximumY = max(
                0,
                textView.frame.height - scrollView.contentView.bounds.height
            )
            scrollView.contentView.scroll(
                to: NSPoint(x: 0, y: min(maximumY, max(0, origin.y)))
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
            syncActiveHeading()
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
                        let highlighted = try await Self.highlightService.highlightPreservingWhitespace(
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
                      NSMaxRange(destination) <= NSMaxRange(targetRange) else { return }
                textStorage.addAttribute(.foregroundColor, value: value, range: destination)
            }
            textStorage.endEditing()
        }

        private func scrollToHeading(id: String) {
            guard let heading = headings.first(where: { $0.id == id }),
                  let scrollView,
                  let textView,
                  let textContainer = textView.textContainer,
                  let layoutManager = textView.layoutManager else { return }
            layoutManager.ensureLayout(forCharacterRange: heading.range)
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: heading.range,
                actualCharacterRange: nil
            )
            let rect = layoutManager.boundingRect(
                forGlyphRange: glyphRange,
                in: textContainer
            )
            let targetY = max(
                0,
                rect.minY + textView.textContainerOrigin.y - AtelierMetrics.spaceL
            )
            let maximumY = max(
                0,
                textView.frame.height - scrollView.contentView.bounds.height
            )
            scrollView.contentView.scroll(
                to: NSPoint(x: 0, y: min(maximumY, targetY))
            )
            scrollView.reflectScrolledClipView(scrollView.contentView)
            reportActiveHeading(id)
        }

        private func syncActiveHeading() {
            guard isActive,
                  !headings.isEmpty,
                  let scrollView,
                  let textView,
                  let textContainer = textView.textContainer,
                  let layoutManager = textView.layoutManager else { return }
            let origin = textView.textContainerOrigin
            let point = NSPoint(
                x: 1,
                y: max(0, scrollView.contentView.bounds.minY + 64 - origin.y)
            )
            let characterIndex = layoutManager.characterIndex(
                for: point,
                in: textContainer,
                fractionOfDistanceBetweenInsertionPoints: nil
            )
            let active = headings.last(where: { $0.range.location <= characterIndex })
                ?? headings.first
            reportActiveHeading(active?.id)
        }

        private func reportActiveHeading(_ id: String?) {
            guard lastReportedOutlineID != id else { return }
            lastReportedOutlineID = id
            Task { @MainActor [onSelectedOutlineChange] in
                onSelectedOutlineChange(id)
            }
        }
    }
}
