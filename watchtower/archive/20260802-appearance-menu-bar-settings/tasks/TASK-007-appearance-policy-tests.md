# TASK-007 Tests for the appearance policy and persistence

Group: tests
Class: code

## Brief

Goal: Prove the clamping rules, the percent label, and the stored values, without a running window.

Change: one new test file covers `AtelierAppearancePolicy` and `AtelierAppearanceModel`.

How:

- Create [app/Atelier/Tests/AtelierTests/AtelierAppearancePolicyTests.swift](app/Atelier/Tests/AtelierTests/AtelierAppearancePolicyTests.swift).
  Follow the shape of the existing
  [app/Atelier/Tests/AtelierTests/AgentResponseTextSizeTests.swift](app/Atelier/Tests/AtelierTests/AgentResponseTextSizeTests.swift).
- Policy cases:
  - A value below 0.8 clamps to 0.8. A value above 1.6 clamps to 1.6.
  - A value between two steps snaps to the nearest step. For example 1.07 becomes 1.05.
  - The default text scale is 1.0 and survives a clamp unchanged.
  - `percentLabel(1.0)` is `100%`. `percentLabel(1.15)` is `115%`.
  - Every key constant has the exact string from the plan, so a rename cannot pass silently.
- Model cases, using a fresh `UserDefaults(suiteName:)` per test and removing the suite at the end:
  - A new model with an empty suite reports ligatures on and the menu bar item visible.
  - Turning ligatures off writes the key, and a second model built on the same suite reads `false`.
  - Turning ligatures off increases `codeFontRevision` by one. Setting the same value again does
    not change it.
  - Hiding the menu bar item writes the key and reloads as `false`.
- Zoom model persistence: add these cases only if `AtelierZoomModel` can be built in a test without
  a live window. Try `AtelierZoomModel(windowController: WindowController(), defaults: suite)`.
  - Setting the three text scales writes the three keys, and a second model reads them back.
  - If the construction needs a real window or a real screen, skip these cases, cover the storage
    round trip through the policy keys alone, and write the reason in the outcome sidecar.

Files:

- [app/Atelier/Tests/AtelierTests/AtelierAppearancePolicyTests.swift](app/Atelier/Tests/AtelierTests/AtelierAppearancePolicyTests.swift): new test file.

Expected result:

- The suite fails when a clamp bound, a step, a percent label, or a key string changes by accident.

## Verify

- `swift test --package-path app/Atelier` -> every test passes, and the new file's tests appear in
  the output.
- `swift test --package-path app/Atelier --filter AtelierAppearancePolicyTests` -> the filtered run
  passes and reports more than five tests.
- `git status --short -- app/Atelier/Tests` -> only the new test file changed.
