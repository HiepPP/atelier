import Luminare
import SwiftUI

private struct AtelierPointerCursorModifier: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    (isEnabled ? NSCursor.pointingHand : NSCursor.arrow).set()
                case .ended:
                    NSCursor.arrow.set()
                }
            }
            .onDisappear {
                NSCursor.arrow.set()
            }
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
                .atelierFont(size: 11, weight: .medium)
                .frame(minWidth: 24, minHeight: 24)
        }
        .buttonStyle(.luminareCompact)
        .foregroundStyle(Color.primary)
        .luminareTint(overridingWith: AtelierTheme.accent)
        .luminareMinHeight(24)
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
                .atelierFont(size: 11, weight: .semibold)
                .foregroundStyle(AtelierTheme.accentInk)
                .padding(.horizontal, 12)
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
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(height: 28)
            .modifier(LuminareFilledModifier(
                isHovering: isHovering,
                isPressed: configuration.isPressed,
                fill: Color.clear,
                hovering: AtelierTheme.accentInk.opacity(0.06),
                pressed: AtelierTheme.accentInk.opacity(0.12)
            ))
            .background(AtelierTheme.accent.opacity(isEnabled ? 1 : 0.42))
            .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
            .opacity(isEnabled ? 1 : 0.7)
            .onHover { isHovering in
                self.isHovering = isHovering
            }
            .animation(animationFast, value: isHovering)
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
                .padding(12)
                .frame(maxWidth: .infinity)
        }
        .background(AtelierTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AtelierTheme.controlRadius)
                .stroke(AtelierTheme.border, lineWidth: 0.75)
        }
    }
}

private struct AtelierLuminarePopoverContentModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(8)
            .background(AtelierTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
            .overlay {
                RoundedRectangle(cornerRadius: AtelierTheme.controlRadius)
                    .stroke(AtelierTheme.border, lineWidth: 0.75)
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
