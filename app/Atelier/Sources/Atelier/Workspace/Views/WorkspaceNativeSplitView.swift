import AppKit
import SwiftUI

nonisolated enum WorkspaceSplitAnimationPolicy {
    static let panelDuration = 0.32

    static func animates(
        panelChanged: Bool,
        reduceMotion: Bool,
        requestsAnimation: Bool
    ) -> Bool {
        panelChanged && !reduceMotion && requestsAnimation
    }
}

nonisolated enum WorkspaceSplitLayoutPolicy {
    static let sidePanelHoldingPriority = NSLayoutConstraint.Priority(
        rawValue: NSLayoutConstraint.Priority.defaultLow.rawValue + 1
    )
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

        let sidebarController = NSHostingController(rootView: sidebar)
        let sidebarItem = NSSplitViewItem(viewController: sidebarController)
        sidebarItem.minimumThickness = AtelierMetrics.workspaceSidebarMinWidth
        sidebarItem.maximumThickness = AtelierMetrics.workspaceSidebarMaxWidth
        sidebarItem.canCollapse = true
        sidebarItem.canCollapseFromWindowResize = false
        sidebarItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        sidebarItem.holdingPriority = WorkspaceSplitLayoutPolicy.sidePanelHoldingPriority
        sidebarItem.isCollapsed = !showsSidebar

        let detailController = NSHostingController(rootView: detail)
        let detailItem = NSSplitViewItem(viewController: detailController)
        detailItem.minimumThickness = AtelierMetrics.centerMinWidth

        let inspectorController = NSHostingController(rootView: inspector)
        let inspectorItem = NSSplitViewItem(viewController: inspectorController)
        inspectorItem.minimumThickness = AtelierMetrics.inspectorMinWidth
        inspectorItem.maximumThickness = AtelierMetrics.inspectorMaxWidth
        inspectorItem.canCollapse = true
        inspectorItem.canCollapseFromWindowResize = false
        inspectorItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
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
        context.coordinator.sidebarController?.rootView = sidebar
        context.coordinator.detailController?.rootView = detail
        context.coordinator.inspectorController?.rootView = inspector

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

    final class Coordinator {
        weak var controller: NSSplitViewController?
        var sidebarController: NSHostingController<Sidebar>?
        weak var sidebarItem: NSSplitViewItem?
        var detailController: NSHostingController<Detail>?
        var inspectorController: NSHostingController<Inspector>?
        weak var inspectorItem: NSSplitViewItem?
        var showsSidebar = false
        var showsInspector = false
        var sidebarAnimationRequestID = 0
        var inspectorAnimationRequestID = 0
        private var updateGeneration = 0

        func install(
            controller: NSSplitViewController,
            sidebarController: NSHostingController<Sidebar>,
            sidebarItem: NSSplitViewItem,
            detailController: NSHostingController<Detail>,
            inspectorController: NSHostingController<Inspector>,
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
            guard sidebarChanged || inspectorChanged else { return }

            self.showsSidebar = showsSidebar
            self.showsInspector = showsInspector
            self.sidebarAnimationRequestID = sidebarAnimationRequestID
            self.inspectorAnimationRequestID = inspectorAnimationRequestID
            updateGeneration += 1
            let generation = updateGeneration

            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, generation == updateGeneration else { return }

                if inspectorChanged && !animatesInspector {
                    inspectorItem?.isCollapsed = !showsInspector
                }
                if sidebarChanged && !animatesSidebar {
                    sidebarItem?.isCollapsed = !showsSidebar
                }
                guard animatesSidebar || animatesInspector else { return }

                await NSAnimationContext.runAnimationGroup { animationContext in
                    animationContext.duration = WorkspaceSplitAnimationPolicy.panelDuration
                    if inspectorChanged && animatesInspector {
                        inspectorItem?.animator().isCollapsed = !showsInspector
                    }
                    if sidebarChanged && animatesSidebar {
                        sidebarItem?.animator().isCollapsed = !showsSidebar
                    }
                }
            }
        }
    }
}
