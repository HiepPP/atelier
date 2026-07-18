# TASK-002 Add Session Navigation History

Group: A (file tab state foundation)

## Brief

Goal: Add bounded session-only file navigation and closed-file history. Keep state transitions pure and deterministic.

Change: Current selected file only -> Back, Forward, and closed permanent file stacks.

How:

- Add a small file navigation state type with backward, forward, and closed stacks.
- Store standardized file URLs and their preview or permanent disposition.
- Cap each stack at 100 entries and remove consecutive duplicate targets.
- Record normal file navigation and clear Forward after a new branch.
- Suppress history recording while Back, Forward, or Reopen Closed Tab runs.
- Reuse an open target tab or reopen the target with its stored disposition.
- Record closed permanent file tabs in last-closed-first order.
- Exclude preview replacement, preview closure, and non-file tabs from closed history.
- Clear all history when `closeAll()` ends the workspace session.
- Expose live availability for Back, Forward, and Reopen Closed Tab.
- Add deterministic tests for ordering, branching, bounds, deduplication, and exclusions.

Files:

- [app/Atelier/Sources/Atelier/Terminal/FileNavigationHistory.swift](app/Atelier/Sources/Atelier/Terminal/FileNavigationHistory.swift) (new pure bounded navigation state)
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift) (record and execute file navigation transitions)
- [app/Atelier/Tests/AtelierTests/TerminalTabsNavigationTests.swift](app/Atelier/Tests/AtelierTests/TerminalTabsNavigationTests.swift) (history transition and tab integration tests)

Expected result:

- A -> B -> C supports Back to B and Forward to C.
- Opening D after going Back clears the old Forward path.
- Back, Forward, and Reopen do not create recursive history entries.
- Reopen Closed Tab restores the newest closed permanent file.
- Preview and non-file closure never enable Reopen Closed Tab.
- Closing the workspace drops all navigation and closed-file state.

Prompt:

```text
Implement the session file navigation state described in this TASK. Keep the pure stack transitions separate from TerminalTabsModel integration. Track file URLs only, cap each stack at 100, and exclude cursor state, non-file tabs, and preview closure.
```

## Verify

- `swift test --package-path app/Atelier --filter TerminalTabsNavigationTests` -> ordering, branching, bounds, deduplication, and closed-file tests pass.
- Run A -> B -> C -> Back -> D -> Forward -> Forward remains disabled after D.
- Close one preview and one permanent file -> only the permanent file is reopened.
- Call `closeAll()` -> all three action availability values become false.
