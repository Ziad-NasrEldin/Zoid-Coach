# Active away-from-Mac work verification

## Candidate and verifier

The candidate `a2ec031` was applied to authoritative base `c73fbd5` in an isolated verifier worktree.
Focused verification found and fixed three end-user blockers in verifier commit `52f5c14`.

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

The shared runtime remains untouched while the dark-appearance verifier owns its lease.
When the lease is released, the capped journey is:

1. Install the verifier's signed QA artifact under its isolated QA root.
2. Create and start one local Today task and confirm Add Away Work is visible for that exact active task.
3. Open the sheet, choose a non-default completed interval of 35 minutes, enter `Read deployment notes`, and save once.
4. Verify the success message names 35 minutes and the exact task, then activate the default action again and confirm no second entry exists.
5. Open Reviews for the same configured local day and verify Actual Time and Away from Mac increase by 35 while Screenwatch-observed time does not.
6. Relaunch and verify the entry, task binding, duration, note, and separated totals persist.
7. Reopen the active-task sheet, cancel, and verify no mutation.
8. Select a future start and then a past start whose duration ends in the future, and verify both paths remain unsaved.

Tracker, registry, Lavish, root, and the shared runtime remain outside this verifier until the serialized lease is granted.
