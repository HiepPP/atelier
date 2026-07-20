# TASK-010 Unified feed redesign and larger type

Group: standalone

## Brief

Goal: collapse the sidecar's stacked feature boxes into one feed with one input, and raise the interface type scale.

Change: 7 fixed sections and 2 text inputs -> header with intent chip and gear, one card feed, one prompt field with quick-action chips.

How:

- Rewrite [app/Atelier/Sources/Atelier/Agent/Sidecar/GemmaSidecarView.swift](app/Atelier/Sources/Atelier/Agent/Sidecar/GemmaSidecarView.swift): header (icon, title, status, intent chip popover, gear popover with feature toggles), one feed scroll view, chip row plus single prompt bar.
- Convert feature views to feed cards that render nothing while idle: Guardian, Whisper, Intent warning, Journal milestones, Briefing (idle state becomes a Claude Handoff chip).
- Raise type tokens in [app/Atelier/Sources/Atelier/Theme/AtelierTheme.swift](app/Atelier/Sources/Atelier/Theme/AtelierTheme.swift): caption 12, label 12.5, body 13.5, uiSize 14, headline 16.
- Update [DESIGN.md](DESIGN.md) sidecar contract and typography table first.

Files:

- [DESIGN.md](DESIGN.md) (sidecar layout contract, typography table)
- [app/Atelier/Sources/Atelier/Theme/AtelierTheme.swift](app/Atelier/Sources/Atelier/Theme/AtelierTheme.swift) (type scale)
- [app/Atelier/Sources/Atelier/Agent/Sidecar/GemmaSidecarView.swift](app/Atelier/Sources/Atelier/Agent/Sidecar/GemmaSidecarView.swift) (three-zone layout)
- [app/Atelier/Sources/Atelier/Agent/Sidecar/TerminalGuardianFeature.swift](app/Atelier/Sources/Atelier/Agent/Sidecar/TerminalGuardianFeature.swift) (card, toggle moved to gear)
- [app/Atelier/Sources/Atelier/Agent/Sidecar/SessionJournalFeature.swift](app/Atelier/Sources/Atelier/Agent/Sidecar/SessionJournalFeature.swift) (milestone rows)
- [app/Atelier/Sources/Atelier/Agent/Sidecar/IntentGuardFeature.swift](app/Atelier/Sources/Atelier/Agent/Sidecar/IntentGuardFeature.swift) (warning card only)
- [app/Atelier/Sources/Atelier/Agent/Sidecar/PrecommitWhisperFeature.swift](app/Atelier/Sources/Atelier/Agent/Sidecar/PrecommitWhisperFeature.swift) (card)
- [app/Atelier/Sources/Atelier/Agent/Sidecar/ClaudeBriefingFeature.swift](app/Atelier/Sources/Atelier/Agent/Sidecar/ClaudeBriefingFeature.swift) (idle hidden, card states)
- [app/Atelier/Tests/AtelierTests/DisplaySizingTests.swift](app/Atelier/Tests/AtelierTests/DisplaySizingTests.swift) (token assertions)

Expected result:

- Sidecar shows exactly one text input in the body; intent moves to a header chip.
- Idle background features occupy zero space in the feed.
- Interface text renders at the raised scale.

## Verify

- `swift build --package-path app/Atelier` -> builds clean.
- `swift test --package-path app/Atelier` -> all tests pass.
- `app/Atelier/.build/debug/Atelier --selftest` -> passes.
- Manual: launch app, terminal tab -> header shows chip and gear; feed empty state; chips above one input; quick action streams an answer into the feed.
