import SwiftUI

struct GitBranchPickerView: View {
    @Bindable var model: GitBranchPickerModel
    let onDismiss: () -> Void

    @FocusState private var queryIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            queryField
            Divider()
            results
            if let message = model.errorMessage {
                errorBanner(message)
            }
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
        .onKeyPress(.upArrow) {
            model.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            model.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            if !model.goBack() { onDismiss() }
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Branch picker")
    }

    private var queryField: some View {
        HStack(spacing: AtelierMetrics.spaceM) {
            Image(systemName: model.stage.isNaming ? "plus" : "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(
                model.stage.prompt,
                text: Binding(
                    get: { model.query },
                    set: { model.updateQuery($0) }
                )
            )
            .textFieldStyle(.plain)
            .atelierFont(size: AtelierTypography.uiSize)
            .focused($queryIsFocused)
            .onSubmit { model.activateSelection() }
            .accessibilityLabel(model.stage.prompt)

            if model.isLoading || model.isRunningAction {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(model.isRunningAction ? "Running" : "Loading refs")
            }
        }
        .padding(.horizontal, AtelierMetrics.spaceL)
        .frame(height: 52)
        .background(AtelierTheme.editor)
    }

    @ViewBuilder
    private var results: some View {
        if model.stage.isNaming {
            namingHint
        } else if model.orderedIDs.isEmpty, !model.isLoading {
            AtelierEmptyState(
                systemImage: "arrow.triangle.branch",
                title: "No Matching Refs",
                message: "Try a shorter query."
            )
        } else {
            List(selection: selectionBinding) {
                if !model.visibleActions.isEmpty {
                    Section {
                        ForEach(model.visibleActions) { action in
                            actionRow(action)
                                .tag(action.id)
                                .contentShape(Rectangle())
                                .onTapGesture { model.begin(action) }
                                .atelierPointerCursor()
                        }
                    }
                }

                ForEach(GitRefKind.allCases, id: \.self) { kind in
                    let refs = model.refs(in: kind)
                    if !refs.isEmpty {
                        Section(kind.sectionTitle) {
                            ForEach(refs) { ref in
                                refRow(ref)
                                    .tag(ref.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.activate(ref) }
                                    .atelierPointerCursor()
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AtelierTheme.raised)
        }
    }

    private var namingHint: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            Text(model.stage.prompt)
                .atelierFont(size: AtelierTypography.body, weight: .medium)
            Text("Return creates the branch and checks it out. Esc goes back.")
                .atelierFont(size: AtelierTypography.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AtelierMetrics.spaceL)
        .background(AtelierTheme.raised)
    }

    private func actionRow(_ action: GitBranchPickerAction) -> some View {
        HStack(spacing: AtelierMetrics.spaceM) {
            Image(systemName: action.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(action.title)
                .atelierFont(size: AtelierTypography.body, weight: .medium)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, AtelierMetrics.spaceXS)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(action.title)
        .accessibilityValue(model.selectedID == action.id ? "Selected" : "Not selected")
    }

    private func refRow(_ ref: GitRef) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AtelierMetrics.spaceS) {
                Image(systemName: ref.kind.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(ref.name)
                    .atelierFont(size: AtelierTypography.body, weight: .medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(GitRelativeTime.label(for: ref.date))
                    .atelierFont(size: AtelierTypography.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if ref.isCurrent {
                    Image(systemName: "checkmark")
                        .atelierFont(size: AtelierTypography.micro, weight: .semibold)
                        .foregroundStyle(.secondary)
                }
            }
            Text(subtitle(for: ref))
                .atelierFont(size: AtelierTypography.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 16 + AtelierMetrics.spaceS)
        }
        .padding(.vertical, AtelierMetrics.spaceXS)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ref.name), \(subtitle(for: ref))")
        .accessibilityValue(model.selectedID == ref.id ? "Selected" : "Not selected")
    }

    private func subtitle(for ref: GitRef) -> String {
        [ref.author, ref.shortHash, ref.subject]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .atelierFont(size: AtelierTypography.caption)
            .foregroundStyle(AtelierTheme.danger)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AtelierMetrics.spaceL)
            .padding(.vertical, AtelierMetrics.spaceS)
            .background(AtelierTheme.danger.opacity(0.10))
            .accessibilityLabel("Git error: \(message)")
    }

    private var footer: some View {
        HStack(spacing: AtelierMetrics.spaceM) {
            Text("Up/Down Select")
            Text(model.stage.isNaming ? "Return Create" : "Return Checkout")
            Spacer()
            Text(model.stage == .selectingRef ? "Esc Close" : "Esc Back")
        }
        .atelierFont(size: AtelierTypography.micro, design: .monospaced)
        .foregroundStyle(.secondary)
        .padding(.horizontal, AtelierMetrics.spaceL)
        .frame(height: 34)
        .background(AtelierTheme.chrome)
        .accessibilityHidden(true)
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { model.selectedID },
            set: { model.selectedID = $0 }
        )
    }
}
