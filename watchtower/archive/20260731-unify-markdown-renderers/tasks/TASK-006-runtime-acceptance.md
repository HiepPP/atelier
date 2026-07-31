# TASK-006 Drive the on-screen and idle CPU acceptance pass

Group: standalone (needs a session with UI automation, so it cannot ride with the code group)

## Brief

Goal: Prove the unified renderer on screen and prove it did not add idle CPU cost. A builder cannot prove an on-screen SwiftUI claim, so this runs as its own TASK.

Change: code merged -> code accepted with real runtime evidence.

How:

- Build and launch with `app/Atelier/scripts/build_and_run.sh run`. Keep the window zoomed to full size.
- Check `app/Atelier/scripts/atelier-doctor status --json` first. Confirm `workspace.active` is true. An ad hoc signed build can drop the bookmark and report a false low idle number.
- Acceptance point one: open the response panel, select an answer with code and a table, and drag a selection from the first heading into the table. The selection stays continuous.
- Acceptance point two: click a Mermaid source toggle in a response. The source appears, then hides on a second click.
- Acceptance point three: open the Gemma sidecar and confirm a chat message renders with correct text and no clipped height.
- Measure idle CPU with `ps -p PID -o %cpu=` over a 60 second window while the app sits idle. Expect the 0.2 to 2 percent band.
- Measure again while an agent writes a transcript. Sample with `sample PID 3` if the number stays high, and look for a repeating reload or draw frame.
- Record the exact numbers, not a summary word.

Files:

- None. This TASK writes no code.

Expected result:

- All three acceptance points pass at full window size.
- Idle CPU stays inside the 0.2 to 2 percent band.
- No new crash report appears in `~/Library/Logs/DiagnosticReports/`.

Prompt:

```text
Use $computer-use:computer-use for the on-screen points only. Target bundle identifier app.atelier.Atelier. Use accessibility text and element_index actions. Do not take screenshots unless the user asks.
```

## Verify

- `app/Atelier/scripts/atelier-doctor status --json` -> status healthy and `workspace.active` true.
- Selection drag across a heading, a paragraph, and a table -> one continuous selection.
- Mermaid source toggle -> source shows, then hides.
- `ps -p PID -o %cpu=` sampled over 60 seconds -> idle stays in the 0.2 to 2 percent band.
- `ls -t ~/Library/Logs/DiagnosticReports/ | head` -> no new Atelier report after the pass.
