# TASK-001 Luminare compatibility gate

Group: A (dependency foundation)

## Brief

Goal: Prove that Luminare can build beside SwiftUI-Introspect `26.0.1`. Do not change the production package until this gate passes.

Change: unverified package idea -> isolated, repeatable compatibility result

How:

- Create a small Swift package under [spike/luminare-spike](../../spike/luminare-spike/).
- Exercise `.luminareCompact`, `.luminareProminent`, and `LuminareSection` in one preview view.
- Confirm the stable `0.2.0` resolver conflict with the current Introspect pin.
- Test the smallest maintainable package patch that keeps Introspect `26.0.1`.
- Do not lower the Introspect version or remove `.v26` support.
- If a remote fork is required, stop and ask before creating it.

Files:

- [spike/luminare-spike/Package.swift](../../spike/luminare-spike/Package.swift) (isolated dependency matrix)
- [spike/luminare-spike/Sources/LuminareSpike/main.swift](../../spike/luminare-spike/Sources/LuminareSpike/main.swift) (minimal compile surface)

Expected result:

- One approved package source resolves with SwiftUI-Introspect `26.0.1`.
- The spike compiles on macOS 13 deployment settings.
- A failed safe route records a blocker and stops dependent tasks.

## Verify

- `swift package --package-path spike/luminare-spike resolve` -> dependency resolution completes.
- `swift build --package-path spike/luminare-spike` -> the three selected Luminare surfaces compile.
- `rg -n '26.0.1' spike/luminare-spike/Package.resolved` -> Introspect remains `26.0.1`.
