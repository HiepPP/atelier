# TASK-002 Show the question above each response

Group: A

## Brief

Goal: Show the user question that produced each final answer, above the answer, inside the response
panel card.

Today `AgentTranscriptParser` keeps only assistant final answers, so the panel shows an answer with
no prompt. The reader cannot tell what was asked.

Change: carry the newest preceding user message with each response, then render it as a quiet
collapsible block above the answer markdown.

### Transcript record shapes

Both providers write the user turn as its own JSON line, before the answer, in the same file.

Codex, in `~/.codex/sessions`:

```json
{"timestamp":"...","type":"response_item","payload":{"type":"message","id":"msg_...","role":"user","content":[{"type":"input_text","text":"..."}]}}
```

Claude, in `~/.claude/projects/<munged-workspace>`:

```json
{"type":"user","message":{"role":"user","content":"..."},"uuid":"...","timestamp":"...","cwd":"/Users/hiep/Projects/atelier","sessionId":"..."}
```

Claude `message.content` is a `String` on a plain turn and an array of blocks on a tool turn. Read
both: for an array, join the `text` blocks and ignore `tool_result` and `tool_use` blocks.

### Records to skip

These user lines are not questions and must not reach the panel:

- Claude: `isMeta` is true, or `isSidechain` is true.
- Claude: content whose only blocks are `tool_result`.
- Text that starts with `<local-command-caveat>`, `<command-name>`, or `<system-reminder>`.
- Codex: text that starts with `# AGENTS.md instructions`, `<INSTRUCTIONS>`, `<environment_context>`,
  or `## Referenced ChatGPT conversation:`.
- Any text that trims to empty.

When a skipped line is the only candidate, keep the previous kept question. When there is none,
`question` stays nil.

### Pairing rule

Parsing is streaming and resumable: `AgentTranscriptParser.State` is cached per file in
`CachedTranscript.parserState` and reused for the next appended read. Put the pending question in that
state so it survives across appends.

- On a kept user line, replace `state.pendingQuestion`.
- On an accepted final answer, attach the current `state.pendingQuestion` to the `AgentResponse`.
- Keep `pendingQuestion` after attaching. Two answers in one turn then share one question, which is
  correct.
- The 1 MiB first-parse cap can drop the question line. A response with no question in the parsed
  window gets `question: nil`. The UI must handle that.

### UI

- Add the question block above `selectableMarkdown(response.markdown)` inside `responseCard`.
- Label it `Question`, in `AtelierTypography.caption`, secondary, matching the existing card header row.
- Render the question as plain text, not markdown, so a pasted prompt cannot restyle the card.
- Clamp it to 3 lines by default. Add a disclosure control to expand and collapse it.
- Put `.atelierPointerCursor()` on the disclosure control. This is a hard rule.
- Cap the stored question length at 4000 characters so a giant pasted prompt cannot bloat memory or
  layout. Trim and add a trailing `...` marker when cut.
- Render nothing when `question` is nil. Do not show an empty label.

How:

- Run `impact({target: "AgentResponse", direction: "upstream"})` and
  `impact({target: "consume", direction: "upstream"})` before editing. Report the blast radius. Warn
  before proceeding on HIGH or CRITICAL risk.
- Read [app/Atelier/Sources/Atelier/Agent/AgentResponses.swift](app/Atelier/Sources/Atelier/Agent/AgentResponses.swift),
  [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift),
  and the `### Agent Responses` section of [DESIGN.md](DESIGN.md) first.
- Update [DESIGN.md](DESIGN.md) before the code change: state that each card shows the question above
  the answer, collapsed to 3 lines with a disclosure, as plain text, capped at 4000 characters, and
  hidden when unknown.
- Add `let question: String?` to `AgentResponse`. Keep `Equatable` and `Sendable`. Keep `id` built from
  the answer only, so an existing response id does not change.
- Add `pendingQuestion` to `AgentTranscriptParser.State`. Add the codex and Claude user readers next to
  `codexAssistantText` and `claudeAssistantText`.
- Update [app/Atelier/Sources/Atelier/Agent/AgentResponseMemoryFixture.swift](app/Atelier/Sources/Atelier/Agent/AgentResponseMemoryFixture.swift)
  and every `AgentResponse(...)` construction in tests for the new field.
- Add deterministic tests to [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift).
- Run `detect_changes()` at the end.

Files:

- [app/Atelier/Sources/Atelier/Agent/AgentResponses.swift](app/Atelier/Sources/Atelier/Agent/AgentResponses.swift):
  add `AgentResponse.question`, `State.pendingQuestion`, the two user-text readers, the skip list, and
  the 4000 character cap.
- [app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift](app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift):
  add the collapsible question block to `responseCard`.
- [app/Atelier/Sources/Atelier/Agent/AgentResponseMemoryFixture.swift](app/Atelier/Sources/Atelier/Agent/AgentResponseMemoryFixture.swift):
  fill the new field in its fixture responses.
- [app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift](app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift):
  add parser and pairing tests, and fix existing constructions.
- [DESIGN.md](DESIGN.md): update the `### Agent Responses` contract.

Expected result:

- A codex final answer carries the newest preceding codex user text.
- A Claude final answer carries the newest preceding Claude user text, from both the string and the
  array content shape.
- Injected instruction blocks, meta lines, slash-command lines, and tool results never appear as a
  question.
- The card shows `Question` above the answer, clamped to 3 lines, expandable, with the pointer cursor
  on the disclosure control.
- A response whose question was outside the parsed window renders with no question block and no gap.
- Response ids stay unchanged, so read state and unread counts keep working across a relaunch.

Prompt:

```text
Invoke $swiftui-expert-skill. Read app/Atelier/Sources/Atelier/Agent/AgentResponses.swift and
app/Atelier/Sources/Atelier/Agent/AgentResponsesView.swift in full, plus the "### Agent Responses"
section of DESIGN.md. Update DESIGN.md first, then add AgentResponse.question, carry a pending
question through AgentTranscriptParser.State so it survives appended reads, apply the skip list in
watchtower/tasks/TASK-002-show-question-in-response-panel.md, and render a collapsible plain-text
Question block above the answer in responseCard with .atelierPointerCursor() on its disclosure
control. Do not change how a response id is built. Keep every existing performance guard. Add
deterministic tests in app/Atelier/Tests/AtelierTests/AgentResponsesTests.swift.
```

## Verify

1. `swift build --package-path app/Atelier` -> succeeds.
2. `swift test --package-path app/Atelier` -> all tests pass, including the new ones.
3. `app/Atelier/.build/debug/Atelier --selftest` -> passes.
4. New test: codex lines `session_meta`, then a `role: "user"` `input_text` line, then a
   `phase: "final_answer"` line, produce one response whose `question` equals the user text.
5. New test: a Claude `type: "user"` line with a `String` content, then an `end_turn` assistant line,
   produce one response whose `question` equals that string. Repeat with an array content holding one
   `text` block.
6. New test: a user line with `isMeta: true`, a `<command-name>` line, an `<INSTRUCTIONS>` line, and a
   `tool_result`-only content line all leave `question` nil when they are the only candidates.
7. New test: a question line in the first read and its answer in an appended read still pair, proving
   `pendingQuestion` survives in the cached parser state.
8. New test: a question above 4000 characters is stored trimmed to 4000 characters plus the `...`
   marker.
9. New test: response ids for a fixture with and without a question are identical.
10. `app/Atelier/scripts/build_and_run.sh run` -> builds, signs, installs, and opens the app.
11. Open the panel with `Cmd-R` on a workspace with recent agent turns. Confirm the card shows
    `Question` above the answer, clamped to 3 lines. Click the disclosure control and confirm it
    expands, collapses, and shows the link pointer cursor on hover.
12. Confirm a response with no known question shows no `Question` label and no empty row.
13. `detect_changes()` -> only the expected symbols and flows changed.
