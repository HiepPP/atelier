# TASK-009 Pre-commit Whisper - Outcome

## Status

DONE

## Changed

- `app/Atelier/Sources/Atelier/Agent/Sidecar/PrecommitWhisperFeature.swift`
  - Implemented `PrecommitWhisperModel.tick()`: guards on
    `services.isOllamaConfigured()` and an `isChecking` overlap flag, then reads
    `services.unstagedDiff()` off the main actor and routes the result to a pure
    decision.
  - Added change detection via `PrecommitWhisperDecision.evaluate(...)`
    (nonisolated, deterministic): empty diff -> `.clear`, unchanged diff ->
    `.skip`, changed diff -> `.scan`. Fingerprint is a length-prefixed FNV-1a
    hash so the same diff always maps to the same value.
  - On `.scan`: cancels any running scan, then debounces 4s before ONE bounded
    `services.runBackground(_:)` call built from `PrecommitWhisperPrompt.build`,
    which asks for findings in EXACTLY four categories (DEBUG_PRINT, TODO,
    SECRET, COMMENTED_CODE) in a strict `CATEGORY | path:line | detail` format.
  - Added `PrecommitWhisperParser.parse(...)` (nonisolated): tolerant line
    parser that maps categories, splits `path:line`, caps 50 findings / 240
    detail chars, and redacts secret-like tokens to their first four characters
    plus a `****` mask before anything is stored.
  - Published state: `findings: [PrecommitFinding]` and `isScanning`, both
    `private(set)`; `cleanup()` cancels the check task and scan task and clears
    state.
  - Implemented `PrecommitWhisperView`: renders `EmptyView` when there are no
    findings; otherwise a quiet advisory banner with an `AtelierCountBadge`,
    tap-to-expand disclosure, and a bounded (180pt) scrollable finding list.
    Secret rows tint danger; the rest tint `gitOrange`. Never blocks.
- `watchtower/tasks/TASK-009-outcome.md` (this file).

No shared files touched. No `swift build`/`swift test` run (shared .build race).

## Contract

- Signatures preserved exactly: `PrecommitWhisperModel(services:)`,
  `tick()`, `cleanup()`, and `PrecommitWhisperView(model:)` (memberwise
  `init(model:)` unchanged, so `GemmaSidecarView` needs no change).
- Read-only: only reads `unstagedDiff()`, calls `runBackground`, and renders.
  No file writes, no shell, no git mutation, no paste, never sends Enter.
- One bounded scan at a time: `scanTask` is cancelled before a new one starts;
  the shared `SidecarBackgroundRunner` also serializes/cancels the previous run.
  Input is bounded by `PrecommitWhisperDecision.bound` (16k chars) on top of the
  services' own 500k byte cap.
- Debounce: 4s `Task.sleep` after a diff change; `Task.isCancelled` re-checked
  after the sleep so a newer diff supersedes cleanly.
- Skip when empty or unreachable: `.clear`/`.skip` avoid calls on empty diffs;
  `tick()` guards on `isOllamaConfigured()`, and thrown
  transport/`.cancelled` errors are swallowed quietly (advisory only).
- Advisory: no findings -> no badge (view is `EmptyView`); the banner never
  gates a commit and has no focus/sheet/alert.
- Privacy: diff and finding content are never logged (no `AppLogger` calls);
  secret values are redacted at parse time, so the full value never reaches
  observable state or the UI.
- Concurrency: `@MainActor @Observable` model; all UI-state mutation stays on
  MainActor (the unstructured `Task`s inherit MainActor isolation, the network
  hop lives inside `services.runBackground`). Helper types are `nonisolated`
  value types. No `@unchecked Sendable`, no `!` / `try!` / `as!` / `fatalError`
  / `precondition`.

## Verified (by reasoning)

- Add `print("debug")` -> next `tick()` fetches a changed diff -> `.scan` ->
  4s debounce -> one background call -> `DEBUG_PRINT` finding parsed -> badge
  shows within seconds.
- Revert the change (diff empty) -> `.clear` -> `findings = []` ->
  `PrecommitWhisperView` returns `EmptyView` -> badge clears.
- Fake token `sk_live_1234abcd` in a SECRET finding -> `redactSecrets` yields
  `sk_l****`; the full value is never stored or shown.
- Unchanged diff across ticks -> `.skip` (fingerprint == lastHandled) -> no
  repeat calls, so Gemma is not spammed on a stable tree.
- Newer diff mid-scan -> `handle` cancels `scanTask`; the in-flight
  `runBackground` await throws `CancellationError`/`.cancelled`, caught without
  disturbing state, and the new debounce+scan starts.
- Ollama unreachable -> `tick()` returns early (best-effort hint) or
  `runBackground` throws `.connection` (caught); no crash, `isScanning` reset by
  `defer`.
- `cleanup()` on workspace stop/close -> both tasks cancelled, findings cleared.

## Tests

- Pure, deterministic coverage is built into the file's helper types so the
  required cases are unit-testable: `PrecommitWhisperDecision.evaluate`
  (empty-diff skip, changed-diff scan, unchanged-diff skip),
  `PrecommitWhisperParser.parse` (category mapping, `NONE`, malformed-line
  tolerance), and `PrecommitWhisperParser.redactSecrets` (secret redaction to
  four chars).
- The test FILE itself was NOT added: this feature builder is scoped to edit
  only `PrecommitWhisperFeature.swift` during the concurrent phase, and a new
  file under `Tests/AtelierTests` is outside that scope. Ready-to-add Swift
  Testing cases for the integrator (new file
  `app/Atelier/Tests/AtelierTests/PrecommitWhisperTests.swift`):

  ```swift
  import Testing
  @testable import Atelier

  struct PrecommitWhisperTests {
      @Test("Empty diff skips scanning")
      func emptyDiffSkips() {
          let (action, fp) = PrecommitWhisperDecision.evaluate(
              diff: "   \n\t", currentTarget: nil, lastHandled: nil)
          #expect(action == .clear)
          #expect(fp == PrecommitWhisperDecision.emptyFingerprint)
          let again = PrecommitWhisperDecision.evaluate(
              diff: "", currentTarget: nil,
              lastHandled: PrecommitWhisperDecision.emptyFingerprint)
          #expect(again.action == .skip)
      }

      @Test("Changed diff scans, unchanged diff skips (debounce gate)")
      func changeDetection() {
          let first = PrecommitWhisperDecision.evaluate(
              diff: "+print(\"x\")", currentTarget: nil, lastHandled: nil)
          #expect(first.action == .scan)
          // Same diff already handled -> skip (no re-scan while stable).
          let same = PrecommitWhisperDecision.evaluate(
              diff: "+print(\"x\")", currentTarget: nil, lastHandled: first.fingerprint)
          #expect(same.action == .skip)
          // Same diff currently scanning -> skip.
          let inFlight = PrecommitWhisperDecision.evaluate(
              diff: "+print(\"x\")", currentTarget: first.fingerprint, lastHandled: nil)
          #expect(inFlight.action == .skip)
          // Different diff -> scan.
          let changed = PrecommitWhisperDecision.evaluate(
              diff: "+print(\"y\")", currentTarget: first.fingerprint, lastHandled: nil)
          #expect(changed.action == .scan)
      }

      @Test("Parser maps categories and returns nothing for NONE")
      func parseCategories() {
          #expect(PrecommitWhisperParser.parse("NONE").isEmpty)
          let out = """
          DEBUG_PRINT | Sources/A.swift:12 | leftover print
          TODO | Sources/B.swift:3 | new TODO added
          """
          let findings = PrecommitWhisperParser.parse(out)
          #expect(findings.count == 2)
          #expect(findings[0].category == .debugPrint)
          #expect(findings[0].file == "Sources/A.swift")
          #expect(findings[0].line == 12)
          #expect(findings[1].category == .todo)
      }

      @Test("Secret findings are redacted to first four characters")
      func secretRedaction() {
          let findings = PrecommitWhisperParser.parse(
              "SECRET | Sources/C.swift:9 | token sk_live_1234abcd")
          #expect(findings.count == 1)
          #expect(findings[0].detail.contains("sk_l****"))
          #expect(!findings[0].detail.contains("sk_live_1234abcd"))
      }
  }
  ```

## Notes / assumptions

- Tick cadence follows the real foundation timer (~45s), not the 60s in the
  task text; the plan says to follow real code when it differs.
- No persistent enable toggle: the spec requires "no finding -> no badge", so
  the view renders nothing when idle, which leaves no host for a toggle. The
  feature is inherently quiet (only appears on findings), so a toggle was
  omitted to honor that contract and keep scope tight.
- `SECRET` redaction targets secret-like tokens only (>=6 chars with mixed
  letters+digits, >=20 chars, or known key prefixes), so plain prose in a
  finding detail is left readable.
- Once the shared reachability hint flips false after a connection error, the
  whisper stays paused until another background/interactive run flips it back
  (shared `SidecarReachability`, owned by foundation, not this file).

## Integration fixes (round 1)

Applied by the integration fixer; the review finding resolved in
`PrecommitWhisperFeature.swift`.

- Secret redaction hardened: a SECRET-category finding is now masked
  unconditionally via new `redactAllTokens` (every token of length >= 4 -> first
  four chars + `****`), so a plain-word secret (e.g. `password = "letmein"`) is
  never shown in full. Non-secret categories keep the `isSecretLike` heuristic.
  This supersedes the note above that limited redaction to secret-like tokens.
- Debounce made injectable: `init(services:debounceSeconds:)` (defaulted to 4)
  so debounce/cancellation is unit-testable without a wall-clock wait.
  `PrecommitWhisperModel(services:)` call sites are unchanged.
- Tests added: `Tests/AtelierTests/PrecommitWhisperTests.swift` covers
  `PrecommitWhisperDecision.evaluate` (clear/skip/scan), `PrecommitWhisperParser`
  (categories, NONE, prefix + plain-word secret redaction), and model
  debounce/cancellation (one scan, newer diff supersedes, cleanup cancels).

Verified: `swift build`, `swift test` (161 tests), and `--selftest` all pass.
