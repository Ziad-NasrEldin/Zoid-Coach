# Active away-from-Mac work verification

## Candidate and verifier

The candidate `a2ec031` was applied to authoritative base `c73fbd5` in an isolated verifier worktree.
Focused verification found and fixed three end-user blockers in verifier commit `52f5c14`.
After rebasing onto authoritative dark-appearance commit `9df31e0`, those fixes became `07cf110`.

## Blockers fixed

- Success feedback now shows the exact selected duration instead of the literal text `(durationMinutes)`.
- A new sheet defaults to a completed 15-minute interval ending now instead of an interval beginning now and extending into the future.
- Validation rejects both future start times and intervals whose selected duration ends in the future.
- Identical task, start-time, and duration facts now receive a deterministic private entry identifier, so reopening the sheet and submitting the same work updates one entry instead of duplicating actual time.

## Focused verification

- The active-entry seam saved one 35-minute Research task entry with a trimmed non-default note.
- Exact success feedback named 35 minutes, the task, actual-time inclusion, and Screenwatch separation.
- A second activation in the same sheet produced no additional mutation.
- A reopened sheet with identical facts remained one entry and updated its note idempotently.
- The review snapshot reported Actual Time 35, Away from Mac 35, and Screenwatch-observed 0.
- Future-start, future-end, below-minimum, and above-maximum validation paths write nothing.
- Existing offline-work persistence, restart, correction, review reopening, deletion, observed-coverage preservation, and description validation seams passed.
- The Today integration exposes Add Away Work only for active or paused primary commitments.
- Cancel dismisses the sheet without invoking the only persistence boundary, `save()`.
- `git diff --check` passed.

## Release and package proof

- The single release package gate built both `ZoidCoach` and `ZoidCoachAgent` successfully.
- Package, LaunchAgent, Mach service, and signing identities were coherent.
- The isolated QA app passed on-disk signature and designated-requirement validation.
- The prepared artifact is `.build/app-qa/Zoid 666 QA.app` inside the verifier worktree.

## Capped signed journey

The installed signed QA app completed the capped journey under isolated root `.build/qa-active-offline-signed`.
Today created and started `Research migration risks`, then exposed Add Away Work only for that active commitment.
The sheet visibly named the exact task, showed privacy and evidence-boundary copy, changed from its 15-minute default to 10 minutes, accepted `Read deployment notes`, and displayed exact 10-minute success feedback.
The save action disappeared after success, and SQLite contained exactly one matching row after cancel and relaunch.
Reviews visibly showed 10 minutes Actual Time, 0 minutes Screenwatch-observed, and 10 minutes Away from Mac with the exact note.
Foreground-app relaunch preserved the active task, entry, note, and separated totals.
Cancel returned without mutation.
The DatePicker clamped a future start to now, and Record Work became disabled because the selected duration would extend beyond now.

The installed Reviews row exposed the raw local task identifier instead of its readable title.
Verifier commit `341eb59` resolves planned task identifiers to their readable titles with an honest identifier fallback.
The resolver's focused test and the final release package, LaunchAgent, Mach-service, signature, and designated-requirement checks passed.
The ten-minute UI cap ended before reinstalling that final package, so both scenarios remain conservative at Touches remaining until one installed Reviews title recheck passes.
