import SwiftUI

struct AgentResponsesView: View {
    @Bindable var model: AgentResponsesModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
        }
        .background(AtelierTheme.editor)
        .onAppear { model.markAllRead() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .foregroundStyle(AtelierTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Agent Responses")
                    .atelierFont(size: 12, weight: .semibold)
                Text("Codex and Claude - workspace transcript")
                    .atelierFont(size: 9.5, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(model.responses.count)")
                .atelierFont(size: 10, weight: .semibold, design: .monospaced)
                .foregroundStyle(.secondary)
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(AtelierLuminareIconButtonStyle())
            .accessibilityLabel("Refresh agent responses")
            .help("Refresh agent responses")
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(AtelierTheme.chrome)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if model.responses.isEmpty {
                        emptyState
                    }
                    ForEach(model.responses) { response in
                        responseCard(response)
                            .id(response.id)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.editor)
            .onChange(of: model.responses.last?.id) {
                if let id = model.responses.last?.id {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No agent responses yet")
                .atelierFont(size: 20, weight: .semibold)
            Text("Final Codex and Claude answers for this workspace will appear here.")
                .atelierFont(size: 12)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 520, alignment: .leading)
        .padding(.vertical, 24)
    }

    private func responseCard(_ response: AgentResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(response.provider.rawValue.uppercased())
                    .atelierFont(size: 9, weight: .bold, design: .monospaced)
                    .foregroundStyle(providerColor(response.provider))
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
        .padding(14)
        .background(AtelierTheme.editor)
        .overlay {
            RoundedRectangle(cornerRadius: AtelierTheme.controlRadius)
                .stroke(AtelierTheme.border, lineWidth: 0.75)
        }
        .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
    }

    private func providerColor(_ provider: AgentProvider) -> Color {
        switch provider {
        case .codex:
            AtelierTheme.accent
        case .claude:
            AtelierTheme.gitOrange
        }
    }

    private func shortSessionID(_ sessionID: String) -> String {
        let value = URL(fileURLWithPath: sessionID).lastPathComponent
        return value.count > 20 ? String(value.prefix(20)) : value
    }
}
