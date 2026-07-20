import AppKit
import Foundation
import Observation
import SwiftUI

/// TASK-007 - Session Journal.
///
/// Keeps a rolling, read-only summary of the session. `tick()` is called by the
/// sidecar's periodic timer; it accumulates elapsed active time and, once a
/// bounded interval of activity has passed, runs ONE serialized
/// `services.runBackground(_:)` call built from `services.diffStat()`,
/// `services.changedFiles()`, and `services.readTerminalOutput(_:)`, asking for a
/// 1-2 line entry describing what happened since the last entry. Entries are held
/// in memory only and cleared on workspace close via `cleanup()`. Cycles are
/// skipped when nothing changed since the last entry, when a request is already
/// running, when the feature is disabled, or when Ollama is unreachable. Thrown
/// transport/cancellation errors are swallowed silently (no entry, no error UI).
///
/// Edit ONLY this file. Do not modify GemmaSidecarModel, GemmaSidecarView, or any
/// shared file; if you need a shared change, return BLOCKED with the exact change.

/// A single timestamped journal line. Value type so it is cheap to diff and copy.
nonisolated struct SessionJournalEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let text: String

    init(id: UUID = UUID(), timestamp: Date, text: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
    }
}

@MainActor
@Observable
final class SessionJournalModel {
    static let settingsKey = "sidecar.sessionJournal.enabled"

    /// Interval of accumulated active time before a journal cycle runs. A short
    /// value in DEBUG makes the behavior observable during manual testing.
    #if DEBUG
    static let defaultInterval: TimeInterval = 20
    #else
    static let defaultInterval: TimeInterval = 15 * 60
    #endif

    /// A single tick can advance accumulated time by at most this much, so a long
    /// sleep or an inactive gap between ticks does not inflate "activity" time.
    static let maxTickStep: TimeInterval = 120

    static let terminalLines = 60
    // Referenced from the nonisolated `makePrompt`, so these bounds must be
    // reachable off the main actor. They are immutable Sendable literals.
    nonisolated static let maxFiles = 40
    nonisolated static let maxStatChars = 4_000
    nonisolated static let maxTerminalChars = 4_000
    static let maxEntries = 50

    /// The visible journal. Observed by `SessionJournalView`; cleared on session end.
    private(set) var entries: [SessionJournalEntry] = []

    private let services: SidecarServices
    private let interval: TimeInterval
    private let defaults: UserDefaults
    private let clock: () -> Date

    @ObservationIgnored private var requestTask: Task<Void, Never>?
    @ObservationIgnored private var accumulatedSeconds: TimeInterval = 0
    @ObservationIgnored private var lastTickAt: Date?
    @ObservationIgnored private var lastSignature: String?

    init(
        services: SidecarServices,
        interval: TimeInterval = SessionJournalModel.defaultInterval,
        defaults: UserDefaults = .standard,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.services = services
        self.interval = interval
        self.defaults = defaults
        self.clock = clock
    }

    /// True unless the user has explicitly turned journaling off. Defaults on so
    /// the feature works out of the box, matching the resource-safety toggle.
    var isEnabled: Bool {
        if defaults.object(forKey: Self.settingsKey) == nil { return true }
        return defaults.bool(forKey: Self.settingsKey)
    }

    /// Copy-all payload: chronological `time  text` lines.
    var transcript: String {
        entries
            .map { "\($0.timestamp.formatted(date: .omitted, time: .shortened))  \($0.text)" }
            .joined(separator: "\n\n")
    }

    /// Called by the sidecar timer. Accumulates active time and launches a bounded
    /// cycle once a full interval has elapsed. Never runs two cycles at once.
    func tick() {
        let now = clock()
        defer { lastTickAt = now }

        guard isEnabled else {
            accumulatedSeconds = 0
            return
        }
        guard let last = lastTickAt else { return }

        let delta = min(max(0, now.timeIntervalSince(last)), Self.maxTickStep)
        accumulatedSeconds += delta
        guard accumulatedSeconds >= interval else { return }

        accumulatedSeconds = 0
        guard requestTask == nil, services.isOllamaConfigured() else { return }
        startCycle()
    }

    /// Cancels in-flight work and clears the per-session journal.
    func cleanup() {
        requestTask?.cancel()
        requestTask = nil
        entries.removeAll(keepingCapacity: false)
        accumulatedSeconds = 0
        lastTickAt = nil
        lastSignature = nil
    }

    private func startCycle() {
        requestTask = Task { [weak self] in
            await self?.runCycle()
            self?.requestTask = nil
        }
    }

    /// Runs one bounded journal cycle. Reads git activity, skips when idle or
    /// unchanged, otherwise asks Gemma for a short entry. Internal so it can be
    /// driven deterministically by tests without the timer.
    func runCycle() async {
        let files = await services.changedFiles()
        let stat = await services.diffStat()
        let signature = Self.signature(files: files, stat: stat)

        guard !signature.isEmpty else { return }          // idle: nothing changed
        guard signature != lastSignature else { return }  // unchanged since last entry
        guard !Task.isCancelled else { return }

        let terminal = await services.readTerminalOutput(Self.terminalLines)
        let prompt = Self.makePrompt(files: files, stat: stat, terminal: terminal)

        do {
            let text = try await services.runBackground(prompt)
            guard !Task.isCancelled else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            appendEntry(text: trimmed, at: clock())
            lastSignature = signature
        } catch {
            // Transport error or cancellation: stay silent, no entry, retry later.
        }
    }

    private func appendEntry(text: String, at date: Date) {
        entries.append(SessionJournalEntry(timestamp: date, text: text))
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
    }

    /// Stable signature of the current git working state. Empty when there is no
    /// activity. Terminal output is deliberately excluded so streaming process
    /// output does not defeat skip-when-idle.
    nonisolated static func signature(files: [String], stat: String) -> String {
        let statTrim = stat.trimmingCharacters(in: .whitespacesAndNewlines)
        if files.isEmpty && statTrim.isEmpty { return "" }
        return files.sorted().joined(separator: "\n") + "\u{1}" + statTrim
    }

    nonisolated static func makePrompt(files: [String], stat: String, terminal: String?) -> String {
        var lines: [String] = [
            "You keep a concise work journal for a coding session.",
            "Using the signals below, write ONE journal entry of 1-2 short lines "
                + "describing what changed since the last entry. State facts only. "
                + "No preamble, no headings, no bullet list."
        ]

        if !files.isEmpty {
            lines.append("Changed files:")
            lines.append(files.prefix(maxFiles).joined(separator: "\n"))
            if files.count > maxFiles {
                lines.append("(+\(files.count - maxFiles) more)")
            }
        }

        let statTrim = stat.trimmingCharacters(in: .whitespacesAndNewlines)
        if !statTrim.isEmpty {
            lines.append("Diff stat:")
            lines.append(String(statTrim.prefix(maxStatChars)))
        }

        if let terminal,
           !terminal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("Recent terminal output:")
            lines.append(String(terminal.suffix(maxTerminalChars)))
        }

        return lines.joined(separator: "\n")
    }
}

/// Feed milestones. Renders nothing while the journal is empty. Entries read as
/// quiet timeline markers inside the shared feed: a timestamp rule followed by a
/// short secondary-text summary. The enable toggle lives in the gear popover.
struct SessionJournalView: View {
    @Bindable var model: SessionJournalModel

    var body: some View {
        if !model.entries.isEmpty {
            VStack(alignment: .leading, spacing: AtelierMetrics.spaceS) {
                copyRow
                ForEach(model.entries) { entry in
                    milestone(entry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var copyRow: some View {
        HStack(spacing: AtelierMetrics.spaceXS) {
            Text("Session Journal")
                .atelierFont(size: AtelierTypography.micro, weight: .semibold)
                .foregroundStyle(.secondary)
            Text("\(model.entries.count)")
                .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.transcript, forType: .string)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(AtelierGhostButtonStyle())
            .atelierPointerCursor()
            .accessibilityLabel("Copy all journal entries")
        }
    }

    private func milestone(_ entry: SessionJournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AtelierMetrics.spaceS) {
                Text(entry.timestamp, style: .time)
                    .atelierFont(size: AtelierTypography.micro, design: .monospaced)
                    .foregroundStyle(.secondary)
                Rectangle()
                    .fill(AtelierTheme.border)
                    .frame(height: AtelierTheme.strokeHairline)
            }
            Text(entry.text)
                .atelierFont(size: AtelierTypography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
