# Watchtower Memory

## Purpose

Read this file before creating or implementing Watchtower tasks in this repo.

This file holds long-term intent. It keeps task planning aligned across sessions.

## Core Intent

- Grow Atelier into a native agent control plane through small, verified slices.
- Keep Git review, workspace ownership, native focus, and predictable cleanup central.
- Start agent integration with Gemma 4 through Ollama Cloud.

## Planning Rules

- Add provider-neutral protocols only after a second provider creates a real need.
- Keep UI state on `MainActor`. Keep network and tool execution off `MainActor`.
- Give every agent task a clear cancellation and workspace cleanup path.
- Keep the first Gemma slice read-only until safety and tool-call tests pass.

## Source Anchors

- [app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift](app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift): owns workspace resources and cleanup.
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift): owns center terminal and editor tabs.
- [app/Atelier/Sources/Atelier/Git/GitService.swift](app/Atelier/Sources/Atelier/Git/GitService.swift): provides cancellable Git process work.
- [app/Atelier/Sources/Atelier/Shared/Logging/AppLogger.swift](app/Atelier/Sources/Atelier/Shared/Logging/AppLogger.swift): defines unified logging categories.
- [app/Atelier/Sources/Atelier/Agent/Sidecar/](app/Atelier/Sources/Atelier/Agent/Sidecar/): Gemma sidecar assistant. GemmaSidecarModel owns its own interactive + background runtimes (separate from the chat-tab gemmaAgent) plus the six feature models; SidecarServices is the read-only closure surface features consume; GemmaSidecarView is the container. Add a new sidecar feature as ONE self-contained file (model + view) wired via SidecarServices and a slot in GemmaSidecarView; do not spread it across shared files.

## Verification Bias

- `swift build --package-path app/Atelier`
- `swift test --package-path app/Atelier`
- `app/Atelier/.build/debug/Atelier --selftest`
- Verify cancellation, path containment, bounded output, and sensitive-file rejection.

## Avoid

- Do not let SwiftUI views read the filesystem or call Ollama directly.
- Do not add file writes, arbitrary shell execution, or automatic Git actions in the first slice.
- Do not log prompts, file contents, tool results, or credentials by default.
- Do not weaken strict concurrency with `@unchecked Sendable` shortcuts.

## Learnings

- 2026-07-18: Keep Codex and Claude interaction in SwiftTerm. Native response UI observes transcripts and never replaces or mutates terminal state.
- 2026-07-18: Keep FocusedValue-only palette shortcuts in a separate Commands type. Mixing them into model-bearing AppCommands crashed SwiftUI during app launch.
- 2026-07-19: Persist only the ordered workspace catalog and active identity. Keep tabs, terminals, navigation, Git, agents, and palettes inside live sessions.
- 2026-07-19: Defer catalog writes until startup load merges with user changes. Serialize later writes and flush the final catalog before app termination.
- 2026-07-19: Resign the old AppKit responder when switching workspaces. Restore a responder only when its workspace owner and revision remain active.
- 2026-07-20: Sidecar features use a registry/slot pattern so each feature is one file with no shared-file edits; this let a fan-out team build six features in parallel. Background features run bounded, serialized, cancellable calls via SidecarServices.runBackground on a runtime separate from the interactive one. Terminal Guardian gets exit codes from a TerminalController OSC 133 handler (registerOscHandler code 133; no marks -> never fires). read_terminal_output bridges the actor tool executor to the MainActor SwiftTerm buffer via an injected @Sendable snapshot provider (getText/buffer.lines + BufferLine.translateToString).
- 2026-07-21: Agent threads belong inside each Workspace rail group, below its workspace header. Do not add a Threads tab. Workspace-header clicks activate the project; nested thread clicks activate the project, select the exact terminal, and focus input.
- 2026-07-28: `WorkspaceSession.invalidateFileTree` fans one file-tree revision out to every consumer. A consumer must not do expensive work on that signal unless its UI is visible. The Quick Open palette re-walked the whole workspace on every revision while closed. Record the revision and defer the walk until the panel opens.
- 2026-07-28: A running agent writes its own transcript continuously, so the transcript watcher emits a steady event stream, not occasional events. Any per-event refresh becomes a hot loop. Debounce the burst first, then refresh once. Measure idle CPU with a full 5-minute `top -l 150 -s 2` window: a 12-second window misses the burst and reports a false pass.
- 2026-07-28: When planning a fan-out, group TASKs by the files the fix will touch, not by the files the symptom points at. A performance TASK and a feature TASK looked independent but both landed in `AtelierPaletteModel.swift`, and the parallel builders collided.
- 2026-07-28: `URL.resourceValues(forKeys:)` caches its answer on the URL, so a stored URL keeps reporting the old size after a file grows. Use a direct `stat` call for any change detection on a long-lived URL. It is also the cheaper call.
- 2026-07-28: The transcript roots hold hundreds of megabytes for one workspace: about 384 MB across the 100 newest `~/.codex/sessions` files plus 76 MB of Claude transcripts. Roughly half the codex files belong to other workspaces and yield no response. Any transcript work must bound how much it parses, not only how often it parses.
- 2026-07-28: A single transcript file reaches 8 MB, so the first parse of one file is a multi-second CPU burst on its own. Bounding file count or refresh rate is not enough; the bytes read per file need a bound too.
- 2026-07-28: To measure this class of burst, drive real transcript writes while sampling. A watcher that only polls CPU sees a quiet process, because no agent write means no refresh. Long sleeps between tool calls create false quiet windows.
- 2026-07-28: Check `app/Atelier/scripts/atelier-doctor status --json` for `workspace.active` before trusting any runtime measurement. The build script signs ad hoc, which can drop the security-scoped bookmark, so the app can relaunch with no workspace and read a false 0.6 percent idle.
- 2026-07-28: The transcript backlog is wide, not deep. About 97 own files hold 23 responses for this workspace. Bounding bytes per file does not remove warmup; bounding which files are opened is the lever that remains.
- 2026-07-28: The response overlay restores only the last three days. `AgentTranscriptMonitor.defaultHistoryWindow` holds that window, and `WorkspaceSession` passes it as `modifiedAfter`, which filters both the file walk and response timestamps. Keep the `init` default at `.distantPast` so dated test fixtures keep working.
- 2026-07-28: After the transcript work, the idle CPU owner moved to Git status refresh: `GitOutputBox.capture` and `GitCommand.run` dominate a sample taken during activity. Profile before assuming the transcript path is still the cost.
- 2026-07-28: A trailing debounce only collapses events closer than its window. Agent activity emits filesystem events spaced 0.3 to 1 second apart, so a 300 ms debounce still spawns one `git status` per event. Pair the debounce with a minimum spacing between spawns (`GitRefreshThrottlePolicy`, 2 seconds) and keep trailing behavior so the final state always refreshes.
- 2026-07-28: In a `sample`, `GitOutputBox.capture` frames sitting under `read` in `libsystem_kernel` are reader threads blocked waiting for pipe EOF, not CPU. Judge git cost by top-of-stack compute frames, not by symbol presence in the call tree. During a workspace write burst, the remaining compute is per-event file-tree and SwiftUI refresh, not git.
- 2026-07-28: A recursive discovery walk caches cleanly on directory mtimes: an append moves only the file's mtime, while create/delete/rename moves the parent directory's mtime. Fingerprint every visited directory with one `stat` and reuse the previous file list while none moved (`AgentTranscriptMonitor.transcriptURLs`), with a 60 second forced re-walk for unvisited subtrees. This cut the transcript-window p90 from 20.7 to 2.4 percent.
- 2026-07-28: An `@Observable` computed read (`unreadCount`, `fileTreeRevision`, `gitModel.snapshot`) inside a large SwiftUI body re-evaluates that whole body on every mutation; the sample shows it as AttributeGraph propagate_dirty plus initializeWithCopy/destroy of big view values. Fix by extracting a tiny view that owns the read (`AgentResponseOverlayButton`, `ExplorerFileTree`). Attribute churn with a frame-count aggregation over `sample` output, not guesses.
- 2026-07-28: The 2-percent idle bar has a floor while an agent actively produces a new response every 0.5 seconds: after removing walk, parse, and render waste, top-of-stack compute is syscall-level and the window still shows 2-4 percent samples. Distinguish burst waste from the cost of genuinely new work before hunting further cuts.
- 2026-07-28: Reuse `GitRefreshThrottlePolicy` (300 ms debounce + 2 s minimum spacing, trailing) for any filesystem-driven refresh consumer; applying it to watcher-driven `invalidateFileTree` at the watcher call site only (user actions stay immediate) cut a workspace write burst from 16.9 to 1.4 percent median.
- 2026-07-30: A watcher-driven refresh must coalesce a call that arrives mid-flight, never drop it. `guard !isRefreshInFlight else { return }` looks safe because another event will follow, but the last event before an agent stops writing is exactly the one that carries the final answer. Set a single pending flag and run one more pass after the current one, never a queue.
- 2026-07-30: A skip-if-unchanged fingerprint cache and a per-refresh work budget poison each other. A pass that records a discovered file's fingerprint but skips caching its content makes the next equality check hide that file until it changes again. Arm the unchanged shortcut only when the pass cached every file it fingerprinted. Separate a retryable skip (byte budget, read failure) from a permanent one (over the size cap), or a permanently rejected file keeps the shortcut off forever.
- 2026-07-30: Lowering an FSEvents latency does not add refreshes when a debounce sits behind it. A callback arriving inside a burst reschedules the pending debounce instead of starting work, so `1.0 -> 0.3` seconds only shortens the wait before a final answer reaches the panel. Idle CPU stayed at 0.047 percent mean over 60 seconds.
- 2026-07-30: Any UI that filters a list by a selected identity needs an explicit "the user picked this" flag. Auto-selecting only when the selection is nil silently pins the view to the first thing ever seen, so a brand-new session's response never renders. Track the manual pick, follow the newest while it is false, and let clearing the selection return to automatic follow.
- 2026-07-30: A Claude transcript writes harness injections with the user role, so a text-prefix skip list can never be complete. A background task notification is plain prose under `"type":"user"` and looks exactly like a real turn. The record says why it exists: `origin.kind` is `human` for a typed or queued turn and `task-notification` for an injection, and `promptSource` is `typed`, `queued`, or `system`. Gate on `origin.kind` and keep the prefix list only as the fallback for older CLI versions, which wrote no `origin` at all (230 real human lines across 554 local transcripts have none). Codex has no equivalent field, so it still needs prefixes, including `<skill>` and `The following is the Codex agent history`.
- 2026-07-30: A fan-out builder cannot prove an on-screen SwiftUI claim. `atelier-doctor probe` covers `main`, `editor`, `editor-scroll`, and `diff` only, so a response-overlay check has no CLI path, and repo rules forbid screenshots unless the user asks. Write on-screen acceptance points as a separate TASK for a session with UI automation, instead of burying them in a builder's Verify list where they come back as NOT DRIVEN.
