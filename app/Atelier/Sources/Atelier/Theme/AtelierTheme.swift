import AppKit
import SwiftUI
@_spi(Advanced) import SwiftUIIntrospect

enum AtelierTheme {
    static let accent = Color(nsColor: AppKitThemeAdapter.accent)
    static let accentInk = Color(nsColor: AppKitThemeAdapter.accentInk)
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
    static let panelRadius: CGFloat = 8
    static let controlRadius: CGFloat = 6
    static let rowRadius: CGFloat = 5
}

enum AtelierMetrics {
    static let grid: CGFloat = 8
    static let commandBarHeight: CGFloat = 44
    static let sectionHeaderHeight: CGFloat = 36
    static let tabBarHeight: CGFloat = 38
    static let statusBarHeight: CGFloat = 22
    static let iconButtonSize: CGFloat = 28
}

enum AtelierTypography {
    static let uiSize: CGFloat = 13
    static let editorSize: CGFloat = 16
    static let terminalSize: CGFloat = 20

    static func codeFont(size: CGFloat) -> NSFont {
        NSFont(name: "JetBrains Mono", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
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
                    .stroke(AtelierTheme.border, lineWidth: 0.5)
            }
    }
}

extension View {
    func atelierPanel() -> some View {
        modifier(AtelierPanelModifier())
    }

    func atelierSplitViewChrome() -> some View {
        introspect(.atelierSplitView, on: .macOS(.v26)) { splitView in
            splitView.dividerStyle = .thin
        }
    }

    func atelierScrollChrome(backgroundColor: NSColor) -> some View {
        introspect(.scrollView, on: .macOS(.v26)) { scrollView in
            scrollView.autohidesScrollers = true
            scrollView.borderType = .noBorder
            scrollView.drawsBackground = true
            scrollView.backgroundColor = backgroundColor
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
