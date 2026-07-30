import Foundation
import Observation

nonisolated enum ThreadStatus: Equatable, Sendable {
    case running
    case done
}

nonisolated struct ThreadEntry: Equatable, Identifiable, Sendable {
    let terminalID: UUID
    let title: String
    let agentName: String
    let status: ThreadStatus
    let startedAt: Date
    let finishedAt: Date?

    var id: UUID { terminalID }
}

nonisolated struct WorkspaceThreadGroup: Equatable, Identifiable, Sendable {
    let workspaceID: String
    let name: String
    let threads: [ThreadEntry]

    var id: String { workspaceID }
}

nonisolated struct TerminalSnapshot: Equatable, Sendable {
    let terminalID: UUID
    let title: String
    let workspaceID: String
    let workspaceName: String
    let agentName: String?
}

/// A snapshot before its agent name is known. Gathering these is pure main-actor
/// property reading; resolving them costs two `sysctl` calls per terminal and
/// runs off the main actor.
nonisolated struct TerminalAgentProbe: Sendable {
    let terminalID: UUID
    let title: String
    let workspaceID: String
    let workspaceName: String
    let agentProbe: TerminalForegroundAgentProbe?
}

@MainActor
@Observable
final class ThreadsPanelModel {
    private struct RunState: Equatable {
        let agentName: String
        let status: ThreadStatus
        let startedAt: Date
        let finishedAt: Date?
    }

    private(set) var groups: [WorkspaceThreadGroup] = []
    private var runStates: [UUID: RunState] = [:]
    /// Shell-reported finish times, keyed by terminal tab. The poll observes the
    /// running -> done edge up to one interval late, and later still while the
    /// window is off screen, so the edge alone cannot date the row.
    private var shellFinishTimes: [UUID: Date] = [:]

    /// Records an OSC 133 command-finished mark. Only the timestamp is kept: the
    /// mark fires for every command, so whether an agent actually exited is
    /// still decided by the next probe.
    func recordShellCommandFinished(terminalID: UUID, at time: Date) {
        guard runStates[terminalID]?.status == .running else { return }
        shellFinishTimes[terminalID] = time
    }

    /// Main-actor phase: read terminal identity and PTY handles only.
    func makeProbes(sessions: [WorkspaceSession]) -> [TerminalAgentProbe] {
        sessions.flatMap { session in
            let workspaceID = session.state.id
            let workspaceName = WorkspaceRailIdentityPolicy.workspaceName(
                path: session.state.path
            )
            return session.terminalTabs.openTerminalTabs.map { terminal in
                TerminalAgentProbe(
                    terminalID: terminal.id,
                    title: terminal.title,
                    workspaceID: workspaceID,
                    workspaceName: workspaceName,
                    agentProbe: terminal.controller.foregroundAgentProbe
                )
            }
        }
    }

    /// Off-main phase: one `tcgetpgrp` plus two `sysctl` calls per terminal.
    nonisolated static func resolveSnapshots(
        probes: [TerminalAgentProbe]
    ) -> [TerminalSnapshot] {
        probes.map { probe in
            TerminalSnapshot(
                terminalID: probe.terminalID,
                title: probe.title,
                workspaceID: probe.workspaceID,
                workspaceName: probe.workspaceName,
                agentName: probe.agentProbe?.resolveAgentName()
            )
        }
    }

    func refresh(snapshots: [TerminalSnapshot], now: Date) {
        let liveTerminalIDs = Set(snapshots.map(\.terminalID))
        runStates = runStates.filter { liveTerminalIDs.contains($0.key) }
        shellFinishTimes = shellFinishTimes.filter { liveTerminalIDs.contains($0.key) }

        for snapshot in snapshots {
            updateRunState(for: snapshot, now: now)
        }

        var snapshotsByWorkspace: [String: [TerminalSnapshot]] = [:]
        for snapshot in snapshots {
            snapshotsByWorkspace[snapshot.workspaceID, default: []].append(snapshot)
        }

        var seenWorkspaceIDs = Set<String>()
        let nextGroups = snapshots.compactMap { snapshot -> WorkspaceThreadGroup? in
            guard seenWorkspaceIDs.insert(snapshot.workspaceID).inserted else { return nil }
            let workspaceSnapshots = snapshotsByWorkspace[snapshot.workspaceID] ?? []
            let threads = workspaceSnapshots.compactMap { terminal -> ThreadEntry? in
                guard let state = runStates[terminal.terminalID] else { return nil }
                return ThreadEntry(
                    terminalID: terminal.terminalID,
                    title: terminal.title,
                    agentName: state.agentName,
                    status: state.status,
                    startedAt: state.startedAt,
                    finishedAt: state.finishedAt
                )
            }
            return WorkspaceThreadGroup(
                workspaceID: snapshot.workspaceID,
                name: snapshot.workspaceName,
                threads: threads
            )
        }

        if groups != nextGroups {
            groups = nextGroups
        }
    }

    private func updateRunState(for snapshot: TerminalSnapshot, now: Date) {
        switch (snapshot.agentName, runStates[snapshot.terminalID]) {
        case (.some(let agentName), .some(let current))
            where current.status == .running && current.agentName == agentName:
            // Still the same run, so any mark seen since the last poll closed
            // some other command and must not date this one.
            shellFinishTimes[snapshot.terminalID] = nil
            return
        case (.some(let agentName), _):
            shellFinishTimes[snapshot.terminalID] = nil
            runStates[snapshot.terminalID] = RunState(
                agentName: agentName,
                status: .running,
                startedAt: now,
                finishedAt: nil
            )
        case (.none, .some(let current)) where current.status == .running:
            let shellFinishedAt = shellFinishTimes.removeValue(forKey: snapshot.terminalID)
            runStates[snapshot.terminalID] = RunState(
                agentName: current.agentName,
                status: .done,
                startedAt: current.startedAt,
                finishedAt: Self.finishTime(
                    shellReported: shellFinishedAt,
                    startedAt: current.startedAt,
                    now: now
                )
            )
        case (.none, _):
            return
        }
    }

    /// Prefer the shell's own finish time; fall back to the poll time. A mark
    /// dated before the run started, or after the poll, belongs to a different
    /// command and is discarded rather than shown as a negative or future age.
    nonisolated static func finishTime(
        shellReported: Date?,
        startedAt: Date,
        now: Date
    ) -> Date {
        guard let shellReported,
              shellReported >= startedAt,
              shellReported <= now else {
            return now
        }
        return shellReported
    }
}
