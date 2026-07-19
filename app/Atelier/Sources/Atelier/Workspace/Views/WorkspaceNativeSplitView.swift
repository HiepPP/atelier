import AppKit
import SwiftUI

nonisolated enum WorkspaceSplitAnimationPolicy {
    static let panelDuration = 0.20
    static let panelRollDistance: CGFloat = 24
    static let frameCount = 12

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

                let opensPanel = (sidebarChanged && showsSidebar)
                    || (inspectorChanged && showsInspector)
                if opensPanel {
                    applyPanelStateImmediately(
                        showsSidebar: showsSidebar,
                        showsInspector: showsInspector,
                        sidebarChanged: sidebarChanged,
                        inspectorChanged: inspectorChanged
                    )
                    return
                }

                if inspectorChanged && !animatesInspector {
                    applyInspectorState(isPresented: showsInspector)
                }
                if sidebarChanged && !animatesSidebar {
                    applySidebarState(isPresented: showsSidebar)
                }
                guard animatesSidebar || animatesInspector else { return }

                guard let splitView = controller?.splitView else {
                    applyPanelStateImmediately(
                        showsSidebar: showsSidebar,
                        showsInspector: showsInspector,
                        sidebarChanged: sidebarChanged,
                        inspectorChanged: inspectorChanged
                    )
                    return
                }

                if sidebarChanged && animatesSidebar {
                    sidebarItem?.minimumThickness = 0
                    sidebarItem?.canCollapse = false
                }
                if inspectorChanged && animatesInspector {
                    inspectorItem?.minimumThickness = 0
                    inspectorItem?.canCollapse = false
                }

                let arrangedSubviews = splitView.arrangedSubviews
                let sidebarStart = arrangedSubviews.first?.frame.maxX ?? 0
                let inspectorStart = arrangedSubviews.count > 2
                    ? arrangedSubviews[2].frame.minX - splitView.dividerThickness
                    : splitView.bounds.width
                let frameInterval = WorkspaceSplitAnimationPolicy.panelDuration
                    / Double(WorkspaceSplitAnimationPolicy.frameCount)
                defer {
                    if sidebarChanged && animatesSidebar {
                        sidebarItem?.canCollapse = true
                        sidebarItem?.minimumThickness = AtelierMetrics.workspaceSidebarMinWidth
                    }
                    if inspectorChanged && animatesInspector {
                        inspectorItem?.canCollapse = true
                        inspectorItem?.minimumThickness = AtelierMetrics.inspectorMinWidth
                    }
                }

                for frame in 1...WorkspaceSplitAnimationPolicy.frameCount {
                    guard generation == updateGeneration else { return }
                    let progress = CGFloat(frame)
                        / CGFloat(WorkspaceSplitAnimationPolicy.frameCount)
                    let easedProgress = 1 - pow(1 - progress, 3)

                    if inspectorChanged && animatesInspector {
                        let position = inspectorStart
                            + (splitView.bounds.width - inspectorStart) * easedProgress
                        splitView.setPosition(position, ofDividerAt: 1)
                    }
                    if sidebarChanged && animatesSidebar {
                        splitView.setPosition(
                            sidebarStart * (1 - easedProgress),
                            ofDividerAt: 0
                        )
                    }

                    if frame < WorkspaceSplitAnimationPolicy.frameCount {
                        try? await Task.sleep(for: .seconds(frameInterval))
                    }
                }

                guard generation == updateGeneration else { return }
                if sidebarChanged && animatesSidebar {
                    applySidebarState(isPresented: showsSidebar)
                }
                if inspectorChanged && animatesInspector {
                    applyInspectorState(isPresented: showsInspector)
                }
            }
        }

        private func applyPanelStateImmediately(
            showsSidebar: Bool,
            showsInspector: Bool,
            sidebarChanged: Bool,
            inspectorChanged: Bool
        ) {
            if sidebarChanged {
                applySidebarState(isPresented: showsSidebar)
            }
            if inspectorChanged {
                applyInspectorState(isPresented: showsInspector)
            }
        }

        private func applySidebarState(isPresented: Bool) {
            sidebarItem?.canCollapse = true
            sidebarItem?.isCollapsed = !isPresented
            sidebarItem?.minimumThickness = AtelierMetrics.workspaceSidebarMinWidth
        }

        private func applyInspectorState(isPresented: Bool) {
            inspectorItem?.canCollapse = true
            inspectorItem?.isCollapsed = !isPresented
            inspectorItem?.minimumThickness = AtelierMetrics.inspectorMinWidth
        }
    }
}
