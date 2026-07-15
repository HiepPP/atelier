# Repository Guidelines

## Project Structure & Module Organization

Atelier is a macOS 13+ SwiftUI application built with Swift Package Manager.

- `app/Atelier/Sources/Atelier/`: production Swift sources. Keep views, models, services, and AppKit bridges in focused files.
- `app/Atelier/Packaging/`: application bundle metadata, including `Info.plist`.
- `app/Atelier/script/` and `app/Atelier/scripts/`: build, install, signing, logging, and verification scripts.
- `spike/swiftterm-spike/`: isolated SwiftTerm experiments. Do not add production behavior here.
- `watchtower/tasks/`: task specifications and verification outcomes. Update these only when working through the Watchtower workflow.
- `IDEA.md`, `PLAN.md`, `M0.md`, and `M1.md`: product and milestone notes.

Generated directories such as `.build/` and `dist/` must remain untracked.

## Build, Test, and Development Commands

Run commands from the repository root:

```bash
swift build --package-path app/Atelier
app/Atelier/.build/debug/Atelier --selftest
app/Atelier/script/build_and_run.sh run
app/Atelier/script/build_and_run.sh --verify
app/Atelier/scripts/build-app.sh release
```

`swift build` compiles the package. `--selftest` checks persistence, file loading, Git parsing, and Git operations. The main script builds, signs, installs, and optionally verifies the app process. The release script creates `app/Atelier/dist/Atelier.app`.

## Coding Style & Naming Conventions

Use four-space indentation and standard Swift API naming. Types use `UpperCamelCase`; properties, methods, and enum cases use `lowerCamelCase`. Name SwiftUI views with a `View` suffix and observable models with a `Model` suffix. Prefer small extensions and native SwiftUI modifiers before adding abstractions. Keep AppKit customization defensive and idempotent.

Use `rg` for repository search. Do not add or use GitNexus metadata in this repository.

## Testing Guidelines

There is no separate XCTest target yet. Extend `SelfTest` in `AtelierApp.swift` for deterministic non-UI behavior. Every change must pass the build and self-test commands. UI changes also require a native app check at narrow and wide window sizes. Record exact failures and screenshots when relevant.

## Commit & Pull Request Guidelines

This repository has no commit history yet. Use concise Conventional Commit messages, such as `fix(ui): align split-view dividers`. Keep commits scoped to one outcome.

Pull requests should include a short problem statement, implementation summary, verification commands, linked Watchtower task when applicable, and before/after screenshots for visual changes. Never include `.build`, `dist`, temporary workspaces, credentials, or signing identities.
