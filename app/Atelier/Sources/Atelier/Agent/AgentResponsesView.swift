import SwiftUI

nonisolated enum AgentResponseSelectionPolicy {
    static let defaultEnabled = false
}

nonisolated enum AgentPreviewPanePolicy {
    static let minimumHeight: CGFloat = 220
    static let workspaceMinimumHeight: CGFloat = 220
    static let preferredMaximumHeight: CGFloat = 560

    static func preferredHeight(containerHeight: CGFloat) -> CGFloat {
        min(
            maximumHeight(containerHeight: containerHeight),
            max(minimumHeight, (containerHeight * 0.46).rounded())
        )
    }

    static func maximumHeight(containerHeight: CGFloat) -> CGFloat {
        min(
            preferredMaximumHeight,
            max(minimumHeight, containerHeight - workspaceMinimumHeight)
        )
    }
}

nonisolated enum AgentResponseTimelinePolicy {
    static func showsPendingResponse(
        previousLastID: AgentResponseReadIdentity?,
        newLastID: AgentResponseReadIdentity?,
        isPinnedToBottom: Bool
    ) -> Bool {
        guard let previousLastID, let newLastID, previousLastID != newLastID else {
            return false
        }
        return !isPinnedToBottom
    }
}

struct AgentResponsesView: View {
    @Bindable var model: AgentResponsesModel
    let onClose: () -> Void
    let textSelectionEnabled: Bool
    let profileScrollCycles: Int

    @State private var isPinnedToBottom = true
    @State private var showsPendingResponse = false

    init(
        model: AgentResponsesModel,
        onClose: @escaping () -> Void,
        textSelectionEnabled: Bool = AgentResponseSelectionPolicy.defaultEnabled,
        profileScrollCycles: Int = 0
    ) {
        self.model = model
        self.onClose = onClose
        self.textSelectionEnabled = textSelectionEnabled
        self.profileScrollCycles = max(0, profileScrollCycles)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            transcript
        }
        .background(AtelierTheme.editor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent response preview")
    }

    private var header: some View {
        HStack(spacing: AtelierMetrics.spaceS) {
            Image(systemName: "doc.richtext")
                .atelierFont(size: AtelierTypography.label, weight: .medium)
                .foregroundStyle(AtelierTheme.accent)
                .frame(width: 26, height: 26)
                .background(AtelierTheme.accent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.rowRadius))

            VStack(alignment: .leading, spacing: 1) {
                Text("Responses")
                    .atelierFont(
                        size: AtelierTypography.headline,
                        weight: .semibold,
                        design: .serif
                    )
                Text("Read-only")
                    .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: AtelierMetrics.spaceS)

            sessionPicker

            Button {
                Task { await model.refresh() }
            } label: {
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
            .buttonStyle(.glass)
            .disabled(model.isRefreshing)
            .accessibilityLabel("Refresh agent responses")
            .accessibilityValue(model.isRefreshing ? "Loading" : "Ready")
            .help("Refresh agent responses")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Close agent preview")
            .help("Close agent preview")
        }
        .padding(.horizontal, AtelierMetrics.spaceM)
        .frame(height: AtelierMetrics.panelHeaderHeight)
        .background(AtelierTheme.chrome)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(height: AtelierTheme.strokeHairline)
        }
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
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous)
            )
            .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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
                LazyVStack(alignment: .leading, spacing: AtelierMetrics.spaceL) {
                    if model.responses.isEmpty {
                        if model.isRefreshing {
                            loadingState
                        } else {
                            emptyState
                        }
                    } else if model.selectedSession == nil {
                        noSelectionState
                    }
                    ForEach(model.selectedResponses) { response in
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
            .overlay(alignment: .bottomTrailing) {
                if showsPendingResponse {
                    Button {
                        proxy.scrollTo("agent-response-bottom", anchor: .bottom)
                        showsPendingResponse = false
                    } label: {
                        Label("New response", systemImage: "arrow.down")
                    }
                    .buttonStyle(AtelierLuminarePrimaryButtonStyle())
                    .padding(AtelierMetrics.spaceL)
                    .accessibilityLabel("Show new agent response")
                    .accessibilityHint("Scrolls to the latest response")
                }
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height
                    >= geometry.contentSize.height - 56
            } action: { _, isPinned in
                isPinnedToBottom = isPinned
                if isPinned {
                    showsPendingResponse = false
                }
            }
            .onChange(of: model.selectedResponses.last?.readIdentity) { previous, current in
                if AgentResponseTimelinePolicy.showsPendingResponse(
                    previousLastID: previous,
                    newLastID: current,
                    isPinnedToBottom: isPinnedToBottom
                ) {
                    showsPendingResponse = true
                }
                if isPinnedToBottom {
                    proxy.scrollTo("agent-response-bottom", anchor: .bottom)
                    showsPendingResponse = false
                }
            }
            .onChange(of: model.selectedSession) {
                showsPendingResponse = false
                proxy.scrollTo("agent-response-bottom", anchor: .bottom)
            }
            .task(id: model.selectedResponses.last?.readIdentity) {
                guard profileScrollCycles > 0,
                      let firstResponse = model.selectedResponses.first else { return }
                for _ in 0..<profileScrollCycles {
                    withAnimation(.linear(duration: 0.02)) {
                        proxy.scrollTo(firstResponse.id, anchor: .top)
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
