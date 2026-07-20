import AppKit
import STTextView

@MainActor
final class FileLineNumberRulerView: NSView {
    private weak var textView: STTextView?
    var backgroundColor = AppKitThemeAdapter.code {
        didSet { needsDisplay = true }
    }
    var font = AtelierTypography.codeFont(size: AtelierTypography.editorSize) {
        didSet { scheduleVisibleLineRefresh() }
    }

    private var textLength = 0
    private var lineCenters: [CGFloat] = []
    private var visibleLineLabels: [(number: Int, centerY: CGFloat)] = []
    private var visibleLineRefreshTask: Task<Void, Never>?
    private var visibleLineRefreshPending = false

    init(
        scrollView: NSScrollView,
        textView: STTextView,
        gutterView: STGutterView
    ) {
        self.textView = textView
        font = gutterView.font
        super.init(frame: gutterView.bounds)
        autoresizingMask = [.width, .height]
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewDidChange),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var isFlipped: Bool {
        true
    }

    func updateText(_ text: String) {
        textLength = text.utf16.count
        scheduleVisibleLineRefresh()
    }

    func updateLineCenters(_ lineCenters: [CGFloat]) {
        self.lineCenters = lineCenters
        scheduleVisibleLineRefresh()
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        dirtyRect.fill()
        drawHashMarksAndLabels(in: dirtyRect)

        AppKitThemeAdapter.border.setFill()
        NSRect(
            x: bounds.maxX - 1,
            y: dirtyRect.minY,
            width: 1,
            height: dirtyRect.height
        ).fill()
    }

    private func drawHashMarksAndLabels(in rect: NSRect) {
        guard textLength > 0 else {
            drawLineNumber(1, centeredAt: bounds.minY + font.lineHeight / 2)
            return
        }

        for label in visibleLineLabels where rect.minY...rect.maxY ~= label.centerY {
            drawLineNumber(label.number, centeredAt: label.centerY)
        }
    }

    @objc private func clipViewDidChange() {
        scheduleVisibleLineRefresh()
    }

    func scheduleVisibleLineRefresh() {
        visibleLineRefreshPending = true
        guard visibleLineRefreshTask == nil else { return }
        visibleLineRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            var didRefresh = false
            repeat {
                visibleLineRefreshPending = false
                try? await Task.sleep(nanoseconds: 16_000_000)
                guard !Task.isCancelled else { return }
                didRefresh = refreshVisibleLines()
            } while visibleLineRefreshPending
            if !didRefresh {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return }
                _ = refreshVisibleLines()
            }
            visibleLineRefreshTask = nil
        }
    }

    @discardableResult
    private func refreshVisibleLines() -> Bool {
        guard let textView else {
            visibleLineLabels = []
            needsDisplay = true
            return true
        }
        guard textLength > 0 else {
            visibleLineLabels = []
            needsDisplay = true
            return true
        }
        guard !lineCenters.isEmpty else { return false }

        let documentBounds = textView.convert(visibleRect, from: self)
        let firstLine = max(0, lowerBoundCenter(for: documentBounds.minY) - 1)
        let lastLine = min(
            lineCenters.count,
            upperBoundCenter(for: documentBounds.maxY) + 1
        )
        guard firstLine < lastLine else { return false }
        var labels: [(number: Int, centerY: CGFloat)] = []
        labels.reserveCapacity(lastLine - firstLine)
        for lineIndex in firstLine..<lastLine {
            let rulerPoint = convert(
                NSPoint(x: 0, y: lineCenters[lineIndex]),
                from: textView
            )
            labels.append((lineIndex + 1, rulerPoint.y))
        }

        let visibleBounds = visibleRect
        let visibleLabels = labels.filter {
            visibleBounds.minY...visibleBounds.maxY ~= $0.centerY
        }
        visibleLineLabels = visibleLabels
        needsDisplay = true
        return !visibleLabels.isEmpty
    }

    private func drawLineNumber(_ number: Int, centeredAt centerY: CGFloat) {
        let value = "\(number)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: AppKitThemeAdapter.secondary
        ]
        let size = value.size(withAttributes: attributes)
        value.draw(
            at: NSPoint(
                x: max(0, bounds.maxX - AtelierMetrics.spaceS - size.width),
                y: centerY - size.height / 2
            ),
            withAttributes: attributes
        )
    }

    private func lowerBoundCenter(for position: CGFloat) -> Int {
        var lower = 0
        var upper = lineCenters.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if lineCenters[middle] < position {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }

    private func upperBoundCenter(for position: CGFloat) -> Int {
        var lower = 0
        var upper = lineCenters.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if lineCenters[middle] <= position {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return lower
    }
}

private extension NSFont {
    var lineHeight: CGFloat {
        ceil(ascender - descender + leading)
    }
}
