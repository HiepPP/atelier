import SwiftUI

nonisolated enum AgentPreviewLayout: Equatable, Sendable {
    case docked
    case overlay
}

nonisolated enum AgentPreviewLayoutPolicy {
    static let dockedBreakpoint: CGFloat = 1_400
    static let minimumDockedWidth: CGFloat = 360
    static let maximumDockedWidth: CGFloat = 640

    static func layout(containerWidth: CGFloat) -> AgentPreviewLayout {
        containerWidth >= dockedBreakpoint ? .docked : .overlay
    }

    static func panelWidth(containerWidth: CGFloat, layout: AgentPreviewLayout) -> CGFloat {
        switch layout {
        case .docked:
            min(500, max(380, containerWidth * 0.28)).rounded()
        case .overlay:
            min(480, max(320, containerWidth * 0.46)).rounded()
        }
    }

    static func clampedDockedWidth(_ proposedWidth: CGFloat, containerWidth: CGFloat) -> CGFloat {
        let workspaceMinimumWidth: CGFloat = 620
        let availableMaximum = max(minimumDockedWidth, containerWidth - workspaceMinimumWidth)
        return min(
            min(maximumDockedWidth, availableMaximum),
            max(minimumDockedWidth, proposedWidth)
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

    @State private var isPinnedToBottom = true
    @State private var showsPendingResponse = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
        }
        .background(AtelierTheme.editor)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent response preview")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.richtext")
                .foregroundStyle(AtelierTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Response Preview")
                    .atelierFont(size: 12, weight: .semibold)
                Text("Read-only - terminal stays interactive")
                    .atelierFont(size: 9.5, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            sessionPicker
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(AtelierLuminareIconButtonStyle())
            .accessibilityLabel("Refresh agent responses")
            .help("Refresh agent responses")
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(AtelierLuminareIconButtonStyle())
            .accessibilityLabel("Close agent preview")
            .help("Close agent preview")
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(AtelierTheme.chrome)
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
                    Text(shortSessionID(summary.sessionID))
                        .foregroundStyle(.secondary)
                    Text(summary.latestResponseTime, style: .time)
                        .foregroundStyle(.secondary)
                    if summary.unreadCount > 0 {
                        Text("\(summary.unreadCount)")
                            .foregroundStyle(AtelierTheme.gitOrange)
                    }
                } else {
                    Text("Select session")
                }
                Image(systemName: "chevron.down")
                    .atelierFont(size: 8, weight: .semibold)
            }
            .atelierFont(size: 9.5, weight: .semibold, design: .monospaced)
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
                LazyVStack(alignment: .leading, spacing: 14) {
                    if model.responses.isEmpty {
                        emptyState
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
                .padding(18)
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
                    .padding(14)
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
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Waiting for a final response", systemImage: "waveform.path")
                .atelierFont(size: 20, weight: .semibold)
            Text("Use Codex or Claude in the terminal. Markdown and Mermaid previews appear here.")
                .atelierFont(size: 12)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.vertical, 24)
    }

    private var noSelectionState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Select a session", systemImage: "rectangle.stack")
                .atelierFont(size: 20, weight: .semibold)
            Text("Choose a Codex or Claude session to preview its final responses.")
                .atelierFont(size: 12)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.vertical, 24)
    }

    private func responseCard(_ response: AgentResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(response.provider.rawValue.uppercased())
                    .atelierFont(size: 9, weight: .bold, design: .monospaced)
                    .foregroundStyle(AtelierTheme.accent)
                Text(response.timestamp, style: .time)
                    .atelierFont(size: 9.5, design: .monospaced)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(shortSessionID(response.sessionID))
                    .atelierFont(size: 9, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            AgentMarkdownView(source: response.markdown)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(height: 0.5)
        }
        .onAppear {
            model.markRead(response)
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
