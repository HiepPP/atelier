import AppKit
import SwiftUI

private struct WatchtowerWorkflowSegment: Identifiable {
    let id: String
    let label: String
    let count: Int
    let tint: Color
    // Only the Done band is filled solid; every pending band renders as a wash.
    var isComplete = false
}

// One pass over the tracker. The summary strip and the group headers read the same
// counts instead of re-filtering the task array once per state per body evaluation.
private struct WatchtowerGroupedTasks {
    var active: [WatchtowerTask] = []
    var blocked: [WatchtowerTask] = []
    var todo: [WatchtowerTask] = []
    var done: [WatchtowerTask] = []

    init(_ tasks: [WatchtowerTask]) {
        for task in tasks {
            switch WatchtowerTaskGroup(status: task.status) {
            case .active: active.append(task)
            case .blocked: blocked.append(task)
            case .todo: todo.append(task)
            case .done: done.append(task)
            case nil: continue
            }
        }
    }

    func tasks(in group: WatchtowerTaskGroup) -> [WatchtowerTask] {
        switch group {
        case .active: active
        case .blocked: blocked
        case .todo: todo
        case .done: done
        }
    }
}

// Read-only Watchtower panel, ordered plan identity -> file actions -> task groups ->
// commands -> Archive. Task ids and archive rows are clickable and jump to the file via
// onOpenFile.
//
// Crash-rule note: mount this as an overlay side panel, never as an HSplitView
// child that can collapse to zero. The view is pure - it derives layout from the
// model only and never mutates state from a layout-derived value.
struct WatchtowerPanelView: View {
    let model: WatchtowerModel
    var onOpenFile: (URL) -> Void = { _ in }
    var onClose: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Every section opens by default; the panel shows the whole plan without a click.
    @State private var activeExpanded = true
    @State private var blockedExpanded = true
    @State private var todoExpanded = true
    @State private var doneExpanded = true
    @State private var archiveExpanded = true
    @State private var commandsExpanded = true
    @State private var refreshTurns = 0

    var body: some View {
        let grouped = WatchtowerGroupedTasks(model.tasks)
        VStack(spacing: 0) {
            header
            separator
            ScrollView {
                VStack(alignment: .leading, spacing: AtelierMetrics.spaceM) {
                    if model.hasPlan {
                        summaryCard(grouped)
                        fileActions
                        taskGroups(grouped)
                    } else {
                        emptyNotice
                    }
                    commandsSection
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
            Text("Watchtower")
                .atelierFont(size: AtelierTypography.label, weight: .semibold)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            refreshButton
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(width: AtelierTheme.strokeHairline, height: AtelierMetrics.regularIconSize)
            iconButton("xmark", label: "Close Watchtower", action: onClose)
        }
        .padding(.horizontal, AtelierMetrics.spaceL)
        .frame(height: AtelierMetrics.panelHeaderHeight)
    }

    // One short turn acknowledges a refresh that finds no change. Reduce Motion skips it.
    private var refreshButton: some View {
        iconButton("arrow.clockwise", label: "Refresh plan") {
            model.refresh()
            if !reduceMotion {
                refreshTurns += 1
            }
        }
        .rotationEffect(.degrees(Double(refreshTurns) * 360))
        .animation(.easeInOut(duration: 0.45), value: refreshTurns)
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

    // MARK: - Plan summary

    private func summaryCard(_ grouped: WatchtowerGroupedTasks) -> some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            HStack(alignment: .firstTextBaseline, spacing: AtelierMetrics.spaceS) {
                Text(model.title.isEmpty ? "Untitled plan" : model.title)
                    .atelierFont(size: AtelierTypography.headline, weight: .semibold)
                    .lineLimit(2)
                Spacer(minLength: 0)
                planStatusBadge
            }
            HStack(spacing: AtelierMetrics.spaceM) {
                Text(shortSlug)
                    .atelierFont(size: AtelierTypography.caption, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(model.plan?.slug ?? "")
                    .accessibilityLabel("Plan slug \(model.plan?.slug ?? "")")
                Spacer(minLength: 0)
                if let updated = model.plan?.updated, !updated.isEmpty {
                    Text(updated)
                        .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .help("Updated \(updated)")
                        .accessibilityLabel("Updated \(updated)")
                }
            }
            VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
                completionReadout
                workflowStrip(grouped)
            }
            .padding(.top, 2)
        }
        .padding(AtelierMetrics.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atelierCard(radius: AtelierTheme.panelRadius, fill: AtelierTheme.raised)
    }

    // The slug repeats its own date prefix next to the updated date, so drop it here
    // and keep the complete slug in the tooltip and the accessibility label.
    private var shortSlug: String {
        let slug = model.plan?.slug ?? ""
        let prefix = slug.prefix(8)
        guard prefix.count == 8, prefix.allSatisfy(\.isNumber) else { return slug }
        return String(slug.dropFirst(8)).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
    }

    private var completionReadout: some View {
        HStack(alignment: .firstTextBaseline, spacing: AtelierMetrics.spaceXS) {
            Text(percentText)
                .atelierFont(size: AtelierTypography.label, weight: .semibold)
                .foregroundStyle(.primary)
                .monospacedDigit()
            Text("\(model.doneCount) of \(model.totalCount) done")
                .atelierFont(size: AtelierTypography.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.doneCount) of \(model.totalCount) tasks done, \(percentText)")
    }

    private var percentText: String {
        "\(Int((model.progress * 100).rounded()))%"
    }

    // Done is the only solid band. Pending states stay washed with a hairline edge so a plan
    // with nothing done reads as composition, never as a filled progress bar.
    private func workflowStrip(_ grouped: WatchtowerGroupedTasks) -> some View {
        let segments = workflowSegments(grouped).filter { $0.count > 0 }
        return GeometryReader { proxy in
            let gapCount = max(0, segments.count - 1)
            let availableWidth = max(0, proxy.size.width - CGFloat(gapCount * 2))
            HStack(spacing: 2) {
                ForEach(segments) { segment in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(segment.isComplete ? segment.tint : segment.tint.opacity(0.22))
                        .overlay {
                            if !segment.isComplete {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .stroke(
                                        segment.tint.opacity(0.48),
                                        lineWidth: AtelierTheme.strokeControl
                                    )
                            }
                        }
                        .frame(
                            width: availableWidth
                                * CGFloat(segment.count)
                                / CGFloat(max(model.totalCount, 1))
                        )
                        .help("\(segment.label) \(segment.count)")
                }
            }
        }
        .frame(height: 10)
        .background(
            AtelierTheme.border.opacity(0.32),
            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workflow distribution")
        .accessibilityValue(workflowDistributionText(grouped))
    }

    private func workflowSegments(_ grouped: WatchtowerGroupedTasks) -> [WatchtowerWorkflowSegment] {
        [
            WatchtowerWorkflowSegment(
                id: "done",
                label: "Done",
                count: grouped.done.count,
                tint: AtelierTheme.workflowDone,
                isComplete: true
            ),
            WatchtowerWorkflowSegment(
                id: "active",
                label: "Active",
                count: grouped.active.count,
                tint: AtelierTheme.accent
            ),
            WatchtowerWorkflowSegment(
                id: "blocked",
                label: "Blocked",
                count: grouped.blocked.count,
                tint: AtelierTheme.workflowBlocked
            ),
            WatchtowerWorkflowSegment(
                id: "todo",
                label: "Todo",
                count: grouped.todo.count,
                tint: AtelierTheme.workflowTodo
            ),
        ]
    }

    private func workflowDistributionText(_ grouped: WatchtowerGroupedTasks) -> String {
        workflowSegments(grouped)
            .map { "\($0.label) \($0.count)" }
            .joined(separator: ", ")
    }

    private var planStatusBadge: some View {
        let tint = planStatusColor
        return Text(planStatusText.uppercased())
            .atelierFont(size: AtelierTypography.micro, weight: .semibold)
            .tracking(0.5)
            .foregroundStyle(.primary)
            .padding(.horizontal, AtelierMetrics.spaceS)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(tint.opacity(0.28), lineWidth: AtelierTheme.strokeControl)
            }
            .fixedSize()
            .accessibilityLabel("Plan status \(planStatusText)")
    }

    private var planStatusColor: Color {
        switch model.plan?.status {
        case .active: AtelierTheme.accent
        case .done: AtelierTheme.workflowDone
        case .archived: .secondary
        default: .secondary
        }
    }

    private var planStatusText: String {
        switch model.plan?.status {
        case .active: "Active"
        case .done: "Done"
        case .archived: "Archived"
        default: "Unknown"
        }
    }

    // MARK: - File actions

    private var fileActions: some View {
        HStack(spacing: AtelierMetrics.spaceS) {
            WatchtowerFileActionButton(title: "NEXT", path: model.plan?.manifestPath, onOpen: open)
            WatchtowerFileActionButton(title: "CONTEXT", path: model.contextPath, onOpen: open)
        }
    }

    // MARK: - Empty state

    private var emptyNotice: some View {
        HStack(spacing: AtelierMetrics.spaceM) {
            Image(systemName: "binoculars")
                .font(.system(size: AtelierTypography.headline, weight: .medium))
                .foregroundStyle(AtelierTheme.accent)
                .frame(width: 32, height: 32)
                .background(
                    AtelierTheme.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("No active plan")
                    .atelierFont(size: AtelierTypography.headline, weight: .semibold)
                    .foregroundStyle(.primary)
                Text("Start one with a command below.")
                    .atelierFont(size: AtelierTypography.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AtelierMetrics.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atelierCard(radius: AtelierTheme.panelRadius, fill: AtelierTheme.raised)
    }

    // MARK: - Commands

    private var commandsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                commandsExpanded.toggle()
            } label: {
                HStack(spacing: AtelierMetrics.spaceS) {
                    Image(systemName: commandsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: AtelierTypography.micro, weight: .semibold))
                        .foregroundStyle(AtelierTheme.workspaceRailSecondary)
                    Text("Commands")
                        .atelierFont(size: AtelierTypography.label, weight: .semibold)
                        .foregroundStyle(AtelierTheme.workspaceRailForeground)
                    Spacer(minLength: 0)
                    Text("\(WatchtowerCommand.all.count)")
                        .atelierFont(size: AtelierTypography.caption, weight: .medium)
                        .foregroundStyle(AtelierTheme.workspaceRailSecondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, AtelierMetrics.spaceM)
                .frame(height: AtelierMetrics.sectionHeaderHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Commands, \(WatchtowerCommand.all.count)")
            .accessibilityValue(commandsExpanded ? "Expanded" : "Collapsed")
            .atelierPointerCursor()

            if commandsExpanded {
                commandDeckDivider
                commandDeck
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .atelierCard(radius: AtelierTheme.panelRadius, fill: AtelierTheme.workspaceRailSolid)
        .accessibilityElement(children: .contain)
    }

    private var commandDeck: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            ForEach(WatchtowerCommand.all.prefix(1)) { command in
                WatchtowerCommandChip(command: command, isPrimary: true)
            }
            LazyVGrid(columns: commandColumns, spacing: AtelierMetrics.spaceXS) {
                ForEach(WatchtowerCommand.all.dropFirst()) { command in
                    WatchtowerCommandChip(command: command)
                }
            }
            Text("Click to copy. Drag onto a terminal to run.")
                .atelierFont(size: AtelierTypography.micro)
                .foregroundStyle(AtelierTheme.workspaceRailSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AtelierMetrics.spaceM)
    }

    private var commandDeckDivider: some View {
        Rectangle()
            .fill(AtelierTheme.workspaceRailBorder.opacity(0.72))
            .frame(height: AtelierTheme.strokeHairline)
    }

    private var commandColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: AtelierMetrics.spaceXS),
            GridItem(.flexible(), spacing: AtelierMetrics.spaceXS),
        ]
    }

    // MARK: - Task groups

    private func taskGroups(_ grouped: WatchtowerGroupedTasks) -> some View {
        ForEach(WatchtowerTaskGroup.allCases, id: \.self) { group in
            let tasks = grouped.tasks(in: group)
            if !tasks.isEmpty {
                disclosureSection(
                    title: title(for: group),
                    count: tasks.count,
                    tint: color(for: group),
                    isExpanded: binding(for: group)
                ) {
                    VStack(spacing: AtelierMetrics.spaceXS) {
                        ForEach(tasks, id: \.order) { task in
                            taskRow(task)
                        }
                    }
                    .padding(.top, AtelierMetrics.spaceXS)
                }
            }
        }
    }

    // Every group owns its disclosure state so collapsing Todo never collapses Done.
    private func binding(for group: WatchtowerTaskGroup) -> Binding<Bool> {
        switch group {
        case .active: $activeExpanded
        case .blocked: $blockedExpanded
        case .todo: $todoExpanded
        case .done: $doneExpanded
        }
    }

    private func taskRow(_ task: WatchtowerTask) -> some View {
        WatchtowerTaskCard(
            task: task,
            statusLabel: statusText(task.status),
            statusTint: statusColor(task.status)
        ) {
            open(task.specPath ?? model.plan?.manifestPath)
        }
    }

    // MARK: - Archive

    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                archiveExpanded.toggle()
            } label: {
                HStack(spacing: AtelierMetrics.spaceS) {
                    Image(systemName: archiveExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: AtelierTypography.micro, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("Archive")
                        .atelierFont(size: AtelierTypography.label, weight: .semibold)
                    Spacer(minLength: 0)
                    Text(archiveCountText)
                        .atelierFont(size: AtelierTypography.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, AtelierMetrics.spaceM)
                .frame(height: AtelierMetrics.sectionHeaderHeight)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Archive, \(archiveCountText)")
            .accessibilityValue(archiveExpanded ? "Expanded" : "Collapsed")
            .atelierPointerCursor()

            if archiveExpanded {
                separator
                ForEach(model.archive, id: \.slug) { entry in
                    WatchtowerArchiveRow(entry: entry) {
                        open(entry.manifestPath)
                    }
                    if entry.slug != model.archive.last?.slug {
                        separator
                            .padding(.horizontal, AtelierMetrics.spaceM)
                    }
                }
            }
        }
        .atelierCard(radius: AtelierTheme.panelRadius, fill: AtelierTheme.panel)
    }

    private var archiveCountText: String {
        model.archive.count == 1 ? "1 plan" : "\(model.archive.count) plans"
    }

    // MARK: - Building blocks

    private func disclosureSection<Content: View>(
        title: String,
        count: Int,
        tint: Color? = nil,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let sectionTint = tint ?? AtelierTheme.border
        let sectionFill = tint?.opacity(0.06) ?? AtelierTheme.panel
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(sectionTint)
                        .frame(width: 2)
                        .accessibilityHidden(true)
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
                    .padding(.horizontal, AtelierMetrics.spaceS)
                }
                .frame(height: AtelierMetrics.sectionHeaderHeight)
                .background(sectionFill)
                .clipShape(.rect(cornerRadius: AtelierTheme.rowRadius))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(count)")
            .accessibilityValue(isExpanded.wrappedValue ? "Expanded" : "Collapsed")
            .atelierPointerCursor()

            if isExpanded.wrappedValue {
                content()
            }
        }
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
        case .done: AtelierTheme.workflowDone
        case .inProgress: AtelierTheme.accent
        case .blocked: AtelierTheme.workflowBlocked
        case .todo: AtelierTheme.workflowTodo
        case .unknown: .secondary
        }
    }

    private func color(for group: WatchtowerTaskGroup) -> Color {
        switch group {
        case .active: AtelierTheme.accent
        case .blocked: AtelierTheme.workflowBlocked
        case .todo: AtelierTheme.workflowTodo
        case .done: AtelierTheme.workflowDone
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

// Opens one plan file. Disabled when the model could not resolve the path, so the
// panel never asks the editor to open something that is not on disk.
private struct WatchtowerFileActionButton: View {
    let title: String
    let path: String?
    let onOpen: (String?) -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private var isHighlighted: Bool {
        (isHovered || isFocused) && path != nil
    }

    var body: some View {
        Button {
            onOpen(path)
        } label: {
            Text(title)
                .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                .foregroundStyle(isHighlighted ? AtelierTheme.accent : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: AtelierMetrics.controlHeight)
                .background(
                    isHighlighted ? AtelierTheme.accent.opacity(0.10) : AtelierTheme.panel,
                    in: RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous)
                        .stroke(
                            isHighlighted
                                ? AtelierTheme.accent.opacity(0.34)
                                : AtelierTheme.border.opacity(0.72),
                            lineWidth: AtelierTheme.strokeControl
                        )
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .disabled(path == nil)
        .opacity(path == nil ? AtelierTheme.disabledOpacity : 1)
        .accessibilityLabel("Open \(title)")
        .help(path == nil ? "\(title) is not available in this workspace" : "Open \(title)")
        .onHover { isHovered = $0 }
        .atelierPointerCursor()
    }
}

private struct WatchtowerTaskCard: View {
    let task: WatchtowerTask
    let statusLabel: String
    let statusTint: Color
    let onOpen: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private var isHighlighted: Bool {
        isHovered || isFocused
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: AtelierMetrics.spaceXS) {
                HStack(alignment: .center, spacing: AtelierMetrics.spaceS) {
                    Text(task.id)
                        .atelierFont(
                            size: AtelierTypography.caption,
                            weight: .medium,
                            design: .monospaced
                        )
                        .foregroundStyle(isHighlighted ? AtelierTheme.accent : .secondary)
                        .lineLimit(1)

                    Spacer(minLength: AtelierMetrics.spaceS)

                    Text(statusLabel)
                        .atelierFont(size: AtelierTypography.micro, weight: .medium)
                        .tracking(0.4)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, AtelierMetrics.spaceS)
                        .padding(.vertical, 2)
                        .background(statusTint.opacity(0.10), in: Capsule())
                        .overlay {
                            Capsule().stroke(
                                statusTint.opacity(0.28),
                                lineWidth: AtelierTheme.strokeControl
                            )
                        }
                        .fixedSize()
                }

                Text(task.title)
                    .atelierFont(size: AtelierTypography.body, weight: .medium)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AtelierMetrics.spaceM)
            .padding(.vertical, AtelierMetrics.spaceS)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(
                isHighlighted
                    ? AtelierTheme.accent.opacity(0.07)
                    : AtelierTheme.panel.opacity(0.76),
                in: RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                    .stroke(
                        isHighlighted
                            ? AtelierTheme.accent.opacity(0.34)
                            : AtelierTheme.border.opacity(0.72),
                        lineWidth: AtelierTheme.strokeControl
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .accessibilityLabel("\(task.id), \(task.title), \(statusLabel)")
        .accessibilityHint("Opens the task specification")
        .help("Open \(task.id)")
        .onHover { isHovered = $0 }
        .atelierPointerCursor()
    }
}

// One command row on the graphite deck: click copies to the clipboard; drag drops
// onto the terminal to run.
private struct WatchtowerCommandChip: View {
    let command: WatchtowerCommand
    var isPrimary = false

    @State private var copied = false
    @State private var isHovered = false

    var body: some View {
        Button(action: copy) {
            HStack(spacing: AtelierMetrics.spaceS) {
                Text(isPrimary ? command.command : command.label)
                    .atelierFont(
                        size: AtelierTypography.caption,
                        weight: isPrimary ? .semibold : .regular,
                        design: .monospaced
                    )
                    .foregroundStyle(commandForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(isPrimary ? 1 : 0.82)
                    .allowsTightening(true)
                Spacer(minLength: AtelierMetrics.spaceXS)
                Image(systemName: copied ? "checkmark" : (isPrimary ? "doc.on.doc" : "arrow.up.left"))
                    .font(.system(size: AtelierTypography.micro, weight: .semibold))
                    .foregroundStyle(commandIconForeground)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, AtelierMetrics.spaceS)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: isPrimary ? 34 : AtelierMetrics.controlHeight)
            .background(
                chipFill,
                in: RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                    .stroke(chipStroke, lineWidth: AtelierTheme.strokeControl)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(WatchtowerCommandDrop(command: command.command))
        .help("Click to copy \(command.command). Drag onto the terminal to run.")
        .accessibilityLabel("\(command.command) command")
        .accessibilityHint("Copies to the clipboard. Drag onto the terminal to run.")
        .onHover { isHovered = $0 }
        .atelierPointerCursor()
    }

    private var commandForeground: Color {
        if isPrimary && !copied {
            return AtelierTheme.accentInk
        }
        return AtelierTheme.workspaceRailForeground
    }

    private var commandIconForeground: Color {
        if copied {
            return AtelierTheme.workflowDone
        }
        if isPrimary {
            return AtelierTheme.accentInk.opacity(0.84)
        }
        return AtelierTheme.workspaceRailSecondary
    }

    private var chipFill: Color {
        if copied {
            return AtelierTheme.workflowDone.opacity(isPrimary ? 0.18 : 0.10)
        }
        if isPrimary {
            return isHovered ? AtelierTheme.accent.opacity(0.88) : AtelierTheme.accent
        }
        return isHovered
            ? AtelierTheme.accent.opacity(0.18)
            : AtelierTheme.workspaceRailHover.opacity(0.72)
    }

    private var chipStroke: Color {
        if copied {
            return AtelierTheme.workflowDone.opacity(0.32)
        }
        if isPrimary {
            return AtelierTheme.accent
        }
        return isHovered
            ? AtelierTheme.accent.opacity(0.56)
            : AtelierTheme.workspaceRailBorder.opacity(0.72)
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

private struct WatchtowerArchiveRow: View {
    let entry: WatchtowerArchivePlan
    let onOpen: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private var isHighlighted: Bool {
        isHovered || isFocused
    }

    var body: some View {
        let display = archiveDisplay
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: AtelierMetrics.spaceM) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(display.title)
                        .atelierFont(size: AtelierTypography.caption, weight: .medium)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(display.date)
                        .atelierFont(
                            size: AtelierTypography.micro,
                            weight: .medium,
                            design: .monospaced
                        )
                        .foregroundStyle(isHighlighted ? AtelierTheme.accent : .secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: AtelierMetrics.spaceS)

                Image(systemName: "chevron.right")
                    .font(.system(size: AtelierTypography.micro, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, AtelierMetrics.spaceM)
            .padding(.vertical, AtelierMetrics.spaceS)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 44)
            .background(isHighlighted ? AtelierTheme.accent.opacity(0.07) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .accessibilityLabel("Open archived plan \(display.title), \(display.date), \(entry.slug)")
        .accessibilityHint("Opens the archived plan manifest")
        .onHover { isHovered = $0 }
        .atelierPointerCursor()
    }

    private var archiveDisplay: (date: String, title: String) {
        let datePrefix = String(entry.slug.prefix(8))
        let hasDate = datePrefix.count == 8 && datePrefix.allSatisfy(\.isNumber)
        let rawTitle = hasDate ? String(entry.slug.dropFirst(8)) : entry.slug
        let title = rawTitle
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        guard hasDate else {
            return ("PLAN", title)
        }
        let year = datePrefix.prefix(4)
        let month = datePrefix.dropFirst(4).prefix(2)
        let day = datePrefix.suffix(2)
        return ("\(year).\(month).\(day)", title)
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
            "| 1 | TASK-001 Completed summary surface | ui | DONE | - | - | - | n |",
            "| 2 | TASK-002 Active workflow strip | ui | IN PROGRESS | - | TASK-001 | - | n |",
            "| 3 | TASK-003 Blocked accessibility audit | ui | BLOCKED | - | TASK-002 | - | n |",
            "| 4 | TASK-004 Pending command polish | ui | TODO | - | TASK-003 | - | n |",
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
