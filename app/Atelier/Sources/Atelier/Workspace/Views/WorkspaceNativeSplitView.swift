import AppKit
import SwiftUI

nonisolated enum WorkspaceSplitAnimationPolicy {
    static let panelDuration = 0.20
    static let panelRollDistance: CGFloat = 24

    static func animates(
        panelChanged: Bool,
        reduceMotion: Bool,
        requestsAnimation: Bool
    ) -> Bool {
        panelChanged && !reduceMotion && requestsAnimation
    }
}

nonisolated enum WorkspacePanelMotionEdge: Sendable {
    case leading
    case trailing

    var hiddenOffset: CGFloat {
        switch self {
        case .leading: -WorkspaceSplitAnimationPolicy.panelRollDistance
        case .trailing: WorkspaceSplitAnimationPolicy.panelRollDistance
        }
    }
}

nonisolated enum WorkspaceSplitLayoutPolicy {
    static let sidePanelHoldingPriority = NSLayoutConstraint.Priority(
        rawValue: NSLayoutConstraint.Priority.defaultLow.rawValue + 1
    )
    static let panelCollapseBehavior = NSSplitViewItem.CollapseBehavior.useConstraints
}

nonisolated enum WorkspaceDividerInteractionPolicy {
    static let minimumThickness: CGFloat = 12

    static func effectiveRect(
        proposed: NSRect,
        isVertical: Bool,
        within bounds: NSRect
    ) -> NSRect {
        let thickness = isVertical ? proposed.width : proposed.height
        let expansion = max(0, (minimumThickness - thickness) / 2)
        let expanded = isVertical
            ? proposed.insetBy(dx: -expansion, dy: 0)
            : proposed.insetBy(dx: 0, dy: -expansion)
        return expanded.intersection(bounds)
    }
}

enum WorkspaceSidebarWidthPolicy {
    static let updateTolerance: CGFloat = 0.5

    static func clamped(_ width: CGFloat) -> CGFloat {
        min(
            max(width, AtelierMetrics.workspaceSidebarMinWidth),
            AtelierMetrics.workspaceSidebarMaxWidth
        )
    }

    static func differs(_ lhs: CGFloat, from rhs: CGFloat) -> Bool {
        abs(lhs - rhs) >= updateTolerance
    }
}

enum WorkspaceInspectorWidthPolicy {
    static let updateTolerance: CGFloat = 0.5

    static func clamped(_ width: CGFloat) -> CGFloat {
        min(
            max(width, AtelierMetrics.inspectorMinWidth),
            AtelierMetrics.inspectorMaxWidth
        )
    }

    static func differs(_ lhs: CGFloat, from rhs: CGFloat) -> Bool {
        abs(lhs - rhs) >= updateTolerance
    }
}

final class WorkspaceSplitViewController: NSSplitViewController {
    var onSidebarWidthChange: ((CGFloat) -> Void)?
    var onInspectorWidthChange: ((CGFloat) -> Void)?

    private var isSynchronizingSidebarWidth = false
    private var isSynchronizingInspectorWidth = false
    private var pendingSidebarWidth: CGFloat?
    private var pendingInspectorWidth: CGFloat?
    private var isSidebarWidthPublishScheduled = false
    private var isInspectorWidthPublishScheduled = false
    private var inspectorWidthConstraint: NSLayoutConstraint?

    override func splitView(
        _ splitView: NSSplitView,
        effectiveRect proposedEffectiveRect: NSRect,
        forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    ) -> NSRect {
        let systemRect = super.splitView(
            splitView,
            effectiveRect: proposedEffectiveRect,
            forDrawnRect: drawnRect,
            ofDividerAt: dividerIndex
        )
        return WorkspaceDividerInteractionPolicy.effectiveRect(
            proposed: systemRect,
            isVertical: splitView.isVertical,
            within: splitView.bounds
        )
    }

    override func splitView(
        _ splitView: NSSplitView,
        constrainSplitPosition proposedPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        if dividerIndex == 0, !isSynchronizingSidebarWidth {
            scheduleSidebarWidthPublish(proposedPosition)
        } else if dividerIndex == 1, !isSynchronizingInspectorWidth {
            let width = WorkspaceInspectorWidthPolicy.clamped(
                splitView.bounds.maxX - proposedPosition - splitView.dividerThickness
            )
            inspectorWidthConstraint?.constant = width
            scheduleInspectorWidthPublish(width)
        }
        return proposedPosition
    }

    func installInspectorWidthConstraint(for inspectorView: NSView, width: CGFloat) {
        inspectorWidthConstraint?.isActive = false
        let constraint = inspectorView.widthAnchor.constraint(
            equalToConstant: WorkspaceInspectorWidthPolicy.clamped(width)
        )
        constraint.priority = NSLayoutConstraint.Priority(rawValue: 999)
        constraint.isActive = true
        inspectorWidthConstraint = constraint
    }

    func synchronizeSidebarWidth(_ proposedWidth: CGFloat) {
        guard splitViewItems.indices.contains(0),
              !splitViewItems[0].isCollapsed,
              let sidebarView = splitViewItems[0].viewController.viewIfLoaded else {
            return
        }
        let width = WorkspaceSidebarWidthPolicy.clamped(proposedWidth)
        guard WorkspaceSidebarWidthPolicy.differs(sidebarView.frame.width, from: width) else {
            return
        }

        isSynchronizingSidebarWidth = true
        splitView.setPosition(width, ofDividerAt: 0)
        isSynchronizingSidebarWidth = false
    }

    func synchronizeInspectorWidth(_ proposedWidth: CGFloat) {
        let width = WorkspaceInspectorWidthPolicy.clamped(proposedWidth)
        if inspectorWidthConstraint?.constant != width {
            inspectorWidthConstraint?.constant = width
        }
        guard splitViewItems.indices.contains(2),
              !splitViewItems[2].isCollapsed,
              let inspectorView = splitViewItems[2].viewController.viewIfLoaded else {
            return
        }
        guard WorkspaceInspectorWidthPolicy.differs(inspectorView.frame.width, from: width) else {
            return
        }

        isSynchronizingInspectorWidth = true
        splitView.setPosition(
            splitView.bounds.maxX - width - splitView.dividerThickness,
            ofDividerAt: 1
        )
        splitView.layoutSubtreeIfNeeded()
        isSynchronizingInspectorWidth = false
    }

    private func scheduleSidebarWidthPublish(_ proposedWidth: CGFloat) {
        pendingSidebarWidth = WorkspaceSidebarWidthPolicy.clamped(proposedWidth)
        guard !isSidebarWidthPublishScheduled else { return }
        isSidebarWidthPublishScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isSidebarWidthPublishScheduled = false
            guard let width = pendingSidebarWidth else { return }
            pendingSidebarWidth = nil
            onSidebarWidthChange?(width)
        }
    }

    private func scheduleInspectorWidthPublish(_ proposedWidth: CGFloat) {
        pendingInspectorWidth = WorkspaceInspectorWidthPolicy.clamped(proposedWidth)
        guard !isInspectorWidthPublishScheduled else { return }
        isInspectorWidthPublishScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isInspectorWidthPublishScheduled = false
            guard let width = pendingInspectorWidth else { return }
            pendingInspectorWidth = nil
            onInspectorWidthChange?(width)
        }
    }
}

struct WorkspacePanelMotionContainer<Content: View>: View {
    let content: Content
    let isPresented: Bool
    let edge: WorkspacePanelMotionEdge
    let reduceMotion: Bool

    var body: some View {
        content
            .offset(
                x: isPresented || reduceMotion ? 0 : edge.hiddenOffset
            )
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: WorkspaceSplitAnimationPolicy.panelDuration),
                value: isPresented
            )
            .clipped()
    }
}

struct WorkspaceNativeSplitView<Sidebar: View, Detail: View, Inspector: View>:
    NSViewControllerRepresentable {
    let sidebar: Sidebar
    let detail: Detail
    let inspector: Inspector
    let sidebarWidth: CGFloat
    let inspectorWidth: CGFloat
    let onSidebarWidthChange: (CGFloat) -> Void
    let onInspectorWidthChange: (CGFloat) -> Void
    let showsSidebar: Bool
    let showsInspector: Bool
    let sidebarAnimationRequestID: Int
    let inspectorAnimationRequestID: Int
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = WorkspaceSplitViewController()
        controller.splitView.isVertical = true
        controller.splitView.dividerStyle = .thin
        controller.onSidebarWidthChange = onSidebarWidthChange
        controller.onInspectorWidthChange = onInspectorWidthChange

        let sidebarController = NSHostingController(
            rootView: WorkspacePanelMotionContainer(
                content: sidebar,
                isPresented: showsSidebar,
                edge: .leading,
                reduceMotion: reduceMotion
            )
        )
        sidebarController.view.frame.size.width = WorkspaceSidebarWidthPolicy.clamped(sidebarWidth)
        let sidebarItem = NSSplitViewItem(viewController: sidebarController)
        sidebarItem.minimumThickness = AtelierMetrics.workspaceSidebarMinWidth
        sidebarItem.maximumThickness = AtelierMetrics.workspaceSidebarMaxWidth
        sidebarItem.canCollapse = true
        sidebarItem.canCollapseFromWindowResize = false
        sidebarItem.collapseBehavior = WorkspaceSplitLayoutPolicy.panelCollapseBehavior
        sidebarItem.holdingPriority = WorkspaceSplitLayoutPolicy.sidePanelHoldingPriority
        sidebarItem.isCollapsed = !showsSidebar

        let detailController = NSHostingController(rootView: detail)
        let detailItem = NSSplitViewItem(viewController: detailController)
        detailItem.minimumThickness = AtelierMetrics.centerMinWidth

        let inspectorController = NSHostingController(
            rootView: WorkspacePanelMotionContainer(
                content: inspector,
                isPresented: showsInspector,
                edge: .trailing,
                reduceMotion: reduceMotion
            )
        )
        inspectorController.view.frame.size.width = WorkspaceInspectorWidthPolicy.clamped(
            inspectorWidth
        )
        let inspectorItem = NSSplitViewItem(viewController: inspectorController)
        inspectorItem.minimumThickness = AtelierMetrics.inspectorMinWidth
        inspectorItem.maximumThickness = AtelierMetrics.inspectorMaxWidth
        inspectorItem.canCollapse = true
        inspectorItem.canCollapseFromWindowResize = false
        inspectorItem.collapseBehavior = WorkspaceSplitLayoutPolicy.panelCollapseBehavior
        inspectorItem.holdingPriority = WorkspaceSplitLayoutPolicy.sidePanelHoldingPriority
        inspectorItem.isCollapsed = !showsInspector

        controller.addSplitViewItem(sidebarItem)
        controller.addSplitViewItem(detailItem)
        controller.addSplitViewItem(inspectorItem)

        context.coordinator.install(
            controller: controller,
            sidebarController: sidebarController,
            sidebarItem: sidebarItem,
            detailController: detailController,
            inspectorController: inspectorController,
            inspectorItem: inspectorItem,
            showsSidebar: showsSidebar,
            showsInspector: showsInspector,
            sidebarAnimationRequestID: sidebarAnimationRequestID,
            inspectorAnimationRequestID: inspectorAnimationRequestID,
            sidebarWidth: sidebarWidth,
            inspectorWidth: inspectorWidth
        )
        return controller
    }

    func updateNSViewController(
        _ controller: NSSplitViewController,
        context: Context
    ) {
        if let splitController = controller as? WorkspaceSplitViewController {
            splitController.onSidebarWidthChange = onSidebarWidthChange
            splitController.onInspectorWidthChange = onInspectorWidthChange
        }
        context.coordinator.sidebarController?.rootView = WorkspacePanelMotionContainer(
            content: sidebar,
            isPresented: showsSidebar,
            edge: .leading,
            reduceMotion: reduceMotion
        )
        context.coordinator.detailController?.rootView = detail
        context.coordinator.inspectorController?.rootView = WorkspacePanelMotionContainer(
            content: inspector,
            isPresented: showsInspector,
            edge: .trailing,
            reduceMotion: reduceMotion
        )

        let sidebarChanged = context.coordinator.showsSidebar != showsSidebar
        let inspectorChanged = context.coordinator.showsInspector != showsInspector
        let animatesSidebar = WorkspaceSplitAnimationPolicy.animates(
            panelChanged: sidebarChanged,
            reduceMotion: reduceMotion,
            requestsAnimation: context.coordinator.sidebarAnimationRequestID
                != sidebarAnimationRequestID
        )
        let animatesInspector = WorkspaceSplitAnimationPolicy.animates(
            panelChanged: inspectorChanged,
            reduceMotion: reduceMotion,
            requestsAnimation: context.coordinator.inspectorAnimationRequestID
                != inspectorAnimationRequestID
        )

        context.coordinator.update(
            showsSidebar: showsSidebar,
            showsInspector: showsInspector,
            sidebarChanged: sidebarChanged,
            inspectorChanged: inspectorChanged,
            sidebarAnimationRequestID: sidebarAnimationRequestID,
            inspectorAnimationRequestID: inspectorAnimationRequestID,
            animatesSidebar: animatesSidebar,
            animatesInspector: animatesInspector
        )
        context.coordinator.synchronizeSidebarWidth(sidebarWidth)
        context.coordinator.synchronizeInspectorWidth(inspectorWidth)
    }

    // Fill the proposed size instead of the split view's Auto Layout fitting
    // height. Without this, SwiftUI sizes the controller to the tallest column's
    // fitting height; when every column is short (git sidebar showing the error
    // block, diff detail in a GeometryReader) the whole surface collapses and
    // centers. Matches FileViewer's representable sizing.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsViewController: NSSplitViewController,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsViewController.view.frame.width,
            height: proposal.height ?? nsViewController.view.frame.height
        )
    }

    final class Coordinator {
        weak var controller: NSSplitViewController?
        var sidebarController: NSHostingController<WorkspacePanelMotionContainer<Sidebar>>?
        weak var sidebarItem: NSSplitViewItem?
        var detailController: NSHostingController<Detail>?
        var inspectorController: NSHostingController<WorkspacePanelMotionContainer<Inspector>>?
        weak var inspectorItem: NSSplitViewItem?
        var showsSidebar = false
        var showsInspector = false
        var sidebarAnimationRequestID = 0
        var inspectorAnimationRequestID = 0
        private var updateGeneration = 0
        private var pendingUpdateGeneration: Int?
        private var desiredSidebarWidth = AtelierMetrics.workspaceSidebarIdealWidth
        private var desiredInspectorWidth = AtelierMetrics.inspectorIdealWidth
        private var sidebarWidthUpdateGeneration = 0
        private var inspectorWidthUpdateGeneration = 0

        func install(
            controller: NSSplitViewController,
            sidebarController: NSHostingController<WorkspacePanelMotionContainer<Sidebar>>,
            sidebarItem: NSSplitViewItem,
            detailController: NSHostingController<Detail>,
            inspectorController: NSHostingController<WorkspacePanelMotionContainer<Inspector>>,
            inspectorItem: NSSplitViewItem,
            showsSidebar: Bool,
            showsInspector: Bool,
            sidebarAnimationRequestID: Int,
            inspectorAnimationRequestID: Int,
            sidebarWidth: CGFloat = AtelierMetrics.workspaceSidebarIdealWidth,
            inspectorWidth: CGFloat = AtelierMetrics.inspectorIdealWidth
        ) {
            self.controller = controller
            self.sidebarController = sidebarController
            self.sidebarItem = sidebarItem
            self.detailController = detailController
            self.inspectorController = inspectorController
            self.inspectorItem = inspectorItem
            self.showsSidebar = showsSidebar
            self.showsInspector = showsInspector
            self.sidebarAnimationRequestID = sidebarAnimationRequestID
            self.inspectorAnimationRequestID = inspectorAnimationRequestID
            desiredSidebarWidth = WorkspaceSidebarWidthPolicy.clamped(sidebarWidth)
            desiredInspectorWidth = WorkspaceInspectorWidthPolicy.clamped(inspectorWidth)
            (controller as? WorkspaceSplitViewController)?.installInspectorWidthConstraint(
                for: inspectorController.view,
                width: desiredInspectorWidth
            )
        }

        func synchronizeSidebarWidth(_ proposedWidth: CGFloat) {
            desiredSidebarWidth = WorkspaceSidebarWidthPolicy.clamped(proposedWidth)
            sidebarWidthUpdateGeneration += 1
            let generation = sidebarWidthUpdateGeneration

            DispatchQueue.main.async { [weak self] in
                guard let self, generation == sidebarWidthUpdateGeneration,
                      let controller = controller as? WorkspaceSplitViewController else {
                    return
                }
                controller.synchronizeSidebarWidth(desiredSidebarWidth)
            }
        }

        func synchronizeInspectorWidth(_ proposedWidth: CGFloat) {
            desiredInspectorWidth = WorkspaceInspectorWidthPolicy.clamped(proposedWidth)
            inspectorWidthUpdateGeneration += 1
            let generation = inspectorWidthUpdateGeneration

            DispatchQueue.main.async { [weak self] in
                guard let self, generation == inspectorWidthUpdateGeneration,
                      let controller = controller as? WorkspaceSplitViewController else {
                    return
                }
                controller.synchronizeInspectorWidth(desiredInspectorWidth)
            }
        }

        func update(
            showsSidebar: Bool,
            showsInspector: Bool,
            sidebarChanged: Bool,
            inspectorChanged: Bool,
            sidebarAnimationRequestID: Int,
            inspectorAnimationRequestID: Int,
            animatesSidebar: Bool,
            animatesInspector: Bool
        ) {
            let reconcilesSidebar = sidebarItem?.isCollapsed == showsSidebar
            let reconcilesInspector = inspectorItem?.isCollapsed == showsInspector

            self.showsSidebar = showsSidebar
            self.showsInspector = showsInspector
            self.sidebarAnimationRequestID = sidebarAnimationRequestID
            self.inspectorAnimationRequestID = inspectorAnimationRequestID
            guard sidebarChanged || inspectorChanged || reconcilesSidebar
                || reconcilesInspector else { return }
            if !sidebarChanged && !inspectorChanged && pendingUpdateGeneration != nil {
                return
            }

            updateGeneration += 1
            let generation = updateGeneration
            pendingUpdateGeneration = generation

            DispatchQueue.main.async { [weak self] in
                guard let self, generation == updateGeneration else {
                    return
                }
                defer {
                    if pendingUpdateGeneration == generation {
                        pendingUpdateGeneration = nil
                    }
                }

                let updatesSidebar = sidebarItem?.isCollapsed == showsSidebar
                let updatesInspector = inspectorItem?.isCollapsed == showsInspector

                if updatesInspector && !animatesInspector {
                    inspectorItem?.isCollapsed = !showsInspector
                }
                if updatesSidebar && !animatesSidebar {
                    sidebarItem?.isCollapsed = !showsSidebar
                }
                guard (updatesSidebar && animatesSidebar)
                    || (updatesInspector && animatesInspector) else {
                    synchronizeSidebarWidth(desiredSidebarWidth)
                    synchronizeInspectorWidth(desiredInspectorWidth)
                    return
                }

                NSAnimationContext.runAnimationGroup { animationContext in
                    animationContext.duration = WorkspaceSplitAnimationPolicy.panelDuration
                    animationContext.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    if updatesInspector && animatesInspector {
                        inspectorItem?.animator().isCollapsed = !showsInspector
                    }
                    if updatesSidebar && animatesSidebar {
                        sidebarItem?.animator().isCollapsed = !showsSidebar
                    }
                }
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + WorkspaceSplitAnimationPolicy.panelDuration
                ) { [weak self] in
                    guard let self else { return }
                    synchronizeSidebarWidth(desiredSidebarWidth)
                    synchronizeInspectorWidth(desiredInspectorWidth)
                }
            }
        }
    }
}
