# Design QA

## Scope

- Source visual: `/Users/hiep/.codex/generated_images/019f7513-0fda-7bc3-bc2c-c936289be4a1/exec-e7d30251-f092-4254-965d-c0ff85762d47.png`
- State: Explorer selected, terminal active, Agent Responses open.
- 760x552 capture: `/var/folders/pc/q6gvjjw921z663q3lkd__4t40000gn/T/atelier-760x550-sidecar.jpeg`
- 1000x702 capture: `/var/folders/pc/q6gvjjw921z663q3lkd__4t40000gn/T/atelier-1000x700-sidecar.jpeg`
- Maximum native capture: `/var/folders/pc/q6gvjjw921z663q3lkd__4t40000gn/T/atelier-1440x900-sidecar.jpeg`
- Full comparison: `/tmp/atelier-design-qa-full.png`
- Sidecar comparison: `/tmp/atelier-design-qa-sidecar.png`

## Comparison

- Wide layout preserves the reference's Explorer, terminal, and response columns.
- Response sidecar stays visually subordinate to the terminal.
- Narrow layout uses a trailing overlay and keeps the terminal tab visible.
- Header controls remain on one line after the compact `Final` fallback.
- Live content shows the correct empty state because no agent response exists.
- Source visual uses synthetic response content, so body density is not comparable.

## Interaction Checks

- Explorer and Git switch inside one left sidebar.
- Opening an editor removes the response control and sidecar.
- Returning to the terminal restores the open sidecar.
- Focus mode hides the left sidebar while preserving terminal responses.
- Close, refresh, previous, and next controls expose native accessibility labels.

## Findings History

| Severity | Finding | Resolution |
|---|---|---|
| P2 | `Final` wrapped in the combined narrow sidebar and sidecar state. | Added `ViewThatFits` with an icon-only compact fallback. |
| P2 | Exact 1440x900 capture exceeded the active display. | Captured the native maximum at 1284x768 and covered split selection with layout policy tests. |

## Result

Final result: passed
