# TASK-004 Outcome

## Outcome

Status: DONE

Changed:
- Removed the incorrect Workspace and Threads rail tab switch.
- Kept one static Workspaces header and the existing Add Workspace action.
- Restored the trailing workspace count in the Workspaces header.
- Nested separate 28-point thread rows below each 44-point workspace row.
- Preserved workspace click, drag, drop, and context-menu targets.
- Added an active-scene, rail-owned two-second refresh task.
- Kept the next sidebar limited to Explorer and Git.
- Added an explicit terminal focus request after thread selection, including already-selected tabs.

Verified:
- Native smoke showed every workspace header with a nested thread area and no Threads tab.
- The header accessibility value was `Workspaces 6`, preserving the baseline count.
- `zsh -c 'exec -a claude /bin/sleep 14'` appeared as Running after five seconds while Atelier stayed active, covering two refresh cycles.
- The same live row changed to Done after the foreground process exited.
- Clicking another workspace header changed only the active project.
- Clicking the thread changed to its workspace and selected its exact terminal.
- Clicking the Done row while Terminal 1 was already selected focused its input. The typed command created `/tmp/atelier-thread-focus-sentinel-20260721-1350` with `THREAD_FOCUS_SENTINEL`.
- The deterministic model test proved running-to-done and terminal-removal transitions.
- Idle CPU sample was 0.0 percent while the rail refresh task was active.
- Focused terminal navigation, model, and detection tests -> 23 tests in three suites passed.
- Full `swift test --package-path app/Atelier` -> 188 tests in 21 suites passed.
- `app/Atelier/.build/debug/Atelier --selftest` -> all checks passed.
- `app/Atelier/scripts/build_and_run.sh run` -> built, signed, installed, and launched.
