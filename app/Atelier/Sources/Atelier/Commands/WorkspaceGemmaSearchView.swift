import SwiftUI

struct WorkspaceGemmaSearchResultsView: View {
    @Bindable var model: WorkspaceGemmaSearchModel
    let onActivate: (WorkspaceGemmaSearchSource) -> Void

    var body: some View {
        if showsEmptyState {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AtelierMetrics.spaceL) {
                        if !model.answer.isEmpty {
                            answer
                        }
                        if !model.sources.isEmpty {
                            sources
                        }
                        if let errorMessage = model.errorMessage {
                            error(errorMessage)
                        }
                    }
                    .padding(AtelierMetrics.spaceL)
                    .frame(maxWidth: AtelierMetrics.transcriptMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .atelierScrollChrome(backgroundColor: AppKitThemeAdapter.raised)
                .background(AtelierTheme.raised)
                .onChange(of: model.selectedSourceID) {
                    guard let selectedSourceID = model.selectedSourceID else { return }
                    proxy.scrollTo(selectedSourceID, anchor: .center)
                }
            }
        }
    }

    private var showsEmptyState: Bool {
        model.answer.isEmpty && model.sources.isEmpty && model.errorMessage == nil
    }

    private var emptyState: some View {
        AtelierEmptyState(
            systemImage: emptyStateImage,
            title: emptyStateTitle,
            message: emptyStateMessage
        )
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            Text("Gemma")
                .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                .foregroundStyle(AtelierTheme.accent)
            AgentMarkdownView(source: model.answer)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            HStack {
                Text("Sources")
                    .atelierFont(size: AtelierTypography.label, weight: .semibold)
                Spacer()
                Text("\(model.sources.count)")
                    .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: AtelierMetrics.spaceXS) {
                ForEach(model.sources) { source in
                    Button {
                        model.selectSource(id: source.id)
                        onActivate(source)
                    } label: {
                        sourceRow(source)
                    }
                    .id(source.id)
                    .buttonStyle(.plain)
                    .atelierPointerCursor()
                    .accessibilityLabel(
                        "Open \(source.path), line \(source.lineNumber)"
                    )
                    .accessibilityValue(
                        model.selectedSourceID == source.id ? "Selected" : "Not selected"
                    )
                }
            }
        }
    }

    private func sourceRow(_ source: WorkspaceGemmaSearchSource) -> some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
            HStack(spacing: AtelierMetrics.spaceS) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(URL(fileURLWithPath: source.path).lastPathComponent)
                    .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                    .lineLimit(1)
                Text("Line \(source.lineNumber)")
                    .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(source.path)
                .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if !source.excerpt.isEmpty {
                Text(source.excerpt)
                    .atelierFont(size: AtelierTypography.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AtelierMetrics.spaceS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            model.selectedSourceID == source.id
                ? AtelierTheme.selection
                : AtelierTheme.panel
        )
        .clipShape(
            RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
        )
        .contentShape(
            RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
        )
    }

    private func error(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
            Text("Gemma could not finish")
                .atelierFont(size: AtelierTypography.label, weight: .semibold)
                .foregroundStyle(AtelierTheme.danger)
            Text(message)
                .atelierFont(size: AtelierTypography.caption)
            if let recoverySuggestion = model.recoverySuggestion {
                Text(recoverySuggestion)
                    .atelierFont(size: AtelierTypography.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AtelierMetrics.spaceS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AtelierTheme.danger.opacity(0.07))
        .clipShape(
            RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous)
        )
    }

    private var emptyStateImage: String {
        if model.isRunning { return "sparkles" }
        if model.status == .cancelled { return "stop.circle" }
        return "sparkle.magnifyingglass"
    }

    private var emptyStateTitle: String {
        if model.isRunning { return "Gemma is Searching" }
        if model.status == .cancelled { return "Search Stopped" }
        return "Ask Gemma"
    }

    private var emptyStateMessage: String {
        if model.isRunning {
            return "Searching indexed workspace files and reading relevant lines."
        }
        if model.status == .cancelled {
            return "Edit the question or press Return to search again."
        }
        return "Ask where or how something works, then press Return."
    }
}
