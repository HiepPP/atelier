import AppKit
import SwiftUI

nonisolated struct WorkspaceRecoveryPresentation: Equatable, Sendable {
    let systemImage: String
    let title: String
    let message: String
    let accessibilityValue: String
}

nonisolated enum WorkspaceRecoveryPolicy {
    static func presentation(
        for status: WorkspaceCatalogItemStatus,
        workspaceName: String
    ) -> WorkspaceRecoveryPresentation? {
        switch status {
        case .unavailable(let message):
            WorkspaceRecoveryPresentation(
                systemImage: "questionmark.folder",
                title: workspaceName,
                message: message,
                accessibilityValue: "Workspace unavailable"
            )
        case .error(let message):
            WorkspaceRecoveryPresentation(
                systemImage: "exclamationmark.triangle.fill",
                title: "Could not open \(workspaceName)",
                message: "Atelier hit an error while opening this workspace. \(message)",
                accessibilityValue: "Workspace error"
            )
        case .active, .inactive, .loading:
            nil
        }
    }
}

nonisolated enum WorkspaceRailPolicy {
    static let railWidth: CGFloat = 176

    static func contentWidth(containerWidth: CGFloat) -> CGFloat {
        max(0, containerWidth - railWidth)
    }
}

nonisolated enum WorkspaceRailIdentityPolicy {
    static func workspaceName(path: String) -> String {
        let name = URL(fileURLWithPath: path, isDirectory: true).lastPathComponent
        return name.isEmpty ? path : name
    }
}

nonisolated enum WorkspaceRailShortcutPolicy {
    static let maximumShortcutCount = 9

    static func number(for index: Int) -> Int? {
        guard (0..<maximumShortcutCount).contains(index) else { return nil }
        return index + 1
    }

    static func index(for number: Int) -> Int? {
        guard (1...maximumShortcutCount).contains(number) else { return nil }
        return number - 1
    }

    static func label(for index: Int) -> String? {
        guard let number = number(for: index) else { return nil }
        return "⌘\(number)"
    }
}

struct WorkspaceRailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var expandedWorkspaceIDs: Set<String> = []
    @State private var workspaceFrames: [String: CGRect] = [:]

    private var expandAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Workspaces")
                    .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                    .foregroundStyle(AtelierTheme.workspaceRailSecondary)
                Spacer()
                Text(app.workspaceItems.count.formatted())
                    .atelierFont(size: AtelierTypography.caption, design: .monospaced)
                    .foregroundStyle(AtelierTheme.workspaceRailSecondary.opacity(0.76))
            }
            .padding(.horizontal, AtelierMetrics.spaceM)
            .frame(height: AtelierMetrics.sectionHeaderHeight)

            ScrollView(.vertical) {
                ZStack(alignment: .topLeading) {
                    if let selectedID = app.selectedWorkspaceID,
                       let frame = workspaceFrames[selectedID] {
                        AtelierMovingGlassIndicator(
                            frame: frame,
                            tint: AtelierTheme.workspaceRailSelection.opacity(0.5),
                            fallbackFill: AtelierTheme.workspaceRailSelection.opacity(0.72)
                        )
                    }

                    LazyVStack(spacing: AtelierMetrics.workspaceRailItemGap) {
                        ForEach(
                            Array(app.workspaceItems.enumerated()),
                            id: \.element.id
                        ) { index, item in
                            workspaceGroup(index: index, item: item)
                        }
                    }
                    .padding(.horizontal, AtelierMetrics.spaceS)
                    .padding(.vertical, AtelierMetrics.spaceS)
                }
                .coordinateSpace(.named("workspaceRailItems"))
                .onPreferenceChange(WorkspaceRailFramePreferenceKey.self) { frames in
                    guard workspaceFrames != frames else { return }
                    Task { @MainActor in
                        guard workspaceFrames != frames else { return }
                        workspaceFrames = frames
                    }
                }
                .clipped()
            }
            .atelierScrollChrome(backgroundColor: .clear)

            Rectangle()
                .fill(AtelierTheme.workspaceRailBorder.opacity(0.72))
                .frame(height: AtelierTheme.strokeHairline)

            WorkspaceRailAddButton {
                AtelierActionRegistry.perform(.openFolder, model: app)
            }
            .padding(AtelierMetrics.spaceS)
        }
        .frame(width: AtelierMetrics.workspaceRailWidth)
        .background {
            AtelierWorkspaceRailBackground()
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.09))
                .frame(height: AtelierTheme.strokeHairline)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AtelierTheme.workspaceRailBorder)
                .frame(width: AtelierTheme.strokeHairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace panel")
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                let snapshots = app.threadsPanel.makeSnapshots(sessions: app.liveSessions)
                app.threadsPanel.refresh(snapshots: snapshots, now: Date())
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
            }
        }
        .onAppear { expandActiveWorkspace() }
        .onChange(of: app.selectedWorkspaceID) { expandActiveWorkspace() }
    }

    @ViewBuilder
    private func workspaceGroup(index: Int, item: WorkspaceCatalogItem) -> some View {
        let threads = threadGroup(for: item.id)?.threads ?? []
        let runningCount = threads.reduce(0) { $0 + ($1.status == .running ? 1 : 0) }
        let isExpanded = expandedWorkspaceIDs.contains(item.id)
        let showThreads = !threads.isEmpty && isExpanded
        VStack(spacing: 0) {
            WorkspaceRailItemButton(
                item: item,
                index: index,
                hasThreads: !threads.isEmpty,
                runningCount: runningCount,
                isExpanded: isExpanded,
                onToggleExpand: { toggleExpand(item.id) }
            )
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: WorkspaceRailFramePreferenceKey.self,
                        value: [
                            item.id: proxy.frame(in: .named("workspaceRailItems"))
                        ]
                    )
                }
            }
            if showThreads {
                ThreadsPanelView(workspaceID: item.id, threads: threads)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, AtelierMetrics.spaceXS)
        .padding(.vertical, showThreads ? AtelierMetrics.spaceXS : 0)
        .background { recessedGroupBackground(active: showThreads) }
    }

    @ViewBuilder
    private func recessedGroupBackground(active: Bool) -> some View {
        if active {
            let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
            shape
                .fill(Color.black.opacity(0.16))
                .overlay {
                    shape
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.05), .clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
                .allowsHitTesting(false)
        }
    }

    private func threadGroup(for workspaceID: String) -> WorkspaceThreadGroup? {
        app.threadsPanel.groups.first { $0.workspaceID == workspaceID }
    }

    private func toggleExpand(_ id: String) {
        withAnimation(expandAnimation) {
            if expandedWorkspaceIDs.contains(id) {
                expandedWorkspaceIDs.remove(id)
            } else {
                expandedWorkspaceIDs.insert(id)
            }
        }
    }

    private func expandActiveWorkspace() {
        guard let id = app.selectedWorkspaceID, !expandedWorkspaceIDs.contains(id) else { return }
        withAnimation(expandAnimation) {
            _ = expandedWorkspaceIDs.insert(id)
        }
    }
}

private struct WorkspaceRailAddButton: View {
    let action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: AtelierMetrics.spaceM) {
                Image(systemName: "plus")
                    .atelierFont(size: AtelierTypography.body, weight: .medium)
                    .frame(width: AtelierMetrics.regularIconSize)
                Text("Add Workspace")
                    .atelierFont(size: AtelierTypography.caption, weight: .medium)
                Spacer()
            }
            .padding(.horizontal, AtelierMetrics.spaceM)
            .frame(maxWidth: .infinity)
            .frame(height: AtelierMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .foregroundStyle(AtelierTheme.workspaceRailForeground)
        .buttonStyle(
            WorkspaceRailItemButtonStyle(
                isSelected: false,
                isHovered: isHovered,
                isFocused: isFocused,
                isDropTargeted: false
            )
        )
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Add workspace")
        .accessibilityValue(isFocused ? "Focused" : "Available")
        .help("Add workspace")
    }
}

private struct WorkspaceRailItemButton: View {
    let item: WorkspaceCatalogItem
    let index: Int
    var hasThreads: Bool = false
    var runningCount: Int = 0
    var isExpanded: Bool = false
    var onToggleExpand: () -> Void = {}
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHovered = false
    @State private var isDropTargeted = false
    @FocusState private var isFocused: Bool

    private var isSelected: Bool { item.status == .active }
    private var isLoading: Bool { item.status == .loading }

    private static let chevronGutter: CGFloat = 14

    var body: some View {
        Button {
            app.selectWorkspace(id: item.id)
        } label: {
            HStack(spacing: AtelierMetrics.spaceS) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(workspaceName)
                        .atelierFont(
                            size: AtelierTypography.body,
                            weight: isSelected ? .semibold : .regular
                        )
                        .foregroundStyle(
                            isLoading
                                ? AtelierTheme.workspaceRailSecondary
                                : AtelierTheme.workspaceRailForeground
                        )
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let shortcutLabel {
                        Text(shortcutLabel)
                            .atelierFont(size: AtelierTypography.micro, weight: .medium, design: .monospaced)
                            .foregroundStyle(
                                isSelected
                                    ? AtelierTheme.workspaceRailForeground.opacity(0.76)
                                    : AtelierTheme.workspaceRailSecondary.opacity(0.68)
                            )
                            .tracking(0.2)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                if runningCount > 0, !isExpanded {
                    runningBadge
                }

                statusAccessory
                    .frame(width: AtelierMetrics.regularIconSize)

                if hasThreads {
                    Color.clear
                        .frame(width: Self.chevronGutter, height: 1)
                }
            }
            .padding(.horizontal, AtelierMetrics.spaceM)
            .frame(maxWidth: .infinity)
            .frame(height: AtelierMetrics.workspaceRailItemHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(
            WorkspaceRailItemButtonStyle(
                isSelected: isSelected,
                isHovered: isHovered,
                isFocused: isFocused,
                isDropTargeted: isDropTargeted
            )
        )
        .overlay(alignment: .trailing) {
            if hasThreads {
                disclosureChevron
                    .padding(.trailing, AtelierMetrics.spaceM)
            }
        }
        .disabled(isLoading)
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .draggable(item.id)
        .dropDestination(for: String.self) { workspaceIDs, location in
            guard let workspaceID = workspaceIDs.first else { return false }
            app.moveWorkspace(
                id: workspaceID,
                relativeTo: item.id,
                insertAfter: location.y > AtelierMetrics.workspaceRailItemHeight / 2
            )
            return true
        } isTargeted: { isDropTargeted = $0 }
        .contextMenu {
            Button("Activate Workspace", systemImage: "arrow.right.circle") {
                app.selectWorkspace(id: item.id)
            }
            .disabled(isSelected)

            Button("Show in Finder", systemImage: "folder.badge.magnifyingglass") {
                NSWorkspace.shared.activateFileViewerSelecting([workspaceURL])
            }
            .disabled(!FileManager.default.fileExists(atPath: item.state.path))

            Button("Copy Project Path", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.state.path, forType: .string)
            }

            Divider()

            Button("Move Up", systemImage: "arrow.up") {
                guard let previousWorkspaceID else { return }
                app.moveWorkspace(id: item.id, relativeTo: previousWorkspaceID, insertAfter: false)
            }
            .disabled(previousWorkspaceID == nil)

            Button("Move Down", systemImage: "arrow.down") {
                guard let nextWorkspaceID else { return }
                app.moveWorkspace(id: item.id, relativeTo: nextWorkspaceID, insertAfter: true)
            }
            .disabled(nextWorkspaceID == nil)

            Divider()

            Button("Close Workspace", systemImage: "xmark.rectangle", role: .destructive) {
                app.closeWorkspace(id: item.id)
            }
        }
        .accessibilityLabel(workspaceName)
        .accessibilityValue(accessibilityDescription)
        .help(helpText)
    }

    private var disclosureChevron: some View {
        Button(action: onToggleExpand) {
            Image(systemName: "chevron.right")
                .atelierFont(size: AtelierTypography.micro, weight: .semibold)
                .foregroundStyle(AtelierTheme.workspaceRailSecondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: Self.chevronGutter, height: AtelierMetrics.workspaceRailItemHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .atelierPointerCursor()
        .accessibilityLabel(isExpanded ? "Collapse threads" : "Expand threads")
    }

    private var runningBadge: some View {
        AtelierCountBadge(value: runningCount, color: AtelierTheme.gitAdded)
            .accessibilityLabel("\(runningCount) running")
            .help("\(runningCount) running")
    }

    @ViewBuilder
    private var statusAccessory: some View {
        switch item.status {
        case .active:
            EmptyView()
        case .loading:
            ProgressView()
                .controlSize(.mini)
                .tint(AtelierTheme.workspaceRailSecondary)
                .accessibilityHidden(true)
        case .unavailable:
            Image(systemName: "questionmark.folder")
                .foregroundStyle(AtelierTheme.workspaceRailSecondary)
                .accessibilityHidden(true)
        case .error:
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(AtelierTheme.danger)
                .accessibilityHidden(true)
        case .inactive:
            EmptyView()
        }
    }

    private var workspaceName: String {
        WorkspaceRailIdentityPolicy.workspaceName(path: item.state.path)
    }

    private var shortcutLabel: String? {
        WorkspaceRailShortcutPolicy.label(for: index)
    }

    private var workspaceURL: URL {
        URL(fileURLWithPath: item.state.path, isDirectory: true)
    }

    private var previousWorkspaceID: String? {
        guard let index = app.workspaceItems.firstIndex(where: { $0.id == item.id }), index > 0 else {
            return nil
        }
        return app.workspaceItems[index - 1].id
    }

    private var nextWorkspaceID: String? {
        guard let index = app.workspaceItems.firstIndex(where: { $0.id == item.id }),
              app.workspaceItems.indices.contains(index + 1) else {
            return nil
        }
        return app.workspaceItems[index + 1].id
    }

    private var accessibilityValue: String {
        switch item.status {
        case .active: "Selected, available"
        case .inactive: "Available"
        case .loading: "Loading"
        case .unavailable: "Unavailable"
        case .error: "Error"
        }
    }

    private var accessibilityDescription: String {
        guard let shortcutLabel else {
            return "\(accessibilityValue), \(item.state.path)"
        }
        return "\(accessibilityValue), shortcut \(shortcutLabel), \(item.state.path)"
    }

    private var helpText: String {
        guard let shortcutLabel else {
            return "\(workspaceName)\n\(item.state.path)\n\(accessibilityValue)"
        }
        return "\(workspaceName)\n\(shortcutLabel)\n\(item.state.path)\n\(accessibilityValue)"
    }
}

private struct WorkspaceRailItemButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isSelected: Bool
    let isHovered: Bool
    let isFocused: Bool
    let isDropTargeted: Bool

    func makeBody(configuration: Configuration) -> some View {
        let interactionState: AtelierInteractionState = if !isEnabled {
            .disabled
        } else if configuration.isPressed {
            .pressed
        } else if isFocused || isDropTargeted {
            .focused
        } else if isSelected {
            .selected
        } else if isHovered {
            .hovered
        } else {
            .normal
        }

        configuration.label
            .background {
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.clear
                            : AtelierTheme.workspaceRailControlFill(for: interactionState)
                    )
            }
            .clipShape(
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
            )
            .overlay {
                if isFocused || isDropTargeted {
                    RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                        .stroke(
                            isDropTargeted ? AtelierTheme.accent : AtelierTheme.workspaceRailBorder,
                            lineWidth: AtelierTheme.strokeFocus
                        )
                }
            }
            .opacity(AtelierTheme.controlOpacity(for: interactionState))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .atelierPointerCursor()
    }
}

private struct WorkspaceRailFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct WorkspaceUnavailableView: View {
    let item: WorkspaceCatalogItem
    let message: String
    @Environment(AppModel.self) private var app

    var body: some View {
        if let presentation = WorkspaceRecoveryPolicy.presentation(
            for: item.status,
            workspaceName: workspaceName
        ) {
            AtelierEmptyState(
                systemImage: presentation.systemImage,
                title: presentation.title,
                message: presentation.message
            ) {
                Button("Choose Folder") {
                    AtelierActionRegistry.perform(.openFolder, model: app)
                }
                .buttonStyle(AtelierLuminarePrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AtelierTheme.canvas)
            .accessibilityValue(presentation.accessibilityValue)
        }
    }

    private var workspaceName: String {
        URL(fileURLWithPath: item.state.path, isDirectory: true).lastPathComponent
    }
}
