# TASK-005 Outcome

## Outcome

Status: DONE

## Changed

- Added image-only Markdown blocks with exact author alt text.
- Passed each Markdown file directory into the native preview.
- Added off-main local decoding and stable native attachments.
- Added framed placeholders and images with the design radius and hairline.

## Contract

- Only local file URLs are requested. Remote URLs remain placeholders.
- Loaded images retain the exact reserved bounds and scroll origin.
- Captions equal the source alt text. No caption is invented.

## Verified

- `swift test --package-path app/Atelier --filter AgentResponsesTests.markdownImageFigure --quiet` passed.
- The test covers local paths, remote rejection, checked-Sendable pixel decoding, cancellation, caption text, and stable bounds.
- The full-window native fixture rendered the local icon at fixed bounds with its exact alt-text caption.
- `swift build --package-path app/Atelier` and packaged selftest passed.
- Full `swift test --package-path app/Atelier --quiet` later passed all 282 tests after the Git pipe inheritance fix.
- `git diff --check` passed.
