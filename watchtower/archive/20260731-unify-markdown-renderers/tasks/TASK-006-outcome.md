# TASK-006 Outcome

## Outcome

Status: BLOCKED

Blocked: the three on-screen acceptance points need UI automation this session does not have. No `computer-use` plugin or skill is installed, so `$computer-use:computer-use` from the TASK Prompt cannot be invoked. The repo rule also forbids screenshots unless the user asks for visual evidence, and the user did not. `atelier-doctor probe` covers `main`, `editor`, `editor-scroll`, and `diff` only, so it has no path to a response card, a Mermaid toggle, or the Gemma sidecar.

Next decision needed: either install the `computer-use` plugin and rerun this TASK, or accept the on-screen points as a manual pass by the user.

## Changed

- None. This TASK writes no code.

## Contract

The runtime half of the acceptance pass is recorded below and holds. The on-screen half is not driven and must not be read as passed.

## Verified

- `app/Atelier/scripts/build_and_run.sh run` -> built, ad hoc signed, installed, launched. `No Apple signing identity found` is the expected local fallback.
- `app/Atelier/scripts/atelier-doctor status --json` -> `status healthy`, `workspace.active` true, `relativeRootName` `proto-cube-pvs`, `verdicts` empty. The measurement below is therefore trustworthy.
- Idle CPU, 30 samples of `ps -p 6030 -o %cpu=` at 2 second spacing over 60 seconds -> mean 1.01 percent, max 8.80 percent. The two samples above the band, 6.2 and 8.8 percent, land in the first 20 seconds after launch and are startup work.
- Settled idle CPU, `atelier-doctor` at 129 seconds uptime -> `cpuPercent` 0.0100 percent, with `cpuTimeSeconds` 0.141 across 129 seconds of uptime, which is a 0.11 percent lifetime average. Inside the 0.2 to 2 percent band once startup ends.
- `physicalFootprintBytes` 178,275,576 with one terminal tab and no file tabs.
- `ls -t ~/Library/Logs/DiagnosticReports/ | grep -ci atelier` -> `0`. No new Atelier crash report after the pass.
- NOT DRIVEN: acceptance point one, the continuous selection drag from a heading into a table.
- NOT DRIVEN: acceptance point two, the Mermaid source toggle showing then hiding on screen. The underlying range behavior is covered by the unit test "Toggling a Mermaid figure adds then removes its source range".
- NOT DRIVEN: acceptance point three, a Gemma sidecar chat message rendering with no clipped height.
- NOT MEASURED: idle CPU while an agent writes a transcript. That window needs a running agent inside the launched app.
