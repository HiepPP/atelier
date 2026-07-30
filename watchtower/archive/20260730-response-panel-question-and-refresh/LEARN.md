# Learn 20260730-response-panel-question-and-refresh

## Summary

Discrepancy: 2 found. Both TASKs shipped what they promised and passed every listed check, but one
spec wrote a skip rule that could not hold, and neither spec could prove its on-screen result.

## Per TASK

- TASK-001: plan named five suspects and asked the implementer to confirm each one before fixing.
  Shipped exactly that: suspects 1, 2, and 4 held and were fixed, suspect 3 was confirmed as a latency
  budget and the watcher latency still moved from 1.0 to 0.3 seconds after the CPU check passed, and
  suspect 5 did not hold so the view stayed unchanged. Mistake: none in the work. Writing a spec that
  ranks its own suspects and demands confirmation worked well, and it correctly caught one wrong guess.
- TASK-002: plan said to skip an injected user line by matching how its text opens, and listed the
  openers. Shipped that list. Mistake: the rule was wrong in kind, not in detail. A harness injection
  is written with the user role and plain prose, so no list of text openings can separate it from a
  real turn. A background task notification reached the panel as the question the same day the plan was
  marked DONE. Likely cause: the skip list was written from a sample of transcript lines that happened
  to be tagged, instead of from the field that records why a line exists. Fix: gate on `origin.kind`
  and keep the prefix list only as the fallback for older transcripts that carry no `origin`. That
  landed as a follow-up, recorded in `tasks/TASK-002-outcome.md`.

## Plan-Level

- Verify lists can pass in full while the real defect sits outside them. TASK-002 Verify steps 4 to 9
  all passed, including a step for injected lines, because each one tested a line shape the spec had
  already thought of. Write at least one verify step against live data, not only crafted fixtures.
- On-screen acceptance was written into both TASKs and neither could run it. A fan-out builder has no
  native UI automation, and repository rules forbid screenshots unless the user asks. Both builders
  reported NOT DRIVEN, and the reviewer had to pass it through as non-blocking. Put on-screen checks in
  their own TASK for a session that can drive them.
- Grouping held. Both TASKs touched `AgentResponses.swift` and TASK-002 depended on TASK-001, so they
  collapsed into one group and one builder edited the file in order. No collision, unlike the earlier
  parallel-builder failure recorded in `watchtower/MEMORY.md`.

## Lessons

- Prefer a field that records intent over text matching. When a transcript, log, or event says why a
  record exists, gate on that. Treat string prefixes as a fallback for records written before the field
  existed, and check how many real records lack it before removing the fallback.
- A DONE row means the listed checks passed. It does not mean the rule behind them is sound. When a
  spec invents a classification rule, verify it against a real corpus before marking the TASK done.
- Keep a separate TASK for any acceptance point that needs a human or UI automation at the screen, so a
  fan-out run does not close with unproven claims folded into a passing verdict.
