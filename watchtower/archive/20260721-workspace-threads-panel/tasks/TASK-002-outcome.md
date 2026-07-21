# TASK-002 Outcome

## Outcome

Status: DONE

Changed:
- Added `AgentDetectionPolicy` with the five default agent names.
- Added a foreground process reader using `tcgetpgrp` and `KERN_PROCARGS2`.
- Added `TerminalController.currentForegroundAgentName()` with closed-fd guards.
- Kept argv reads on demand and added no background timer or logging.

Verified:
- Agent detection tests cover direct executable, path token, shell, and regular command cases.
- Native smoke detected a harmless foreground `claude` argv fixture as Running.
- `swift build --package-path app/Atelier` -> passed.
- `swift test --package-path app/Atelier` -> 188 tests in 21 suites passed.
