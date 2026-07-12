# Calendar Plan Approval Candidate Evidence

## Scope

This batch implements the user-visible approval boundary before Zoid 666 writes an accepted daily plan to Apple Calendar and Reminders.

The primary tracker target is `ZC-058-005`.

The batch also strengthens the Calendar-write portion of `ZC-008-007` without changing the capacity-warning implementation.

## End-user behavior

- `ACCEPT BLOCKS` now opens a review sheet instead of immediately queueing external changes.
- The sheet names every reviewed task, rank, main objective, estimate, planned minutes, available minutes, fixed Calendar commitment minutes, and remaining capacity.
- The sheet explicitly distinguishes conflict-aware Calendar availability from configured-work-window fallback.
- `CONFIRM AND WRITE` is the only control that crosses the external-write boundary.
- The agent returns the exact command identifiers created or reused for the accepted plan.
- The app shows pending, confirmed, and failed write states from those exact command identifiers.
- A terminal failure is never presented as a successful Calendar write.
- Source Health remains directly reachable from write-result and repair states.
- If current Calendar fragmentation cannot fit every reviewed task, scheduling queues no Calendar or Reminder mutation and returns the user to the review with an honest explanation.
- Repeated scheduling uses the existing idempotent outbox and returns the same command identifiers instead of creating duplicate changes.

## Automated proof

`CalendarPlanApprovalStateTests` proves exact preview contents, conflict-aware capacity copy inputs, pending-to-applied reconciliation, terminal-failure presentation, and duplicate command identifier collapse.

`agentScheduler` focused tests prove fixed-Calendar placement, exact command identifier propagation, and atomic no-write behavior when the complete reviewed plan cannot fit.

Both focused commands exited with status `0`.

Raw compact command output and explicit exit-code files are stored beside this report.

## Files

- `Sources/ZoidCoachApp/CalendarPlanApprovalState.swift`
- `Sources/ZoidCoachApp/Views/CalendarPlanApprovalSheet.swift`
- `Sources/ZoidCoachApp/AppModel.swift`
- `Sources/ZoidCoachApp/Views/DashboardView.swift`
- `Sources/ZoidCoachInfrastructure/AgentPlanScheduler.swift`
- `Sources/ZoidCoachInfrastructure/AgentMutationRouter.swift`
- `Tests/ZoidCoachAppTests/CalendarPlanApprovalStateTests.swift`
- `Tests/ZoidCoachAppTests/AgentPlanSchedulerTests.swift`

## Remaining acceptance

The root-owned signed-QA installation lease was not taken during this batch.

A fresh verifier must run one signed-QA journey for review, confirmation, visible pending state, confirmed Calendar write, restart-safe result, conflict-induced atomic refusal, and Calendar-denied repair before the authoritative tracker can advance to fully implemented.

## Independent verifier pass

The candidate was independently replayed on `0fb9507` in an isolated worktree.

The verifier fixed one direct usability blocker where atomic conflict refusal and Calendar-permission errors were retained behind the modal instead of shown to the user.

The approval preview now presents an explicit `NOTHING WAS WRITTEN` explanation and a direct Source Health repair action.

The verifier also corrected reconciliation so a cancelled exact command is treated as failed instead of ever being summarized as an applied Calendar write.

Focused `CalendarPlanApprovalStateTests` and `AgentPlanSchedulerTests` both pass after these fixes.

The root-owned signed-QA acceptance journey remains intentionally unclaimed until the package lease is available.
