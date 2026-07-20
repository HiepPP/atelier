import Foundation
import Observation
import SwiftUI

/// TASK-008 - Intent Guard.
///
/// The user states a one-line intent for the current work. When set, each
/// `tick()` (~ every tick interval) refreshes the changed-file set and, at most
/// every few minutes after meaningful diff growth, runs ONE bounded read-only
/// `services.runBackground(_:)` call asking which changed files do not serve the
/// intent. Out-of-scope files surface as a quiet advisory row; dismissing
/// suppresses the row until the changed-file set changes again. An empty intent
/// disables the feature completely: no checks, no background calls. The check is
/// cancellable and skipped when `services.isOllamaConfigured()` is false; thrown
/// transport errors are swallowed and never block the UI.
///
/// Edit ONLY this file. Do not modify GemmaSidecarModel, GemmaSidecarView, or any
/// shared file; if you need a shared change, return BLOCKED with the exact change.

/// An advisory naming changed files that appear to drift from the stated intent.
/// Carries the changed-file-set signature it was computed for so a stale row can
/// be hidden once the working tree moves on.
nonisolated struct IntentGuardWarning: Equatable, Sendable {
    let signature: String
    let files: [String]

    var headline: String {
        files.count == 1
            ? "1 changed file may not serve your intent"
            : "\(files.count) changed files may not serve your intent"
    }
}

/// Pure, deterministic gating and parsing helpers. Kept isolation-free so the
/// drift logic can be unit tested without a runtime or a live model.
nonisolated enum IntentGuardPolicy {
    /// Minimum spacing between background checks. `tick()` fires far more often;
    /// this keeps the feature to at most one call every few minutes.
    static let minInterval: TimeInterval = 180
    /// Added insertions + deletions (from `git diff --stat`) required to treat an
    /// unchanged file set as meaningfully grown since the last check.
    static let growthThreshold = 8

    /// Empty or whitespace-only intent disables every check.
    static func isActive(intent: String) -> Bool {
        !intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Order-independent signature of the changed-file set.
    static func signature(for files: [String]) -> String {
        Set(files).sorted().joined(separator: "\n")
    }

    /// A dismissed warning suppresses the row until the file set changes.
    static func isSuppressed(signature: String, dismissedSignature: String?) -> Bool {
        signature == dismissedSignature
    }

    /// Returns the dismissal that should remain in effect for the current set:
    /// keeps it while the set is unchanged, clears it once the set moves on.
    static func liftedDismissal(current: String, dismissed: String?) -> String? {
        guard let dismissed else { return nil }
        return dismissed == current ? dismissed : nil
    }

    static func cadenceElapsed(now: Date, lastRun: Date?, minInterval: TimeInterval) -> Bool {
        guard let lastRun else { return true }
        return now.timeIntervalSince(lastRun) >= minInterval
    }

    /// True when there is enough new work to justify another check: a non-empty
    /// set that was never checked, a changed set, or enough added volume.
    static func hasMeaningfulGrowth(
        currentSignature: String,
        lastSignature: String?,
        currentVolume: Int,
        lastVolume: Int,
        growthThreshold: Int
    ) -> Bool {
        guard !currentSignature.isEmpty else { return false }
        guard let lastSignature else { return true }
        if lastSignature != currentSignature { return true }
        return (currentVolume - lastVolume) >= growthThreshold
    }

    /// Total insertions + deletions parsed from a `git diff --stat` summary line.
    static func changeVolume(fromDiffStat stat: String) -> Int {
        let tokens = stat
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "," })
            .map(String.init)
        var total = 0
        for index in tokens.indices where index > 0 {
            let token = tokens[index]
            if token.hasPrefix("insertion") || token.hasPrefix("deletion") {
                if let count = Int(tokens[index - 1]) { total += count }
            }
        }
        return total
    }

    static func prompt(intent: String, files: [String], diffStat: String) -> String {
        let fileList = files.map { "- \($0)" }.joined(separator: "\n")
        return """
        [Intent Guard]
        The developer stated this intent for the current work:
        "\(intent)"

        These files changed in the working tree:
        \(fileList)

        Change summary (git diff --stat):
        \(diffStat)

        List only the changed file paths above that clearly do NOT serve the \
        stated intent, one path per line, copied exactly. If every changed file \
        plausibly serves the intent, reply with the single word NONE. Do not \
        explain.
        """
    }

    /// Maps a background response back onto the known changed files. Treats a bare
    /// "NONE" as no drift; otherwise flags each changed file the model echoed,
    /// preserving the original order. Matches whole trimmed lines and their
    /// whitespace-separated tokens so a longer path (e.g. "a/b/Package.swift")
    /// never flags a shorter one ("Package.swift") by substring collision.
    static func parseOutOfScope(response: String, changedFiles: [String]) -> [String] {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.range(of: #"^none[.!]?$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return []
        }
        var echoed = Set<String>()
        for line in response.split(whereSeparator: { $0.isNewline }) {
            let cleaned = line.trimmingCharacters(in: .whitespaces)
            guard !cleaned.isEmpty else { continue }
            echoed.insert(cleaned)
            for token in cleaned.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                echoed.insert(String(token))
            }
        }
        return changedFiles.filter { echoed.contains($0) }
    }
}

@MainActor
@Observable
final class IntentGuardModel {
    /// User-entered one-line intent. Empty disables the feature.
    var intent: String = ""

    private let services: SidecarServices

    private var warning: IntentGuardWarning?
    private var dismissedSignature: String?
    private var currentSignature: String = ""
    private var lastSignature: String?
    private var lastVolume: Int = 0
    private var lastRun: Date?
    private var checkTask: Task<Void, Never>?

    init(services: SidecarServices) {
        self.services = services
    }

    /// The warning to display, if any: non-empty, matching the current file set,
    /// and not currently dismissed.
    var activeWarning: IntentGuardWarning? {
        guard let warning, !warning.files.isEmpty else { return nil }
        guard warning.signature == currentSignature else { return nil }
        guard !IntentGuardPolicy.isSuppressed(
            signature: warning.signature,
            dismissedSignature: dismissedSignature
        ) else { return nil }
        return warning
    }

    /// Suppresses the current advisory until the changed-file set changes again.
    func dismissWarning() {
        if let warning { dismissedSignature = warning.signature }
        warning = nil
    }

    func tick() {
        guard IntentGuardPolicy.isActive(intent: intent) else {
            resetForDisabledIntent()
            return
        }
        guard checkTask == nil else { return }
        let statedIntent = intent.trimmingCharacters(in: .whitespacesAndNewlines)
        checkTask = Task { [weak self] in
            guard let self else { return }
            await self.evaluate(statedIntent: statedIntent)
        }
    }

    private func resetForDisabledIntent() {
        // Only cancel; `evaluate`'s `defer` is the sole owner that clears the
        // handle, so an in-flight run can never be replaced mid-unwind.
        checkTask?.cancel()
        warning = nil
        dismissedSignature = nil
        currentSignature = ""
        lastSignature = nil
        lastVolume = 0
        lastRun = nil
    }

    private func evaluate(statedIntent: String) async {
        defer { checkTask = nil }

        let files = await services.changedFiles()
        let signature = IntentGuardPolicy.signature(for: files)
        currentSignature = signature
        dismissedSignature = IntentGuardPolicy.liftedDismissal(
            current: signature,
            dismissed: dismissedSignature
        )
        if let current = warning, current.signature != signature { warning = nil }

        guard !files.isEmpty else {
            lastSignature = signature
            return
        }
        guard services.isOllamaConfigured() else { return }
        guard !IntentGuardPolicy.isSuppressed(
            signature: signature,
            dismissedSignature: dismissedSignature
        ) else { return }

        let now = Date()
        guard IntentGuardPolicy.cadenceElapsed(
            now: now,
            lastRun: lastRun,
            minInterval: IntentGuardPolicy.minInterval
        ) else { return }

        let diffStat = await services.diffStat()
        let volume = IntentGuardPolicy.changeVolume(fromDiffStat: diffStat)
        guard IntentGuardPolicy.hasMeaningfulGrowth(
            currentSignature: signature,
            lastSignature: lastSignature,
            currentVolume: volume,
            lastVolume: lastVolume,
            growthThreshold: IntentGuardPolicy.growthThreshold
        ) else { return }

        // Record the attempt time so a failed call still respects cadence.
        lastRun = now
        let prompt = IntentGuardPolicy.prompt(
            intent: statedIntent,
            files: files,
            diffStat: diffStat
        )
        do {
            let response = try await services.runBackground(prompt)
            try Task.checkCancellation()
            guard IntentGuardPolicy.isActive(intent: intent) else { return }
            let flagged = IntentGuardPolicy.parseOutOfScope(
                response: response,
                changedFiles: files
            )
            // Commit baselines only on success so failures retry once reachable.
            lastSignature = signature
            lastVolume = volume
            warning = flagged.isEmpty
                ? nil
                : IntentGuardWarning(signature: signature, files: flagged)
        } catch {
            // Transport error or cancellation: stay quiet, keep baselines so the
            // next reachable tick can retry the same growth.
        }
    }

    isolated deinit {
        checkTask?.cancel()
    }
}

/// Feed card. Renders nothing while there is no active drift warning. The intent
/// itself is edited through the sidecar header's intent chip popover.
struct IntentGuardWarningCard: View {
    let model: IntentGuardModel

    var body: some View {
        if let warning = model.activeWarning {
            warningCard(warning)
        }
    }

    private func warningCard(_ warning: IntentGuardWarning) -> some View {
        HStack(alignment: .top, spacing: AtelierMetrics.spaceS) {
            Image(systemName: "exclamationmark.triangle.fill")
                .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                .foregroundStyle(AtelierTheme.gitOrange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(warning.headline)
                    .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Text(warning.files.joined(separator: ", "))
                    .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                model.dismissWarning()
            } label: {
                Image(systemName: "xmark")
                    .atelierFont(size: AtelierTypography.micro, weight: .semibold)
            }
            .buttonStyle(AtelierGhostButtonStyle())
            .accessibilityLabel("Dismiss intent warning")
            .help("Dismiss")
        }
        .padding(AtelierMetrics.spaceS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .atelierCard(fill: AtelierTheme.gitOrange.opacity(0.08))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(warning.headline): \(warning.files.joined(separator: ", "))"
        )
    }
}
