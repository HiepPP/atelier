import SwiftUI

struct WorkspaceSearchView: View {
    @Bindable var model: WorkspaceSearchModel
    let isPresented: Bool
    let onActivate: (WorkspaceSearchMatch) -> Void
    let onActivateGemmaSource: (WorkspaceGemmaSearchSource) -> Void
    let onDismiss: () -> Void

    @FocusState private var queryIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            queryBar
            Divider()
            results
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AtelierTheme.raised)
        .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.panelRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AtelierTheme.panelRadius, style: .continuous)
                .stroke(AtelierTheme.border, lineWidth: AtelierTheme.strokeControl)
        }
        .shadow(color: AtelierTheme.shadowFloating, radius: 24, y: 12)
        .onAppear {
            updateQueryFocus(isPresented)
        }
        .onChange(of: isPresented) { _, isPresented in
            updateQueryFocus(isPresented)
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
            submit()
            return .handled
        }
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search All Files")
    }

    private func updateQueryFocus(_ shouldFocus: Bool) {
        Task { @MainActor in
            if shouldFocus {
                await Task.yield()
            }
            guard model.isPresented == shouldFocus else { return }
            queryIsFocused = shouldFocus
        }
    }

    private var queryBar: some View {
        HStack(spacing: AtelierMetrics.spaceS) {
            if model.supportsGemma {
                Picker("Search mode", selection: modeBinding) {
                    ForEach(WorkspaceSearchMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue)
                            .tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 132)
                .atelierPointerCursor()
                .accessibilityLabel("Search mode")
            }

            Image(systemName: model.mode == .text ? "magnifyingglass" : "sparkles")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(
                model.mode == .text
                    ? "Search workspace..."
                    : "Ask where or how something works...",
                text: Binding(
                    get: { model.query },
                    set: { value in model.updateQuery(value) }
                )
            )
            .textFieldStyle(.plain)
            .atelierFont(size: AtelierTypography.uiSize)
            .focused($queryIsFocused)
            .onSubmit {
                submit()
            }
            .accessibilityLabel(
                model.mode == .text ? "Workspace search query" : "Gemma workspace question"
            )

            if model.isSearching || model.gemmaSearch?.isRunning == true {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Searching workspace files")
            }

            if model.mode == .text {
                searchOption(
                    label: "Aa",
                    help: "Match Case",
                    isSelected: model.isCaseSensitive,
                    action: { model.toggleCaseSensitivity() }
                )
                searchOption(
                    label: "ab",
                    help: "Match Whole Word",
                    isSelected: model.matchesWholeWords,
                    action: { model.toggleWholeWords() }
                )
                searchOption(
                    label: "Ignored",
                    help: "Include Ignored Files",
                    isSelected: model.includesIgnoredFiles,
                    action: { model.toggleIncludesIgnoredFiles() }
                )
            } else if model.gemmaSearch?.isRunning == true {
                Button("Stop") {
                    model.stopGemma()
                    queryIsFocused = true
                }
                .buttonStyle(AtelierGhostButtonStyle())
                .help("Stop Gemma search")
            }
        }
        .padding(.horizontal, AtelierMetrics.spaceL)
        .frame(height: 52)
        .background(AtelierTheme.editor)
    }

    @ViewBuilder
    private var results: some View {
        if model.mode == .gemma, let gemmaSearch = model.gemmaSearch {
            WorkspaceGemmaSearchResultsView(
                model: gemmaSearch,
                onActivate: onActivateGemmaSource
            )
        } else if model.groups.isEmpty {
            emptyState
        } else {
            List(selection: selectionBinding) {
                ForEach(model.groups) { group in
                    Section {
                        ForEach(group.matches) { match in
                            matchRow(match)
                                .tag(match.id)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    model.select(id: match.id)
                                    onActivate(match)
                                }
                                .atelierPointerCursor()
                        }
                    } header: {
                        fileHeader(group)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(AtelierTheme.raised)
        }
    }

    private var emptyState: some View {
        AtelierEmptyState(
            systemImage: emptyStateImage,
            title: emptyStateTitle,
            message: emptyStateMessage
        )
    }

    private var footer: some View {
        HStack(spacing: AtelierMetrics.spaceM) {
            Text(statusText)
            Spacer()
            Text(returnHint)
            Text("Up/Down Select")
            Text("Esc Close")
        }
        .atelierFont(size: AtelierTypography.micro, design: .monospaced)
        .foregroundStyle(.secondary)
        .padding(.horizontal, AtelierMetrics.spaceL)
        .frame(height: 34)
        .background(AtelierTheme.chrome)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statusText)
    }

    private func searchOption(
        label: String,
        help: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            queryIsFocused = true
        } label: {
            Text(label)
                .atelierFont(
                    size: AtelierTypography.micro,
                    weight: .semibold,
                    design: .monospaced
                )
                .padding(.horizontal, AtelierMetrics.spaceS)
                .frame(height: AtelierMetrics.controlHeight)
                .contentShape(
                    RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .atelierGlassControl(isSelected: isSelected)
        .atelierPointerCursor()
        .help(help)
        .accessibilityLabel(help)
        .accessibilityValue(isSelected ? "On" : "Off")
    }

    private func fileHeader(_ group: WorkspaceSearchFileGroup) -> some View {
        let resultCount = group.matches.reduce(0) { $0 + $1.matchCount }

        return HStack(alignment: .center, spacing: AtelierMetrics.spaceM) {
            Image(systemName: "doc.text")
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.candidate.fileName)
                    .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                    .lineLimit(1)
                Text(group.candidate.relativePath)
                    .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
            Text("\(resultCount) \(resultCount == 1 ? "match" : "matches")")
                .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, AtelierMetrics.spaceXS)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(group.candidate.relativePath), \(group.matches.count) matching lines"
        )
    }

    private func matchRow(_ match: WorkspaceSearchMatch) -> some View {
        HStack(alignment: .top, spacing: AtelierMetrics.spaceM) {
            Text("\(match.lineNumber)")
                .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
                .padding(.top, 1)

            Text(
                """
                \(Text(verbatim: match.leadingText).foregroundStyle(.secondary))\
                \(Text(verbatim: match.matchedText).foregroundStyle(AtelierTheme.accent).bold())\
                \(Text(verbatim: match.trailingText).foregroundStyle(.secondary))
                """
            )
            .atelierFont(size: AtelierTypography.editorSize, design: .monospaced)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)

            if match.matchCount > 1 {
                Text("\(match.matchCount)")
                    .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, AtelierMetrics.spaceXS)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(match.candidate.relativePath), line \(match.lineNumber), \(match.matchCount) matches"
        )
        .accessibilityValue(model.selectedID == match.id ? "Selected" : "Not selected")
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { model.selectedID },
            set: { selection in model.select(id: selection) }
        )
    }

    private var modeBinding: Binding<WorkspaceSearchMode> {
        Binding(
            get: { model.mode },
            set: { model.setMode($0) }
        )
    }

    private var statusText: String {
        if model.mode == .gemma {
            guard let gemmaSearch = model.gemmaSearch else { return "Gemma unavailable" }
            if gemmaSearch.isRunning { return "Gemma is searching..." }
            if gemmaSearch.status == .failed { return "Gemma search failed" }
            if model.needsGemmaSearch { return "Press Return to ask Gemma" }
            if !gemmaSearch.sources.isEmpty {
                return "\(gemmaSearch.sources.count) sources"
            }
            if !gemmaSearch.answer.isEmpty { return "Gemma answer complete" }
            return "Ask Gemma about this workspace"
        }
        if model.isSearching {
            return "Searching..."
        }
        if model.isWaitingToSearch {
            return "Searching after typing stops"
        }
        if model.needsSearch {
            return "Press Return to search now"
        }
        if model.isTruncated {
            return "\(model.matchCount)+ matches in \(model.matchedFileCount) files"
        }
        if model.matchCount > 0 {
            return "\(model.matchCount) matches in \(model.matchedFileCount) files"
        }
        return "\(model.searchedFileCount) files searched"
    }

    private var returnHint: String {
        if model.mode == .gemma {
            guard let gemmaSearch = model.gemmaSearch else { return "Return Ask" }
            return model.needsGemmaSearch || gemmaSearch.selection == nil
                ? "Return Ask"
                : "Return Open"
        }
        return model.needsSearch || model.selection == nil ? "Return Search" : "Return Open"
    }

    private var emptyStateImage: String {
        if model.errorMessage != nil { return "exclamationmark.magnifyingglass" }
        return "doc.text.magnifyingglass"
    }

    private var emptyStateTitle: String {
        if model.errorMessage != nil { return "Search Failed" }
        if model.isSearching { return "Searching..." }
        if model.isWaitingToSearch { return "Waiting to Search" }
        if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Search All Files"
        }
        if model.needsSearch { return "Ready to Search" }
        return "No Results"
    }

    private var emptyStateMessage: String {
        if let errorMessage = model.errorMessage { return errorMessage }
        if model.isSearching { return "Scanning indexed workspace files." }
        if model.isWaitingToSearch {
            return "Search starts 300 milliseconds after typing stops."
        }
        if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Type a query. Search starts after 300 milliseconds."
        }
        if model.needsSearch { return "Press Return to scan this workspace now." }
        return "Try another query or search option."
    }

    private func submit() {
        switch model.mode {
        case .text:
            if model.needsSearch || model.selection == nil {
                model.search()
            } else if let selection = model.selection {
                onActivate(selection)
            }
        case .gemma:
            guard let gemmaSearch = model.gemmaSearch else { return }
            if model.needsGemmaSearch || gemmaSearch.selection == nil {
                model.searchGemma()
            } else if let selection = gemmaSearch.selection {
                onActivateGemmaSource(selection)
            }
        }
    }
}
