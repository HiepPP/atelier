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

struct MarkdownCodeBlockRegion: Equatable {
    let id: String
    let headerRange: NSRange
    let sourceRange: NSRange
    let source: String
}

struct MarkdownAttributedDocument {
    let attributedString: NSAttributedString
    let headings: [MarkdownAttributedHeading]
    let codeHighlights: [MarkdownCodeHighlightRequest]
    let codeBlocks: [MarkdownCodeBlockRegion]

    static let empty = MarkdownAttributedDocument(
        attributedString: NSAttributedString(),
        headings: [],
        codeHighlights: [],
        codeBlocks: []
    )
}

extension NSAttributedString.Key {
    nonisolated static let atelierInlineCode = NSAttributedString.Key(
        "app.atelier.markdown.inline-code"
    )
    nonisolated static let atelierBlockquoteBar = NSAttributedString.Key(
        "app.atelier.markdown.blockquote-bar"
    )
    /// Heading level (1 or 2). Drives the drawn accent + hairline rule.
    nonisolated static let atelierHeadingRule = NSAttributedString.Key(
        "app.atelier.markdown.heading-rule"
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

private enum MarkdownHeadingRuleLayout {
    static let thickness: CGFloat = 1.5
    static let primaryLeadWidth = AtelierMetrics.space2XL
    static let secondaryLeadWidth = AtelierMetrics.spaceL
}

nonisolated enum MarkdownCodeCardLayout {
    static let bodyTintAlpha: CGFloat = 0.30
    static let copyControlReservation: CGFloat = 44
}

/// Editorial type decisions taken once during document construction.
nonisolated enum MarkdownDocumentTypePolicy {
    static let ledeScale: CGFloat = 1.08

    /// A document that opens with an H1 gives its first paragraph the lede treatment.
    static func hasLedeParagraph(blocks: [AgentMarkdownBlock]) -> Bool {
        guard blocks.count > 1,
              case .heading(let level, _) = blocks[0],
              level == 1,
              case .paragraph = blocks[1] else {
            return false
        }
        return true
    }
}

nonisolated enum MarkdownTableCellPolicy {
    static let fontScale: CGFloat = 0.9
    static let unbrokenTokenLimit = 24

    static func wrapsByCharacter(_ value: String) -> Bool {
        var tokenLength = 0
        for character in value {
            if character.isWhitespace {
                tokenLength = 0
                continue
            }
            tokenLength += 1
            if tokenLength > unbrokenTokenLimit { return true }
        }
        return false
    }
}

/// Draw-time geometry resolved once on the main actor and captured by the layout
/// manager. Keeps the draw path free of theme lookups and allocations.
nonisolated struct MarkdownPreviewDecorationMetrics: Sendable {
    let inlineCodePadding: NSSize
    let inlineCodeHorizontalReservation: CGFloat
    let headingRuleThickness: CGFloat
    let headingRulePrimaryLead: CGFloat
    let headingRuleSecondaryLead: CGFloat
    let hairline: CGFloat

    @MainActor
    static var current: Self {
        Self(
            inlineCodePadding: MarkdownInlineCodeLayout.padding,
            inlineCodeHorizontalReservation:
                MarkdownInlineCodeLayout.horizontalReservation,
            headingRuleThickness: MarkdownHeadingRuleLayout.thickness,
            headingRulePrimaryLead: MarkdownHeadingRuleLayout.primaryLeadWidth,
            headingRuleSecondaryLead: MarkdownHeadingRuleLayout.secondaryLeadWidth,
            hairline: AtelierTheme.strokeHairline
        )
    }
}

nonisolated final class MarkdownPreviewLayoutManager: NSLayoutManager {
    private let metrics: MarkdownPreviewDecorationMetrics
    private let inlineCodePadding: NSSize
    private let inlineCodeHorizontalReservation: CGFloat

    init(metrics: MarkdownPreviewDecorationMetrics) {
        self.metrics = metrics
        self.inlineCodePadding = metrics.inlineCodePadding
        self.inlineCodeHorizontalReservation = metrics.inlineCodeHorizontalReservation
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
        let glyphCount = numberOfGlyphs
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
                lineRect, _, textContainer, lineGlyphRange, _ in
                let visibleRange = NSIntersectionRange(
                    NSIntersectionRange(codeGlyphRange, lineGlyphRange),
                    glyphsToShow
                )
                guard visibleRange.length > 0 else { return }
                var glyphRect = self.boundingRect(
                    forGlyphRange: visibleRange,
                    in: textContainer
                )
                // The fragment rect carries the paragraph's lineSpacing below the
                // glyphs, so it cannot drive the fill height: the chip would sit
                // high with a fat bottom gap. Use the run's own font box around
                // the baseline so top and bottom padding read the same.
                let font = textStorage.attribute(
                    .font,
                    at: range.location,
                    effectiveRange: nil
                ) as? NSFont
                if let font {
                    let baselineY = lineRect.minY
                        + self.location(forGlyphAt: visibleRange.location).y
                    glyphRect.origin.y = baselineY - font.ascender
                    glyphRect.size.height = font.ascender - font.descender
                }
                // Trailing edge must not depend on how the font reports the last
                // glyph's kerned advance in boundingRect (it varies per font). Clamp
                // the fill to the following glyph's pen minus the reserved gap so the
                // padding stays symmetric with the leading side for every font.
                if NSMaxRange(visibleRange) == NSMaxRange(codeGlyphRange) {
                    let afterIndex = NSMaxRange(codeGlyphRange)
                    if afterIndex < glyphCount {
                        let afterRect = self.boundingRect(
                            forGlyphRange: NSRange(location: afterIndex, length: 1),
                            in: textContainer
                        )
                        if abs(afterRect.minY - glyphRect.minY) < 1 {
                            let cleanMaxX = afterRect.minX
                                - self.inlineCodeHorizontalReservation
                            glyphRect.size.width = max(0, cleanMaxX - glyphRect.minX)
                        }
                    }
                }
                let backgroundRect = self.inlineCodeBackgroundRect(
                    for: glyphRect,
                    at: origin
                )
                color.setFill()
                backgroundRect.fill()
            }
        }
        textStorage.enumerateAttribute(
            .atelierBlockquoteBar,
            in: characterRange
        ) { value, range, _ in
            guard let color = value as? NSColor else { return }
            let barGlyphRange = glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            // One fill for the whole visible run: per-fragment fills band on soft wrap.
            var minY = CGFloat.greatestFiniteMagnitude
            var maxY = -CGFloat.greatestFiniteMagnitude
            enumerateLineFragments(forGlyphRange: barGlyphRange) {
                lineRect, _, _, lineGlyphRange, _ in
                let visibleRange = NSIntersectionRange(
                    NSIntersectionRange(barGlyphRange, lineGlyphRange),
                    glyphsToShow
                )
                guard visibleRange.length > 0 else { return }
                minY = min(minY, lineRect.minY)
                maxY = max(maxY, lineRect.maxY)
            }
            guard maxY > minY else { return }
            color.setFill()
            NSRect(
                x: origin.x + MarkdownQuoteLayout.leadingInset,
                y: minY + origin.y,
                width: MarkdownQuoteLayout.barWidth,
                height: maxY - minY
            ).fill()
        }
        textStorage.enumerateAttribute(
            .atelierHeadingRule,
            in: characterRange
        ) { value, range, _ in
            guard let level = (value as? NSNumber)?.intValue else { return }
            drawHeadingRule(level: level, characterRange: range, at: origin)
        }
    }

    /// Accent lead segment plus a hairline across the measure, aligned to the bottom
    /// of the heading's last line fragment. Colors are precomputed theme constants.
    private func drawHeadingRule(level: Int, characterRange: NSRange, at origin: NSPoint) {
        let headingGlyphRange = glyphRange(
            forCharacterRange: characterRange,
            actualCharacterRange: nil
        )
        var lastRect: NSRect?
        var measureWidth: CGFloat = 0
        enumerateLineFragments(forGlyphRange: headingGlyphRange) {
            lineRect, _, textContainer, _, _ in
            lastRect = lineRect
            measureWidth = textContainer.size.width - textContainer.lineFragmentPadding * 2
        }
        guard let lastRect, measureWidth > 0 else { return }
        let thickness = metrics.headingRuleThickness
        let leadWidth = min(
            measureWidth,
            level == 1
                ? metrics.headingRulePrimaryLead
                : metrics.headingRuleSecondaryLead
        )
        let y = (lastRect.maxY + origin.y - thickness).rounded(.down)
        let x = origin.x + lastRect.minX
        AppKitThemeAdapter.accent.setFill()
        NSRect(x: x, y: y, width: leadWidth, height: thickness).fill()
        guard measureWidth > leadWidth else { return }
        AppKitThemeAdapter.border.setFill()
        NSRect(
            x: x + leadWidth,
            y: y + (thickness - metrics.hairline) / 2,
            width: measureWidth - leadWidth,
            height: metrics.hairline
        ).fill()
    }

    func inlineCodeBackgroundRect(
        for rect: NSRect,
        at origin: NSPoint
    ) -> NSRect {
        rect.offsetBy(dx: origin.x, dy: origin.y).insetBy(
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
        var codeBlocks: [MarkdownCodeBlockRegion] = []
        let bodySize = AtelierFontScaling.snapped(
            AtelierTypography.editorSize * scale,
            displayScale: displayScale
        )
        let bodyFont = NSFont.systemFont(ofSize: bodySize)
        let codeFont = AtelierTypography.codeFont(
            size: AtelierFontScaling.snapped(
                AtelierTypography.uiSize * scale,
                displayScale: displayScale
            )
        )

        let hasLede = MarkdownDocumentTypePolicy.hasLedeParagraph(
            blocks: document.blocks
        )

        for (index, block) in document.blocks.enumerated() {
            switch block {
            case .frontMatter(let entries):
                appendFrontMatter(
                    entries,
                    to: output,
                    bodySize: bodySize,
                    codeFont: codeFont
                )

            case .heading(let level, let content):
                let start = output.length
                let font = headingFont(level: level, bodySize: bodySize)
                let paragraph = paragraphStyle(
                    lineSpacing: level <= 2
                        ? AtelierMetrics.spaceS
                        : AtelierMetrics.spaceXS,
                    before: index == 0 ? 0 : headingTopSpacing(level: level),
                    after: level <= 2 ? AtelierMetrics.spaceL : AtelierMetrics.spaceXS
                )
                let text = inlineText(
                    content,
                    font: font,
                    foregroundColor: headingColor(level: level),
                    paragraphStyle: paragraph,
                    codeFont: codeFont
                )
                let headingRange = NSRange(location: 0, length: text.length)
                if level <= 2 {
                    // Rule is drawn in the layout pass; a glyph underline would
                    // stop at the text width and clip on wrapped headings.
                    text.addAttributes([
                        .kern: -0.5,
                        .atelierHeadingRule: NSNumber(value: level)
                    ], range: headingRange)
                } else if level == 3 {
                    text.addAttribute(.kern, value: 0.6, range: headingRange)
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
                let isLede = hasLede && index == 1
                let ledeFont = isLede
                    ? NSFont.systemFont(
                        ofSize: AtelierFontScaling.snapped(
                            bodySize * MarkdownDocumentTypePolicy.ledeScale,
                            displayScale: displayScale
                        )
                    )
                    : bodyFont
                appendInlineParagraph(
                    content,
                    to: output,
                    font: ledeFont,
                    codeFont: codeFont,
                    paragraphStyle: paragraphStyle(
                        lineSpacing: isLede
                            ? AtelierMetrics.spaceS + 2
                            : AtelierMetrics.spaceS,
                        before: index == 0 ? 0 : AtelierMetrics.spaceM,
                        after: isLede ? AtelierMetrics.spaceS : AtelierMetrics.spaceXS
                    )
                )

            case .unorderedItem(let content):
                appendListItem(
                    marker: "\u{2022}",
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
                    marker: isCompleted ? "\u{2611}" : "\u{2610}",
                    content: content,
                    to: output,
                    bodyFont: bodyFont,
                    codeFont: codeFont,
                    isCompleted: isCompleted
                )

            case .quote(let content):
                let paragraph = paragraphStyle(
                    lineSpacing: AtelierMetrics.spaceS,
                    before: AtelierMetrics.spaceL,
                    after: AtelierMetrics.spaceL,
                    firstLineHeadIndent: MarkdownQuoteLayout.indent,
                    headIndent: MarkdownQuoteLayout.indent,
                    tailIndent: -AtelierMetrics.spaceL
                )
                let quoteStart = output.length
                let quote = inlineText(
                    content,
                    font: serifItalicFont(size: bodySize),
                    foregroundColor: AppKitThemeAdapter.secondary,
                    paragraphStyle: paragraph,
                    codeFont: codeFont
                )
                output.append(quote)
                output.append(NSAttributedString(string: "\n", attributes: [
                    .font: bodyFont,
                    .paragraphStyle: paragraph
                ]))
                output.addAttribute(
                    .atelierBlockquoteBar,
                    value: AppKitThemeAdapter.accent,
                    range: NSRange(
                        location: quoteStart,
                        length: output.length - quoteStart
                    )
                )

            case .code(let language, let content):
                appendCode(
                    id: AgentMarkdownBlock.blockAnchorID(index),
                    language: language,
                    content: content,
                    to: output,
                    codeFont: codeFont,
                    codeHighlights: &codeHighlights,
                    codeBlocks: &codeBlocks
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
                    before: AtelierMetrics.spaceXL,
                    after: AtelierMetrics.spaceXL
                )
                paragraph.alignment = .center
                let ornament = NSMutableAttributedString(
                    string: "\u{2022}\u{2003}\u{2022}\u{2003}\u{2022}\n",
                    attributes: [
                        .font: NSFont.systemFont(
                            ofSize: max(6, bodySize * 0.55),
                            weight: .semibold
                        ),
                        .foregroundColor: AppKitThemeAdapter.border,
                        .paragraphStyle: paragraph
                    ]
                )
                ornament.addAttribute(
                    .foregroundColor,
                    value: AppKitThemeAdapter.accent,
                    range: NSRange(location: 2, length: 1)
                )
                output.append(ornament)
            }
        }

        return MarkdownAttributedDocument(
            attributedString: NSAttributedString(attributedString: output),
            headings: headings,
            codeHighlights: codeHighlights,
            codeBlocks: codeBlocks
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
        codeFont: NSFont,
        isCompleted: Bool = false
    ) {
        let markerWidth = AtelierMetrics.spaceXL
        let paragraph = paragraphStyle(
            lineSpacing: AtelierMetrics.spaceS,
            before: AtelierMetrics.spaceXS,
            after: AtelierMetrics.spaceXS,
            firstLineHeadIndent: 0,
            headIndent: markerWidth
        )
        // One explicit stop keeps single-line and wrapped items on the same indent.
        paragraph.tabStops = [
            NSTextTab(textAlignment: .left, location: markerWidth, options: [:])
        ]
        paragraph.defaultTabInterval = markerWidth
        output.append(NSAttributedString(string: marker + "\t", attributes: [
            .font: NSFont.systemFont(ofSize: bodyFont.pointSize, weight: .semibold),
            .foregroundColor: AppKitThemeAdapter.accent,
            .paragraphStyle: paragraph
        ]))
        let text = inlineText(
            content,
            font: bodyFont,
            foregroundColor: isCompleted
                ? AppKitThemeAdapter.secondary
                : AppKitThemeAdapter.foreground,
            paragraphStyle: paragraph,
            codeFont: codeFont
        )
        if isCompleted {
            text.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: AppKitThemeAdapter.secondary
            ], range: NSRange(location: 0, length: text.length))
        }
        output.append(text)
        output.append(NSAttributedString(string: "\n", attributes: [
            .font: bodyFont,
            .paragraphStyle: paragraph
        ]))
    }

    private static func appendCode(
        id: String,
        language: String?,
        content: String,
        to output: NSMutableAttributedString,
        codeFont: NSFont,
        codeHighlights: inout [MarkdownCodeHighlightRequest],
        codeBlocks: inout [MarkdownCodeBlockRegion]
    ) {
        let table = NSTextTable()
        table.numberOfColumns = 1
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        table.setContentWidth(100, type: .percentageValueType)

        let headerBlock = NSTextTableBlock(
            table: table,
            startingRow: 0,
            rowSpan: 1,
            startingColumn: 0,
            columnSpan: 1
        )
        configureCodeBlock(
            headerBlock,
            backgroundColor: AppKitThemeAdapter.raised,
            horizontalPadding: AtelierMetrics.spaceM,
            verticalPadding: AtelierMetrics.spaceXS
        )
        let headerStyle = paragraphStyle(
            lineSpacing: 0,
            before: AtelierMetrics.spaceL,
            after: 0,
            firstLineHeadIndent: 0,
            headIndent: 0,
            tailIndent: -MarkdownCodeCardLayout.copyControlReservation
        )
        headerStyle.textBlocks = [headerBlock]
        let headerStart = output.length
        output.append(NSAttributedString(
            string: (language?.uppercased() ?? "CODE") + "\n",
            attributes: [
                .font: AtelierTypography.codeFont(
                    size: codeFont.pointSize
                        * AtelierTypography.micro
                        / AtelierTypography.uiSize
                ),
                .foregroundColor: AppKitThemeAdapter.secondary,
                .kern: 1.5,
                .paragraphStyle: headerStyle
            ]
        ))

        let bodyBlock = NSTextTableBlock(
            table: table,
            startingRow: 1,
            rowSpan: 1,
            startingColumn: 0,
            columnSpan: 1
        )
        configureCodeBlock(
            bodyBlock,
            // `code` equals the editor surface; a light raised wash sets the card apart.
            backgroundColor: AppKitThemeAdapter.raised.withAlphaComponent(
                MarkdownCodeCardLayout.bodyTintAlpha
            ),
            horizontalPadding: AtelierMetrics.spaceM,
            verticalPadding: AtelierMetrics.spaceS
        )
        let codeStyle = paragraphStyle(
            lineSpacing: AtelierMetrics.spaceXS,
            before: 0,
            after: 0,
            firstLineHeadIndent: 0,
            headIndent: 0,
            tailIndent: 0
        )
        codeStyle.textBlocks = [bodyBlock]
        let trailingCodeStyle = paragraphStyle(
            lineSpacing: AtelierMetrics.spaceXS,
            before: 0,
            after: AtelierMetrics.spaceL,
            firstLineHeadIndent: 0,
            headIndent: 0,
            tailIndent: 0
        )
        trailingCodeStyle.textBlocks = [bodyBlock]
        let source = content.isEmpty ? " " : content
        let range = NSRange(location: output.length, length: (source as NSString).length)
        let code = NSMutableAttributedString(string: source + "\n", attributes: [
            .font: codeFont,
            .foregroundColor: AppKitThemeAdapter.foreground,
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
        codeBlocks.append(
            MarkdownCodeBlockRegion(
                id: id,
                headerRange: NSRange(
                    location: headerStart,
                    length: range.location - headerStart
                ),
                sourceRange: range,
                source: content
            )
        )
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

    private static func configureCodeBlock(
        _ block: NSTextTableBlock,
        backgroundColor: NSColor,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat
    ) {
        block.setWidth(
            AtelierTheme.strokeHairline,
            type: .absoluteValueType,
            for: .border
        )
        block.setBorderColor(AppKitThemeAdapter.border)
        block.setWidth(
            horizontalPadding,
            type: .absoluteValueType,
            for: .padding,
            edge: .minX
        )
        block.setWidth(
            horizontalPadding,
            type: .absoluteValueType,
            for: .padding,
            edge: .maxX
        )
        block.setWidth(
            verticalPadding,
            type: .absoluteValueType,
            for: .padding,
            edge: .minY
        )
        block.setWidth(
            verticalPadding,
            type: .absoluteValueType,
            for: .padding,
            edge: .maxY
        )
        block.backgroundColor = backgroundColor
    }

    /// Leading YAML metadata as one quiet two-column card in the same text storage.
    private static func appendFrontMatter(
        _ entries: [MarkdownFrontMatterEntry],
        to output: NSMutableAttributedString,
        bodySize: CGFloat,
        codeFont: NSFont
    ) {
        guard !entries.isEmpty else { return }
        let table = NSTextTable()
        table.numberOfColumns = 2
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        table.setContentWidth(100, type: .percentageValueType)
        let keyFont = AtelierTypography.codeFont(size: max(9, bodySize * 0.68))
        let valueFont = NSFont.systemFont(ofSize: max(10, bodySize * 0.84))
        let background = AppKitThemeAdapter.raised.withAlphaComponent(0.26)

        for (rowIndex, entry) in entries.enumerated() {
            for columnIndex in 0..<2 {
                let block = NSTextTableBlock(
                    table: table,
                    startingRow: rowIndex,
                    rowSpan: 1,
                    startingColumn: columnIndex,
                    columnSpan: 1
                )
                block.backgroundColor = background
                block.setBorderColor(AppKitThemeAdapter.border)
                if rowIndex == 0 {
                    block.setWidth(
                        AtelierTheme.strokeHairline,
                        type: .absoluteValueType,
                        for: .border,
                        edge: .minY
                    )
                }
                if rowIndex == entries.count - 1 {
                    block.setWidth(
                        AtelierTheme.strokeHairline,
                        type: .absoluteValueType,
                        for: .border,
                        edge: .maxY
                    )
                }
                block.setContentWidth(
                    columnIndex == 0
                        ? MarkdownFrontMatterLayout.keyColumnPercentage
                        : 100 - MarkdownFrontMatterLayout.keyColumnPercentage,
                    type: .percentageValueType
                )
                block.setWidth(
                    AtelierMetrics.spaceM,
                    type: .absoluteValueType,
                    for: .padding,
                    edge: columnIndex == 0 ? .minX : .maxX
                )
                block.setWidth(
                    AtelierMetrics.spaceS,
                    type: .absoluteValueType,
                    for: .padding,
                    edge: columnIndex == 0 ? .maxX : .minX
                )
                block.setWidth(
                    AtelierMetrics.spaceXS,
                    type: .absoluteValueType,
                    for: .padding,
                    edge: .minY
                )
                block.setWidth(
                    AtelierMetrics.spaceXS,
                    type: .absoluteValueType,
                    for: .padding,
                    edge: .maxY
                )

                // Table cells keep zero paragraph spacing; the next block owns the gap.
                let paragraph = paragraphStyle(
                    lineSpacing: AtelierMetrics.spaceXS,
                    before: 0,
                    after: 0
                )
                if columnIndex == 0 {
                    paragraph.lineBreakMode = .byCharWrapping
                }
                paragraph.textBlocks = [block]
                output.append(NSAttributedString(
                    string: (columnIndex == 0 ? entry.key : entry.value) + "\n",
                    attributes: [
                        .font: columnIndex == 0 ? keyFont : valueFont,
                        .foregroundColor: columnIndex == 0
                            ? AppKitThemeAdapter.accent
                            : AppKitThemeAdapter.secondary,
                        .kern: columnIndex == 0 ? 0.4 : 0,
                        .paragraphStyle: paragraph
                    ]
                ))
            }
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
        let columnPercentages = tableColumnPercentages(headers: headers, rows: rows)
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
                block.setBorderColor(AppKitThemeAdapter.border)
                block.setWidth(
                    AtelierTheme.strokeHairline,
                    type: .absoluteValueType,
                    for: .border,
                    edge: .maxY
                )
                if rowIndex == 0 {
                    block.setWidth(
                        AtelierTheme.strokeHairline,
                        type: .absoluteValueType,
                        for: .border,
                        edge: .minY
                    )
                }
                block.setContentWidth(
                    columnPercentages[columnIndex],
                    type: .percentageValueType
                )
                block.setWidth(
                    AtelierMetrics.spaceM,
                    type: .absoluteValueType,
                    for: .padding,
                    edge: .minX
                )
                block.setWidth(
                    AtelierMetrics.spaceM,
                    type: .absoluteValueType,
                    for: .padding,
                    edge: .maxX
                )
                block.setWidth(
                    AtelierMetrics.spaceS,
                    type: .absoluteValueType,
                    for: .padding,
                    edge: .minY
                )
                block.setWidth(
                    AtelierMetrics.spaceS,
                    type: .absoluteValueType,
                    for: .padding,
                    edge: .maxY
                )
                if rowIndex == 0 {
                    block.backgroundColor = AppKitThemeAdapter.accent.withAlphaComponent(
                        usesDarkAppearance ? 0.16 : 0.10
                    )
                } else if rowIndex.isMultiple(of: 2) {
                    block.backgroundColor = AppKitThemeAdapter.raised.withAlphaComponent(
                        usesDarkAppearance ? 0.26 : 0.30
                    )
                }

                let value = row.indices.contains(columnIndex) ? row[columnIndex] : ""
                let paragraph = paragraphStyle(
                    lineSpacing: AtelierMetrics.spaceXS,
                    before: 0,
                    after: 0
                )
                // Long unbroken tokens (paths, URLs) must wrap inside their column.
                if MarkdownTableCellPolicy.wrapsByCharacter(value) {
                    paragraph.lineBreakMode = .byCharWrapping
                }
                paragraph.textBlocks = [block]
                let cellSize = bodyFont.pointSize * MarkdownTableCellPolicy.fontScale
                let font = rowIndex == 0
                    ? NSFont.systemFont(ofSize: cellSize, weight: .semibold)
                    : NSFont.systemFont(ofSize: cellSize)
                let cell = inlineText(
                    value,
                    font: font,
                    foregroundColor: AppKitThemeAdapter.foreground,
                    paragraphStyle: paragraph,
                    codeFont: codeFont
                )
                if rowIndex == 0 {
                    cell.addAttribute(
                        .kern,
                        value: 0.4,
                        range: NSRange(location: 0, length: cell.length)
                    )
                }
                output.append(cell)
                output.append(NSAttributedString(string: "\n", attributes: [
                    .font: font,
                    .paragraphStyle: paragraph
                ]))
            }
        }
    }

    static func tableColumnPercentages(
        headers: [String],
        rows: [[String]]
    ) -> [CGFloat] {
        guard !headers.isEmpty else { return [] }
        let sample = rows.prefix(128)
        let scores = headers.indices.map { columnIndex -> CGFloat in
            let values = [headers[columnIndex]] + sample.map { row in
                row.indices.contains(columnIndex) ? row[columnIndex] : ""
            }
            let longest = values.reduce(1) { current, value in
                let lineLength = value.split(
                    separator: "\n",
                    omittingEmptySubsequences: false
                ).reduce(0) { max($0, min(80, $1.count)) }
                return max(current, lineLength)
            }
            return sqrt(CGFloat(longest) + 4)
        }
        let scoreTotal = scores.reduce(0, +)
        let equalShare = 100 / CGFloat(headers.count)
        let minimumShare = min(14, equalShare * 0.72)
        let maximumShare = max(equalShare, min(48, equalShare * 2.4))
        let blended = scores.map { score in
            let weightedShare = scoreTotal > 0 ? score / scoreTotal * 100 : equalShare
            return min(
                maximumShare,
                max(minimumShare, equalShare * 0.3 + weightedShare * 0.7)
            )
        }
        let blendedTotal = blended.reduce(0, +)
        guard blendedTotal > 0 else {
            return Array(repeating: equalShare, count: headers.count)
        }
        return blended.map { $0 / blendedTotal * 100 }
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
        let weight: NSFont.Weight = level <= 3 ? .semibold : .medium
        return level <= 2
            ? serifFont(size: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
    }

    private static func serifFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.serif) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    private static func serifItalicFont(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        guard let serif = base.fontDescriptor.withDesign(.serif) else { return base }
        let italic = serif.withSymbolicTraits(.italic)
        return NSFont(descriptor: italic, size: size)
            ?? NSFont(descriptor: serif, size: size)
            ?? base
    }

    private static func headingColor(level: Int) -> NSColor {
        switch level {
        case 1, 2: AppKitThemeAdapter.foreground
        case 3: AppKitThemeAdapter.accent
        default: AppKitThemeAdapter.secondary
        }
    }

    private static func headingTopSpacing(level: Int) -> CGFloat {
        level <= 2 ? AtelierMetrics.space2XL + AtelierMetrics.spaceS : AtelierMetrics.spaceXL
    }
}

private struct MarkdownCodeCopyControl: View {
    let source: String

    var body: some View {
        MarkdownCopyButton(source: source, label: "Copy code")
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
            metrics: .current
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
        private var codeBlocks: [MarkdownCodeBlockRegion] = []
        private var codeCopyControls: [String: NSHostingView<MarkdownCodeCopyControl>] = [:]
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
                    self?.syncVisibleCodeCopyControls()
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
            for control in codeCopyControls.values {
                control.removeFromSuperview()
            }
            codeCopyControls.removeAll(keepingCapacity: false)
            codeBlocks = []
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
            codeBlocks = document.codeBlocks
            let validCodeBlockIDs = Set(codeBlocks.map(\.id))
            let staleCodeBlockIDs = codeCopyControls.keys.filter {
                !validCodeBlockIDs.contains($0)
            }
            for id in staleCodeBlockIDs {
                codeCopyControls[id]?.removeFromSuperview()
                codeCopyControls[id] = nil
            }
            for block in codeBlocks {
                codeCopyControls[block.id]?.rootView = MarkdownCodeCopyControl(
                    source: block.source
                )
            }
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
            syncVisibleCodeCopyControls()
        }

        private func syncVisibleCodeCopyControls() {
            guard let scrollView,
                  let textView,
                  let textContainer = textView.textContainer,
                  let layoutManager = textView.layoutManager,
                  !codeBlocks.isEmpty else {
                for control in codeCopyControls.values {
                    control.removeFromSuperview()
                }
                codeCopyControls.removeAll(keepingCapacity: true)
                return
            }
            let textOrigin = textView.textContainerOrigin
            let visibleRect = scrollView.contentView.bounds.offsetBy(
                dx: -textOrigin.x,
                dy: -textOrigin.y
            )
            let visibleGlyphRange = layoutManager.glyphRange(
                forBoundingRect: visibleRect,
                in: textContainer
            )
            let visibleCharacterRange = layoutManager.characterRange(
                forGlyphRange: visibleGlyphRange,
                actualGlyphRange: nil
            )
            let visibleBlocks = codeBlocks.filter {
                NSIntersectionRange($0.headerRange, visibleCharacterRange).length > 0
            }
            let visibleIDs = Set(visibleBlocks.map(\.id))
            let hiddenCodeBlockIDs = codeCopyControls.keys.filter {
                !visibleIDs.contains($0)
            }
            for id in hiddenCodeBlockIDs {
                codeCopyControls[id]?.removeFromSuperview()
                codeCopyControls[id] = nil
            }

            for block in visibleBlocks {
                let control: NSHostingView<MarkdownCodeCopyControl>
                if let existing = codeCopyControls[block.id] {
                    control = existing
                } else {
                    let created = NSHostingView(
                        rootView: MarkdownCodeCopyControl(source: block.source)
                    )
                    scrollView.addSubview(
                        created,
                        positioned: .above,
                        relativeTo: scrollView.contentView
                    )
                    codeCopyControls[block.id] = created
                    control = created
                }
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: block.headerRange,
                    actualCharacterRange: nil
                )
                let headerRect = layoutManager.boundingRect(
                    forGlyphRange: glyphRange,
                    in: textContainer
                )
                let size = control.fittingSize
                let origin = textView.convert(
                    NSPoint(
                        x: textView.bounds.maxX
                            - textView.textContainerInset.width
                            - AtelierMetrics.spaceS
                            - size.width,
                        y: textOrigin.y
                            + headerRect.midY
                            - size.height / 2
                    ),
                    to: scrollView
                )
                control.frame = NSRect(
                    x: max(scrollView.contentView.frame.minX, origin.x),
                    y: origin.y,
                    width: size.width,
                    height: size.height
                ).integral
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
