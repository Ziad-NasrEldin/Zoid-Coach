# Active offline work candidate

## Scope

This candidate implements the end-user entry path for `ZC-022-001` and `ZC-022-002` without changing authoritative tracker status.
An active or paused Today commitment now exposes Add Away Work beside its ordinary task controls.

## User-visible behavior

- The sheet is bound to the exact current task, so users do not need to retype or guess a task identifier.
- Users choose when the work began, enter a bounded 5-to-240-minute duration in five-minute steps, and may add an optional note.
- Future start times and out-of-range durations cannot be saved.
- The sheet states before submission that only intentional completed work belongs here.
- The sheet states that away-from-Mac work counts toward actual task time, remains separate from Screenwatch-aligned time, and never converts missing telemetry into work.
- A successful save remains visible in the sheet with the exact task and duration before the user closes it.
- Repeated Save activation after success is rejected, preventing duplicate entries.
- Every control has a stable accessibility identifier, and Return and Escape map to Record and Cancel or Close.

## Persistence boundary

The new controller reuses `DailyReviewStore.saveOfflineWork` and the existing `offline_work_entries` schema.
No migration, AppModel mutation, agent composition, or alternate data path was introduced.
The source day follows the configured schedule timezone, and empty notes remain null rather than fabricated text.

## Focused proof

- `swift test --filter "activeOfflineWorkEntry|offlineWork"` passed the new active-entry validation and exactly-once tests plus the existing persistence, correction, restart, coverage-separation, validation, and deletion seams.
- The real-store test saved one 35-minute Research entry, reopened the Daily Review snapshot, and proved Actual Time 35, Away from Mac 35, and Screenwatch-observed 0.
- `swift build -c release --product ZoidCoach` passed.
- `git diff --check` passed.

## Fresh verifier plan

1. Rebase or cherry-pick the candidate onto the authoritative root once.
2. Install one isolated signed QA application under the runtime lease.
3. Create and start one local Today task, then prove Add Away Work is visible only for the active or paused commitment.
4. Open the sheet and prove its task binding, privacy boundary copy, time control, bounded duration, optional note, and stable accessibility identifiers.
5. Record a non-default duration and note, then prove the exact success state and that a second activation cannot duplicate the entry.
6. Open Reviews for the same day and prove Actual Time increased by that duration while Screenwatch-observed time did not.
7. Relaunch and prove the away-from-Mac entry, task binding, duration, note, and separated totals persist.
8. Exercise Cancel without mutation and an invalid future start without a database write before cleanup.

The verifier must keep both scenario statuses conservative until the installed journey passes.
