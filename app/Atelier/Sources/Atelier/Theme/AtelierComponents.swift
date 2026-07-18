import SwiftUI

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
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .atelierFont(size: AtelierTypography.label, weight: .semibold)
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
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AtelierTheme.border)
                .frame(height: AtelierTheme.strokeHairline)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Standard empty / loading / error state: centered, calm, one accent.
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
        VStack(spacing: AtelierMetrics.spaceS) {
            Image(systemName: systemImage)
                .atelierFont(size: AtelierMetrics.emptyStateIconSize, weight: .ultraLight)
                .foregroundStyle(AtelierTheme.accent)
            Text(title)
                .atelierFont(size: AtelierTypography.headline, weight: .semibold)
            Text(message)
                .atelierFont(size: AtelierTypography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: AtelierMetrics.emptyStateMaxWidth)
                .fixedSize(horizontal: false, vertical: true)
            accessory()
                .padding(.top, AtelierMetrics.spaceXS)
        }
        .padding(AtelierMetrics.spaceXL)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
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
            .foregroundStyle(AtelierTheme.accentInk)
            .frame(maxWidth: .infinity)
            .frame(height: AtelierMetrics.fieldHeight)
            .background {
                ZStack {
                    AtelierTheme.accent.opacity(isEnabled ? 1 : AtelierTheme.disabledOpacity)
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
            .opacity(isEnabled ? 1 : 0.7)
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
