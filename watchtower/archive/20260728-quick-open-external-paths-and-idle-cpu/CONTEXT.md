# Watchtower Context

Shared context for the active plan. Read this before any TASK in [watchtower/NEXT.md](NEXT.md).

## Repository Rules

- Read [DESIGN.md](../DESIGN.md) before changing code. Update it first when a TASK changes the contract.
- Invoke `$swiftui-expert-skill` before writing, editing, or reviewing Swift code.
- Run GitNexus `impact` before editing a symbol, and `detect_changes` before committing.
- Every clickable control needs `.atelierPointerCursor()`.
- Keep the simplest structure that gives the required behavior.

## Verification Bias

Run these from the repository root:

```bash
swift build --package-path app/Atelier
swift test --package-path app/Atelier
app/Atelier/.build/debug/Atelier --selftest
app/Atelier/scripts/build_and_run.sh run
```

Two tests already fail on a clean tree. They are timing tests, not regressions:

- `WorkspaceToolExecutorTests.swift:90` "In-flight search stops when its owner is cancelled"
- `WorkspaceSearchTests.swift:653` "New typing cancels a running stale search"

Treat only new failures as regressions.

## Source Anchors

- [app/Atelier/Sources/Atelier/Commands/AtelierPaletteModel.swift](../app/Atelier/Sources/Atelier/Commands/AtelierPaletteModel.swift): owns Quick Open state, query, and ranked results.
- [app/Atelier/Sources/Atelier/Commands/WorkspaceFileIndex.swift](../app/Atelier/Sources/Atelier/Commands/WorkspaceFileIndex.swift): walks the workspace root and builds file candidates.
- [app/Atelier/Sources/Atelier/Commands/AtelierPaletteSearch.swift](../app/Atelier/Sources/Atelier/Commands/AtelierPaletteSearch.swift): ranks file and command matches.
- [app/Atelier/Sources/Atelier/Commands/AtelierPaletteView.swift](../app/Atelier/Sources/Atelier/Commands/AtelierPaletteView.swift): renders the shared palette panel.
- [app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift](../app/Atelier/Sources/Atelier/Terminal/TerminalTabs.swift): `openFile(_:)` at line 703 opens a URL as an editor tab.

## Performance Baseline

The repository rule is 0.2 to 2 percent CPU at idle. Measure with:

```bash
PID=$(pgrep -x Atelier | head -1)
top -l 50 -s 2 -pid $PID -stats pid,cpu
```
