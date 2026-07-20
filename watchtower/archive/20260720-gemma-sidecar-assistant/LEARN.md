# Learn 20260720-gemma-sidecar-assistant

## Summary

Discrepancy: 1 found. All 9 planned TASKs shipped as specified; the shipped UI then needed an unplanned redesign (TASK-010) because the planned per-feature sections cluttered the sidecar.

## Per TASK

- TASK-001: match.
- TASK-002: match. Shipped with a registry/slot pattern beyond the spec, which made the later feature work and the redesign cheap.
- TASK-003: match.
- TASK-004: match.
- TASK-005: match. Toggle later moved from the card into the gear popover by TASK-010.
- TASK-006: match. Idle Generate row later replaced by a chip in TASK-010.
- TASK-007: match. Section chrome later replaced by feed milestones in TASK-010.
- TASK-008: match. Persistent intent field later replaced by a header chip in TASK-010.
- TASK-009: match.
- TASK-010: added mid-plan after user feedback on clutter. Plan spec said each feature owns its own view; shipped result stacked 7 fixed sections and 2 inputs. Fix: one feed, one input, toggles in a gear popover, plus a raised type scale.

## Plan-Level

- The plan specified feature behavior well but never specified a shared surface budget. Each feature adding its own always-visible section was the predictable result.

## Lessons

- When several features share one panel, define the shared layout contract (zones, one input, idle-renders-nothing rule) in the first design TASK, not per feature.
- Cards that render nothing while idle keep background features free in visual cost; make that a default contract for advisory features.
