import SwiftUI

private struct AtelierGlassControlModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(
                    isSelected ? AtelierTheme.selection : AtelierTheme.raised,
                    in: RoundedRectangle(
                        cornerRadius: AtelierTheme.controlRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: AtelierTheme.controlRadius,
                        style: .continuous
                    )
                    .stroke(
                        isSelected ? AtelierTheme.accent : AtelierTheme.border,
                        lineWidth: contrast == .increased ? 1.5 : AtelierTheme.strokeControl
                    )
                }
        } else {
            content.glassEffect(
                .regular
                    .tint(isSelected ? AtelierTheme.accent.opacity(0.16) : nil)
                    .interactive(),
                in: RoundedRectangle(
                    cornerRadius: AtelierTheme.controlRadius,
                    style: .continuous
                )
            )
        }
    }
}

extension View {
    func atelierGlassControl(isSelected: Bool = false) -> some View {
        modifier(AtelierGlassControlModifier(isSelected: isSelected))
    }
}

/// Standard panel header: icon, title, optional mono subtitle, trailing controls.
/// One height, one background, one hairline for every panel in the app.
struct AtelierPanelHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: AtelierMetrics.spaceS) {
            if let systemImage {
                Image(systemName: systemImage)
                    .atelierFont(size: AtelierTypography.label, weight: .medium)
                    .foregroundStyle(AtelierTheme.accent)
                    .frame(width: 26, height: 26)
                    .background(AtelierTheme.accent.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.rowRadius))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .atelierFont(
                        size: AtelierTypography.headline,
                        weight: .semibold,
                        design: .serif
                    )
                if let subtitle {
                    Text(subtitle)
                        .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: AtelierMetrics.spaceS)

            trailing()
        }
        .padding(.horizontal, AtelierMetrics.spaceM)
        .frame(height: AtelierMetrics.panelHeaderHeight)
        .background(AtelierTheme.chrome)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.28))
                .frame(height: AtelierTheme.strokeHairline)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(height: AtelierTheme.strokeHairline)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Standard empty / loading / error state: calm editorial hierarchy, one accent.
struct AtelierEmptyState<Accessory: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var accessory: () -> Accessory

    init(
        systemImage: String,
        title: String,
        message: String,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.accessory = accessory
    }

    var body: some View {
        VStack(spacing: AtelierMetrics.spaceM) {
            ZStack {
                RoundedRectangle(cornerRadius: AtelierTheme.panelRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AtelierTheme.accent.opacity(0.20),
                                AtelierTheme.accent.opacity(0.07)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: systemImage)
                    .atelierFont(size: AtelierMetrics.emptyStateIconSize, weight: .light)
                    .foregroundStyle(AtelierTheme.accent)
            }
            .frame(width: 54, height: 54)
            .overlay {
                RoundedRectangle(cornerRadius: AtelierTheme.panelRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: AtelierTheme.strokeHairline)
            }
            .shadow(color: AtelierTheme.shadowSoft, radius: 7, y: 3)
            Text(title)
                .atelierFont(
                    size: AtelierTypography.title,
                    weight: .semibold,
                    design: .serif
                )
            Text(message)
                .atelierFont(size: AtelierTypography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: AtelierMetrics.emptyStateMaxWidth)
                .fixedSize(horizontal: false, vertical: true)
            accessory()
                .padding(.top, AtelierMetrics.spaceXS)
        }
        .padding(AtelierMetrics.space2XL)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

struct AtelierToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .atelierFont(size: AtelierTypography.label, weight: .medium)
            .frame(width: AtelierMetrics.iconButtonSize, height: AtelierMetrics.iconButtonSize)
            .foregroundStyle(isSelected ? AtelierTheme.accent : Color.primary)
            .atelierGlassControl(isSelected: isSelected)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Capsule()
                        .fill(AtelierTheme.accent)
                        .frame(width: 10, height: 2)
                        .padding(.bottom, 3)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: AtelierTheme.controlRadius))
            .opacity(isEnabled ? 1 : AtelierTheme.disabledOpacity)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.96)
            .atelierPointerCursor()
    }
}

struct AtelierCountBadge: View {
    let value: Int
    var color = AtelierTheme.accent

    var body: some View {
        Text(value.formatted())
            .atelierFont(size: AtelierTypography.micro, weight: .bold, design: .monospaced)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .frame(minHeight: 18)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: AtelierTheme.rowRadius))
            .accessibilityLabel("\(value) items")
    }
}

private struct AtelierOverlayPanelModifier: ViewModifier {
    let edge: Edge

    func body(content: Content) -> some View {
        content
            .background(AtelierTheme.panel)
            .overlay(alignment: edge == .leading ? .trailing : .leading) {
                Rectangle()
                    .fill(AtelierTheme.border)
                    .frame(width: AtelierTheme.strokeControl)
            }
            .shadow(
                color: AtelierTheme.shadowSoft,
                radius: 4,
                x: edge == .leading ? 1 : -1
            )
    }
}

extension View {
    func atelierOverlayPanel(edge: Edge) -> some View {
        modifier(AtelierOverlayPanelModifier(edge: edge))
    }
}

/// Quiet text button for inline actions (Stop, Clear, Copy, Open, View source).
/// Full state cycle: default, hover fill, pressed fill, disabled fade.
struct AtelierGhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var tint: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .atelierFont(size: AtelierTypography.caption, weight: .medium)
            .foregroundStyle(isEnabled ? tint : .secondary)
            .padding(.horizontal, AtelierMetrics.spaceS)
            .frame(height: AtelierMetrics.compactControlHeight)
            .background {
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                    .fill(AtelierTheme.controlFill(for: interactionState(configuration)))
            }
            .contentShape(
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
            )
            .opacity(AtelierTheme.controlOpacity(for: interactionState(configuration)))
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.98)
            .onHover { isHovering = $0 }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: isHovering
            )
            .atelierPointerCursor()
    }

    private func interactionState(_ configuration: Configuration) -> AtelierInteractionState {
        if !isEnabled { return .disabled }
        if configuration.isPressed { return .pressed }
        if isHovering { return .hovered }
        return .normal
    }
}

/// Filled accent button that stretches to its container (commit, pinned CTAs).
struct AtelierFilledButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .atelierFont(size: AtelierTypography.label, weight: .semibold)
            .foregroundStyle(isEnabled ? AtelierTheme.accentInk : Color.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: AtelierMetrics.fieldHeight)
            .background {
                ZStack {
                    isEnabled ? AtelierTheme.accent : AtelierTheme.raised
                    if configuration.isPressed {
                        AtelierTheme.accentInk.opacity(0.12)
                    } else if isHovering && isEnabled {
                        AtelierTheme.accentInk.opacity(0.06)
                    }
                }
            }
            .clipShape(
                RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: AtelierTheme.controlRadius, style: .continuous)
            )
            .opacity(1)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.985)
            .onHover { isHovering = $0 }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: isHovering
            )
            .atelierPointerCursor()
    }
}

/// Small icon action used inside rows with rounded hover and press feedback.
struct AtelierRowIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .atelierFont(size: AtelierTypography.caption, weight: .medium)
            .frame(
                width: AtelierMetrics.compactControlHeight,
                height: AtelierMetrics.compactControlHeight
            )
            .background {
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
                    .fill(AtelierTheme.controlFill(for: interactionState(configuration)))
            }
            .contentShape(
                RoundedRectangle(cornerRadius: AtelierTheme.rowRadius, style: .continuous)
            )
            .opacity(AtelierTheme.controlOpacity(for: interactionState(configuration)))
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.96)
            .onHover { isHovering = $0 }
            .atelierPointerCursor()
    }

    private func interactionState(_ configuration: Configuration) -> AtelierInteractionState {
        if !isEnabled { return .disabled }
        if configuration.isPressed { return .pressed }
        if isHovering { return .hovered }
        return .normal
    }
}
