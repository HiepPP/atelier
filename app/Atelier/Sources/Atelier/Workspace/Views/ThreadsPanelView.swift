import Foundation
import SwiftUI

struct ThreadsPanelView: View {
    let workspaceID: String
    let threads: [ThreadEntry]
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            ForEach(threads) { thread in
                ThreadRowButton(
                    thread: thread,
                    isSelected: app.selectedWorkspaceID == workspaceID
                        && app.workspace?.terminalTabs.selectedID == thread.terminalID
                ) {
                    activate(thread)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace threads")
    }

    private func activate(_ thread: ThreadEntry) {
        guard let session = app.liveSessions.first(where: {
            $0.state.id == workspaceID
        }) else { return }
        app.selectWorkspace(id: workspaceID)
        session.terminalTabs.selectTerminal(id: thread.terminalID)
    }
}

private struct ThreadRowButton: View {
    let thread: ThreadEntry
    let isSelected: Bool
    let action: () -> Void

    // Indent the status dot under the workspace name (rail insets + chevron gutter).
    private static let contentInset: CGFloat = 28

    var body: some View {
        Button(action: action) {
            HStack(spacing: AtelierMetrics.spaceS) {
                Group {
                    if thread.status == .running {
                        Circle().fill(AtelierTheme.gitAdded)
                    } else {
                        Circle().strokeBorder(
                            AtelierTheme.workspaceRailSecondary.opacity(0.7),
                            lineWidth: 1.2
                        )
                    }
                }
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

                Text(thread.agentName)
                    .atelierFont(size: AtelierTypography.label, weight: .regular)
                    .foregroundStyle(AtelierTheme.workspaceRailForeground.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: AtelierMetrics.spaceS)

                if thread.status == .done, let finishedAt = thread.finishedAt {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        Text(Self.relativeTime(from: finishedAt, to: context.date))
                            .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                            .foregroundStyle(AtelierTheme.workspaceRailSecondary.opacity(0.7))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.leading, Self.contentInset)
            .padding(.trailing, AtelierMetrics.spaceM)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: AtelierMetrics.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(ThreadRowButtonStyle(isSelected: isSelected))
        .accessibilityLabel("\(thread.agentName), \(thread.title)")
        .accessibilityValue(thread.status == .running ? "Running" : "Done")
        .help("\(thread.title), \(thread.status == .running ? "Running" : "Done")")
    }

    private static func relativeTime(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)d"
    }
}

private struct ThreadRowButtonStyle: ButtonStyle {
    let isSelected: Bool

    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                    .fill(fill(isPressed: configuration.isPressed))
            }
            .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous))
            .onHover { isHovering = $0 }
            .atelierPointerCursor()
    }

    private func fill(isPressed: Bool) -> Color {
        if isPressed { return AtelierTheme.workspaceRailPressed }
        if isSelected { return AtelierTheme.workspaceRailSelection.opacity(0.72) }
        if isHovering { return AtelierTheme.workspaceRailHover }
        return .clear
    }
}
