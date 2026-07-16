import Pow
import SwiftUI

private struct AtelierRefreshCompletionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isLoading: Bool

    func body(content: Content) -> some View {
        content.changeEffect(
            .shine(duration: 0.45),
            value: isLoading,
            isEnabled: !reduceMotion && !isLoading
        )
    }
}

private struct AtelierGitErrorModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let errorMessage: String?

    func body(content: Content) -> some View {
        content.changeEffect(
            .shake,
            value: errorMessage,
            isEnabled: !reduceMotion && errorMessage != nil
        )
    }
}

private struct AtelierNewTerminalModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var previousSessionCount: Int?
    let sessionCount: Int

    init(sessionCount: Int) {
        self.sessionCount = sessionCount
    }

    func body(content: Content) -> some View {
        content.changeEffect(
            .jump(height: 4),
            value: sessionCount,
            isEnabled: !reduceMotion && sessionCount > (previousSessionCount ?? sessionCount)
        )
        .onAppear {
            previousSessionCount = sessionCount
        }
        .onChange(of: sessionCount) { _, newCount in
            previousSessionCount = newCount
        }
    }
}

extension View {
    func atelierRefreshCompletionEffect(isLoading: Bool) -> some View {
        modifier(AtelierRefreshCompletionModifier(isLoading: isLoading))
    }

    func atelierGitErrorEffect(value: String?) -> some View {
        modifier(AtelierGitErrorModifier(errorMessage: value))
    }

    func atelierNewTerminalEffect(sessionCount: Int) -> some View {
        modifier(AtelierNewTerminalModifier(sessionCount: sessionCount))
    }
}
