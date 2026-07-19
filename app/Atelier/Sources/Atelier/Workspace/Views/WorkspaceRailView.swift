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

    static func abbreviatedParentPath(path: String, homePath: String) -> String {
        let parentPath = URL(fileURLWithPath: path, isDirectory: true)
            .deletingLastPathComponent()
            .standardizedFileURL
            .path
        if parentPath == homePath { return "~" }
        if parentPath.hasPrefix(homePath + "/") {
            return "~" + parentPath.dropFirst(homePath.count)
        }

        let components = URL(fileURLWithPath: parentPath, isDirectory: true)
            .pathComponents
            .filter { $0 != "/" }
        guard components.count > 3 else { return parentPath }
        return ".../" + components.suffix(3).joined(separator: "/")
    }
}

struct WorkspaceRailView: View {
    @Environment(AppModel.self) private var app

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
                LazyVStack(spacing: AtelierMetrics.workspaceRailItemGap) {
                    ForEach(app.workspaceItems) { item in
                        WorkspaceRailItemButton(item: item)
                    }
                }
                .padding(.horizontal, AtelierMetrics.spaceS)
                .padding(.vertical, AtelierMetrics.spaceS)
            }
            .scrollIndicators(.hidden)

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
        .accessibilityLabel("Workspaces")
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
    @Environment(AppModel.self) private var app

    @State private var isHovered = false
    @State private var isDropTargeted = false
    @FocusState private var isFocused: Bool

    private var isSelected: Bool { item.status == .active }
    private var isLoading: Bool { item.status == .loading }

    var body: some View {
        Button {
            app.selectWorkspace(id: item.id)
        } label: {
            HStack(spacing: AtelierMetrics.spaceM) {
                Image(systemName: "folder")
                    .atelierFont(size: AtelierTypography.body, weight: .medium)
                    .foregroundStyle(AtelierTheme.workspaceRailSecondary)
                    .frame(width: AtelierMetrics.regularIconSize)

                VStack(alignment: .leading, spacing: 2) {
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

                    Text(parentPath)
                        .atelierFont(size: AtelierTypography.caption, design: .monospaced)
                        .foregroundStyle(AtelierTheme.workspaceRailSecondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                statusAccessory
                    .frame(width: AtelierMetrics.regularIconSize)
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
        .accessibilityValue("\(accessibilityValue), \(parentPath)")
        .help("\(workspaceName)\n\(item.state.path)\n\(accessibilityValue)")
    }

    @ViewBuilder
    private var statusAccessory: some View {
        switch item.status {
        case .active:
            Image(systemName: "checkmark")
                .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                .foregroundStyle(AtelierTheme.accent)
                .accessibilityHidden(true)
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

    private var parentPath: String {
        WorkspaceRailIdentityPolicy.abbreviatedParentPath(
            path: item.state.path,
            homePath: FileManager.default.homeDirectoryForCurrentUser.path
        )
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
            .background(AtelierTheme.workspaceRailControlFill(for: interactionState))
            .clipShape(
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle()
                        .fill(AtelierTheme.accent)
                        .frame(width: 2, height: 24)
                }
            }
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
