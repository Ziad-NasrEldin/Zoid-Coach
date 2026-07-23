# ZC-024-008 fixture correction

## Outcome

The namespaced signed-QA fixture now uses the supported local-task source instead of pretending to be an Apple Reminder.

This keeps the fixture on the real production schemas and Today row-building path without requiring Apple Reminders or Calendar permission.

No product code, build, installed runtime, canonical checkout, tracker, registry, or production state was changed.

## Root cause

The old fixture inserted `qa-zc024008-active-task` into `source_tasks` with `source_kind = reminders`.

`ReminderSnapshotStore.synchronize` treats every stored `reminders` row as externally owned and removes IDs absent from the latest EventKit snapshot.

When the isolated signed runtime had no Apple Reminders permission, the external refresh removed the fixture source row.

The durable execution interval and active execution state remained, so `TodayDashboardAgent` still produced an `activeTask` value.

However, `TodayDashboardAgent` creates `taskRows` by joining the daily plan to incomplete source tasks loaded by `ReminderSnapshotStore`.

With the source row gone, `taskRows` was empty and `MenuBarCoachState` could not resolve the active task row.

It therefore exposed source attention instead of the active-task comparison.

## Correction

- Seed the namespaced task as `source_kind = local`, which is a supported `ReminderSourceKind` and is loaded by the same `loadIncomplete` production path.
- Keep the real `source_tasks`, `daily_plan_entries`, `task_execution_states`, `task_activity_intervals`, and `behavior_records` tables.
- Assert that the incomplete local source, current-day plan entry, active execution state, and open interval form one resolvable Today task-row input.
- Simulate an external Reminder refresh in the self-test by removing all externally owned Reminder rows.
- Reassert that the local fixture remains resolvable after that refresh.
- Preserve and verify unrelated local source and behavior rows through fixture cleanup.

## Verification

- Old fixture plus the new assertion: deterministic failure, `permission-independent local source task: expected '1', got '0'`.
- Corrected fixture self-test run 1: passed.
- Corrected fixture self-test run 2: passed.
- `bash -n Scripts/qa-active-time-comparison-fixture.sh`: passed.
- `git diff --check`: passed.
- No build or runtime command was run.

## Candidate identity

- Starting combined candidate: `ee102ec5999f060cfb379b0581d5ada0555f82ba`
- Verifier-only correction commit: `1d621951eb45ff573798a1587bdcc00eac72e915`

## Exact signed rerun sequence

Run this only after obtaining the exclusive signed-QA runtime lease.

1. Create a fresh isolated worktree at `1d621951eb45ff573798a1587bdcc00eac72e915` and confirm it is clean.
2. Run `bash -n Scripts/qa-active-time-comparison-fixture.sh`.
3. Run `Scripts/qa-active-time-comparison-fixture.sh self-test`.
4. Set unique `ZOID_COACH_QA_RUN_ROOT` and `ZOID_COACH_QA_INSTALL_ROOT` values.
5. Install the clean release QA package with `CONFIGURATION=release Scripts/install-signed-qa-runtime.sh`.
6. Verify deep signing, exact build identity, QA LaunchAgent, Mach service, XPC registration, and heartbeat.
7. Stop the installed QA app and helper.
8. Run `Scripts/qa-active-time-comparison-fixture.sh seed --database "$DATABASE" --local-day "$LOCAL_DAY"`.
9. Run `Scripts/qa-active-time-comparison-fixture.sh verify --database "$DATABASE" --local-day "$LOCAL_DAY"` and require the permission-independent local-source pass line.
10. Restart the installed helper and wait until the generated Today snapshot contains `qa-zc024008-active-task` inside `taskRows`.
11. Relaunch the installed app so it loads that snapshot.
12. Run `Scripts/qa-active-time-comparison-ax-probe.swift` with minimum elapsed 14 and expected aligned 5.
13. Record the baseline elapsed value.
14. Restart both helper and app, then rerun the probe with the baseline elapsed value as the new minimum and aligned time fixed at 5.
15. Exercise the missing-producer and explicit-zero cases through the same signed UI contract.
16. Stop the app and helper, run fixture cleanup and `verify-clean`, uninstall the isolated QA runtime, and prove the QA agent, app, roots, private sentinels, and production fixture rows are absent.

## Remaining acceptance boundary

This correction makes the fixture ready for a signed rerun.

It does not itself prove ZC-024-008 because this assignment intentionally prohibited build and runtime verification.
