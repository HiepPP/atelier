# TASK-010 Outcome

## Outcome

Status: DONE

Changed:
- DESIGN.md: sidecar contract rewritten to the one-feed, one-input layout; typography table raised (caption 12, label 12.5, body 13.5, uiSize 14, headline 16).
- AtelierTheme.swift: type tokens raised to match.
- GemmaSidecarView.swift: three-zone layout; intent chip popover and gear popover (Guardian and Journal toggles) in the header; single feed; chip row plus one prompt bar; Claude Handoff chip triggers the briefing.
- Guardian, Whisper, Intent warning, Journal, Briefing views became feed cards that render nothing while idle; body toggles removed.
- DisplaySizingTests.swift: token assertions updated.

Contract:
- One text input in the panel body; intent edited via the header chip.
- Idle background features reserve no space.
- Feature models unchanged; only their views moved into the feed.

Verified:
- swift build -> clean.
- swift test -> 171 tests, 18 suites, all pass.
- Atelier --selftest -> ALL PASS.
- build_and_run.sh run -> app launched; screenshot confirms header chip and gear, feed with streamed Gemma answer and one-line tool row, chips above a single input.
