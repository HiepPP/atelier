import Foundation
import Observation
import SwiftUI

/// TASK-005 - Terminal Guardian.
///
/// Feature builder: when a terminal command finishes with a non-zero exit code
/// (`handleCommandFinished(exitCode:)`), read the recent terminal output via
/// `services.readTerminalOutput(_:)`, then run ONE bounded read-only analysis
/// with `services.runBackground(_:)` and present it as a dismissible card. Keep
/// it read-only and cancellable; skip work when `services.isOllamaConfigured()`
/// is false and handle thrown transport errors. Gate the feature behind an
/// `@AppStorage(TerminalGuardianModel.settingsKey)` toggle in the view. Cancel
/// in-flight work in `cleanup()`. Render `EmptyView` while there is no card.
///
/// Edit ONLY this file. Do not modify GemmaSidecarModel, GemmaSidecarView, or any
/// shared file; if you need a shared change, return BLOCKED with the exact change.
@MainActor
@Observable
final class TerminalGuardianModel {
    static let settingsKey = "sidecar.terminalGuardian.enabled"

    /// Published diagnosis. `nil` means the card slot renders nothing.
    private(set) var card: TerminalGuardianCard?
    /// True while a diagnosis run is in flight. Drives the loading state and the
    /// single-run debounce.
    private(set) var isRunning = false

    private let services: SidecarServices
    private let defaults: UserDefaults
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Identifies the current run so a stale task's `defer` cannot wipe a newer
    /// run's handle after cancel/restart interleaving on the main actor.
    @ObservationIgnored private var currentRunID = 0

    init(services: SidecarServices, defaults: UserDefaults = .standard) {
        self.services = services
        self.defaults = defaults
    }

    /// Called on MainActor when a terminal command reports its exit code (OSC 133).
    /// Non-zero exits trigger one bounded, read-only diagnosis. Zero exits, a
    /// disabled toggle, an unreachable Ollama hint, or an already-running task are
    /// dropped so at most one Guardian run exists at a time.
    func handleCommandFinished(exitCode: Int32) {
        guard exitCode != 0 else { return }
        guard isGuardianEnabled else { return }
        guard services.isOllamaConfigured() else { return }
        guard task == nil else { return }
        startDiagnosis(exitCode: exitCode)
    }

    /// Hide the card and cancel any in-flight run. Never sends anything.
    func dismissCard() {
        task?.cancel()
        task = nil
        isRunning = false
        card = nil
    }

    /// Cancel in-flight work and clear state. Called when the sidecar stops.
    func cleanup() {
        task?.cancel()
        task = nil
        isRunning = false
        card = nil
    }

    /// Reads the persisted toggle. Absent key defaults to enabled so the guardian
    /// works on first run and stays consistent with the view's `@AppStorage`.
    private var isGuardianEnabled: Bool {
        guard defaults.object(forKey: Self.settingsKey) != nil else { return true }
        return defaults.bool(forKey: Self.settingsKey)
    }

    private func startDiagnosis(exitCode: Int32) {
        isRunning = true
        card = nil
        currentRunID &+= 1
        let runID = currentRunID
        AppLogger.agent.debug("Terminal guardian started a diagnosis")
        task = Task { [weak self] in
            guard let self else { return }
            defer {
                // Only clear if this run still owns the handle; a newer run that
                // started while this one was suspended must not be wiped.
                if self.currentRunID == runID {
                    self.isRunning = false
                    self.task = nil
                }
            }
            let output = await self.services.readTerminalOutput(200)
            if Task.isCancelled { return }
            guard let output,
                  !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            let prompt = Self.diagnosisPrompt(exitCode: exitCode, output: output)
            do {
                let text = try await self.services.runBackground(prompt)
                if Task.isCancelled { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                self.card = TerminalGuardianCard(exitCode: exitCode, message: trimmed)
            } catch {
                // Connection, cancellation, and transport errors stay quiet: no card.
            }
        }
    }

    private static func diagnosisPrompt(exitCode: Int32, output: String) -> String {
        let capped = String(output.suffix(8000))
        return """
        A terminal command just finished with a non-zero exit code (\(exitCode)). \
        The recent terminal output is between the markers below.

        --- terminal output ---
        \(capped)
        --- end output ---

        In 1-3 short sentences, diagnose the most likely cause of the failure. \
        Then suggest a single fix command inside a fenced code block. \
        Be concise and do not run anything.
        """
    }
}

/// A dismissible Guardian diagnosis published to the sidecar.
struct TerminalGuardianCard: Equatable {
    let exitCode: Int32
    let message: String
}

/// Feed card. Renders nothing until a diagnosis runs or completes, so it never
/// reserves space while idle. Never steals focus and is never modal. The enable
/// toggle lives in the sidecar's gear popover.
struct TerminalGuardianCardView: View {
    let model: TerminalGuardianModel

    var body: some View {
        if model.isRunning || model.card != nil {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
            header
            if let card = model.card {
                AgentMarkdownView(source: card.message)
                    .textSelection(.enabled)
            } else if model.isRunning {
                HStack(spacing: AtelierMetrics.spaceS) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Diagnosing the failed command...")
                        .atelierFont(size: AtelierTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(AtelierMetrics.spaceM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atelierCard(fill: AtelierTheme.danger.opacity(0.06))
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: AtelierMetrics.spaceS) {
            Image(systemName: "exclamationmark.triangle.fill")
                .atelierFont(size: AtelierTypography.label, weight: .medium)
                .foregroundStyle(AtelierTheme.danger)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Command failed")
                    .atelierFont(size: AtelierTypography.label, weight: .semibold)
                if let card = model.card {
                    Text("Exit code \(card.exitCode)")
                        .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Button {
                model.dismissCard()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(AtelierRowIconButtonStyle())
            .accessibilityLabel("Dismiss guardian diagnosis")
            .help("Dismiss")
        }
    }

}
