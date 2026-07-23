# Completed Task History Candidate

## Scope

- Scenario `ZC-006-014`: completed tasks remain excluded from active task inventory.
- Scenario `ZC-006-015`: completed tasks remain discoverable in the selected day's Reviews history.
- The last factual pause reason is shown where a pause episode exists before completion.

## End-User Behavior

- Completing a task snapshots its readable title and source kind into append-only local history.
- Reviews shows a dedicated `COMPLETED TODAY` section for the selected day.
- Each completed entry shows the task title, completion time, source, and last pause context when available.
- Duplicate completion commands for the same task and day render one latest history entry.
- Completed tasks stay excluded from the active source list.
- Historical title and source context survive app and store restart without depending on the current Reminder record.
- The section exposes stable accessibility identifiers and a combined spoken label for every history row.

## Persistence

- Migration 33 adds nullable `title_snapshot` and backward-compatible `source_kind` context to `task_history`.
- Migration 33 is append-only and preserves migrations 28 through 32 in their existing order.
- Older history without snapshot context falls back to a current local source title when one remains, then to an honest generic label.

## Focused Proof

- `TaskHistoryStoreTests`: 6 tests passed.
- `DailyReviewTests`: 9 tests passed.
- `AutonomousDatabaseMigratorTests`: 12 tests passed.
- `TodayDashboardAgentTests`: 9 tests passed.
- `git diff --check`: passed.

Logs are stored beside this report in the worktree-local evidence directory.

## Remaining Acceptance

- A fresh verifier should merge the candidate onto the latest integration branch.
- The verifier should run the current full suite after concurrent migration work is reconciled.
- The verifier should seed one completed task in isolated signed QA, open Reviews, inspect the completed row, relaunch, and prove the same row remains while Today excludes it.
