import AppKit
import SwiftUI

nonisolated enum AgentResponseSelectionPolicy {
    static let defaultEnabled = false
}

/// Reading-comfort scale for the response transcript. It multiplies the zoom
/// scale for transcript text only, so panel chrome keeps its own metrics.
/// Maps the answer's scroll position to the section the reader is in. Pure value
/// logic so it can be tested without a view.
nonisolated enum AgentResponseSectionBarPolicy {
    /// Room below the pinned bar before a heading counts as passed.
    static let viewportLead: CGFloat = 36

    static func showsBar(headingCount: Int) -> Bool {
        headingCount >= 2
    }

    /// The rail needs the answer measure plus its own width plus breathing room.
    /// Below that the pinned bar covers the same job, exactly as in file Preview.
    @MainActor
    static func showsOutline(headingCount: Int, containerWidth: CGFloat) -> Bool {
        guard headingCount >= 2, containerWidth > 0 else { return false }
        let required = AtelierMetrics.transcriptMaxWidth
            + AtelierMetrics.markdownOutlineWidth
            + AtelierMetrics.space2XL * 2
        return containerWidth >= required
    }

    /// Heading rows and outline entries both come from the answer's headings in
    /// document order, so one index identifies the same heading in both.
    static func activeIndex(
        headings: [MarkdownTranscriptHeading],
        answerTop: CGFloat
    ) -> Int? {
        guard showsBar(headingCount: headings.count) else { return nil }
        var active: Int?
        for (index, heading) in headings.enumerated() {
            if answerTop + heading.y <= viewportLead {
                active = index
            } else {
                break
            }
        }
        return active ?? 0
    }

    /// `answerTop` is the answer's top edge measured from the viewport top, so
    /// `answerTop + heading.y` is that heading's distance from the viewport top.
    static func activeTitle(
        headings: [MarkdownTranscriptHeading],
        answerTop: CGFloat
    ) -> String? {
        guard let index = activeIndex(headings: headings, answerTop: answerTop),
              headings.indices.contains(index) else { return nil }
        return headings[index].title
    }
}

nonisolated enum AgentResponseTextSizePolicy {
    static let defaultScale: CGFloat = 1.3
    static let minimumScale: CGFloat = 0.8
    static let maximumScale: CGFloat = 1.6
    static let step: CGFloat = 0.1

    static func clamped(_ scale: CGFloat) -> CGFloat {
        guard scale.isFinite else { return defaultScale }
        return min(max(snapped(scale), minimumScale), maximumScale)
    }

    static func increased(_ scale: CGFloat) -> CGFloat {
        clamped(clamped(scale) + step)
    }

    static func decreased(_ scale: CGFloat) -> CGFloat {
        clamped(clamped(scale) - step)
    }

    static func canIncrease(_ scale: CGFloat) -> Bool {
        clamped(scale) < maximumScale
    }

    static func canDecrease(_ scale: CGFloat) -> Bool {
        clamped(scale) > minimumScale
    }

    /// Repeated step addition drifts in binary floating point, so every value
    /// lands back on a two-decimal grid before it is compared or stored.
    private static func snapped(_ scale: CGFloat) -> CGFloat {
        (scale * 100).rounded() / 100
    }
}

nonisolated enum AgentResponseNavigationPolicy {
    static func previousIndex(currentIndex: Int?, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let currentIndex = currentIndex ?? count - 1
        return currentIndex > 0 ? currentIndex - 1 : nil
    }

    static func nextIndex(currentIndex: Int?, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let currentIndex = currentIndex ?? count - 1
        return currentIndex < count - 1 ? currentIndex + 1 : nil
    }
}

struct AgentResponsesView: View {
    @Bindable var model: AgentResponsesModel
    let onClose: () -> Void
    let isFullWidth: Bool
    let onToggleWidth: () -> Void
    let textSelectionEnabled: Bool
    let profileScrollCycles: Int
    let textScale: CGFloat
    let onChangeTextScale: (CGFloat) -> Void

    nonisolated static let transcriptSpace = "atelier.agent.transcript"

    @Environment(\.atelierZoomScale) private var zoomScale
    @State private var selectedResponseID: AgentResponseReadIdentity?
    @State private var transcriptScrolled = false
    @State private var answerHeadings: [MarkdownTranscriptHeading] = []
    /// Answer top edge measured from the viewport top. Negative once scrolled past.
    @State private var answerTop: CGFloat = 0
    @State private var readingProgress: CGFloat = 0
    @State private var answerOutline: [MarkdownOutlineEntry] = []
    @State private var transcriptWidth: CGFloat = 0
    @State private var contentOffsetY: CGFloat = 0
    @State private var scrollSurface = MarkdownDocumentScrollSurface()

    init(
        model: AgentResponsesModel,
        onClose: @escaping () -> Void,
        isFullWidth: Bool = true,
        onToggleWidth: @escaping () -> Void = {},
        textSelectionEnabled: Bool = AgentResponseSelectionPolicy.defaultEnabled,
        profileScrollCycles: Int = 0,
        textScale: CGFloat = AgentResponseTextSizePolicy.defaultScale,
        onChangeTextScale: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.model = model
        self.onClose = onClose
        self.isFullWidth = isFullWidth
        self.onToggleWidth = onToggleWidth
        self.textSelectionEnabled = textSelectionEnabled
        self.profileScrollCycles = max(0, profileScrollCycles)
        self.textScale = AgentResponseTextSizePolicy.clamped(textScale)
        self.onChangeTextScale = onChangeTextScale
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
                .environment(\.atelierZoomScale, zoomScale * textScale)
            footer
        }
        .background(AtelierTheme.editor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent responses")
        .onAppear(perform: selectLatestResponse)
        .onChange(of: model.selectedSession) {
            selectLatestResponse()
        }
        .onChange(of: model.selectedResponses.last?.readIdentity) { previous, current in
            if selectedResponseID == nil || selectedResponseID == previous {
                selectedResponseID = current
            }
        }
    }

    private var header: some View {
        HStack(spacing: AtelierMetrics.spaceS) {
            sessionPicker

            Spacer(minLength: 0)

            ViewThatFits(in: .horizontal) {
                Label("Final", systemImage: "checkmark.circle")
                    .labelStyle(.titleAndIcon)
                    .fixedSize()
                Image(systemName: "checkmark.circle")
                    .accessibilityLabel("Final response")
            }
            .atelierFont(size: AtelierTypography.caption, weight: .semibold)
            .foregroundStyle(.secondary)

            Button(action: showPreviousResponse) {
                Image(systemName: "chevron.left")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(AtelierGhostButtonStyle())
            .disabled(previousResponseIndex == nil)
            .accessibilityLabel("Previous agent response")
            .help("Previous Response")

            Button(action: showNextResponse) {
                Image(systemName: "chevron.right")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(AtelierGhostButtonStyle())
            .disabled(nextResponseIndex == nil)
            .accessibilityLabel("Next agent response")
            .help("Next Response")

            Button(action: refreshResponses) {
                refreshButtonLabel
            }
            .buttonStyle(AtelierGhostButtonStyle())
            .disabled(model.isRefreshing)
            .accessibilityLabel("Refresh agent responses")
            .accessibilityValue(model.isRefreshing ? "Loading" : "Ready")
            .help("Refresh agent responses")

            textSizeControls

            Button(action: onToggleWidth) {
                Image(
                    systemName: isFullWidth
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right"
                )
                .frame(width: 24, height: 24)
            }
            .buttonStyle(AtelierGhostButtonStyle())
            .accessibilityLabel(
                isFullWidth
                    ? "Minimize agent responses to half width"
                    : "Expand agent responses to full width"
            )
            .help(
                isFullWidth
                    ? "Minimize to Half Width"
                    : "Expand to Full Width"
            )

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(AtelierGhostButtonStyle())
            .accessibilityLabel("Close agent responses")
            .help("Close Agent Responses")
        }
        .padding(.horizontal, AtelierMetrics.spaceM)
        .frame(height: AtelierMetrics.panelHeaderHeight)
        .background(AtelierTheme.chrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(height: AtelierTheme.strokeHairline)
                .opacity(transcriptScrolled ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: transcriptScrolled)
        }
    }

    /// Half width leaves the header little room, so the pair of steppers folds
    /// into one menu before it can squeeze the session picker.
    private var textSizeControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AtelierMetrics.spaceS) {
                textSizeButton(
                    systemImage: "textformat.size.smaller",
                    label: "Decrease agent response text size",
                    help: "Smaller Text",
                    isEnabled: AgentResponseTextSizePolicy.canDecrease(textScale),
                    action: decreaseTextSize
                )
                textSizeButton(
                    systemImage: "textformat.size.larger",
                    label: "Increase agent response text size",
                    help: "Larger Text",
                    isEnabled: AgentResponseTextSizePolicy.canIncrease(textScale),
                    action: increaseTextSize
                )
            }

            Menu {
                Button("Larger Text", action: increaseTextSize)
                    .disabled(!AgentResponseTextSizePolicy.canIncrease(textScale))
                Button("Smaller Text", action: decreaseTextSize)
                    .disabled(!AgentResponseTextSizePolicy.canDecrease(textScale))
            } label: {
                Image(systemName: "textformat.size")
                    .frame(width: 24, height: 24)
                    .atelierGlassControl()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .atelierPointerCursor()
            .accessibilityLabel("Agent response text size")
            .help("Text Size")
        }
    }

    private func textSizeButton(
        systemImage: String,
        label: String,
        help: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(AtelierGhostButtonStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .help(help)
    }

    private var refreshButtonLabel: some View {
        ZStack {
            Image(systemName: "arrow.clockwise")
                .opacity(model.isRefreshing ? 0 : 1)
            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: 24, height: 24)
    }

    private var sessionPicker: some View {
        Menu {
            if model.sessionSummaries.isEmpty {
                Text("No sessions")
            } else {
                ForEach(model.sessionSummaries) { summary in
                    Button {
                        model.selectSession(summary.session)
                    } label: {
                        Text(sessionPickerItem(summary))
                    }
                    .accessibilityLabel(sessionAccessibilityLabel(summary))
                }
            }
        } label: {
            HStack(spacing: 5) {
                if let summary = selectedSummary {
                    Text(summary.provider.rawValue)
                    if summary.unreadCount > 0 {
                        Text("\(summary.unreadCount)")
                            .foregroundStyle(AtelierTheme.gitOrange)
                    }
                } else {
                    Text("Session")
                }
                Image(systemName: "chevron.down")
                    .atelierFont(size: AtelierMetrics.smallIconSize, weight: .semibold)
            }
            .atelierFont(
                size: AtelierTypography.caption,
                weight: .semibold,
                design: .default
            )
            .padding(.horizontal, AtelierMetrics.spaceS)
            .frame(height: AtelierMetrics.controlHeight)
            .atelierGlassControl()
            .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .atelierPointerCursor()
        .layoutPriority(1)
        .accessibilityLabel("Agent session picker")
        .accessibilityValue(
            selectedSummary.map { sessionAccessibilityLabel($0) } ?? "No session selected"
        )
    }

    private var selectedSummary: AgentSessionSummary? {
        guard let selected = model.selectedSession else { return nil }
        return model.sessionSummaries.first { $0.session == selected }
    }

    private var showsOutlineRail: Bool {
        AgentResponseSectionBarPolicy.showsOutline(
            headingCount: answerOutline.count,
            containerWidth: transcriptWidth
        )
    }

    private var activeOutlineID: String? {
        guard let index = AgentResponseSectionBarPolicy.activeIndex(
            headings: answerHeadings,
            answerTop: answerTop
        ), answerOutline.indices.contains(index) else { return nil }
        return answerOutline[index].id
    }

    private func jumpToOutlineEntry(_ entry: MarkdownOutlineEntry) {
        guard let index = answerOutline.firstIndex(where: { $0.id == entry.id }),
              answerHeadings.indices.contains(index) else { return }
        // Heading offsets are relative to the answer, and the answer's own top is
        // relative to the viewport, so the current offset closes the gap to content
        // coordinates. No document rebuild and no second scroll surface.
        let target = contentOffsetY
            + answerTop
            + answerHeadings[index].y
            - AgentResponseSectionBarPolicy.viewportLead
        scrollSurface.scrollToContentY(target, animated: true, duration: 0.18)
    }

    private var transcript: some View {
        HStack(spacing: 0) {
            transcriptScroll
            if showsOutlineRail {
                MarkdownDocumentOutline(
                    entries: answerOutline,
                    selectedID: activeOutlineID,
                    readingProgress: readingProgress,
                    onSelect: jumpToOutlineEntry
                )
            }
        }
        // Measure the container, never the scroll view. The rail shrinks the scroll
        // view, so gating on that width would oscillate across the breakpoint.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            Task { @MainActor in
                transcriptWidth = width
            }
        }
        .task(id: selectedResponse?.readIdentity) {
            // One parse per selected response, off the render path.
            guard let source = selectedResponse?.markdown else {
                answerOutline = []
                return
            }
            answerOutline = AgentMarkdownBlock.outline(
                from: AgentMarkdownBlock.parse(source)
            )
        }
    }

    private var transcriptScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: AtelierMetrics.spaceL) {
                    Color.clear
                        .frame(height: 1)
                        .id("agent-response-top")

                    if model.responses.isEmpty {
                        if model.isRefreshing {
                            loadingState
                        } else {
                            emptyState
                        }
                    } else if model.selectedSession == nil {
                        noSelectionState
                    }

                    if let response = selectedResponse {
                        responseCard(response)
                            .id(response.id)
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("agent-response-bottom")
                }
                .padding(AtelierMetrics.spaceL)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .coordinateSpace(name: Self.transcriptSpace)
            .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.editor)
            .introspect(.scrollView, on: .macOS(.v26)) { scrollView in
                scrollSurface.scrollView = scrollView
            }
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, offset in
                contentOffsetY = offset
            }

            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > 0.5
            } action: { _, scrolled in
                transcriptScrolled = scrolled
            }
            // Quantized so a passive scroll only writes state when the drawn
            // progress pixel actually moves.
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let travel = geometry.contentSize.height
                    - geometry.containerSize.height
                guard travel > 1 else { return 0 }
                let fraction = geometry.contentOffset.y / travel
                return (min(1, max(0, fraction)) * 200).rounded() / 200
            } action: { _, fraction in
                readingProgress = fraction
            }
            .overlay(alignment: .top) {
                // The bar covers the layouts where the rail is hidden, exactly as
                // in file Preview. Opacity only, so crossing the width breakpoint
                // never inserts or removes a view during a layout pass.
                if let activeSectionTitle {
                    MarkdownStickySectionBar(
                        title: activeSectionTitle,
                        readingProgress: readingProgress
                    )
                    .opacity(showsOutlineRail ? 0 : 1)
                }
            }
            .task(id: selectedResponse?.readIdentity) {
                guard profileScrollCycles > 0, selectedResponse != nil else { return }
                for _ in 0..<profileScrollCycles {
                    withAnimation(.linear(duration: 0.02)) {
                        proxy.scrollTo("agent-response-top", anchor: .top)
                    }
                    try? await Task.sleep(for: .milliseconds(40))
                    guard !Task.isCancelled else { return }
                    withAnimation(.linear(duration: 0.02)) {
                        proxy.scrollTo("agent-response-bottom", anchor: .bottom)
                    }
                    try? await Task.sleep(for: .milliseconds(40))
                    guard !Task.isCancelled else { return }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let response = selectedResponse {
            HStack(spacing: AtelierMetrics.spaceS) {
                if let selectedResponseIndex {
                    Text("\(selectedResponseIndex + 1) of \(model.selectedResponses.count)")
                        .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(response.markdown, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(AtelierGhostButtonStyle())
                .accessibilityLabel("Copy agent response")
            }
            .padding(.horizontal, AtelierMetrics.spaceM)
            .frame(height: AtelierMetrics.sectionHeaderHeight)
            .background(AtelierTheme.chrome)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AtelierTheme.border)
                    .frame(height: AtelierTheme.strokeHairline)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            Label("Waiting for a final response", systemImage: "waveform.path")
                .atelierFont(
                    size: AtelierTypography.title,
                    weight: .semibold,
                    design: .serif
                )
            Text("Use Codex or Claude in the terminal. Markdown and Mermaid previews appear here.")
                .atelierFont(size: AtelierTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: AtelierMetrics.emptyStateMaxWidth, alignment: .leading)
        .padding(.vertical, AtelierMetrics.spaceXL)
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            HStack(spacing: AtelierMetrics.spaceS) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading responses")
                    .atelierFont(
                        size: AtelierTypography.title,
                        weight: .semibold,
                        design: .serif
                    )
            }
            Text("Checking Codex and Claude sessions for final responses.")
                .atelierFont(size: AtelierTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: AtelierMetrics.emptyStateMaxWidth, alignment: .leading)
        .padding(.vertical, AtelierMetrics.spaceXL)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading agent responses")
    }

    private var noSelectionState: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            Label("Select a session", systemImage: "rectangle.stack")
                .atelierFont(
                    size: AtelierTypography.title,
                    weight: .semibold,
                    design: .serif
                )
            Text("Choose a Codex or Claude session to preview its final responses.")
                .atelierFont(size: AtelierTypography.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: AtelierMetrics.emptyStateMaxWidth, alignment: .leading)
        .padding(.vertical, AtelierMetrics.spaceXL)
    }

    private func responseCard(_ response: AgentResponse) -> some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            HStack(alignment: .firstTextBaseline, spacing: AtelierMetrics.spaceS) {
                Text(response.provider.rawValue.capitalized)
                    .atelierFont(
                        size: AtelierTypography.caption,
                        weight: .semibold
                    )
                    .foregroundStyle(AtelierTheme.accent)
                Text(response.timestamp, style: .time)
                    .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(shortSessionID(response.sessionID))
                    .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let question = response.question {
                AgentResponseQuestionView(question: question)
            }

            selectableMarkdown(response.markdown)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AtelierMetrics.spaceM)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(height: AtelierTheme.strokeHairline)
        }
        .onAppear {
            model.markRead(response)
        }
    }

    private var selectedResponseIndex: Int? {
        guard !model.selectedResponses.isEmpty else { return nil }
        if let selectedResponseID,
           let index = model.selectedResponses.firstIndex(where: {
               $0.readIdentity == selectedResponseID
           }) {
            return index
        }
        return model.selectedResponses.count - 1
    }

    private var selectedResponse: AgentResponse? {
        guard let selectedResponseIndex else { return nil }
        return model.selectedResponses[selectedResponseIndex]
    }

    private var previousResponseIndex: Int? {
        AgentResponseNavigationPolicy.previousIndex(
            currentIndex: selectedResponseIndex,
            count: model.selectedResponses.count
        )
    }

    private var nextResponseIndex: Int? {
        AgentResponseNavigationPolicy.nextIndex(
            currentIndex: selectedResponseIndex,
            count: model.selectedResponses.count
        )
    }

    private func showPreviousResponse() {
        guard let previousResponseIndex else { return }
        selectedResponseID = model.selectedResponses[previousResponseIndex].readIdentity
    }

    private func showNextResponse() {
        guard let nextResponseIndex else { return }
        selectedResponseID = model.selectedResponses[nextResponseIndex].readIdentity
    }

    private func refreshResponses() {
        Task { await model.refresh() }
    }

    private func increaseTextSize() {
        onChangeTextScale(AgentResponseTextSizePolicy.increased(textScale))
    }

    private func decreaseTextSize() {
        onChangeTextScale(AgentResponseTextSizePolicy.decreased(textScale))
    }

    private func selectLatestResponse() {
        selectedResponseID = model.selectedResponses.last?.readIdentity
    }

    @ViewBuilder
    private func selectableMarkdown(_ source: String) -> some View {
        if textSelectionEnabled {
            answerMarkdown(source)
                .textSelection(.enabled)
        } else {
            answerMarkdown(source)
        }
    }

    private func answerMarkdown(_ source: String) -> some View {
        AgentMarkdownView(source: source) { headings in
            answerHeadings = headings
        }
        // The answer's own top edge inside the scroll view. Adding a heading's
        // offset to it gives that heading's distance from the viewport top, so
        // no separate content-offset read is needed.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .named(Self.transcriptSpace)).minY
        } action: { top in
            // Never write state straight from a layout-derived value: that runs
            // inside AppKit's layout pass.
            Task { @MainActor in
                answerTop = top
            }
        }
    }

    private var activeSectionTitle: String? {
        AgentResponseSectionBarPolicy.activeTitle(
            headings: answerHeadings,
            answerTop: answerTop
        )
    }

    private func shortSessionID(_ sessionID: String) -> String {
        let value = URL(fileURLWithPath: sessionID).lastPathComponent
        return value.count > 12 ? String(value.prefix(12)) : value
    }

    private func sessionPickerItem(_ summary: AgentSessionSummary) -> String {
        let time = summary.latestResponseTime.formatted(date: .omitted, time: .shortened)
        let unread = summary.unreadCount > 0 ? " - \(summary.unreadCount) unread" : ""
        return "\(summary.provider.rawValue) - \(shortSessionID(summary.sessionID)) - \(time)\(unread)"
    }

    private func sessionAccessibilityLabel(_ summary: AgentSessionSummary) -> String {
        "\(summary.provider.rawValue) session \(shortSessionID(summary.sessionID)), "
            + "\(summary.responseCount) responses, \(summary.unreadCount) unread"
    }
}

/// The question that produced the answer above it. It owns its own disclosure
/// state, so expanding it re-evaluates this view alone, not the whole panel.
/// The card's `.id(response.id)` resets that state when the shown response
/// changes.
private struct AgentResponseQuestionView: View {
    let question: String

    @State private var isExpanded = false

    private static let collapsedLineLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: AtelierMetrics.spaceXS) {
                    Text("Question")
                        .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                        .foregroundStyle(AtelierTheme.accent)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .atelierFont(size: AtelierTypography.micro, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .atelierPointerCursor()
            .accessibilityLabel(isExpanded ? "Collapse question" : "Expand question")
            .help(isExpanded ? "Collapse Question" : "Expand Question")

            // Plain text, never Markdown: a pasted prompt must not restyle the
            // card. A String argument already skips localization.
            Text(question)
                .atelierFont(size: AtelierTypography.headline, weight: .medium)
                .foregroundStyle(.primary)
                .lineSpacing(3)
                .lineLimit(isExpanded ? nil : Self.collapsedLineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AtelierMetrics.spaceS)
        .padding(.leading, AtelierMetrics.spaceM)
        .padding(.trailing, AtelierMetrics.spaceS)
        // Cap the outer edge, after padding. Capping the inner content instead
        // adds the horizontal padding on top of the measure, which left the
        // question 20 points wider than the answer column.
        .frame(maxWidth: AtelierMetrics.transcriptMaxWidth, alignment: .leading)
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                    .fill(AtelierTheme.raised)
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                    .strokeBorder(AtelierTheme.border, lineWidth: AtelierTheme.strokeHairline)
                // Accent left rule: it marks the question as the lead-in to the
                // answer below without competing with the answer's own text.
                UnevenRoundedRectangle(
                    topLeadingRadius: AtelierTheme.rowRadius,
                    bottomLeadingRadius: AtelierTheme.rowRadius,
                    style: .continuous
                )
                .fill(AtelierTheme.accent)
                .frame(width: Self.accentRuleWidth)
            }
        }
    }

    private static let accentRuleWidth: CGFloat = 2
}
