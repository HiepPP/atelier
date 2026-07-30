import AppKit
import SwiftUI

nonisolated enum AgentResponseSelectionPolicy {
    static let defaultEnabled = false
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

    @State private var selectedResponseID: AgentResponseReadIdentity?
    @State private var transcriptScrolled = false

    init(
        model: AgentResponsesModel,
        onClose: @escaping () -> Void,
        isFullWidth: Bool = true,
        onToggleWidth: @escaping () -> Void = {},
        textSelectionEnabled: Bool = AgentResponseSelectionPolicy.defaultEnabled,
        profileScrollCycles: Int = 0
    ) {
        self.model = model
        self.onClose = onClose
        self.isFullWidth = isFullWidth
        self.onToggleWidth = onToggleWidth
        self.textSelectionEnabled = textSelectionEnabled
        self.profileScrollCycles = max(0, profileScrollCycles)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
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
            .buttonStyle(.glass)
            .atelierPointerCursor()
            .disabled(previousResponseIndex == nil)
            .accessibilityLabel("Previous agent response")
            .help("Previous Response")

            Button(action: showNextResponse) {
                Image(systemName: "chevron.right")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .atelierPointerCursor()
            .disabled(nextResponseIndex == nil)
            .accessibilityLabel("Next agent response")
            .help("Next Response")

            Button(action: refreshResponses) {
                refreshButtonLabel
            }
            .buttonStyle(.glass)
            .atelierPointerCursor()
            .disabled(model.isRefreshing)
            .accessibilityLabel("Refresh agent responses")
            .accessibilityValue(model.isRefreshing ? "Loading" : "Ready")
            .help("Refresh agent responses")

            Button(action: onToggleWidth) {
                Image(
                    systemName: isFullWidth
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right"
                )
                .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .atelierPointerCursor()
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
            .buttonStyle(.glass)
            .atelierPointerCursor()
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

    private var transcript: some View {
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
            .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.editor)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y > 0.5
            } action: { _, scrolled in
                transcriptScrolled = scrolled
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

    private func selectLatestResponse() {
        selectedResponseID = model.selectedResponses.last?.readIdentity
    }

    @ViewBuilder
    private func selectableMarkdown(_ source: String) -> some View {
        if textSelectionEnabled {
            AgentMarkdownView(source: source)
                .textSelection(.enabled)
        } else {
            AgentMarkdownView(source: source)
        }
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
