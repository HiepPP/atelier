# TASK-002 Outcome

## Outcome

Status: DONE

## Changed

- Added capped depth metadata to unordered, ordered, and task list blocks.
- Added depth-aware gutters, tab stops, marker shapes, and marker color fading.
- Added equivalent depth presentation to transcript Markdown.

## Contract

- Leading spaces map to `min(3, spaces / 2)`.
- Wrapped text shares the item text indent.
- All list work is resolved before layout and scrolling.

## Verified

- `swift test --package-path app/Atelier --filter AgentResponsesTests.markdownNestedList --quiet` passed.
- `markdownTranscriptListMarkerDepth` passed a rendered-pixel check for ordered and task depth fading.
- `nativeMarkdownTaskItemStyling` passed.
- The test inspects depth zero through three paragraph indents and tab stops.
- The full-window native fixture showed filled, ring, and dash markers with stable wrapped indents.
- `swift build --package-path app/Atelier` and packaged selftest passed.
- Full `swift test --package-path app/Atelier --quiet` later passed all 282 tests after the Git pipe inheritance fix.
- `git diff --check` passed.
