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
    static let railWidth: CGFloat = 56

    static func contentWidth(containerWidth: CGFloat) -> CGFloat {
        max(0, containerWidth - railWidth)
    }
}

struct WorkspaceRailView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: AtelierMetrics.workspaceRailItemGap) {
            ScrollView(.vertical) {
                LazyVStack(spacing: AtelierMetrics.workspaceRailItemGap) {
                    ForEach(app.workspaceItems) { item in
                        WorkspaceRailItemButton(item: item) {
                            app.selectWorkspace(id: item.id)
                        }
                    }
                }
                .padding(.vertical, AtelierMetrics.spaceM)
            }
            .scrollIndicators(.hidden)

            WorkspaceRailAddButton {
                AtelierActionRegistry.perform(.openFolder, model: app)
            }
            .padding(.bottom, AtelierMetrics.spaceM)
        }
        .frame(width: AtelierMetrics.workspaceRailWidth)
        .background(AtelierTheme.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(width: AtelierTheme.strokeHairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspaces")
    }
}

private struct WorkspaceRailAddButton: View {
    let action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .atelierFont(size: AtelierTypography.uiSize, weight: .semibold)
                .frame(
                    width: AtelierMetrics.workspaceRailItemSize,
                    height: AtelierMetrics.workspaceRailItemSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(
            WorkspaceRailItemButtonStyle(
                isSelected: false,
                isHovered: isHovered,
                isFocused: isFocused
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
    let action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private var isSelected: Bool {
        if case .active = item.status { return true }
        return false
    }

    private var isLoading: Bool {
        if case .loading = item.status { return true }
        return false
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                Text(workspaceInitial)
                    .atelierFont(size: AtelierTypography.body, weight: .semibold)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .frame(
                        width: AtelierMetrics.workspaceRailItemSize,
                        height: AtelierMetrics.workspaceRailItemSize
                    )

                statusAccessory
                    .frame(width: 12, height: 12)
                    .offset(x: 2, y: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(
            WorkspaceRailItemButtonStyle(
                isSelected: isSelected,
                isHovered: isHovered,
                isFocused: isFocused
            )
        )
        .disabled(isLoading)
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .accessibilityLabel(workspaceName)
        .accessibilityValue(accessibilityValue)
        .help("\(workspaceName)\n\(item.state.path)\n\(accessibilityValue)")
    }

    @ViewBuilder
    private var statusAccessory: some View {
        switch item.status {
        case .loading:
            ProgressView()
                .controlSize(.mini)
                .accessibilityHidden(true)
        case .unavailable:
            Image(systemName: "questionmark.folder")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AtelierTheme.danger)
                .accessibilityHidden(true)
        case .active, .inactive:
            EmptyView()
        }
    }

    private var workspaceName: String {
        let name = URL(fileURLWithPath: item.state.path, isDirectory: true).lastPathComponent
        return name.isEmpty ? item.state.path : name
    }

    private var workspaceInitial: String {
        workspaceName.first.map { String($0).uppercased() } ?? "?"
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
}

private struct WorkspaceRailItemButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isSelected: Bool
    let isHovered: Bool
    let isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        let interactionState: AtelierInteractionState = if configuration.isPressed {
            .pressed
        } else if isFocused {
            .focused
        } else if isSelected {
            .selected
        } else if isHovered {
            .hovered
        } else {
            .normal
        }

        configuration.label
            .background(AtelierTheme.controlFill(for: interactionState))
            .clipShape(
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(AtelierTheme.accent)
                        .frame(width: 2, height: 20)
                }
            }
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                        .stroke(AtelierTheme.accent, lineWidth: AtelierTheme.strokeFocus)
                }
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .atelierPointerCursor()
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
