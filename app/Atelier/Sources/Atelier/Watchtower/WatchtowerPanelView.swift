import AppKit
import SwiftUI

// Read-only Watchtower dashboard: header, plan card, progress, status counts,
// file actions, command chips, and Todo / Archive sections. Task ids and archive
// rows are clickable and jump to the file via onOpenFile.
//
// Crash-rule note: mount this as an overlay side panel, never as an HSplitView
// child that can collapse to zero. The view is pure - it derives layout from the
// model only and never mutates state from a layout-derived value.
struct WatchtowerPanelView: View {
    let model: WatchtowerModel
    var onOpenFile: (URL) -> Void = { _ in }
    var onClose: () -> Void = {}

    @State private var todoExpanded = true
    @State private var archiveExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            header
            separator
            ScrollView {
                VStack(alignment: .leading, spacing: AtelierMetrics.spaceM) {
                    if model.hasPlan {
                        planCard
                        progressCard
                        statusCounts
                        fileActions
                    }
                    commandsCard
                    if model.hasPlan {
                        taskGroups
                    } else {
                        noPlanNote
                    }
                    if !model.archive.isEmpty {
                        archiveSection
                    }
                }
                .padding(AtelierMetrics.spaceM)
            }
        }
        .background(AtelierTheme.canvas)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: AtelierMetrics.spaceM) {
            Text("Watchtower: Dashboard".uppercased())
                .atelierFont(size: AtelierTypography.label, weight: .semibold)
                .tracking(0.6)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            iconButton("arrow.clockwise", label: "Refresh plan") { model.refresh() }
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(width: AtelierTheme.strokeHairline, height: AtelierMetrics.regularIconSize)
            iconButton("xmark", label: "Close Watchtower", action: onClose)
        }
        .padding(.horizontal, AtelierMetrics.spaceL)
        .frame(height: AtelierMetrics.panelHeaderHeight)
    }

    private func iconButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: AtelierTypography.body))
                .foregroundStyle(.secondary)
                .frame(width: AtelierMetrics.iconButtonSize, height: AtelierMetrics.iconButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
        .atelierPointerCursor()
    }

    // MARK: - Plan card

    private var planCard: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            HStack(alignment: .firstTextBaseline, spacing: AtelierMetrics.spaceS) {
                Text(model.title.isEmpty ? "Untitled plan" : model.title)
                    .atelierFont(size: AtelierTypography.headline, weight: .semibold)
                    .lineLimit(2)
                Spacer(minLength: 0)
                planStatusBadge
            }
            HStack(spacing: AtelierMetrics.spaceS) {
                Text(model.plan?.slug ?? "")
                    .atelierFont(size: AtelierTypography.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: AtelierMetrics.spaceM)
                if let updated = model.plan?.updated, !updated.isEmpty {
                    Text("Updated \(updated)")
                        .atelierFont(size: AtelierTypography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(AtelierMetrics.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atelierCard(radius: AtelierTheme.panelRadius, fill: AtelierTheme.raised)
    }

    private var planStatusBadge: some View {
        Text(planStatusText.uppercased())
            .atelierFont(size: AtelierTypography.micro, weight: .semibold)
            .tracking(0.5)
            .foregroundStyle(AtelierTheme.accentInk)
            .padding(.horizontal, AtelierMetrics.spaceS)
            .padding(.vertical, 3)
            .background(AtelierTheme.accent, in: Capsule())
            .fixedSize()
    }

    private var planStatusText: String {
        switch model.plan?.status {
        case .active: "Active"
        case .done: "Done"
        case .archived: "Archived"
        default: "Unknown"
        }
    }

    // MARK: - Progress

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int((model.progress * 100).rounded()))%")
                    .atelierFont(size: AtelierTypography.display, weight: .bold)
                    .foregroundStyle(AtelierTheme.accent)
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text("\(model.doneCount) of \(model.totalCount) done")
                    .atelierFont(size: AtelierTypography.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AtelierTheme.border.opacity(0.6))
                    Capsule()
                        .fill(AtelierTheme.accent)
                        .frame(width: max(0, proxy.size.width * model.progress))
                }
            }
            .frame(height: 8)
            .accessibilityElement()
            .accessibilityLabel("Plan progress")
            .accessibilityValue("\(model.doneCount) of \(model.totalCount) done")
        }
        .padding(AtelierMetrics.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atelierCard(radius: AtelierTheme.panelRadius, fill: AtelierTheme.raised)
    }

    // MARK: - Status counts

    private var statusCounts: some View {
        HStack(spacing: 0) {
            countCell("Done", model.doneCount, tint: AtelierTheme.gitAdded)
            countDivider
            countCell("Active", model.tasks(in: .active).count, tint: AtelierTheme.accent)
            countDivider
            countCell("Blocked", model.blockedIds.count, tint: AtelierTheme.danger)
        }
        .frame(maxWidth: .infinity)
        .atelierCard()
    }

    private func countCell(_ label: String, _ value: Int, tint: Color) -> some View {
        HStack(spacing: AtelierMetrics.spaceXS) {
            Text(label.uppercased())
                .atelierFont(size: AtelierTypography.micro, weight: .medium)
                .tracking(0.4)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AtelierMetrics.spaceS)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    private var countDivider: some View {
        Rectangle()
            .fill(AtelierTheme.border)
            .frame(width: AtelierTheme.strokeHairline, height: AtelierMetrics.regularIconSize)
    }

    // MARK: - File actions

    private var fileActions: some View {
        HStack(spacing: AtelierMetrics.spaceS) {
            fileActionButton("NEXT", emphasized: true, path: model.plan?.manifestPath)
            fileActionButton("CONTEXT", emphasized: true, path: contextPath)
            fileActionButton("Archive", emphasized: false, path: model.archive.first?.manifestPath)
        }
    }

    private func fileActionButton(_ title: String, emphasized: Bool, path: String?) -> some View {
        Button {
            open(path)
        } label: {
            Text(title)
                .atelierFont(size: AtelierTypography.caption, weight: emphasized ? .semibold : .regular)
                .foregroundStyle(path == nil ? Color.secondary : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: AtelierMetrics.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .atelierCard(radius: AtelierTheme.controlRadius, fill: AtelierTheme.panel)
        .disabled(path == nil)
        .opacity(path == nil ? AtelierTheme.disabledOpacity : 1)
        .accessibilityLabel("Open \(title)")
        .atelierPointerCursor()
    }

    private var contextPath: String? {
        guard let root = model.rootDir else { return nil }
        return ((root as NSString).appendingPathComponent("watchtower") as NSString)
            .appendingPathComponent("CONTEXT.md")
    }

    // MARK: - Commands

    private var commandsCard: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            Text("watchtower")
                .atelierFont(size: AtelierTypography.caption, design: .monospaced)
                .foregroundStyle(.secondary)
            WatchtowerFlowLayout(spacing: AtelierMetrics.spaceXS) {
                ForEach(WatchtowerCommand.all) { command in
                    WatchtowerCommandChip(command: command)
                }
            }
        }
        .padding(AtelierMetrics.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atelierCard(radius: AtelierTheme.panelRadius, fill: AtelierTheme.raised)
    }

    // MARK: - Task groups

    private var taskGroups: some View {
        ForEach(WatchtowerTaskGroup.allCases, id: \.self) { group in
            let tasks = model.tasks(in: group)
            if !tasks.isEmpty {
                disclosureSection(
                    title: title(for: group),
                    count: tasks.count,
                    isExpanded: group == .active || group == .blocked ? .constant(true) : $todoExpanded
                ) {
                    ForEach(tasks, id: \.order) { task in
                        taskRow(task, group: group)
                    }
                }
            }
        }
    }

    private func taskRow(_ task: WatchtowerTask, group: WatchtowerTaskGroup) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AtelierMetrics.spaceM) {
            Button {
                open(task.specPath ?? model.plan?.manifestPath)
            } label: {
                Text(task.id)
                    .atelierFont(size: AtelierTypography.caption, weight: .medium, design: .monospaced)
                    .foregroundStyle(AtelierTheme.codeCyan)
                    .frame(width: 72, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(task.id)")
            .atelierPointerCursor()

            Text(task.title)
                .atelierFont(size: AtelierTypography.body)
                .lineLimit(2)
            Spacer(minLength: AtelierMetrics.spaceS)
            statusPill(task.status)
        }
        .padding(.vertical, AtelierMetrics.spaceS)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Archive

    private var archiveSection: some View {
        disclosureSection(title: "Archive", count: model.archive.count, isExpanded: $archiveExpanded) {
            ForEach(model.archive, id: \.slug) { entry in
                HStack(alignment: .firstTextBaseline, spacing: AtelierMetrics.spaceM) {
                    Button {
                        open(entry.manifestPath)
                    } label: {
                        Text("Archive")
                            .atelierFont(size: AtelierTypography.caption, weight: .medium)
                            .foregroundStyle(AtelierTheme.codeCyan)
                            .frame(width: 72, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open archived plan \(entry.slug)")
                    .atelierPointerCursor()

                    Text(entry.slug)
                        .atelierFont(size: AtelierTypography.caption, design: .monospaced)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: AtelierMetrics.spaceS)
                    tagPill("SAVED", tint: .secondary)
                }
                .padding(.vertical, AtelierMetrics.spaceS)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Building blocks

    private func disclosureSection<Content: View>(
        title: String,
        count: Int,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: AtelierMetrics.spaceS) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: AtelierTypography.micro, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .atelierFont(size: AtelierTypography.label, weight: .semibold)
                    Spacer(minLength: 0)
                    Text("\(count)")
                        .atelierFont(size: AtelierTypography.caption, weight: .medium)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .frame(height: AtelierMetrics.sectionHeaderHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .atelierPointerCursor()

            if isExpanded.wrappedValue {
                content()
            }
        }
    }

    private func statusPill(_ status: WatchtowerTaskStatus) -> some View {
        tagPill(statusText(status), tint: statusColor(status))
    }

    private func tagPill(_ text: String, tint: Color) -> some View {
        Text(text)
            .atelierFont(size: AtelierTypography.micro, weight: .medium)
            .tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, AtelierMetrics.spaceS)
            .padding(.vertical, 2)
            .overlay {
                Capsule().stroke(tint.opacity(0.5), lineWidth: AtelierTheme.strokeControl)
            }
            .fixedSize()
    }

    private var noPlanNote: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
            Label("No active plan", systemImage: "binoculars")
                .atelierFont(size: AtelierTypography.body, weight: .medium)
            Text("Run /watchtower new to create one.")
                .atelierFont(size: AtelierTypography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AtelierMetrics.spaceM)
        .atelierCard(radius: AtelierTheme.panelRadius, fill: AtelierTheme.raised)
    }

    private var separator: some View {
        Rectangle()
            .fill(AtelierTheme.border)
            .frame(height: AtelierTheme.strokeHairline)
    }

    // MARK: - Helpers

    private func open(_ path: String?) {
        guard let path, !path.isEmpty else { return }
        onOpenFile(URL(fileURLWithPath: path))
    }

    // Theme colors are precomputed constants; no allocation on the draw path.
    private func statusColor(_ status: WatchtowerTaskStatus) -> Color {
        switch status {
        case .done: AtelierTheme.gitAdded
        case .inProgress: AtelierTheme.accent
        case .blocked: AtelierTheme.danger
        case .todo: AtelierTheme.gitOrange
        case .unknown: .secondary
        }
    }

    private func statusText(_ status: WatchtowerTaskStatus) -> String {
        switch status {
        case .done: "DONE"
        case .inProgress: "ACTIVE"
        case .blocked: "BLOCKED"
        case .todo: "TODO"
        case .unknown: "UNKNOWN"
        }
    }

    private func title(for group: WatchtowerTaskGroup) -> String {
        switch group {
        case .active: "Active"
        case .blocked: "Blocked"
        case .todo: "Todo"
        case .done: "Done"
        }
    }
}

// One command chip: click copies to the clipboard; drag drops onto the terminal to run.
private struct WatchtowerCommandChip: View {
    let command: WatchtowerCommand
    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            HStack(spacing: AtelierMetrics.spaceXS) {
                if copied {
                    Image(systemName: "checkmark")
                        .font(.system(size: AtelierTypography.micro, weight: .semibold))
                        .foregroundStyle(AtelierTheme.gitAdded)
                }
                Text(command.label)
                    .atelierFont(size: AtelierTypography.caption, design: .monospaced)
            }
            .padding(.horizontal, AtelierMetrics.spaceS)
            .padding(.vertical, AtelierMetrics.spaceXS)
            .background(AtelierTheme.panel, in: RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                    .stroke(AtelierTheme.border, lineWidth: AtelierTheme.strokeControl)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(WatchtowerCommandDrop(command: command.command))
        .help("Click to copy \(command.command). Drag onto the terminal to run.")
        .accessibilityLabel("\(command.command) command")
        .accessibilityHint("Copies to the clipboard. Drag onto the terminal to run.")
        .atelierPointerCursor()
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command.command, forType: .string)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.2))
            copied = false
        }
    }
}

// Left-to-right wrapping layout for the command chips.
struct WatchtowerFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        let width = proposal.width ?? widest
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#if DEBUG
extension WatchtowerModel {
    // Self-contained mock: parses inline plan content, no disk or services.
    static func previewMock() -> WatchtowerModel {
        let content = [
            "## Current Active Plan",
            "",
            "Title: Mock Task Demo",
            "Slug: 20260623-mock-task-demo",
            "Status: ACTIVE",
            "Updated: 2026-06-23",
            "",
            "## Tracker",
            "",
            "| Order | TASK | Group | Status | Spec | Deps | Context | Notes |",
            "|---|---|---|---|---|---|---|---|",
            "| 1 | TASK-001 Mock dashboard row | ui | TODO | - | - | - | n |",
            "| 2 | TASK-002 Mock command copy check | ui | TODO | - | TASK-001 | - | n |",
        ].joined(separator: "\n")
        let plan = WatchtowerParser.parsePlanContent(content, manifestPath: "/ws/watchtower/NEXT.md")
        let archive = [
            WatchtowerArchivePlan(slug: "20260625-dashboard-row-implement-check", manifestPath: "/ws/a/1/NEXT.md"),
            WatchtowerArchivePlan(slug: "20260625-dashboard-command-groups-copy", manifestPath: "/ws/a/2/NEXT.md"),
            WatchtowerArchivePlan(slug: "20260623-autorefresh-keep-state", manifestPath: "/ws/a/3/NEXT.md"),
            WatchtowerArchivePlan(slug: "20260622-surface-status", manifestPath: "/ws/a/4/NEXT.md"),
            WatchtowerArchivePlan(slug: "20260622-preview-markdown-clicks", manifestPath: "/ws/a/5/NEXT.md"),
        ]
        return WatchtowerModel(rootDir: "/ws", planLoader: { _ in plan }, archiveLoader: { _ in archive })
    }
}

#Preview("Watchtower panel") {
    WatchtowerPanelView(model: .previewMock())
        .frame(width: 360, height: 760)
}

#Preview("Watchtower empty") {
    WatchtowerPanelView(model: WatchtowerModel())
        .frame(width: 360, height: 760)
}
#endif
