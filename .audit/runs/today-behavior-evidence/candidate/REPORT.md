# Today behavior evidence candidate

## Scope

This candidate covers `ZC-013-007`, `ZC-024-006`, `ZC-024-010`, and `ZC-025-008` without changing authoritative scenario status.
Today now provides a persistent keyboard-accessible Behavior Evidence sheet instead of requiring a transient hover popover.
The sheet always shows Work, Gaming, Distraction, Idle observed, and Unknown as five separate totals, including zero-minute categories.
Unknown is explicitly not treated as distraction or strong drift evidence.
Idle is explicitly limited to reliably observed idle state, and missing source time is never relabeled as idle.
Limited coverage shows its factual explanation and names the unhealthy Screenwatch detail when that source is present.
An unrelated Reminders or Calendar outage is never blamed for missing behavior totals.
The sheet provides direct Review and Correct Activity and Open Source Health actions.

## Focused verification

- `swift test --filter BehaviorEvidenceStateTests` passed all five state and attribution tests.
- `swift test --filter TodayDashboardTests` passed.
- The focused build compiled the new sheet and Today trigger.
- `git diff --check` passed.

## Independent verifier plan

1. Rebase or cherry-pick the candidate onto the current authoritative root and build a signed QA package.
2. Seed non-zero Work, Gaming, Distraction, Idle, and Unknown totals with current Screenwatch coverage.
3. Open Today, activate View All Activity by keyboard, and prove all five exact totals are simultaneously visible and separately accessible.
4. Prove the Unknown copy says it is not distraction and does not imply motive.
5. Activate Review and Correct Activity and prove the sheet closes into Reviews without changing any totals.
6. Seed stale Screenwatch coverage and prove the sheet names the limited coverage and exact Screenwatch issue while preserving the last observed totals.
7. Activate Open Source Health and prove it reaches the Screenwatch repair surface.
8. Seed an unrelated Reminders outage with healthy Screenwatch and prove the behavior sheet does not blame Reminders for missing behavior evidence.
9. Relaunch the app and prove the same snapshot-backed evidence remains available without a mouse hover dependency.
