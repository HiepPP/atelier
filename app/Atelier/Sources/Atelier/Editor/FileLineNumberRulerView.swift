import AppKit

/// Line-number gutter driven by the text view's own TextKit 1 layout manager.
/// Because it shares that single layout manager, the numbers can never diverge
/// from the displayed glyphs (the cross-TextKit measurement that used to drop
/// lines is gone), and `NSScrollView` keeps the ruler pinned to the document as
/// it scrolls, so numbers never lag behind the text.
@MainActor
final class FileLineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    // UTF-16 offset of the first character of each logical line. Precomputed on
    // content change so the per-scroll draw resolves the first visible line with
    // a binary search instead of rescanning the document every frame.
    private var lineStartOffsets: [Int] = [0]

    var backgroundColor = AppKitThemeAdapter.editor(usesDarkAppearance: false) {
        didSet { needsDisplay = true }
    }
    var separatorColor = AppKitThemeAdapter.border {
        didSet { needsDisplay = true }
    }
    var textColor = AppKitThemeAdapter.secondary {
        didSet {
            cachedDrawAttributes = nil
            needsDisplay = true
        }
    }
    var numberFont = AtelierTypography.codeFont(size: AtelierTypography.editorSize) {
        didSet {
            guard numberFont != oldValue else { return }
            cachedDrawAttributes = nil
            cachedThicknessDigits = 0
            invalidateThickness()
            needsDisplay = true
        }
    }

    // draw() runs per scroll frame; rebuild the attribute dictionary only when
    // the font or color changes instead of per line per frame.
    private var cachedDrawAttributes: [NSAttributedString.Key: Any]?
    private var drawAttributes: [NSAttributedString.Key: Any] {
        if let cachedDrawAttributes { return cachedDrawAttributes }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: textColor
        ]
        cachedDrawAttributes = attributes
        return attributes
    }

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        numberFont = textView.font ?? AtelierTypography.codeFont(size: AtelierTypography.editorSize)
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = AtelierMetrics.codeGutterWidth

        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clientViewDidScroll),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clientViewDidScroll),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Adopts the controller-owned incremental line index. Called whenever the
    /// document text changes (programmatic load or user edit). The array is
    /// COW-shared, so this is O(1) plus a redraw of the visible gutter.
    func updateLineStarts(_ offsets: [Int]) {
        lineStartOffsets = offsets.isEmpty ? [0] : offsets
        invalidateThickness()
        needsDisplay = true
    }

    @objc private func clientViewDidScroll() {
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()
        separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()

        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let textStorage = textView.textStorage else { return }

        let insetHeight = textView.textContainerInset.height
        // textView (flipped) origin expressed in ruler coordinates.
        let originInRuler = convert(NSPoint.zero, from: textView).y + insetHeight

        guard textStorage.length > 0 else {
            drawNumber(1, atFragmentMinY: 0, fragmentHeight: numberFont.approximateLineHeight, originInRuler: originInRuler)
            return
        }

        let visibleRect = textView.visibleRect
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        guard visibleGlyphRange.length > 0 else { return }

        // Walk visible line fragments only. A fragment whose first character
        // sits on a logical line start gets a number; wrapped continuation
        // fragments stay blank. This never scans characters or forces layout
        // outside the viewport, so one huge minified line stays O(visible)
        // per draw frame instead of O(file).
        var glyphIndex = visibleGlyphRange.location
        let glyphRangeEnd = NSMaxRange(visibleGlyphRange)
        while glyphIndex < glyphRangeEnd {
            var fragmentGlyphRange = NSRange()
            let fragmentRect = layoutManager.lineFragmentRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &fragmentGlyphRange,
                withoutAdditionalLayout: true
            )
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let lineNumber = lineNumber(forCharacterIndex: charIndex)
            if lineStartOffsets[lineNumber - 1] == charIndex {
                drawNumber(
                    lineNumber,
                    atFragmentMinY: fragmentRect.minY,
                    fragmentHeight: fragmentRect.height,
                    originInRuler: originInRuler
                )
            }
            glyphIndex = max(NSMaxRange(fragmentGlyphRange), glyphIndex + 1)
        }

        // Trailing empty line (document ends with a newline).
        if layoutManager.extraLineFragmentTextContainer != nil {
            drawNumber(
                lineStartOffsets.count,
                atFragmentMinY: layoutManager.extraLineFragmentRect.minY,
                fragmentHeight: layoutManager.extraLineFragmentRect.height,
                originInRuler: originInRuler
            )
        }
    }

    private func drawNumber(
        _ number: Int,
        atFragmentMinY fragmentMinY: CGFloat,
        fragmentHeight: CGFloat,
        originInRuler: CGFloat
    ) {
        let value = "\(number)" as NSString
        let attributes = drawAttributes
        let size = value.size(withAttributes: attributes)
        let y = originInRuler + fragmentMinY + (fragmentHeight - size.height) / 2
        let x = max(AtelierMetrics.spaceXS, bounds.maxX - AtelierMetrics.spaceS - size.width)
        value.draw(at: NSPoint(x: x, y: y), withAttributes: attributes)
    }

    // Number of line starts at or before the given UTF-16 index. lineStartOffsets
    // always begins with 0, so any valid index resolves to line >= 1.
    private func lineNumber(forCharacterIndex index: Int) -> Int {
        var lower = 0
        var upper = lineStartOffsets.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if lineStartOffsets[middle] <= index {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return max(1, lower)
    }

    // Skips the string measurement when the digit count is unchanged, so the
    // per-keystroke index refresh does no text sizing.
    private var cachedThicknessDigits = 0

    private func invalidateThickness() {
        let digits = max(3, String(lineStartOffsets.count).count)
        guard digits != cachedThicknessDigits else { return }
        cachedThicknessDigits = digits
        let sample = String(repeating: "0", count: digits) as NSString
        let width = ceil(sample.size(withAttributes: drawAttributes).width) + AtelierMetrics.spaceS * 2
        let thickness = max(AtelierMetrics.codeGutterWidth, width)
        if abs(ruleThickness - thickness) > 0.5 {
            ruleThickness = thickness
        }
    }
}

private extension NSFont {
    var approximateLineHeight: CGFloat {
        ceil(ascender - descender + leading)
    }
}
