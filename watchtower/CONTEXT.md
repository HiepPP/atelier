# Plan Context

## Shared Context

- Product goal: Swift-native lightweight IDE for macOS. Source of truth is [PLAN.md](PLAN.md).
- Toolchain: Swift 6.2.3, Xcode 26.2, target arm64 macOS.
- Main app lives in [app/Atelier](app/Atelier) as an SPM executable package.
- Terminal spike lives in [spike/swiftterm-spike](spike/swiftterm-spike). It is a throwaway proof, not product code.
- Terminal library is SwiftTerm 1.14.0, embedded via LocalProcessTerminalView.
- Git runs through Process with an argument array. Never build shell command strings.
- FSEvents only triggers invalidation. Always run git status after an event for truth.
- Do not parse terminal text to guess agent or process state.

## Decisions

- MVP embeds the terminal in the app. It drops the earlier tmux and Ghostty plan.
- One workspace is open at a time. Switching workspace means opening another folder.
- Diff and file viewer stay read-only for the MVP. No inline editing.
- Verify each milestone with a --selftest mode plus a GUI smoke launch.
- Package Atelier as an ad-hoc signed `.app` bundle for local development and native GUI verification.

## Open Decisions

- None.

## References

- [PLAN.md](PLAN.md)
- [M0.md](M0.md)
- [M1.md](M1.md)
