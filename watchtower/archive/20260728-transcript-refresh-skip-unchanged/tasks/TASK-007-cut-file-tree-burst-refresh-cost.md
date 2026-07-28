# TASK-007 Cut per-event file-tree and SwiftUI refresh cost during write bursts

Group: standalone

## Brief

Goal: a workspace write burst no longer drives double-digit CPU through per-event file-tree
reloads and SwiftUI invalidation. Baseline from the TASK-006 session: 11.3 percent median CPU
while a script appended to one workspace file every 0.5 seconds.

Change: every `.workspaceContent` watcher delivery triggers `invalidateFileTree` and a SwiftUI
update pass -> repeated events on the same paths collapse into fewer, cheaper refreshes.

What is known from the TASK-006 sample:

- During the burst, compute frames were AttributeGraph propagation and SwiftUI layout, not git
  and not the file-tree disk walk alone. The git path is already throttled by
  `GitRefreshThrottlePolicy`.
- The watcher batches with a 200 millisecond debounce in
  [app/Atelier/Sources/Atelier/Workspace/Services/FileWatcher.swift](../../app/Atelier/Sources/Atelier/Workspace/Services/FileWatcher.swift),
  so deliveries arrive about twice per second during a steady write stream.
- `WorkspaceSession.invalidateFileTree` fans one revision out to every consumer
  ([app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift](../../app/Atelier/Sources/Atelier/Workspace/State/WorkspaceSession.swift)
  line 122). Consumers must not do expensive work per revision while their UI is hidden; audit
  which consumer does.

How:

- Profile first: drive the same 0.5 second write loop, sample, and attribute the AttributeGraph
  churn to a concrete consumer (file tree controller, palette, search, or a view observing the
  revision). Do not guess the owner.
- Fix the owner: diff-before-reload for the file tree (repository rule), or a spacing throttle
  like `GitRefreshThrottlePolicy` on the consumer, or defer work while the consuming UI is not
  visible. Pick the smallest fix the profile supports.
- Keep the 200 millisecond watcher debounce; this TASK cuts the cost per delivery, not the
  delivery rate, unless the profile proves the rate itself is the cost.

Files:

- To be confirmed by the profile. Likely
  [app/Atelier/Sources/Atelier/FileTree/FileTreeController.swift](../../app/Atelier/Sources/Atelier/FileTree/FileTreeController.swift)
  or the consumer the sample names.

Expected result:

- The same 0.5 second write loop holds median CPU at or below 5 percent, and the sample no
  longer shows AttributeGraph propagation as the dominant compute path.
- File tree still reflects a new, renamed, and deleted file within about one second.

Prompt (optional):

```text
Invoke $swiftui-expert-skill first. Profile before editing; name the consumer that owns the
AttributeGraph churn with a sample, then run GitNexus impact on that symbol before changing it.
```

## Verify

- `swift build --package-path app/Atelier` -> passes.
- `swift test --package-path app/Atelier` -> no new failures beyond the three known flaky timing tests.
- `app/Atelier/.build/debug/Atelier --selftest` -> prints `SELFTEST: ALL PASS`.
- Launch, run `for i in $(seq 1 120); do echo x >> <workspace>/tmp-burst.txt; sleep 0.5; done`,
  measure 30 top samples at 2 seconds -> median at or below 5 percent (baseline 11.3).
- Sample during the loop -> dominant compute is no longer AttributeGraph propagation from the
  file-tree revision path.
- Create, rename, and delete a file in Finder -> tree updates within about one second.
- Remove the temp file after.
