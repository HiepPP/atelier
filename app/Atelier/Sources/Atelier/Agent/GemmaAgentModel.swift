import Foundation
import Observation

nonisolated enum GemmaAgentStatus: Equatable, Sendable {
    case idle
    case running
    case completed
    case failed
    case cancelled
}

struct GemmaTranscriptMessage: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var content: String

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

@MainActor
@Observable
final class GemmaAgentModel {
    private(set) var messages: [GemmaTranscriptMessage] = []
    private(set) var activities: [GemmaToolActivity] = []
    private(set) var status: GemmaAgentStatus = .idle
    private(set) var errorMessage: String?
    private(set) var recoverySuggestion: String?
    var prompt = ""

    /// Optional block prepended to the prompt sent to the runtime. The visible
    /// transcript keeps the user's raw text. Used by the Gemma sidecar to inject
    /// tab context without changing the runtime system prompt.
    var contextProvider: (() -> String?)?

    private let runtime: GemmaAgentRuntime
    private var runTask: Task<Void, Never>?
    private var assistantMessageID: UUID?
    private var shouldResetRuntime = false
    // Streaming deltas are coalesced so the observable transcript mutates at a
    // bounded rate instead of once per token (each mutation re-renders and
    // re-parses the whole message).
    @ObservationIgnored private var pendingDelta = ""
    @ObservationIgnored private var deltaFlushTask: Task<Void, Never>?

    init(runtime: GemmaAgentRuntime) {
        self.runtime = runtime
    }

    var isRunning: Bool { status == .running }

    func send() {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }
        prompt = ""
        send(cleanPrompt)
    }

    func send(_ prompt: String) {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }
        stopRunningTask(markCancelled: false)
        messages.append(GemmaTranscriptMessage(role: .user, content: cleanPrompt))
        let assistantID = UUID()
        assistantMessageID = assistantID
        messages.append(GemmaTranscriptMessage(id: assistantID, role: .assistant, content: ""))
        activities.removeAll(keepingCapacity: true)
        errorMessage = nil
        recoverySuggestion = nil
        status = .running
        AppLogger.agent.info("Started Gemma agent run")

        let runtimePrompt: String
        if let block = contextProvider?()?.trimmingCharacters(in: .whitespacesAndNewlines),
           !block.isEmpty {
            runtimePrompt = block + "\n\n" + cleanPrompt
        } else {
            runtimePrompt = cleanPrompt
        }

        let resetRuntime = shouldResetRuntime
        shouldResetRuntime = false
        runTask = Task { [weak self, runtime] in
            do {
                if resetRuntime { await runtime.reset() }
                guard !Task.isCancelled else { return }
                let events = await runtime.events(for: runtimePrompt)
                for try await event in events {
                    guard !Task.isCancelled else { return }
                    self?.apply(event)
                }
            } catch is CancellationError {
                guard !Task.isCancelled else { return }
                self?.status = .cancelled
            } catch let error as GemmaAgentRuntimeError where error == .cancelled {
                guard !Task.isCancelled else { return }
                self?.status = .cancelled
            } catch {
                guard !Task.isCancelled else { return }
                self?.status = .failed
                self?.errorMessage = error.localizedDescription
                self?.recoverySuggestion = (error as? OllamaCloudError)?.recoverySuggestion
                AppLogger.agent.error(
                    "Gemma agent run failed; category=\(Self.logCategory(for: error), privacy: .public)"
                )
            }
        }
    }

    func stop() {
        stopRunningTask(markCancelled: true)
    }

    func clear() {
        stopRunningTask(markCancelled: false)
        messages.removeAll(keepingCapacity: false)
        activities.removeAll(keepingCapacity: false)
        errorMessage = nil
        recoverySuggestion = nil
        status = .idle
        shouldResetRuntime = true
    }

    func close() {
        stopRunningTask(markCancelled: true)
    }

    private func apply(_ event: GemmaAgentEvent) {
        switch event {
        case .assistantDelta(let delta):
            pendingDelta.append(delta)
            scheduleDeltaFlush()
            return
        case .toolStarted(let activity):
            flushPendingDelta()
            activities.append(activity)
        case .toolFinished(let activity):
            flushPendingDelta()
            if let index = activities.firstIndex(where: { $0.id == activity.id }) {
                activities[index] = activity
            } else {
                activities.append(activity)
            }
        case .completed:
            flushPendingDelta()
            status = .completed
            runTask = nil
            AppLogger.agent.info("Completed Gemma agent run")
        }
        trimPresentationState()
    }

    private func scheduleDeltaFlush() {
        guard deltaFlushTask == nil else { return }
        deltaFlushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard let self, !Task.isCancelled else { return }
            deltaFlushTask = nil
            flushPendingDelta()
        }
    }

    private func flushPendingDelta() {
        deltaFlushTask?.cancel()
        deltaFlushTask = nil
        guard !pendingDelta.isEmpty else { return }
        let delta = pendingDelta
        pendingDelta = ""
        guard let assistantMessageID,
              let index = messages.firstIndex(where: { $0.id == assistantMessageID }) else {
            return
        }
        messages[index].content.append(delta)
    }

    private func stopRunningTask(markCancelled: Bool) {
        flushPendingDelta()
        let wasRunning = status == .running
        runTask?.cancel()
        runTask = nil
        if wasRunning && markCancelled {
            status = .cancelled
            AppLogger.agent.info("Cancelled Gemma agent run")
        }
    }

    private func trimPresentationState() {
        if messages.count > 100 { messages.removeFirst(messages.count - 100) }
        if activities.count > 100 { activities.removeFirst(activities.count - 100) }
    }

    private nonisolated static func logCategory(for error: Error) -> String {
        if error is OllamaCloudError { return "transport" }
        if error is WorkspaceToolError { return "workspace-tool" }
        if error is GemmaAgentRuntimeError { return "runtime" }
        return "unexpected"
    }

    isolated deinit {
        runTask?.cancel()
        deltaFlushTask?.cancel()
    }
}
