# Menu Bar Break And End-Of-Day Candidate Report

## Scope

This batch owns `ZC-023-008` and `ZC-023-010` from baseline `f9edd27`.

It changes only the compact menu-bar state, menu-bar view, focused menu-bar tests, and candidate evidence.

## End-User Behavior

An active task exposes `BREAK 15` directly in the menu bar.

The confirmed canonical snapshot replaces the active state with an accepted-break countdown, and `END BREAK` resumes the same task without losing tracked time.

An active task also exposes a separate destructive `END WORKDAY` action.

Ending the workday requires an explicit confirmation that explains the active task will pause, tracked time will remain saved, and the task can be resumed later.

After confirmation, the compact status says `Workday ended · Tracked time is saved` and retains the paused task as the primary task.

The menu never changes its local state optimistically.

Every transition waits for the authenticated Today client response and preserves the last confirmed snapshot on failure.

## Focused Proof

`swift test --filter MenuBarCoachTests` passes.

The focused suite proves the break, resume, and end-workday command order through the menu controller.

A canonical database journey starts a real planned task through `TodayDashboardAgent`, starts and ends a break, ends the workday, reopens the agent, and verifies the paused task, end-of-day reason, cleared break state, title, and tracked state remain durable.

`swift test --filter AcceptedBreakLifecycleTests` also passes.

## Independent Verifier Plan

1. Rebase or cherry-pick the candidate onto the latest authoritative root in an isolated verifier worktree.
2. Run `MenuBarCoachTests` and `AcceptedBreakLifecycleTests` once.
3. Build and install one signed isolated QA runtime after obtaining the runtime lease.
4. Seed or create one real planned task and start it through the authenticated helper.
5. Open the macOS menu extra, choose `BREAK 15`, and verify the same task shows a live accepted-break countdown.
6. Choose `END BREAK` and verify the same task resumes with its prior tracked time.
7. Choose `END WORKDAY`, cancel once, and verify no state change occurred.
8. Choose `END WORKDAY` again, confirm, and verify the compact copy says tracked time is saved and the task is paused for the end of the workday.
9. Restart the app and helper, reopen the menu extra, and verify the same end-of-day state remains without duplicate time or an accepted break.
10. Update tracker, registry, backlog, and Lavish only from the verifier lane based on signed evidence.
