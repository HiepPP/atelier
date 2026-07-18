# Repository Guidelines

## Project Structure & Module Organization

Atelier is a macOS 26+ SwiftUI application built with Swift 6.2 and Swift Package Manager.

- `app/Atelier/Sources/Atelier/`: production Swift sources. Keep views, models, services, and AppKit bridges in focused files.
- `app/Atelier/Tests/AtelierTests/`: focused tests for models, parsers, persistence, and services.
- `app/Atelier/Packaging/`: application bundle metadata, including `Info.plist`.
- `app/Atelier/Resources/`: source assets used to build the application bundle.
- `app/Atelier/scripts/`: build, install, signing, logging, and verification scripts.
- `Vendor/Luminare/`: pinned local Luminare package and its required license.
- `README.md`: current product, architecture, and development reference.

Generated directories such as `.build/` and `dist/` must remain untracked.

## Design System Contract

Read `DESIGN.md` before changing code. Follow its current architecture, tokens, component contracts, interaction rules, accessibility rules, and verification requirements.

- Treat `DESIGN.md` as the design contract for the shipped application.
- If a new requirement changes the contract, update `DESIGN.md` before editing code.
- If `DESIGN.md` is stale or conflicts with the requested behavior, reconcile and update it first.
- Do not leave code and `DESIGN.md` describing different behavior after a change.
- When the design contract stays unchanged, keep `DESIGN.md` unchanged and follow it during implementation.

## Build, Test, and Development Commands

Run commands from the repository root:

```bash
swift build --package-path app/Atelier
swift test --package-path app/Atelier
app/Atelier/.build/debug/Atelier --selftest
app/Atelier/scripts/build_and_run.sh run
app/Atelier/scripts/build_and_run.sh --verify
app/Atelier/scripts/build_and_run.sh --release
```

`swift build` compiles the package. `swift test` runs focused core tests. `--selftest` checks persistence, file loading, Git parsing, and Git operations. The main script builds, signs, installs, and optionally verifies the app process. The release script creates `app/Atelier/dist/Atelier.app`.

## Post-Implementation Build

After completing any implementation task, automatically run `app/Atelier/scripts/build_and_run.sh` to build and launch the updated app.

- Run it once the code change is finished and `swift build`/`swift test` pass.
- Default to `app/Atelier/scripts/build_and_run.sh run` to build, sign, install, and open the app.
- If the build fails, report the failure and stop. Do not mark the task complete.
- Skip only when the change touches no Swift sources (docs, scripts, or metadata only).

## Coding Style & Naming Conventions

Use four-space indentation and standard Swift API naming. Types use `UpperCamelCase`; properties, methods, and enum cases use `lowerCamelCase`. Name SwiftUI views with a `View` suffix and observable models with a `Model` suffix. Prefer small extensions and native SwiftUI modifiers before adding abstractions. Keep AppKit customization defensive and idempotent.

Use `rg` for repository search. Do not add or use GitNexus metadata in this repository.

## Testing Guidelines

Add deterministic non-UI coverage under `Tests/AtelierTests`. Keep `SelfTest.swift` for packaged binary checks. Every change must pass build, tests, and self-test. UI changes also require native checks at narrow and wide window sizes. Record exact failures and screenshots when relevant.

## Commit & Pull Request Guidelines

Use concise Conventional Commit messages, such as `fix(ui): align split-view dividers`. Keep commits scoped to one outcome.

Pull requests should include a short problem statement, implementation summary, verification commands, and before/after screenshots for visual changes. Never include `.build`, `dist`, temporary workspaces, credentials, or signing identities.
