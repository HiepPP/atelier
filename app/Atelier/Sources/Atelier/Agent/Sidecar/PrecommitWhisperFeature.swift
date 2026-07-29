import Foundation
import Observation
import SwiftUI

/// TASK-009 - Pre-commit Whisper.
///
/// A quiet, read-only advisory. On each `tick()` (driven ~every 45s by the
/// sidecar) it reads the unstaged diff via `services.unstagedDiff()`. When the
/// diff changes it debounces a few seconds, then runs ONE bounded
/// `services.runBackground(_:)` call asking Gemma for findings in four
/// categories only: debug print, new TODO, secret-like string, commented-out
/// code - each naming file and line. Findings surface as a badge that expands
/// to a list. No findings -> no badge (the view renders nothing).
///
/// Safety: read-only, cancellable, advisory (never blocks a commit). Only one
/// scan runs at a time; a newer diff cancels the running scan. Scans are skipped
/// when the diff is empty or Ollama is unreachable, and thrown transport errors
/// are swallowed quietly. Diff content is never logged. Secret-like values are
/// redacted to their first four characters before they are ever stored for the
/// UI.
///
/// Edit ONLY this file. Do not modify GemmaSidecarModel, GemmaSidecarView, or any
/// shared file; if you need a shared change, return BLOCKED with the exact change.

// MARK: - Finding model

/// One advisory note produced by a whisper scan. `detail` is already redacted for
/// secret findings, so full secret values never live in observable state.
nonisolated struct PrecommitFinding: Identifiable, Equatable, Sendable {
    nonisolated enum Category: String, Equatable, Sendable, CaseIterable {
        case debugPrint
        case todo
        case secret
        case commentedCode

        var title: String {
            switch self {
            case .debugPrint: "Debug print"
            case .todo: "TODO"
            case .secret: "Secret"
            case .commentedCode: "Commented code"
            }
        }

        var systemImage: String {
            switch self {
            case .debugPrint: "terminal"
            case .todo: "checklist.unchecked"
            case .secret: "key.fill"
            case .commentedCode: "text.append"
            }
        }
    }

    let id: String
    let category: Category
    let file: String
    let line: Int?
    let detail: String
}

// MARK: - Model

@MainActor
@Observable
final class PrecommitWhisperModel {
    /// Seconds to wait after a diff change before scanning, so quick edits settle.
    /// Injectable so tests can exercise the debounce without a wall-clock wait.
    private let debounceSeconds: Double

    /// Findings from the most recent completed scan. Empty means no badge.
    private(set) var findings: [PrecommitFinding] = []

    /// True while a background scan is in flight. UI hint only.
    private(set) var isScanning = false

    private let services: SidecarServices

    // Change-detection bookkeeping.
    private var currentTargetFingerprint: String?
    private var lastHandledFingerprint: String?

    /// True while a tick's diff check is in flight. Read-only outside so tests
    /// can sequence on check completion instead of wall-clock sleeps.
    private(set) var isChecking = false

    private var checkTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?

    init(services: SidecarServices, debounceSeconds: Double = 4) {
        self.services = services
        self.debounceSeconds = debounceSeconds
    }

    /// Reads the diff (off the main actor) and decides whether to scan. Guards
    /// against overlapping checks and skips entirely when Ollama looks
    /// unreachable.
    func tick() {
        guard services.isOllamaConfigured() else { return }
        guard !isChecking else { return }
        isChecking = true
        checkTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isChecking = false }
            let diff = await self.services.unstagedDiff()
            guard !Task.isCancelled else { return }
            self.handle(diff: diff)
        }
    }

    /// Cancels any in-flight work and clears advisory state. Called on stop/close.
    func cleanup() {
        checkTask?.cancel()
        checkTask = nil
        cancelScan()
        findings = []
        currentTargetFingerprint = nil
        lastHandledFingerprint = nil
    }

    private func handle(diff: String) {
        let (action, fingerprint) = PrecommitWhisperDecision.evaluate(
            diff: diff,
            currentTarget: currentTargetFingerprint,
            lastHandled: lastHandledFingerprint
        )
        switch action {
        case .skip:
            break
        case .clear:
            cancelScan()
            if !findings.isEmpty { findings = [] }
            currentTargetFingerprint = nil
            lastHandledFingerprint = fingerprint
        case .scan:
            cancelScan()
            currentTargetFingerprint = fingerprint
            let bounded = PrecommitWhisperDecision.bound(diff)
            let debounce = debounceSeconds
            scanTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(debounce))
                guard !Task.isCancelled, let self else { return }
                await self.runScan(diff: bounded, fingerprint: fingerprint)
            }
        }
    }

    private func runScan(diff: String, fingerprint: String) async {
        isScanning = true
        defer { isScanning = false }
        do {
            let prompt = PrecommitWhisperPrompt.build(diff: diff)
            let output = try await services.runBackground(prompt)
            try Task.checkCancellation()
            findings = PrecommitWhisperParser.parse(output)
            lastHandledFingerprint = fingerprint
            if currentTargetFingerprint == fingerprint { currentTargetFingerprint = nil }
        } catch {
            // Superseded by a newer diff (which owns the state), preempted by
            // another feature's background run, or a transport error: release
            // the fingerprint unless a newer scan took ownership, so a later
            // tick can rescan. Findings stay for the surviving scan to replace.
            if currentTargetFingerprint == fingerprint { currentTargetFingerprint = nil }
        }
    }

    private func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }
}

// MARK: - Pure decision logic

/// Deterministic change detection and bounding. Pure so it is unit-testable
/// without a runtime.
nonisolated enum PrecommitWhisperDecision {
    nonisolated enum Action: Equatable, Sendable {
        case skip
        case clear
        case scan
    }

    static let emptyFingerprint = "empty"
    static let maxDiffChars = 16_000

    static func evaluate(
        diff: String,
        currentTarget: String?,
        lastHandled: String?
    ) -> (action: Action, fingerprint: String) {
        let trimmed = diff.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if lastHandled == emptyFingerprint { return (.skip, emptyFingerprint) }
            return (.clear, emptyFingerprint)
        }
        let fp = fingerprint(diff)
        if fp == currentTarget { return (.skip, fp) }
        if fp == lastHandled { return (.skip, fp) }
        return (.scan, fp)
    }

    /// Length-prefixed FNV-1a hash. Deterministic within and across processes so
    /// the same diff always maps to the same fingerprint.
    static func fingerprint(_ diff: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in diff.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return "\(diff.utf8.count):\(String(hash, radix: 16))"
    }

    static func bound(_ diff: String) -> String {
        guard diff.count > maxDiffChars else { return diff }
        return String(diff.prefix(maxDiffChars))
    }
}

// MARK: - Prompt

/// Builds the one-shot review prompt. Kept pure so tests can assert the four
/// categories and the strict output contract are present.
nonisolated enum PrecommitWhisperPrompt {
    static func build(diff: String) -> String {
        """
        You are a quiet pre-commit reviewer. Review ONLY the unified diff below \
        and report leftover issues a developer would want to catch before \
        committing. Consider EXACTLY these four categories and nothing else:
        - DEBUG_PRINT: leftover debug prints or logging added in this diff.
        - TODO: new TODO or FIXME comments added in this diff.
        - SECRET: hard-coded secret-like strings (API keys, tokens, passwords).
        - COMMENTED_CODE: blocks of real code commented out in this diff.

        Output one finding per line using EXACTLY this format:
        CATEGORY | path:line | short detail
        where CATEGORY is one of DEBUG_PRINT, TODO, SECRET, COMMENTED_CODE and \
        path:line comes from the diff hunk headers. For SECRET, include the \
        offending value in the detail. If there are no findings, output the \
        single word NONE. Do not add any other text, headings, or explanation.

        Diff:
        \(diff)
        """
    }
}

// MARK: - Parser + redaction

/// Parses the model output into findings and redacts secret-like values. Pure and
/// deterministic for testing.
nonisolated enum PrecommitWhisperParser {
    static let maxFindings = 50
    static let maxDetailChars = 240

    static func parse(_ output: String) -> [PrecommitFinding] {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.uppercased() != "NONE" else { return [] }

        var results: [PrecommitFinding] = []
        for raw in output.split(whereSeparator: { $0.isNewline }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.uppercased() == "NONE" { continue }

            let parts = line.components(separatedBy: "|").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count >= 2, let category = category(from: parts[0]) else { continue }

            let (file, lineNumber) = splitLocation(parts[1])
            var detail = parts.count >= 3
                ? parts[2...].joined(separator: " | ")
                : ""
            // A SECRET finding names a value the model already flagged, so mask it
            // unconditionally; a plain word like `letmein` must never be shown in
            // full. Other categories only mask tokens that look secret-like.
            detail = category == .secret
                ? redactAllTokens(in: detail)
                : redactSecrets(in: detail)
            if detail.count > maxDetailChars {
                detail = String(detail.prefix(maxDetailChars))
            }

            let index = results.count
            results.append(
                PrecommitFinding(
                    id: "\(index)-\(category.rawValue)-\(file):\(lineNumber ?? -1)",
                    category: category,
                    file: file,
                    line: lineNumber,
                    detail: detail
                )
            )
            if results.count >= maxFindings { break }
        }
        return results
    }

    static func category(from token: String) -> PrecommitFinding.Category? {
        let upper = token.uppercased()
        if upper.contains("DEBUG") { return .debugPrint }
        if upper.contains("TODO") || upper.contains("FIXME") { return .todo }
        if upper.contains("SECRET") { return .secret }
        if upper.contains("COMMENT") { return .commentedCode }
        return nil
    }

    static func splitLocation(_ location: String) -> (file: String, line: Int?) {
        let value = location.trimmingCharacters(in: .whitespaces)
        guard let colon = value.lastIndex(of: ":") else { return (value, nil) }
        let filePart = String(value[value.startIndex..<colon])
        let linePart = String(value[value.index(after: colon)...])
        if let number = Int(linePart.trimmingCharacters(in: .whitespaces)), !filePart.isEmpty {
            return (filePart, number)
        }
        return (value, nil)
    }

    /// Unconditionally masks every token of length >= 4 to its first four
    /// characters plus a mask. Used for SECRET findings, where the flagged value
    /// must always be hidden even if it is a short, all-lowercase word.
    static func redactAllTokens(in text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = ""
        var token = ""
        func flush() {
            guard !token.isEmpty else { return }
            result += token.count >= 4 ? redactToken(token) : token
            token = ""
        }
        for character in text {
            if isTokenCharacter(character) {
                token.append(character)
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return result
    }

    /// Replaces secret-like tokens with their first four characters plus a mask.
    static func redactSecrets(in text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = ""
        var token = ""
        func flush() {
            guard !token.isEmpty else { return }
            result += isSecretLike(token) ? redactToken(token) : token
            token = ""
        }
        for character in text {
            if isTokenCharacter(character) {
                token.append(character)
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return result
    }

    static func isTokenCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber ||
            character == "_" || character == "-" || character == "+" ||
            character == "/" || character == "=" || character == "."
    }

    static func isSecretLike(_ token: String) -> Bool {
        guard token.count >= 6 else { return false }
        let hasLetter = token.contains { $0.isLetter }
        let hasDigit = token.contains { $0.isNumber }
        if hasLetter && hasDigit { return true }
        if token.count >= 20 { return true }
        let prefixes = ["sk_", "pk_", "ghp_", "gho_", "xox", "AKIA", "AIza"]
        return prefixes.contains { token.hasPrefix($0) }
    }

    static func redactToken(_ token: String) -> String {
        String(token.prefix(4)) + "****"
    }
}

// MARK: - View

/// Advisory pre-commit banner. Renders nothing when there are no findings, so it
/// never disturbs the sidecar layout. Expanding lists the findings.
struct PrecommitWhisperView: View {
    let model: PrecommitWhisperModel
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !model.findings.isEmpty {
            VStack(spacing: 0) {
                summaryRow
                if isExpanded {
                    findingList
                }
            }
            .atelierCard()
        }
    }

    private var summaryRow: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: AtelierMetrics.spaceS) {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .atelierFont(size: AtelierTypography.label, weight: .medium)
                    .foregroundStyle(AtelierTheme.gitOrange)
                Text("Pre-commit notes")
                    .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                AtelierCountBadge(value: model.findings.count, color: AtelierTheme.gitOrange)
                if model.isScanning {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .atelierFont(size: AtelierTypography.micro, weight: .semibold)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AtelierMetrics.spaceM)
        .padding(.vertical, AtelierMetrics.spaceS)
        .atelierPointerCursor()
        .accessibilityLabel("Pre-commit notes, \(model.findings.count) advisory")
        .accessibilityHint("Read-only. Expand to review findings.")
    }

    private var findingList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
                ForEach(model.findings) { finding in
                    findingRow(finding)
                }
            }
            .padding(.horizontal, AtelierMetrics.spaceM)
            .padding(.bottom, AtelierMetrics.spaceS)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 180)
    }

    private func findingRow(_ finding: PrecommitFinding) -> some View {
        HStack(alignment: .top, spacing: AtelierMetrics.spaceS) {
            Image(systemName: finding.category.systemImage)
                .atelierFont(size: AtelierTypography.caption, weight: .medium)
                .foregroundStyle(tint(for: finding.category))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: AtelierMetrics.spaceXS) {
                    Text(finding.category.title)
                        .atelierFont(size: AtelierTypography.caption, weight: .semibold)
                        .foregroundStyle(tint(for: finding.category))
                    Text(locationText(finding))
                        .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if !finding.detail.isEmpty {
                    Text(finding.detail)
                        .atelierFont(size: AtelierTypography.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(AtelierMetrics.spaceS)
        .atelierCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(finding.category.title) at \(locationText(finding)). \(finding.detail)")
    }

    private func locationText(_ finding: PrecommitFinding) -> String {
        if let line = finding.line { return "\(finding.file):\(line)" }
        return finding.file
    }

    private func tint(for category: PrecommitFinding.Category) -> Color {
        switch category {
        case .secret: AtelierTheme.danger
        default: AtelierTheme.gitOrange
        }
    }
}
