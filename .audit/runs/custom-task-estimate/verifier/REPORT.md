# Custom task estimate verifier report

## Result

Every plan task estimate selector now offers a custom whole-minute entry path in addition to the existing presets.
Valid input uses the existing durable estimate callback and immediately updates estimate-dependent capacity state.

## Verifier corrections

- Candidate accessibility identifiers were duplicated across every task row.
  Every trigger, input, Save, Cancel, and error identifier now includes the durable task identifier.
- Cancel could leave an existing estimate in change mode.
  Cancel now restores the confirmed estimate state without invoking the callback.
- Cancel now supports the standard Escape keyboard shortcut.

## Verification

- `swift test --filter TaskEstimateInputTests` passed before and after the authoritative rebase.
- `swift test --filter PlanningCapacityStateTests` passed.
- Validation covers empty, zero, negative, decimal, text, and values above 480 minutes with specific corrective copy.
- `swift build -c release` passed after rebase.

## Conservative acceptance boundary

Two pre-rebase package attempts overlapped with active SwiftPM work and were stopped.
The clean post-rebase packaging attempt did not produce the signed QA bundle, so package verification and the installed invalid-input, Cancel, Return-save, capacity, and restart journey were not claimed.
`ZC-011-006` and `ZC-011-007` remain `Touches remaining` pending that installed proof.
