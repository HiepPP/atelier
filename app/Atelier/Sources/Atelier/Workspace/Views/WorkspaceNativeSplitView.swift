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
    let showsSidebar: Bool
    let showsInspector: Bool
    let sidebarAnimationRequestID: Int
    let inspectorAnimationRequestID: Int
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = NSSplitViewController()
        controller.splitView.isVertical = true
        controller.splitView.dividerStyle = .thin

        let sidebarController = NSHostingController(
            rootView: WorkspacePanelMotionContainer(
                content: sidebar,
                isPresented: showsSidebar,
                edge: .leading,
                reduceMotion: reduceMotion
            )
        )
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
            inspectorAnimationRequestID: inspectorAnimationRequestID
        )
        return controller
    }

    func updateNSViewController(
        _ controller: NSSplitViewController,
        context: Context
    ) {
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
            inspectorAnimationRequestID: Int
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
                    || (updatesInspector && animatesInspector) else { return }

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
            }
        }
    }
}
