import SwiftUI
import AppKit
import Observation

@main
struct AtelierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
        }
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup("Atelier") {
            AtelierZoomContainer {
                ContentView()
                    .environment(model)
                    .background(WorkspaceWindowBridge(controller: model.windowController))
            }
            .environment(model.zoom)
            .frame(
                minWidth: AtelierZoomModel.baseMinimumSize.width,
                minHeight: AtelierZoomModel.baseMinimumSize.height
            )
            .onAppear {
                appDelegate.model = model
                model.start()
            }
            .alert(item: presentedError) { error in
                Alert(
                    title: Text(error.title),
                    message: Text(error.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            AppCommands(model: model)
            AtelierTabCommands()
        }

        Settings {
            AtelierSettingsView()
        }
    }

    private var presentedError: Binding<AppError?> {
        Binding(
            get: { model.presentedError },
            set: { model.presentedError = $0 }
        )
    }
}

@MainActor
@Observable
final class AtelierZoomModel {
    static let baseMinimumSize = CGSize(width: 1_000, height: 600)

    private(set) var scale: CGFloat = 1
    private(set) var isFocusMode = false

    private static let minimumScale: CGFloat = 0.8
    private static let maximumScale: CGFloat = 2
    private static let defaultRenderScale: CGFloat = 1.5
    private static let chromeMaximumScale: CGFloat = 1.2
    private static let sidebarMaximumScale: CGFloat = 1.5
    private static let focusThresholdScale = sidebarMaximumScale / defaultRenderScale
    private static let step: CGFloat = 0.1
    private static let settleDelay: UInt64 = 200_000_000

    private var requestedScale: CGFloat = 1
    private var settleTask: Task<Void, Never>?
    private var focusModeIsAutomatic = false
    private weak var responderBeforeZoom: NSResponder?
    private let windowController: WindowController

    init(windowController: WindowController) {
        self.windowController = windowController
    }

    var canZoomIn: Bool { requestedScale < Self.maximumScale }
    var canZoomOut: Bool { requestedScale > Self.minimumScale }
    var chromeScale: CGFloat { min(renderScale, Self.chromeMaximumScale) }
    var sidebarScale: CGFloat { min(renderScale, Self.sidebarMaximumScale) }
    var contentScale: CGFloat { renderScale }

    private var renderScale: CGFloat {
        scale * Self.defaultRenderScale
    }

    func zoomIn() {
        requestScale(requestedScale + Self.step)
    }

    func zoomOut() {
        requestScale(requestedScale - Self.step)
    }

    func reset() {
        if requestedScale > Self.focusThresholdScale {
            focusModeIsAutomatic = true
        } else {
            isFocusMode = false
            focusModeIsAutomatic = false
        }
        requestScale(1)
    }

    func toggleFocusMode() {
        if isFocusMode {
            if requestedScale > Self.focusThresholdScale {
                focusModeIsAutomatic = true
                requestScale(Self.focusThresholdScale)
            } else {
                isFocusMode = false
                focusModeIsAutomatic = false
            }
        } else {
            isFocusMode = true
            focusModeIsAutomatic = false
        }
    }

    private func requestScale(_ value: CGFloat) {
        let clamped = min(Self.maximumScale, max(Self.minimumScale, value))
        requestedScale = (clamped * 100).rounded() / 100

        if settleTask == nil {
            responderBeforeZoom = windowController.currentFirstResponder()
        }
        settleTask?.cancel()

        settleTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.settleDelay)
            } catch {
                return
            }
            guard let self else { return }
            updateFocusMode(for: requestedScale)
            if scale != requestedScale {
                scale = requestedScale
            }
            settleTask = nil
            windowController.restoreFirstResponder(responderBeforeZoom)
            responderBeforeZoom = nil
        }
    }

    private func updateFocusMode(for scale: CGFloat) {
        if scale > Self.focusThresholdScale, !isFocusMode {
            isFocusMode = true
            focusModeIsAutomatic = true
        } else if scale <= Self.focusThresholdScale, focusModeIsAutomatic {
            isFocusMode = false
            focusModeIsAutomatic = false
        }
    }
}

private struct AtelierZoomContainer<Content: View>: View {
    @Environment(AtelierZoomModel.self) private var zoom
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.atelierZoomScale, zoom.chromeScale)
            .font(.system(size: 13 * zoom.chromeScale))
    }
}

