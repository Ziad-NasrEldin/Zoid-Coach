# First-week observation mode candidate evidence

## Scope

This batch implements the baseline counting, persistence, reporting, and accessible Today foundation for scenarios `ZC-032-001` through `ZC-032-006`.
It directly supports `ZC-032-002`, `ZC-032-003`, and `ZC-032-006`.
It does not complete `ZC-032-001`, `ZC-032-004`, or `ZC-032-005` because no production behavior-prompt generator or configured coaching-level model exists yet.

## End-user behavior

- A dedicated first-week surface explains why coaching is quiet and keeps planning and manual task controls available.
- The surface is directly discoverable in Today below the day-state invitation and before the active command overview.
- Progress counts only completed days with at least 30 observed minutes.
- Limited and missing days remain visible and cannot advance the gate.
- The current unfinished day never counts.
- Eligible gaming or distracting episodes are counted without producing prompt records.
- Seven qualifying days freeze the baseline so later observations cannot silently rewrite the result.
- The completed report summarizes observed work capacity, gaming days and minutes, eligible drift, unknown coverage, and conservative alert-sensitivity guidance.
- The report explicitly avoids grading effort or inferring intent.
- Loading, empty, failure, retry, observing, and completed states are accessible.

## Persistence and recovery

Migration 37 adds one local append-safe baseline-day ledger after the reserved migration 35 and 36 lanes.
Complete days cannot be downgraded by a later partial read.
Restart reconstruction restores the exact seven-day gate and report.
Daily Review corrections are applied while calculating the baseline without rewriting source behavior records.
The agent persists its reconciliation checkpoint once per local day across restart, records failures without falsely advancing the checkpoint, and also covers one-shot runs.

## Focused proof

- `swift test --filter BaselineObservation` passed eleven focused tests after independent verification.
- The tests cover seven-day suppression state, completion, restart, frozen results, missing and limited coverage, current-day exclusion, threshold-time drift eligibility only while planned work remains unfinished, completion-time ordering, gaming observation without overclaiming eligibility, correction-aware work and unknown aggregation, durable agent checkpoints, failure recovery, alert guidance, and migration 37.
- All focused migration 35, 36, and 37 tests passed after independent verification.
- `swift build --target ZoidCoachApp` passed.
- `swift build --target ZoidCoachAgent` passed.
- `git diff --check` passed.

## Shared-gate boundary

This builder did not run the full suite, release build, signed package, installed runtime, tracker sync, registry sync, or Lavish refresh.
Independent verification completed the focused gates at `9d2986948cd3fc7760b7ab3027beffb661ca225e`.
The full suite, release build, signed package, installed runtime, tracker sync, registry sync, and Lavish refresh remain reserved for the root integration lane.
