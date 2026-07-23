# Section 21 Immediate-Stop Handoff

## Scope

Assigned section: 21, Changes made in Apple Reminders.

Assigned IDs: `ZC-021-001` through `ZC-021-007`.

Worktree: `/Users/ziadnasreldin/.codex/worktrees/5782/Zoid Coach`.

Branch: detached HEAD.

Baseline HEAD after the required fast-forward: `2cba674f8370fc16f9555cdb6f115f18df1f8ced`.

Stop reason: the user requested an immediate stop while the focused test build was still running.

No implementation commit was created because the current changes had not completed verification.

## Per-scenario status

| ID | Status | Handoff |
| --- | --- | --- |
| `ZC-021-001` | BLOCKED | Not started before the immediate stop. |
| `ZC-021-002` | BLOCKED | Existing integrated candidate and verifier evidence was inspected, but no new work was started. |
| `ZC-021-003` | BLOCKED | Uncommitted implementation in progress. Today rows now carry Reminder notes and list names through the dashboard model and render them in the task row. Verification was interrupted. |
| `ZC-021-004` | BLOCKED | The new focused model test asserts that the local estimate remains unchanged while source-owned details update. Full persistence and installed-app proof remain. |
| `ZC-021-005` | BLOCKED | Existing integrated candidate and verifier evidence was inspected, but no new work was started. |
| `ZC-021-006` | BLOCKED | Existing integrated candidate and verifier evidence was inspected, but no new work was started. |
| `ZC-021-007` | BLOCKED | Not started before the immediate stop. |

## Uncommitted files

- `Sources/ZoidCoachCore/TodayDashboard.swift`
- `Sources/ZoidCoachInfrastructure/TodayDashboardAgent.swift`
- `Sources/ZoidCoachApp/Views/DashboardView.swift`
- `Tests/ZoidCoachAppTests/TodayDashboardTests.swift`

This report is also uncommitted.

## Work completed before stop

- Fast-forwarded successfully from `63351c3` to integration baseline `2cba674` using `git merge --ff-only codex/full-system`.
- Read the orchestration rules, active-work ledger, implementation program, exact tracker entries, exact registry entries, and existing section 21 evidence.
- Selected `ZC-021-003` as the highest-value independent gap because Reminder notes and list identity were synchronized but absent from Today rows.
- Added two focused tests for source detail presentation and legacy snapshot decoding.
- Added optional Reminder notes and list name fields to `TodayTaskRow` with backward-compatible decoding.
- Propagated those fields from current Reminder snapshots and preserved them on deleted or externally completed rows.
- Rendered the list name in the Today task detail and rendered non-empty notes as a two-line accessible detail.

## Tests and evidence

Focused command:

`swift test --filter "reminderOwnedDetailsRemainVisibleWithoutChangingTheLocalEstimate|legacyTodayTaskRowDecodesWithoutReminderOwnedDetails"`

The first run reached the intended red state because the new fields did not exist.

After implementation, the build exposed and fixed one legacy-decoder default for `isOptional`.

The final rerun was interrupted by the immediate-stop request while compiling, so there is no passing test claim.

No built-in Browser QA or proof screenshot was captured.

No installed QA proof was attempted.

## Remaining work

- Resume the focused test and resolve any compiler or test failures.
- Add an integration test proving a source title, notes, list, due date, and priority refresh changes visible source-owned fields while preserving the same local estimate and history.
- Run the affected Today dashboard and agent suites, then the release build.
- Use only Codex built-in in-app Browser for visible QA and capture the required proof screenshot.
- Independently verify the installed QA journey before any `VERIFIED COMPLETE` claim.
- Review whether notes should remain directly visible or move behind a disclosure for dense rows after browser inspection.
- Continue independently through the remaining assigned IDs without editing the tracker, registry, backlog, or active-work ledger.

## Integration and rollback

There is no commit to integrate.

Preserve the current worktree as-is and resume from the uncommitted diff.

If a later owner decides not to continue this candidate, rollback must be performed only after explicit authorization because the immediate-stop instruction forbids reset, discard, or revert operations.

