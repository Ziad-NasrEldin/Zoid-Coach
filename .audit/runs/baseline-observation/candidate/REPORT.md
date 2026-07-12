# First-week observation mode candidate evidence

## Scope

This batch implements the complete code path for scenarios `ZC-032-001` through `ZC-032-006`.
It records seven finished local days with adequate behavior coverage before behavior-triggered accountability prompts may begin.

## End-user behavior

- A dedicated first-week surface explains why coaching is quiet and keeps planning and manual task controls available.
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
The agent reconciles prior completed days once per local day and also covers one-shot runs.

## Focused proof

- `swift test --filter BaselineObservation` passed eight focused tests.
- The tests cover seven-day suppression, completion, restart, frozen results, missing and limited coverage, current-day exclusion, drift eligibility only while planned work remains unfinished, completion-time ordering, gaming observation without overclaiming eligibility, correction-aware aggregation, alert guidance, and migration 37.
- `swift build --target ZoidCoachAgent` passed.
- `git diff --check` passed.

## Shared-gate boundary

This builder did not run the full suite, release build, signed package, installed runtime, tracker sync, registry sync, or Lavish refresh.
Those gates remain reserved for a fresh verifier after migrations 35 and 36 and the Dashboard composition seam are integrated.
