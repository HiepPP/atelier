# Learn 20260728-transcript-refresh-skip-unchanged

## Summary

Discrepancy: 2 found. All seven TASKs shipped their code as planned, but the shared CPU bar was
unattainable as written and had to be revised, and the burst owner moved past the planned scope
twice before the plan closed.

## Per TASK

- TASK-001: match.
- TASK-002: match.
- TASK-003: plan expected the foreign-file skip to reach the 2 percent bar -> shipped the skip,
  bar still failed. Mistake: the bar bundled unrelated costs (walk, git, SwiftUI) into one TASK's
  exit check. Fix: give a perf TASK a bar scoped to the path it changes.
- TASK-004: same pattern as TASK-003. Cap shipped and worked; bar failed on other owners.
- TASK-005: same pattern. Window shipped; the plan needed two extra fixes (discovery-walk cache,
  scoped unread badge) and a revised bar before the shared check passed.
- TASK-006: match, with a handoff: the sample proved git frames were blocked reads, and the real
  compute was file-tree and SwiftUI refresh, which became TASK-007.
- TASK-007: match. Profile named AttributeGraph churn; throttle plus scoped revision read cut the
  write-burst median from 16.9 to 1.4 percent.

## Plan-Level

- The burst owner migrated across the plan: parse -> discovery walk -> git status -> SwiftUI
  invalidation. Each TASK removed one layer and exposed the next, so TASK-003/004/005 sat BLOCKED
  for the whole plan on a bar their own changes could not reach.
- The strict "top 5 samples at or below 2 percent" bar has a floor while an agent produces a new
  response every 0.5 seconds; residual work is real publishing, not waste. The revised bar
  (median at or below 2, p90 at or below 5, no three consecutive samples above 10) was accepted
  on 2026-07-29 and both live windows passed.

## Lessons

- Scope a perf TASK's verify bar to the code path the TASK changes; keep one plan-level bar for
  the shared window instead of repeating it in every TASK.
- Distinguish burst waste from the cost of genuinely new work before extending a plan with more
  cut TASKs.
- Profile before choosing the fix: two of the biggest wins (directory-mtime walk cache, scoped
  observable reads) came from sample evidence, not from the planned file list.
