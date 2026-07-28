# TASK-002 Idle CPU burst investigation

Group: B

## Brief

Goal: find what makes Atelier burn about 50 to 95 percent CPU in short repeating bursts while the app sits idle, then fix it or record why it is acceptable.

Change: this is an investigation first. Only change code after the evidence names one owner.

Evidence already collected on 2026-07-28:

- The burst is not caused by the Markdown preview work in commit `96274bd`. It reproduces on the clean tree at `de153a4`.
- Over a matched 100 second window, the clean build peaked at 71.1, 55.3, 51.1, 50.1, and 46.8 percent.
- Over the same window, the changed build peaked at 69.3, 23.7, 2.5, 1.9, and 1.3 percent.
- Between bursts the process sits at 0.2 to 0.8 percent, which matches the repository rule.
- Each burst lasts about 6 seconds and repeats. The exact period is not measured yet.
- A 4 second `sample` during a burst showed the main thread mostly parked in `mach_msg2_trap`.
- Hot frames seen in that sample, none confirmed as the owner:
  - `LayoutEngineBox.sizeThatFits` and other SwiftUI layout frames.
  - `AgentTranscriptParser.parse(data:workspacePath:sourceID:modifiedAfter:state:)`.
  - `GitOutputBox.capture(_:limit:)` at [app/Atelier/Sources/Atelier/Git/GitService.swift](../../app/Atelier/Sources/Atelier/Git/GitService.swift) line 244.
  - `PrecommitWhisperModel.tick()`.
  - A `JavaScriptCore libpas scavenger` thread.
- The app had no file tab open, so the Markdown preview surface was not mounted.

How:

- Measure the period first. Log wall-clock timestamps of each burst start over at least 5 minutes.
- Take a `sample` that starts inside a burst, not before it. Use a longer duration, for example 8 seconds.
- Read `Sort by top of stack` and the per-thread counts. Ignore threads parked in `__workq_kernreturn` and `mach_msg2_trap`.
- Compare the burst period against the known timers: agent transcript monitoring, Git status refresh, the pre-commit whisper tick, and runtime diagnostics.
- Use `app/Atelier/scripts/atelier-doctor capture --seconds 3` during a burst and read the flight recorder timeline around it.
- Name one owner with a repeating stack before proposing a fix.
- If the owner is a poll, apply the repository performance rules: debounce filesystem-driven refreshes, collapse a burst of events into one refresh, and never reload when a refresh produced no change.

Files:

- Investigation only at first. Likely suspects to read, not to edit blindly:
  - [app/Atelier/Sources/Atelier/Agent/AgentResponses.swift](../../app/Atelier/Sources/Atelier/Agent/AgentResponses.swift): transcript parsing and monitoring.
  - [app/Atelier/Sources/Atelier/Git/GitService.swift](../../app/Atelier/Sources/Atelier/Git/GitService.swift): Git subprocess capture.
  - [app/Atelier/Sources/Atelier/Agent/Sidecar/](../../app/Atelier/Sources/Atelier/Agent/Sidecar/): pre-commit whisper and background sidecar features.

Expected result:

- One named owner with a repeating stack and a measured period.
- A written decision: fix it, or record why the cost is acceptable.
- If fixed, idle CPU stays in the 0.2 to 2 percent range across a 5 minute window with no interaction.

Prompt:

```text
Investigate the periodic idle CPU burst in Atelier. Use /solve. Measure the burst period
first, then sample inside a burst and identify one repeating owner stack. Do not change
code until the evidence names the owner. Follow the runtime-reading guide in CLAUDE.md.
```

## Verify

- Record the burst period in the outcome sidecar, in seconds.
- Attach the repeating stack from the `sample` output that names the owner.
- Run this for 5 minutes with no interaction and record the five highest values:

```bash
PID=$(pgrep -x Atelier | head -1)
top -l 150 -s 2 -pid $PID -stats pid,cpu | rg "^ *$PID" | awk '{print $2}' | sort -rn | head -5
```

- If a fix ships, all five values must be at or below 2 percent.
- If no fix ships, record the reason and the measured cost.
- Run `swift build --package-path app/Atelier` and `app/Atelier/.build/debug/Atelier --selftest` after any code change.
