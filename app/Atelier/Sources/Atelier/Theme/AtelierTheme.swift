import AppKit
import CoreText
import SwiftUI
@_spi(Advanced) import SwiftUIIntrospect

enum AtelierInteractionState: Equatable, Sendable {
    case normal
    case hovered
    case pressed
    case selected
    case focused
    case disabled
}

enum AtelierTheme {
    static let accent = Color(nsColor: AppKitThemeAdapter.accent)
    static let accentInk = Color(nsColor: AppKitThemeAdapter.accentInk)
    static let workflowDone = Color(nsColor: AppKitThemeAdapter.workflowDone)
    static let workflowTodo = Color(nsColor: AppKitThemeAdapter.workflowTodo)
    static let workflowBlocked = Color(nsColor: AppKitThemeAdapter.workflowBlocked)
    static let chrome = Color(nsColor: AppKitThemeAdapter.chrome)
    static let canvas = Color(nsColor: AppKitThemeAdapter.canvas)
    static let sidebar = Color(nsColor: AppKitThemeAdapter.sidebar)
    static let panel = Color(nsColor: AppKitThemeAdapter.panel)
    static let raised = Color(nsColor: AppKitThemeAdapter.raised)
    static let editor = Color(nsColor: AppKitThemeAdapter.editor)
    static let code = editor
    static let tabInactive = Color(nsColor: AppKitThemeAdapter.tabInactive)
    static let border = Color(nsColor: AppKitThemeAdapter.border)
    static let codeCyan = Color(nsColor: AppKitThemeAdapter.gitUntracked)
    static let gitOrange = Color(nsColor: AppKitThemeAdapter.gitModified)
    static let gitAdded = Color(nsColor: AppKitThemeAdapter.gitAdded)
    static let gitDeleted = Color(nsColor: AppKitThemeAdapter.gitDeleted)
    static let gitUntracked = Color(nsColor: AppKitThemeAdapter.gitUntracked)
    static let selection = Color(nsColor: AppKitThemeAdapter.selection)
    static let chromeSelection = Color(nsColor: AppKitThemeAdapter.chromeSelection)
    static let chromeSelectionInk = Color(nsColor: AppKitThemeAdapter.chromeSelectionInk)
    static let workspaceRailTop = Color(nsColor: AppKitThemeAdapter.workspaceRailTop)
    static let workspaceRailBottom = Color(nsColor: AppKitThemeAdapter.workspaceRailBottom)
    static let workspaceRailSolid = Color(nsColor: AppKitThemeAdapter.workspaceRailSolid)
    static let workspaceRailForeground = Color(nsColor: AppKitThemeAdapter.workspaceRailForeground)
    static let workspaceRailSecondary = Color(nsColor: AppKitThemeAdapter.workspaceRailSecondary)
    static let workspaceRailSelection = Color(nsColor: AppKitThemeAdapter.workspaceRailSelection)
    static let workspaceRailHover = Color(nsColor: AppKitThemeAdapter.workspaceRailHover)
    static let workspaceRailPressed = Color(nsColor: AppKitThemeAdapter.workspaceRailPressed)
    static let workspaceRailBorder = Color(nsColor: AppKitThemeAdapter.workspaceRailBorder)
    static let danger = gitDeleted
    static let panelRadius: CGFloat = 12
    static let controlRadius: CGFloat = 8
    static let rowRadius: CGFloat = 6
    static let hoverFill = Color(nsColor: AppKitThemeAdapter.hover)
    static let pressedFill = Color(nsColor: AppKitThemeAdapter.pressed)
    static let accentHoverFill = accent.opacity(0.10)
    static let focusFill = accent.opacity(0.12)
    static let disabledOpacity: Double = 0.45
    static let inactiveOpacity: Double = 0.72
    static let strokeHairline: CGFloat = 0.5
    static let strokeControl: CGFloat = 0.75
    static let strokeFocus: CGFloat = 1.5
    static let shadowSoft = Color(red: 0.18, green: 0.12, blue: 0.08).opacity(0.08)
    static let panelEdgeShadow = Color(red: 0.18, green: 0.12, blue: 0.08).opacity(0.14)
    static let shadowFloating = Color(red: 0.14, green: 0.09, blue: 0.06).opacity(0.22)
    static let scrim = Color.black.opacity(0.12)

    static func controlFill(for state: AtelierInteractionState) -> Color {
        switch state {
        case .normal, .disabled:
            Color.clear
        case .hovered:
            hoverFill
        case .pressed:
            pressedFill
        case .selected:
            selection
        case .focused:
            focusFill
        }
    }

    static func controlStroke(for state: AtelierInteractionState) -> Color {
        switch state {
        case .focused:
            accent
        case .selected:
            accent.opacity(0.72)
        case .normal, .hovered, .pressed, .disabled:
            border
        }
    }

    static func workspaceRailControlFill(for state: AtelierInteractionState) -> Color {
        switch state {
        case .normal, .disabled:
            Color.clear
        case .hovered:
            workspaceRailHover
        case .pressed:
            workspaceRailPressed
        case .selected, .focused:
            workspaceRailSelection
        }
    }

    static func controlOpacity(for state: AtelierInteractionState) -> Double {
        state == .disabled ? disabledOpacity : 1
    }
}

enum AtelierMetrics {
    static let grid: CGFloat = 8
    // Spacing scale: 8pt grid with a 4pt half step.
    static let spaceXS: CGFloat = 4
    static let spaceS: CGFloat = 8
    static let spaceM: CGFloat = 12
    static let spaceL: CGFloat = 16
    static let spaceXL: CGFloat = 24
    static let space2XL: CGFloat = 32
    static let panelHeaderHeight: CGFloat = 40
    static let sectionHeaderHeight: CGFloat = 36
    static let tabBarHeight: CGFloat = 40
    static let statusBarHeight: CGFloat = 26
    static let iconButtonSize: CGFloat = 30
    static let smallIconSize: CGFloat = 8
    static let regularIconSize: CGFloat = 16
    static let emptyStateIconSize: CGFloat = 26
    static let compactControlHeight: CGFloat = 24
    static let controlHeight: CGFloat = 28
    static let fieldHeight: CGFloat = 32
    static let rowHeight: CGFloat = 28
    static let transcriptMaxWidth: CGFloat = 680
    static let documentMaxWidth: CGFloat = 720
    static let markdownOutlineWidth: CGFloat = 200
    static let emptyStateMaxWidth: CGFloat = 460
    static let workspaceRailWidth: CGFloat = 176
    static let workspaceRailItemHeight: CGFloat = 44
    static let workspaceRailItemGap: CGFloat = 4
    static let projectMenuWidth: CGFloat = 420
    static let dialogWidth: CGFloat = 340
    static let settingsWidth: CGFloat = 460
    static let settingsMinHeight: CGFloat = 400
    static let codeGutterWidth: CGFloat = 48
    static let explorerMinWidth: CGFloat = 220
    static let explorerIdealWidth: CGFloat = 280
    static let explorerMaxWidth: CGFloat = 400
    static let centerMinWidth: CGFloat = 420
    static let centerIdealWidth: CGFloat = 660
    static let sourceControlMinWidth: CGFloat = 320
    static let sourceControlIdealWidth: CGFloat = 380
    static let sourceControlMaxWidth: CGFloat = 540
    static let workspaceSidebarMinWidth: CGFloat = 240
    static let workspaceSidebarIdealWidth: CGFloat = 370
    static let workspaceSidebarMaxWidth: CGFloat = 560
    static let watchtowerPanelWidth: CGFloat = 340
    static let inspectorMinWidth: CGFloat = 260
    static let inspectorIdealWidth: CGFloat = 360
    static let inspectorMaxWidth: CGFloat = 640
    static let tabMinWidth: CGFloat = 112
    static let tabIdealWidth: CGFloat = 152
    static let tabMaxWidth: CGFloat = 220
    static let zoomLabelMinWidth: CGFloat = 42
}

enum AtelierTypography {
    // Typographic scale: micro < caption < label < body < uiSize < headline < display.
    static let codeFontFamily = "JetBrains Mono"
    static let codeFontWeight = NSFont.Weight.regular
    static let codeFontLigaturesEnabled = true
    static let micro: CGFloat = 11
    static let caption: CGFloat = 12
    static let label: CGFloat = 12.5
    static let body: CGFloat = 13.5
    static let uiSize: CGFloat = 14
    static let headline: CGFloat = 16
    static let title: CGFloat = 17
    static let display: CGFloat = 24
    static let editorSize: CGFloat = 16
    static let terminalSize: CGFloat = 20

    // Resolving the descriptor + ligature features is expensive; callers hit
    // this per layout/zoom, so cache per size. Ligature-off runs keep their own
    // cache, because the two resolve to different fonts at the same size.
    private static var codeFontCache: [CGFloat: NSFont] = [:]
    private static var plainCodeFontCache: [CGFloat: NSFont] = [:]

    /// - Parameter ligatures: pass `false` for an inline code run inside prose. A
    ///   contextual alternate helps in a block of code and misleads in a sentence:
    ///   `<!--` draws as a left arrow, so quoted source stops reading as itself.
    static func codeFont(size: CGFloat, ligatures: Bool = true) -> NSFont {
        if ligatures {
            if let cached = codeFontCache[size] { return cached }
            let font = makeCodeFont(size: size, ligatures: true)
            codeFontCache[size] = font
            return font
        }
        if let cached = plainCodeFontCache[size] { return cached }
        let font = makeCodeFont(size: size, ligatures: false)
        plainCodeFontCache[size] = font
        return font
    }

    private static func makeCodeFont(size: CGFloat, ligatures: Bool) -> NSFont {
        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: codeFontFamily,
            .traits: [NSFontDescriptor.TraitKey.weight: codeFontWeight]
        ])
        let baseFont = NSFont(descriptor: descriptor, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: codeFontWeight)
        // JetBrains Mono ships contextual alternates on, so the base font already
        // draws them and only the off selector changes anything. Asking for them
        // explicitly is a no-op kept for a fallback face that may default them off.
        let selector = (codeFontLigaturesEnabled && ligatures)
            ? kContextualAlternatesOnSelector
            : kContextualAlternatesOffSelector
        let featureSettings: [[NSFontDescriptor.FeatureKey: Any]] = [[
            .typeIdentifier: kContextualAlternatesType,
            .selectorIdentifier: selector
        ]]
        let featureDescriptor = baseFont.fontDescriptor.addingAttributes([
            .featureSettings: featureSettings
        ])
        return NSFont(descriptor: featureDescriptor, size: size) ?? baseFont
    }
}

enum AtelierFontScaling {
    /// Snap a scaled point size to whole device pixels so text stays crisp on non-Retina displays.
    static func snapped(_ size: CGFloat, displayScale: CGFloat) -> CGFloat {
        guard size > 0, displayScale > 0 else { return size }
        return (size * displayScale).rounded() / displayScale
    }
}

private struct AtelierZoomScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var atelierZoomScale: CGFloat {
        get { self[AtelierZoomScaleKey.self] }
        set { self[AtelierZoomScaleKey.self] = newValue }
    }
}

private struct AtelierScaledFontModifier: ViewModifier {
    @Environment(\.atelierZoomScale) private var scale
    @Environment(\.displayScale) private var displayScale

    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        let resolved = AtelierFontScaling.snapped(size * scale, displayScale: displayScale)
        content.font(.system(size: resolved, weight: weight, design: design))
    }
}

extension View {
    func atelierFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(AtelierScaledFontModifier(size: size, weight: weight, design: design))
    }
}

struct AtelierPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AtelierTheme.panel)
            .overlay {
                Rectangle()
                    .stroke(AtelierTheme.border, lineWidth: AtelierTheme.strokeHairline)
            }
    }
}

/// Raised card chrome: panel fill, continuous rounded corners, control-weight border.
struct AtelierCardModifier: ViewModifier {
    var radius: CGFloat = AtelierTheme.controlRadius
    var fill: Color = AtelierTheme.panel

    func body(content: Content) -> some View {
        content
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(AtelierTheme.border, lineWidth: AtelierTheme.strokeControl)
            }
    }
}

/// Text-input chrome with a visible accent focus ring.
struct AtelierFieldModifier: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    AtelierTheme.editor
                    if isFocused {
                        AtelierTheme.controlFill(for: .focused)
                    }
                }
            }
            .clipShape(
                RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous)
                    .stroke(
                        AtelierTheme.controlStroke(for: isFocused ? .focused : .normal),
                        lineWidth: isFocused ? AtelierTheme.strokeFocus : 1
                    )
            }
    }
}

extension View {
    func atelierPanel() -> some View {
        modifier(AtelierPanelModifier())
    }

    func atelierCard(
        radius: CGFloat = AtelierTheme.controlRadius,
        fill: Color = AtelierTheme.panel
    ) -> some View {
        modifier(AtelierCardModifier(radius: radius, fill: fill))
    }

    func atelierField(isFocused: Bool) -> some View {
        modifier(AtelierFieldModifier(isFocused: isFocused))
    }

    func atelierSplitViewChrome() -> some View {
        introspect(.atelierSplitView, on: .macOS(.v26)) { splitView in
            splitView.dividerStyle = .thin
        }
    }

    func atelierScrollChrome(
        backgroundColor: NSColor,
        drawsBackground: Bool = true
    ) -> some View {
        introspect(.scrollView, on: .macOS(.v26)) { scrollView in
            scrollView.autohidesScrollers = true
            scrollView.borderType = .noBorder
            scrollView.backgroundColor = backgroundColor
            scrollView.drawsBackground = drawsBackground
            scrollView.scrollerStyle = .overlay
        }
    }

    func atelierListChrome() -> some View {
        introspect(.list(style: .sidebar), on: .macOS(.v26)) { tableView in
            tableView.backgroundColor = AppKitThemeAdapter.sidebar
            tableView.gridStyleMask = []
            tableView.intercellSpacing = .zero
            tableView.enclosingScrollView?.autohidesScrollers = true
            tableView.enclosingScrollView?.borderType = .noBorder
            tableView.enclosingScrollView?.drawsBackground = true
            tableView.enclosingScrollView?.backgroundColor = AppKitThemeAdapter.sidebar
            tableView.enclosingScrollView?.scrollerStyle = .overlay
            tableView.enclosingScrollView?.verticalScrollElasticity = .none
        }
    }

}

struct AtelierSplitViewType: IntrospectableViewType {}

extension IntrospectableViewType where Self == AtelierSplitViewType {
    static var atelierSplitView: Self { .init() }
}

extension macOSViewVersion<AtelierSplitViewType, NSSplitView> {
    static let v26 = Self(for: .v26)
}
