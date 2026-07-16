import AppKit
import SwiftUI
@_spi(Advanced) import SwiftUIIntrospect

enum AtelierTheme {
    static let accent = Color(nsColor: AppKitThemeAdapter.accent)
    static let accentInk = Color(nsColor: AppKitThemeAdapter.editor)
    static let chrome = Color(nsColor: AppKitThemeAdapter.chrome)
    static let canvas = Color(nsColor: AppKitThemeAdapter.canvas)
    static let sidebar = Color(nsColor: AppKitThemeAdapter.sidebar)
    static let panel = Color(nsColor: AppKitThemeAdapter.panel)
    static let raised = Color(nsColor: AppKitThemeAdapter.raised)
    static let editor = Color(nsColor: AppKitThemeAdapter.editor)
    static let code = editor
    static let tabInactive = Color(nsColor: AppKitThemeAdapter.tabInactive)
    static let border = Color(nsColor: AppKitThemeAdapter.border)
    static let codeCyan = Color(red: 0.00, green: 0.48, blue: 0.58)
    static let gitOrange = Color(red: 0.77, green: 0.31, blue: 0.15)
    static let panelRadius: CGFloat = 0
    static let controlRadius: CGFloat = 5
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

    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
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
