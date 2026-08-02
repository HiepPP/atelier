import SwiftUI
import AppKit
import Observation

@main
struct AtelierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel
#if DEBUG
    private let responseMemoryFixtureSelection: Bool?
    private let responseMemoryFixtureScrollCycles: Int
#endif

    init() {
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
        }
#if DEBUG
        responseMemoryFixtureSelection = AgentResponseMemoryFixture.textSelectionEnabled(
            arguments: CommandLine.arguments
        )
        responseMemoryFixtureScrollCycles = AgentResponseMemoryFixture.scrollCycleCount(
            arguments: CommandLine.arguments
        )
#endif
        _model = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup("Atelier") {
            rootContent
            .frame(
                minWidth: AtelierZoomModel.baseMinimumSize.width,
                minHeight: AtelierZoomModel.baseMinimumSize.height
            )
            .onAppear {
                appDelegate.model = model
                startModelIfNeeded()
            }
            .onOpenURL { url in
                model.handleDeepLink(url)
            }
            // Route external URL events into the existing window instead of
            // letting WindowGroup spawn a new window scene per deep link.
            .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
            .alert(item: presentedError) { error in
                Alert(
                    title: Text(error.title),
                    message: Text(error.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .windowToolbarStyle(.unifiedCompact)
        .handlesExternalEvents(matching: ["*"])
        .commands {
            AppCommands(model: model)
            AtelierPaletteCommands()
            AtelierTabCommands()
        }

        Settings {
            AtelierSettingsView()
                .environment(model.zoom)
                .environment(model.appearance)
        }

        MenuBarExtra(
            "Atelier",
            systemImage: "slider.horizontal.3",
            isInserted: menuBarExtraVisibility
        ) {
            AtelierMenuBarView()
                .environment(model.zoom)
                .environment(model.appearance)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarExtraVisibility: Binding<Bool> {
        Binding(
            get: { model.appearance.showsMenuBarExtra },
            set: { model.appearance.showsMenuBarExtra = $0 }
        )
    }

    @ViewBuilder
    private var rootContent: some View {
#if DEBUG
        if let responseMemoryFixtureSelection {
            AgentResponseMemoryFixtureView(
                textSelectionEnabled: responseMemoryFixtureSelection,
                profileScrollCycles: responseMemoryFixtureScrollCycles
            )
        } else {
            applicationContent
        }
#else
        applicationContent
#endif
    }

    private var applicationContent: some View {
        AtelierZoomContainer {
            ContentView()
                .environment(model)
                .background(WorkspaceWindowBridge(controller: model.windowController))
        }
        .environment(model.zoom)
        .environment(model.appearance)
    }

    private func startModelIfNeeded() {
#if DEBUG
        guard responseMemoryFixtureSelection == nil else { return }
#endif
        model.start()
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
    static let baseMinimumSize = CGSize(width: 760, height: 512)

    private(set) var scale: CGFloat = 1
    private(set) var isFocusMode = false
    private(set) var currentTier: DisplaySizeTier = DisplaySizing.fallbackTier
    private(set) var agentResponseTextScale = AgentResponseTextSizePolicy.defaultScale
    private(set) var appTextScale = AtelierAppearancePolicy.defaultTextScale
    private(set) var terminalTextScale = AtelierAppearancePolicy.defaultTextScale
    private(set) var editorTextScale = AtelierAppearancePolicy.defaultTextScale

    var sizingMode: DisplaySizingMode {
        didSet {
            guard sizingMode != oldValue else { return }
            defaults.set(sizingMode.rawValue, forKey: DisplaySizing.settingsKey)
        }
    }

    private static let minimumScale: CGFloat = 0.8
    private static let maximumScale: CGFloat = 2
    private static let chromeMaximumScale: CGFloat = 1.2
    private static let sidebarMaximumScale: CGFloat = 1.5
    private static let step: CGFloat = 0.1
    private static let settleDelay: UInt64 = 200_000_000
    private static let agentResponseTextScaleKey = "agentResponseTextScale"

    private var requestedScale: CGFloat = 1
    private var settleTask: Task<Void, Never>?
    private var focusModeIsAutomatic = false
    private weak var responderBeforeZoom: NSResponder?
    private let windowController: WindowController
    @ObservationIgnored private let defaults: UserDefaults
    private var manualScaleByDisplay: [String: CGFloat] = [:]
    private var currentDisplayKey = DisplaySizing.fallbackTier.rawValue
    private var hasResolvedDisplayKey = false

    init(windowController: WindowController, defaults: UserDefaults = .standard) {
        self.windowController = windowController
        self.defaults = defaults
        let stored = defaults.string(forKey: DisplaySizing.settingsKey)
        sizingMode = stored.flatMap(DisplaySizingMode.init(rawValue:)) ?? .automatic

        if let storedTextScale = defaults.object(
            forKey: Self.agentResponseTextScaleKey
        ) as? Double {
            agentResponseTextScale = AgentResponseTextSizePolicy.clamped(CGFloat(storedTextScale))
        }

        appTextScale = Self.storedTextScale(
            forKey: AtelierAppearancePolicy.appTextScaleKey,
            in: defaults
        )
        terminalTextScale = Self.storedTextScale(
            forKey: AtelierAppearancePolicy.terminalTextScaleKey,
            in: defaults
        )
        editorTextScale = Self.storedTextScale(
            forKey: AtelierAppearancePolicy.editorTextScaleKey,
            in: defaults
        )

        if let storedZoom = defaults.dictionary(
            forKey: AtelierAppearancePolicy.manualZoomByDisplayKey
        ) as? [String: Double] {
            manualScaleByDisplay = storedZoom.mapValues { value in
                Self.clampedZoomScale(CGFloat(value))
            }
        }

        let handler: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.updateForCurrentDisplay() }
        }
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main, using: handler)
        center.addObserver(forName: NSWindow.didChangeScreenNotification, object: nil, queue: .main, using: handler)
        updateForCurrentDisplay()
    }

    var canZoomIn: Bool { requestedScale < Self.maximumScale }
    var canZoomOut: Bool { requestedScale > Self.minimumScale }
    var chromeScale: CGFloat { min(renderScale * appTextScale, Self.chromeMaximumScale) }
    var sidebarScale: CGFloat { min(renderScale * appTextScale, Self.sidebarMaximumScale) }
    var contentScale: CGFloat { renderScale * appTextScale }
    var terminalScale: CGFloat { renderScale * terminalTextScale }
    var editorScale: CGFloat { renderScale * editorTextScale }
    var manualScale: CGFloat { requestedScale }
    var layoutProfileState: LayoutProfileZoomState {
        let focusMode: LayoutProfileFocusMode
        if !isFocusMode {
            focusMode = .off
        } else if focusModeIsAutomatic {
            focusMode = .automatic
        } else {
            focusMode = .manual
        }
        return LayoutProfileZoomState(
            sizingMode: sizingMode,
            manualScale: requestedScale,
            focusMode: focusMode
        )
    }

    private var baseScale: CGFloat {
        (sizingMode.forcedTier ?? currentTier).baseScale
    }

    private var focusThresholdScale: CGFloat {
        Self.sidebarMaximumScale / baseScale
    }

    private var renderScale: CGFloat {
        scale * baseScale
    }

    /// Recompute the tier and restore the manual offset for the window's current display.
    func updateForCurrentDisplay() {
        let screen = windowController.currentScreen()
        let key = DisplaySizing.displayKey(for: screen)
        if !hasResolvedDisplayKey {
            // The seed key is a placeholder, not a display the user ever zoomed.
            // Adopt the first resolved key without saving the seed and without a
            // write, so no phantom entry reaches disk and a key that happens to
            // equal the seed still restores its stored zoom.
            hasResolvedDisplayKey = true
            currentDisplayKey = key
            restoreManualScale(forDisplayKey: key)
        } else if key != currentDisplayKey {
            manualScaleByDisplay[currentDisplayKey] = requestedScale
            currentDisplayKey = key
            restoreManualScale(forDisplayKey: key)
            persistManualZoom()
        }
        let tier = DisplaySizing.detectedTier(for: screen)
        if tier != currentTier { currentTier = tier }
    }

    private func restoreManualScale(forDisplayKey key: String) {
        let restored = manualScaleByDisplay[key] ?? 1
        requestedScale = restored
        if scale != restored { scale = restored }
    }

    func setAgentResponseTextScale(_ scale: CGFloat) {
        let clamped = AgentResponseTextSizePolicy.clamped(scale)
        guard clamped != agentResponseTextScale else { return }
        agentResponseTextScale = clamped
        defaults.set(Double(clamped), forKey: Self.agentResponseTextScaleKey)
    }

    func setAppTextScale(_ scale: CGFloat) {
        let clamped = AtelierAppearancePolicy.clampedTextScale(scale)
        guard clamped != appTextScale else { return }
        appTextScale = clamped
        defaults.set(Double(clamped), forKey: AtelierAppearancePolicy.appTextScaleKey)
    }

    func setTerminalTextScale(_ scale: CGFloat) {
        let clamped = AtelierAppearancePolicy.clampedTextScale(scale)
        guard clamped != terminalTextScale else { return }
        terminalTextScale = clamped
        defaults.set(Double(clamped), forKey: AtelierAppearancePolicy.terminalTextScaleKey)
    }

    func setEditorTextScale(_ scale: CGFloat) {
        let clamped = AtelierAppearancePolicy.clampedTextScale(scale)
        guard clamped != editorTextScale else { return }
        editorTextScale = clamped
        defaults.set(Double(clamped), forKey: AtelierAppearancePolicy.editorTextScaleKey)
    }

    /// Return every appearance multiplier to its default, then hand zoom back to
    /// the existing reset so the focus mode rules stay in one place.
    func resetAppearance() {
        setAppTextScale(AtelierAppearancePolicy.defaultTextScale)
        setEditorTextScale(AtelierAppearancePolicy.defaultTextScale)
        setTerminalTextScale(AtelierAppearancePolicy.defaultTextScale)
        reset()
    }

    func zoomIn() {
        requestScale(requestedScale + Self.step)
    }

    func zoomOut() {
        requestScale(requestedScale - Self.step)
    }

    func reset() {
        if requestedScale > focusThresholdScale {
            focusModeIsAutomatic = true
        } else {
            isFocusMode = false
            focusModeIsAutomatic = false
        }
        requestScale(1)
    }

    func toggleFocusMode() {
        if isFocusMode {
            if requestedScale > focusThresholdScale {
                focusModeIsAutomatic = true
                requestScale(focusThresholdScale)
            } else {
                isFocusMode = false
                focusModeIsAutomatic = false
            }
        } else {
            isFocusMode = true
            focusModeIsAutomatic = false
        }
    }

    func applyLayoutProfileState(_ state: LayoutProfileZoomState) {
        settleTask?.cancel()
        settleTask = nil
        responderBeforeZoom = nil
        if sizingMode != state.sizingMode {
            sizingMode = state.sizingMode
        }
        let nextScale = Self.clampedZoomScale(state.manualScale)
        requestedScale = nextScale
        manualScaleByDisplay[currentDisplayKey] = nextScale
        persistManualZoom()
        if scale != nextScale {
            scale = nextScale
        }
        let nextFocusMode = state.focusMode
        let nextIsFocusMode = nextFocusMode.isFocused
        if isFocusMode != nextIsFocusMode {
            isFocusMode = nextIsFocusMode
        }
        focusModeIsAutomatic = nextFocusMode == .automatic
    }

    private func requestScale(_ value: CGFloat) {
        requestedScale = Self.clampedZoomScale(value)

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
            manualScaleByDisplay[currentDisplayKey] = requestedScale
            persistManualZoom()
            settleTask = nil
            windowController.restoreFirstResponder(responderBeforeZoom)
            responderBeforeZoom = nil
        }
    }

    /// One write per settled zoom, not one per step, so a zoom burst still costs
    /// a single defaults round trip.
    private func persistManualZoom() {
        let stored = manualScaleByDisplay.mapValues { Double($0) }
        defaults.set(stored, forKey: AtelierAppearancePolicy.manualZoomByDisplayKey)
    }

    private static func clampedZoomScale(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1 }
        let clamped = min(maximumScale, max(minimumScale, value))
        return (clamped * 100).rounded() / 100
    }

    private static func storedTextScale(forKey key: String, in defaults: UserDefaults) -> CGFloat {
        guard let stored = defaults.object(forKey: key) as? Double else {
            return AtelierAppearancePolicy.defaultTextScale
        }
        return AtelierAppearancePolicy.clampedTextScale(CGFloat(stored))
    }

    private func updateFocusMode(for scale: CGFloat) {
        if scale > focusThresholdScale, !isFocusMode {
            isFocusMode = true
            focusModeIsAutomatic = true
        } else if scale <= focusThresholdScale, focusModeIsAutomatic {
            isFocusMode = false
            focusModeIsAutomatic = false
        }
    }
}

private struct AtelierZoomContainer<Content: View>: View {
    @Environment(AtelierZoomModel.self) private var zoom
    @Environment(\.displayScale) private var displayScale
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.atelierZoomScale, zoom.chromeScale)
            .font(.system(size: AtelierFontScaling.snapped(AtelierTypography.uiSize * zoom.chromeScale, displayScale: displayScale)))
    }
}
