# TASK-002 Outcome

## Status

DONE

## Changed

- `app/Atelier/Sources/Atelier/Agent/AgentResponses.swift`
  - `AgentResponse` gained `let question: String?`. `Equatable` and `Sendable` are unchanged, and
    `stableID` still hashes only provider, session, record id, timestamp, and answer, so no id moved.
  - `AgentTranscriptParser.State` gained `var pendingQuestion: String?`, so a question read in one
    pass survives in `CachedTranscript.parserState` and pairs with an answer from an appended read.
  - Added `questionCharacterLimit = 4_000` and `injectedQuestionPrefixes`.
  - Added `codexUserText(from:)`, `claudeUserText(from:)`, and `questionText(_:)`. Claude reads both
    the string and the block content shape, joins only `text` blocks, and rejects `isMeta` and
    `isSidechain` lines. `questionText` trims, drops empty and injected text, and cuts a long
    question to 4000 characters plus `...`.
  - `consume` sets `state.pendingQuestion` on a kept user line and returns; a skipped line leaves the
    previous question in place. An accepted answer attaches `state.pendingQuestion` and keeps it, so
    two answers in one turn share one question.
- `app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift`
  - `responseCard` renders `AgentResponseQuestionView(question:)` above
    `selectableMarkdown(response.markdown)` and nothing when `question` is nil.
  - New private `AgentResponseQuestionView`: a `Question` caption label in secondary, a
    chevron disclosure `Button` with `.buttonStyle(.plain)` and `.atelierPointerCursor()`, and
    `Text(verbatim: question)` clamped to `lineLimit(3)` when collapsed and `nil` when expanded. It
    owns its `@State private var isExpanded`, so a toggle re-evaluates this view alone. The card's
    existing `.id(response.id)` resets that state when the shown response changes.
- `app/Atelier/Sources/Atelier/Agent/AgentResponseMemoryFixture.swift`: fixture responses 1 and 2
  carry a question, response 3 carries none, so the profile run covers both branches. Byte and row
  counts are unchanged.
- `app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift`: new tests
  `pairsQuestionWithAnswer`, `skipsInjectedQuestionLines`, `keepsPreviousQuestionAndCapsLength`,
  `questionKeepsResponseIDStable`, `pendingQuestionSurvivesAppendedRead`. The `response(...)` helper
  gained `question: String? = nil`, and the one inline `AgentResponse(...)` now passes
  `question: nil`.
- `DESIGN.md`, `### Agent Responses`: added the question block contract, the pairing rule, the skip
  list, and the id-stability rule.

## Contract

DESIGN.md `### Agent Responses` updated before the code change. Each card shows the question above
the answer as plain text, clamped to 3 lines with a pointer-cursor disclosure, capped at 4000
characters with a trailing `...`, and hidden when unknown. The pending question lives in the
resumable parser state. Injected, meta, sidechain, slash-command, and tool-result-only lines are
never questions, and a skipped line keeps the previous question. A response id is built from its
answer alone.

## Verified

1. `swift build --package-path app/Atelier` -> `ok (build complete)`.
2. `swift test --package-path app/Atelier` -> `Test run with 407 tests in 40 suites passed after
   3.726 seconds`. `Memory fixture matches captured response shape` still passes with the new field.
3. `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
4. `Each final answer carries the newest preceding user question` passed. Codex `session_meta` then a
   `role: "user"` `input_text` line then two `final_answer` lines gives
   `["Fix the stale panel", "Fix the stale panel"]`.
5. Same test covers Claude: a `String` content gives `"Show the question"`, and an array content
   holding a `tool_result` plus one `text` block gives `"Block form question"`.
6. `Injected, meta, and tool-only user lines never become a question` passed for `isMeta: true`,
   `isSidechain: true`, `<command-name>`, `<system-reminder>`, `<local-command-caveat>`, a
   `tool_result`-only content, whitespace-only content, and the codex openings
   `# AGENTS.md instructions`, `<INSTRUCTIONS>`, `<environment_context>`, and
   `## Referenced ChatGPT conversation:`. Every case leaves `question == nil` with the answer still
   produced.
7. `A pending question survives into an appended read` passed. The question line is in the first
   monitor read (which yields no response) and the answer arrives in the appended read; the response
   comes back as `["Answered"]` with `question == "Asked before the append"`.
8. `A skipped user line keeps the previous question and long questions are capped` passed. A meta
   line between the question and the answer keeps `"Real question"`, and a 4500 character question is
   stored as `prefix(4000) + "..."` with `count == 4003`.
9. `A question never changes a response id` passed. The same codex answer with no record id yields
   the same id with and without the preceding user line.
10. `app/Atelier/scripts/build_and_run.sh run` -> SwiftLint gate passed, `Build complete! (11.44s)`,
    ad hoc signed, `satisfies its Designated Requirement`, app launched (pid 3632). Runtime health:
    `status healthy`, `workspace.active true`, `verdicts []`, no new `.ips` report.
11. Not driven as a UI observation. No native UI automation is available in this environment and
    screenshots were not requested, so the `Cmd-R` open, the 3-line clamp, the disclosure toggle, and
    the hover cursor were not observed on screen. Code-backed evidence instead:
    `AgentResponseQuestionView` clamps with `lineLimit(isExpanded ? nil : 3)`, toggles through its own
    `@State`, and carries `.atelierPointerCursor()` on the disclosure `Button` (`.buttonStyle(.plain)`
    adds no pointer cursor of its own, so this is not a double-apply).
12. Same limitation as 11 for the no-question case. The branch is structural: `responseCard` only
    builds the block inside `if let question = response.question`, so no label and no spacer row is
    emitted when it is nil. Fixture response 3 exercises that branch in the memory profile view.
13. `detect_changes()` -> 5 changed files, exactly the expected ones. Affected processes are the
    transcript and response flows (`LoadResponsesWithoutInitialGate → *`, `Consume →
    StandardizedPath`, `ChooseWorkspace → Refresh`). No unrelated flow appeared.

## Notes

- No performance guard changed. The question adds one trim and one prefix check per user line inside
  the existing parse walk, and no allocation on a draw, layout, or per-row path.
- No prompt, question, or response text is logged.

## Follow-up 2026-07-30

The user reported that the panel showed a `<task-notification>` block where the question belongs. The
prefix list could not catch it, because a harness injection is written with the user role and plain
text, exactly like a real turn.

Changed:

- `app/Atelier/Sources/Atelier/Agent/AgentResponses.swift`: `claudeUserText` now reads the `origin`
  object first. When it is present, the line is a question only when `origin.kind` is `human`. A line
  with no `origin` comes from an older CLI and still falls back to the prefix list. Added
  `<task-notification>`, `<command-message>`, `<skill>`, and `The following is the Codex agent history`
  to `injectedQuestionPrefixes`.
- `app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift`: `AgentResponseQuestionView` now sits in
  its own container with a raised fill, a row-radius corner, a hairline border, and a 2 point accent
  left rule. The label is caption-size accent text, the chevron moved from 8 to micro size, and the
  question text moved from body secondary to `uiSize` medium primary with 2 point line spacing.
- `DESIGN.md`: the `### Agent Responses` contract now states the origin rule and the new styling.
- `app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift`: added
  `skipsNonHumanOriginLines` and `skipsNotificationAndSkillPrefixes`.

Verified:

- `swift build --package-path app/Atelier` -> `ok (build complete)`.
- `swift test --package-path app/Atelier` -> `Test run with 409 tests in 40 suites passed after 5.592
  seconds`. Both new tests pass by name.
- `app/Atelier/.build/debug/Atelier --selftest` -> `SELFTEST: ALL PASS`.
- `app/Atelier/scripts/build_and_run.sh run` -> built, ad hoc signed, `satisfies its Designated
  Requirement`, launched pid 34748. `atelier-doctor status --json` -> `status healthy`,
  `workspace.active true`, `cpuPercent 0.046`, `verdicts []`.
- GitNexus `impact` on `AgentTranscriptParser.consume` upstream -> 5 impacted, 1 direct, risk LOW.
  `claudeUserText` and `questionText` are not in the index yet, because they were added today.
- `detect_changes()` -> 6 changed files, all expected. Affected processes stay inside the transcript
  and response flow.
- The on-screen check is still not driven. The `Question` container, the larger text, and the accent
  rule were not observed on screen.
