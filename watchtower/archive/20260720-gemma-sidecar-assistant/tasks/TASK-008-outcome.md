# TASK-008 Intent Guard - Outcome

## Status

DONE

## Changed

- `app/Atelier/Sources/Atelier/Agent/Sidecar/IntentGuardFeature.swift`
  - `IntentGuardView`: renders a one-line intent `TextField` (bound to
    `model.intent`) at the top, plus an advisory warning row (orange triangle,
    headline, comma-joined out-of-scope files, dismiss button) shown only when
    `model.activeWarning` is non-nil.
  - `IntentGuardModel` (`@MainActor @Observable`): owns `intent`, the current
    advisory, a dismissed-signature, per-run baselines, and one in-flight
    `checkTask` (`Task<Void, Never>?`). `tick()` disables everything on empty
    intent (via `resetForDisabledIntent()`), otherwise starts at most one
    background evaluation. `dismissWarning()` records the dismissed changed-file
    signature and hides the row. `isolated deinit` cancels the task.
  - `evaluate(statedIntent:)`: refreshes the changed-file signature, lifts a
    dismissal once the set moves on, hides a stale warning, then gates on
    non-empty file set -> `isOllamaConfigured()` -> not suppressed -> cadence
    (>= 180s) -> meaningful diff growth, and only then runs ONE bounded
    `services.runBackground(_:)` call built from the intent, changed-file list,
    and `git diff --stat`. Out-of-scope paths become the advisory; empty result
    clears it. Transport/cancellation errors are swallowed.
  - `IntentGuardPolicy` (`nonisolated enum`): pure, unit-testable helpers -
    `isActive`, `signature(for:)`, `isSuppressed`, `liftedDismissal`,
    `cadenceElapsed`, `hasMeaningfulGrowth`, `changeVolume(fromDiffStat:)`,
    `prompt(intent:files:diffStat:)`, `parseOutOfScope(response:changedFiles:)`.
  - `IntentGuardWarning` (`nonisolated struct`, `Equatable`, `Sendable`):
    signature + files + `headline`.
- `watchtower/tasks/TASK-008-outcome.md` (this file).

No shared files touched. No `swift build`/`swift test` run (shared .build race).

## Tests (ready to add, not committed - test target is shared)

Add as `app/Atelier/Tests/AtelierTests/IntentGuardPolicyTests.swift` during the
integrate stage. Covers empty-intent skip and dismiss suppression plus the drift
decision. All assertions target the pure `IntentGuardPolicy` surface the model
uses, so they need no runtime.

```swift
import XCTest
@testable import Atelier

final class IntentGuardPolicyTests: XCTestCase {
    func testEmptyIntentIsInactive() {
        XCTAssertFalse(IntentGuardPolicy.isActive(intent: ""))
        XCTAssertFalse(IntentGuardPolicy.isActive(intent: "   \n\t"))
        XCTAssertTrue(IntentGuardPolicy.isActive(intent: "add caching"))
    }

    func testDismissSuppressesUntilFileSetChanges() {
        let a = IntentGuardPolicy.signature(for: ["A.swift", "B.swift"])
        // Dismissed for set A: still suppressed for the same set.
        XCTAssertTrue(IntentGuardPolicy.isSuppressed(signature: a, dismissedSignature: a))
        XCTAssertEqual(IntentGuardPolicy.liftedDismissal(current: a, dismissed: a), a)
        // File set changes: dismissal lifts, no longer suppressed.
        let b = IntentGuardPolicy.signature(for: ["A.swift", "C.swift"])
        XCTAssertNil(IntentGuardPolicy.liftedDismissal(current: b, dismissed: a))
        XCTAssertFalse(IntentGuardPolicy.isSuppressed(signature: b, dismissedSignature: nil))
    }

    func testSignatureIsOrderIndependent() {
        XCTAssertEqual(
            IntentGuardPolicy.signature(for: ["b", "a"]),
            IntentGuardPolicy.signature(for: ["a", "b"])
        )
    }

    func testMeaningfulGrowth() {
        let sig = IntentGuardPolicy.signature(for: ["A"])
        // First check for a non-empty set.
        XCTAssertTrue(IntentGuardPolicy.hasMeaningfulGrowth(
            currentSignature: sig, lastSignature: nil,
            currentVolume: 3, lastVolume: 0, growthThreshold: 8))
        // Empty set never triggers.
        XCTAssertFalse(IntentGuardPolicy.hasMeaningfulGrowth(
            currentSignature: "", lastSignature: nil,
            currentVolume: 99, lastVolume: 0, growthThreshold: 8))
        // Same set, not enough new volume.
        XCTAssertFalse(IntentGuardPolicy.hasMeaningfulGrowth(
            currentSignature: sig, lastSignature: sig,
            currentVolume: 5, lastVolume: 2, growthThreshold: 8))
        // Same set, enough new volume.
        XCTAssertTrue(IntentGuardPolicy.hasMeaningfulGrowth(
            currentSignature: sig, lastSignature: sig,
            currentVolume: 12, lastVolume: 2, growthThreshold: 8))
    }

    func testCadence() {
        let now = Date()
        XCTAssertTrue(IntentGuardPolicy.cadenceElapsed(now: now, lastRun: nil, minInterval: 180))
        XCTAssertFalse(IntentGuardPolicy.cadenceElapsed(
            now: now, lastRun: now.addingTimeInterval(-10), minInterval: 180))
        XCTAssertTrue(IntentGuardPolicy.cadenceElapsed(
            now: now, lastRun: now.addingTimeInterval(-200), minInterval: 180))
    }

    func testChangeVolumeParsesDiffStatSummary() {
        let stat = " 3 files changed, 42 insertions(+), 7 deletions(-)\n"
        XCTAssertEqual(IntentGuardPolicy.changeVolume(fromDiffStat: stat), 49)
        XCTAssertEqual(IntentGuardPolicy.changeVolume(fromDiffStat: ""), 0)
    }

    func testParseOutOfScope() {
        let files = ["Sources/Cache.swift", "Sources/Login.swift"]
        XCTAssertEqual(
            IntentGuardPolicy.parseOutOfScope(response: "NONE", changedFiles: files), [])
        XCTAssertEqual(
            IntentGuardPolicy.parseOutOfScope(response: "None.\n", changedFiles: files), [])
        XCTAssertEqual(
            IntentGuardPolicy.parseOutOfScope(
                response: "- Sources/Login.swift", changedFiles: files),
            ["Sources/Login.swift"])
    }
}
```

## Contract

- Signatures preserved: `IntentGuardModel(services:)`, `func tick()`, and
  `IntentGuardView(model:)` (the container calls `IntentGuardView(model:
  model.intentGuard)`; `@Bindable var model` keeps the `init(model:)` param).
- Read-only: only reads `changedFiles()` / `diffStat()` and calls
  `runBackground`; no file writes, no shell, no git mutations, no paste, never
  sends Enter.
- Empty intent disables everything: `tick()` returns via
  `resetForDisabledIntent()` before any task is created -> zero background calls.
- One bounded call at a time: `guard checkTask == nil` in `tick()` plus a single
  owner (`evaluate`'s `defer { checkTask = nil }`) means at most one in-flight
  evaluation; `runBackground` is itself serialized by the foundation runner.
- Cadence + growth: at most one call per `minInterval` (180s), and only after a
  changed file set or `>= growthThreshold` (8) added lines since the last check.
- Dismiss suppression: `dismissWarning()` stores the dismissed signature;
  `activeWarning` and `evaluate` both check `isSuppressed`, and
  `liftedDismissal` re-enables checks once the changed-file set changes.
- Skip when unreachable: guards on `services.isOllamaConfigured()` and swallows
  thrown transport/cancellation errors (no error row, UI never blocks).
- Concurrency: model is `@MainActor @Observable`; the unstructured `Task`
  inherits MainActor isolation, so all state mutation stays on MainActor and the
  only off-actor hop is inside `services.runBackground`. No `@unchecked
  Sendable`. No force unwrap / `try!` / `as!` / `fatalError` / `precondition`.
- Privacy: nothing is logged - no prompts, file paths, diffs, or responses.

## Verified (by reasoning)

- Unrelated edits under a stated intent: intent active, files non-empty,
  reachable, cadence elapsed, growth present -> one `runBackground` call; the
  model echoes the out-of-scope paths, `parseOutOfScope` maps them back, and the
  advisory row lists exactly those files.
- Matching edits: same gates pass, the model replies `NONE` ->
  `parseOutOfScope` returns `[]` -> `warning = nil` -> no row.
- Empty intent: `isActive` false -> `resetForDisabledIntent()` clears state and
  returns; no task, no `changedFiles`/`diffStat`/`runBackground` call ever runs.
- Dismiss then keep editing the same files: `dismissedSignature == signature` ->
  `isSuppressed` true -> row stays hidden and no new call fires; once the changed
  set differs, `liftedDismissal` returns nil and checks resume.
- Ollama unreachable: either `isOllamaConfigured()` is false (skip) or
  `runBackground` throws (caught, no row); `defer` always clears `checkTask`.
- Teardown / intent cleared mid-run: `resetForDisabledIntent()` and `isolated
  deinit` cancel the task; after the awaited call resumes,
  `Task.checkCancellation()` / the empty-intent guard short-circuit before any
  warning is published.

## Notes / assumptions

- Intent is in-model state (not `@AppStorage`) so it never leaks across
  workspaces; empty intent is the natural "off" switch, so no extra toggle was
  added.
- `changeVolume` parses the `git diff --stat` summary line ("N insertions(+), M
  deletions(-)"); an absent summary yields 0, in which case a changed file set
  still triggers via the signature branch.
- `parseOutOfScope` matches by path substring against the known changed files,
  so the advisory can only ever name files that actually changed.
- No test file was created here (the test target is a shared build surface under
  concurrent edits); the block above is ready to drop in during integrate.

## Integration fixes (round 1)

Applied by the integration fixer; the review finding resolved in
`IntentGuardFeature.swift`.

- Substring collision fixed: `IntentGuardPolicy.parseOutOfScope` now matches by
  whole trimmed lines and their whitespace-separated tokens instead of a raw
  `response.range(of: file)` substring scan. A longer echoed path
  (e.g. `Vendor/Luminare/Package.swift`) no longer falsely flags a shorter one
  (`Package.swift`). Order is preserved via `changedFiles.filter`. This corrects
  the outcome note above that described substring matching.
- Tests added: `Tests/AtelierTests/IntentGuardPolicyTests.swift` (Swift Testing)
  covers the collision regression plus core policy helpers.

Verified: `swift build`, `swift test` (161 tests), and `--selftest` all pass.
