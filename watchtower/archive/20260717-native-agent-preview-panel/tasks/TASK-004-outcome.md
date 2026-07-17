# TASK-004 Outcome

## Outcome

Status: DONE

Changed:
- Added 480, 720, and 960 point Mermaid render buckets.
- Added a shared 16-entry LRU cache with one long-lived serialized renderer.
- Bounded in-flight work and made `removeAll()` cancel and clear pending renders.
- Preserved the last valid image while a new width bucket renders.
- Added width-bucket debounce and automatic selectable source fallback.

Contract:
- Pixel-level resizing inside one width bucket does not start another Mermaid render.
- Successful diagrams are reused by source and width bucket.
- Cache growth remains bounded and evicts the least recently used image.
- Render failures expose selectable Mermaid source without touching SwiftTerm.

Verified:
- Mermaid PNG, width bucket, cache reuse, cancellation, and invalid-source fallback tests passed.
- `swift test --package-path app/Atelier` passed all 65 tests.
- `app/Atelier/.build/debug/Atelier --selftest` reported `SELFTEST: ALL PASS`.
- `app/Atelier/scripts/build_and_run.sh run` built, ad hoc signed, installed, and launched Atelier.
- Computer Use confirmed stable empty-state layouts at narrow and wide window sizes.
- Live Codex and Claude Markdown and Mermaid responses rendered while SwiftTerm remained mounted.
- Resizing the populated panel from 448 to 496 points kept the diagram visible without black or blank output.
- Invalid Mermaid displayed its warning and selectable source automatically without affecting terminal state.
