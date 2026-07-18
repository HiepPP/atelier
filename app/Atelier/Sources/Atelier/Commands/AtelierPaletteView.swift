import SwiftUI

struct AtelierPaletteView: View {
    @Bindable var model: AtelierPaletteModel
    let actionContext: AtelierActionContext
    let onActivate: (AtelierPaletteSelection) -> Void
    let onDismiss: () -> Void

    @FocusState private var queryIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            queryField
            Divider()
            results
            footer
        }
        .frame(maxWidth: 640)
        .frame(height: 410)
        .background(AtelierTheme.raised)
        .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AtelierTheme.panelRadius, style: .continuous)
                .stroke(AtelierTheme.border, lineWidth: AtelierTheme.strokeControl)
        }
        .shadow(color: AtelierTheme.shadowFloating, radius: 24, y: 12)
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                queryIsFocused = true
            }
        }
        .onChange(of: actionContext) { _, newContext in
            model.refreshCommands(context: newContext)
        }
        .onKeyPress(.upArrow) {
            model.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            model.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.return) {
            activateSelection()
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.mode == .files ? "Quick Open" : "Command Palette")
    }

    private var queryField: some View {
        HStack(spacing: AtelierMetrics.spaceM) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(
                model.mode == .files ? "Open a file..." : "Run a command...",
                text: Binding(
                    get: { model.query },
                    set: { model.updateQuery($0, actionContext: actionContext) }
                )
            )
            .textFieldStyle(.plain)
            .atelierFont(size: AtelierTypography.uiSize)
            .focused($queryIsFocused)
            .onSubmit {
                activateSelection()
            }
            .accessibilityLabel(model.mode == .files ? "Quick Open query" : "Command query")

            if model.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Searching workspace files")
            }
        }
        .padding(.horizontal, AtelierMetrics.spaceL)
        .frame(height: 52)
        .background(AtelierTheme.editor)
    }

    @ViewBuilder
    private var results: some View {
        if resultIDs.isEmpty, !model.isSearching {
            AtelierEmptyState(
                systemImage: model.mode == .files ? "doc.text.magnifyingglass" : "command",
                title: model.mode == .files ? "No Recent Files" : "No Matching Commands",
                message: model.mode == .files && model.query.isEmpty
                    ? "Open a file or type a name to search this workspace."
                    : "Try a shorter query."
            )
        } else {
            List(selection: selectionBinding) {
                switch model.mode {
                case .files:
                    ForEach(model.fileResults) { match in
                        fileRow(match)
                            .tag(match.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                model.select(id: match.id)
                                activateSelection()
                            }
                            .atelierPointerCursor()
                    }
                case .commands:
                    ForEach(model.commandResults) { match in
                        commandRow(match)
                            .tag(match.id)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                model.select(id: match.id)
                                activateSelection()
                            }
                            .atelierPointerCursor()
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AtelierTheme.raised)
        }
    }

    private var footer: some View {
        HStack(spacing: AtelierMetrics.spaceM) {
            Text("Up/Down Select")
            Text("Return Open")
            Spacer()
            Text("Esc Close")
        }
        .atelierFont(size: AtelierTypography.micro, design: .monospaced)
        .foregroundStyle(.secondary)
        .padding(.horizontal, AtelierMetrics.spaceL)
        .frame(height: 34)
        .background(AtelierTheme.chrome)
        .accessibilityHidden(true)
    }

    private func fileRow(_ match: AtelierPaletteFileMatch) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(match.candidate.fileName)
                .atelierFont(size: AtelierTypography.body, weight: .medium)
                .lineLimit(1)
            Text(match.candidate.relativePath)
                .atelierFont(size: AtelierTypography.caption, design: .monospaced)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, AtelierMetrics.spaceXS)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(match.candidate.fileName), \(match.candidate.relativePath)")
        .accessibilityValue(model.selectedID == match.id ? "Selected" : "Not selected")
    }

    private func commandRow(_ match: AtelierPaletteCommandMatch) -> some View {
        HStack(spacing: AtelierMetrics.spaceM) {
            VStack(alignment: .leading, spacing: 2) {
                Text(match.title)
                    .atelierFont(size: AtelierTypography.body, weight: .medium)
                    .lineLimit(1)
                Text(match.descriptor.category)
                    .atelierFont(size: AtelierTypography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: AtelierMetrics.spaceM)
            if let shortcut = match.descriptor.shortcutLabel {
                Text(shortcut)
                    .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, AtelierMetrics.spaceXS)
        .opacity(match.isEnabled ? 1 : AtelierTheme.disabledOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(commandAccessibilityLabel(match))
        .accessibilityValue(model.selectedID == match.id ? "Selected" : "Not selected")
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { model.selectedID },
            set: { selection in
                model.select(id: selection)
            }
        )
    }

    private var resultIDs: [String] {
        switch model.mode {
        case .files:
            model.fileResults.map(\.id)
        case .commands:
            model.commandResults.map(\.id)
        }
    }

    private func activateSelection() {
        guard let selection = model.selection else { return }
        onActivate(selection)
    }

    private func commandAccessibilityLabel(_ match: AtelierPaletteCommandMatch) -> String {
        let shortcut = match.descriptor.shortcutLabel.map { ", \($0)" } ?? ""
        let availability = match.isEnabled ? "" : ", unavailable"
        return "\(match.title), \(match.descriptor.category)\(shortcut)\(availability)"
    }
}
