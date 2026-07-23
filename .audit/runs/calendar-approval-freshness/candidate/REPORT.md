# Calendar approval freshness candidate

## Scope

This candidate covers `ZC-008-017`, `ZC-009-007`, and `ZC-009-008` without changing their tracker status.
It captures the exact reviewed work windows, visible Calendar selection, and non-Zoid commitments that affect those windows.
Confirm performs a synchronous Calendar refresh and freshness comparison before the XPC schedule command can be queued.
Unavailable Calendar access and any relevant commitment replacement, move, cancellation, or addition return to review with an explicit nothing-was-written message.
The current daily plan and reviewed items are not mutated by either refusal path.
The refusal panel offers `REVIEW UPDATED AVAILABILITY` and `OPEN SOURCE HEALTH` with stable accessibility identifiers.

## Focused verification

- `swift test --filter CalendarPlanApprovalStateTests` passed all 11 focused approval and receipt tests.
- `swift test --filter QAFixtureOSCompositionTests` passed.
- `swift test --filter PlanningCapacityStateTests` passed.
- `git diff --check` passed.

## Independent verifier plan

1. Build and install a signed QA package from the integrated candidate.
2. Seed a realistic plan and a visible Calendar commitment, open Plan Approval, and record the reviewed metrics and task rows.
3. Change or cancel the commitment after the sheet opens, then press Confirm and Write.
4. Prove the refusal remains on the review sheet, names the changed availability, preserves the plan, and creates no schedule-plan XPC command or Calendar block.
5. Press Review Updated Availability and prove the metrics refresh without changing the plan.
6. Confirm the refreshed realistic plan and prove the exact Calendar and Reminder writes complete end to end.
7. Repeat with Calendar permission unavailable and prove no command is queued, the plan remains unchanged, and Open Source Health reaches Calendar repair guidance.
8. Relaunch and confirm only successfully approved receipts restore, while refused attempts never claim success.
