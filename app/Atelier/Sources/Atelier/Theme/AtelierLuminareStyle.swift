import Luminare
import SwiftUI

private struct AtelierPointerCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .pointerStyle(isEnabled ? .link : .default)
    }
}

extension View {
    func atelierPointerCursor() -> some View {
        modifier(AtelierPointerCursorModifier())
    }
}

struct AtelierLuminareIconButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: configuration.trigger) {
            configuration.label
                .atelierFont(size: AtelierTypography.label, weight: .medium)
                .frame(
                    minWidth: AtelierMetrics.iconButtonSize,
                    minHeight: AtelierMetrics.iconButtonSize
                )
        }
        .buttonStyle(.luminareCompact)
        .foregroundStyle(Color.primary)
        .luminareTint(overridingWith: AtelierTheme.accent)
        .luminareMinHeight(AtelierMetrics.iconButtonSize)
        .luminareHorizontalPadding(0)
        .luminareAspectRatio(1, contentMode: .fit)
        .luminareCompactButtonCornerRadius(AtelierTheme.controlRadius)
        .luminareButtonMaterial(nil)
        .luminareBordered(false)
        .atelierPointerCursor()
    }
}

struct AtelierLuminarePrimaryButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(action: configuration.trigger) {
            configuration.label
                .atelierFont(size: AtelierTypography.label, weight: .semibold)
                .padding(.horizontal, AtelierMetrics.spaceM)
        }
        .buttonStyle(AtelierLuminarePrimaryButtonBodyStyle())
        .fixedSize(horizontal: true, vertical: false)
        .luminareButtonMaterial(nil)
        .atelierPointerCursor()
    }
}

private struct AtelierLuminarePrimaryButtonBodyStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.luminareAnimationFast) private var animationFast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: AtelierMetrics.fieldHeight)
            .modifier(LuminareFilledModifier(
                isHovering: isHovering,
                isPressed: configuration.isPressed,
                fill: Color.clear,
                hovering: AtelierTheme.accentInk.opacity(0.06),
                pressed: AtelierTheme.accentInk.opacity(0.12)
            ))
            .background(
                isEnabled ? AtelierTheme.accent : AtelierTheme.raised
            )
            .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
            .foregroundStyle(isEnabled ? AtelierTheme.accentInk : Color.secondary)
            .opacity(1)
            .onHover { isHovering in
                self.isHovering = isHovering
            }
            .animation(reduceMotion ? nil : animationFast, value: isHovering)
    }
}

struct AtelierLuminareSection<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        LuminareSection(hasPadding: false, outerPadding: 0, content: content)
            .luminareSectionLayout(.stacked)
            .luminareSectionMaterial(nil)
            .luminareCornerRadius(AtelierTheme.controlRadius)
            .luminareBordered(false)
            .luminareHasDividers(false)
            .luminareTint(overridingWith: AtelierTheme.accent)
    }
}

struct AtelierStatusCard<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        AtelierLuminareSection {
            content()
                .padding(AtelierMetrics.spaceM)
                .frame(maxWidth: .infinity)
        }
        .background(AtelierTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AtelierTheme.controlRadius)
                .stroke(AtelierTheme.border, lineWidth: AtelierTheme.strokeControl)
        }
    }
}

private struct AtelierLuminarePopoverContentModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(AtelierMetrics.spaceS)
            .background(AtelierTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AtelierTheme.controlRadius)
                    .stroke(AtelierTheme.border, lineWidth: AtelierTheme.strokeControl)
            }
            .luminareSectionMaterial(nil)
            .luminareButtonMaterial(nil)
            .luminareTint(overridingWith: AtelierTheme.accent)
    }
}

extension View {
    func atelierLuminarePopoverContent() -> some View {
        modifier(AtelierLuminarePopoverContentModifier())
    }
}
