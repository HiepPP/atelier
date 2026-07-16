# TASK-006 Additional library compatibility gate

Group: E (dependency foundation)

## Brief

Goal: Prove SwiftUIX, KeyboardShortcuts, and Pow build with Atelier's current dependency pins.

Change: proposed packages -> repeatable compatibility result and exact production pins

How:

- Create an isolated Swift package that depends on all current and proposed packages.
- Pin SwiftUIX `0.3.1`, KeyboardShortcuts `3.0.1`, and Pow `1.0.5` exactly.
- Compile one minimal public API use from each package.
- Keep Luminare local and SwiftUI-Introspect at `26.0.1`.
- Add all three products to Atelier only after the isolated package passes.
- Do not lower the macOS 13 deployment target or any existing package version.

Files:

- [spike/ui-libraries-spike/Package.swift](../../spike/ui-libraries-spike/Package.swift) (isolated dependency matrix)
- [spike/ui-libraries-spike/Sources/UILibrariesSpike/main.swift](../../spike/ui-libraries-spike/Sources/UILibrariesSpike/main.swift) (minimal compile surface)
- [app/Atelier/Package.swift](../../app/Atelier/Package.swift) (exact production dependencies)
- [app/Atelier/Package.resolved](../../app/Atelier/Package.resolved) (resolved versions)

Expected result:

- All three packages resolve beside Luminare and SwiftUI-Introspect `26.0.1`.
- The spike and Atelier build for macOS 13.
- No package uses an unpinned branch or moving revision.

## Verify

- `swift package --package-path spike/ui-libraries-spike resolve` -> all dependencies resolve.
- `swift build --package-path spike/ui-libraries-spike` -> all three public APIs compile.
- `swift package --package-path app/Atelier resolve` -> production dependencies resolve.
- `swift build --package-path app/Atelier` -> Atelier builds.
- `rg -n '0.3.1|3.0.1|1.0.5|26.0.1' app/Atelier/Package.resolved spike/ui-libraries-spike/Package.resolved` -> exact pins appear.
