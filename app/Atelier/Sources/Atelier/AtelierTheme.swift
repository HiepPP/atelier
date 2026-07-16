import AppKit
import SwiftUI
@_spi(Advanced) import SwiftUIIntrospect

enum AtelierNativePalette {
    static let chrome = NSColor(calibratedRed: 0.925, green: 0.91, blue: 0.865, alpha: 1)
    static let canvas = NSColor(calibratedRed: 0.955, green: 0.945, blue: 0.91, alpha: 1)
    static let sidebar = NSColor(calibratedRed: 0.94, green: 0.925, blue: 0.88, alpha: 1)
    static let panel = NSColor(calibratedRed: 0.965, green: 0.955, blue: 0.92, alpha: 1)
    static let raised = NSColor(calibratedRed: 0.905, green: 0.89, blue: 0.845, alpha: 1)
    static let editor = NSColor(calibratedRed: 0.985, green: 0.978, blue: 0.95, alpha: 1)
    static let code = editor
    static let tabInactive = NSColor(calibratedRed: 0.90, green: 0.885, blue: 0.84, alpha: 1)
    static let border = NSColor(calibratedRed: 0.78, green: 0.76, blue: 0.71, alpha: 0.68)
    static let selection = NSColor(calibratedRed: 0.31, green: 0.60, blue: 0.56, alpha: 0.18)
    static let accent = NSColor(calibratedRed: 0.20, green: 0.45, blue: 0.42, alpha: 1)
    static let foreground = NSColor(calibratedRed: 0.29, green: 0.28, blue: 0.26, alpha: 1)
    static let secondary = NSColor(calibratedRed: 0.45, green: 0.43, blue: 0.40, alpha: 1)
    static let terminalBackground = editor
    static let terminalForeground = foreground
}

enum AtelierTheme {
    static let accent = Color(nsColor: AtelierNativePalette.accent)
    static let accentInk = Color(nsColor: AtelierNativePalette.editor)
    static let chrome = Color(nsColor: AtelierNativePalette.chrome)
    static let canvas = Color(nsColor: AtelierNativePalette.canvas)
    static let sidebar = Color(nsColor: AtelierNativePalette.sidebar)
    static let panel = Color(nsColor: AtelierNativePalette.panel)
    static let raised = Color(nsColor: AtelierNativePalette.raised)
    static let editor = Color(nsColor: AtelierNativePalette.editor)
    static let code = editor
    static let tabInactive = Color(nsColor: AtelierNativePalette.tabInactive)
    static let border = Color(nsColor: AtelierNativePalette.border)
    static let codeCyan = Color(red: 0.00, green: 0.48, blue: 0.58)
    static let gitOrange = Color(red: 0.77, green: 0.31, blue: 0.15)
    static let panelRadius: CGFloat = 0
    static let controlRadius: CGFloat = 5
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
        introspect(.atelierSplitView, on: .macOS(.v13, .v14, .v15, .v26)) { splitView in
            splitView.dividerStyle = .thin
        }
    }

    func atelierScrollChrome(backgroundColor: NSColor) -> some View {
        introspect(.scrollView, on: .macOS(.v13, .v14, .v15, .v26)) { scrollView in
            scrollView.autohidesScrollers = true
            scrollView.borderType = .noBorder
            scrollView.drawsBackground = true
            scrollView.backgroundColor = backgroundColor
            scrollView.scrollerStyle = .overlay
        }
    }

    func atelierListChrome() -> some View {
        introspect(.list(style: .sidebar), on: .macOS(.v13, .v14, .v15, .v26)) { tableView in
            tableView.backgroundColor = AtelierNativePalette.sidebar
            tableView.gridStyleMask = []
            tableView.intercellSpacing = .zero
            tableView.enclosingScrollView?.autohidesScrollers = true
            tableView.enclosingScrollView?.borderType = .noBorder
            tableView.enclosingScrollView?.drawsBackground = true
            tableView.enclosingScrollView?.backgroundColor = AtelierNativePalette.sidebar
            tableView.enclosingScrollView?.scrollerStyle = .overlay
        }
    }

    func atelierWindowChrome() -> some View {
        introspect(.window, on: .macOS(.v13, .v14, .v15, .v26)) { window in
            window.backgroundColor = AtelierNativePalette.chrome
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
        }
    }
}

struct AtelierSplitViewType: IntrospectableViewType {}

extension IntrospectableViewType where Self == AtelierSplitViewType {
    static var atelierSplitView: Self { .init() }
}

extension macOSViewVersion<AtelierSplitViewType, NSSplitView> {
    static let v13 = Self(for: .v13)
    static let v14 = Self(for: .v14)
    static let v15 = Self(for: .v15)
    static let v26 = Self(for: .v26)
}
