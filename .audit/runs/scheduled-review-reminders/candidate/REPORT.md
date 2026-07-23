# Scheduled review reminders candidate report

## Scope

- `ZC-054-004` now schedules an end-of-day review reminder at the end of the next configured workday.
- `ZC-054-005` now schedules a weekly review reminder at the end of the final configured workday in the ISO week.
- Overnight work windows preserve the source workday and source ISO week while scheduling delivery on the following calendar day.
- Both reminder types pass through the existing quiet-hours boundary before entering the durable action outbox.
- Stable daily and weekly entity identifiers make repeated reconciliation and agent restarts idempotent.
- Scheduled review reminders remain executable in observation mode because they present factual review prompts and do not mutate Calendar or task data.
- The agent reconciles reminder commands once per minute while automation is running, then uses the existing action executor for notification delivery.

## Automated evidence

- `swift test --filter ReviewReminderServiceTests` passed five focused tests.
- The focused tests cover daily and weekly boundaries, quiet-hours deferral, replay idempotency, roll-forward after the final workday, overnight work windows, observation mode, and missing work schedules.
- `swift test --filter 'observeModeRecordsWouldDoCommandsWithoutClaimingExternalWrites|leavingAutomaticModeCancelsOnlyUnapprovedPlanWrites'` passed two affected outbox regression tests.
- `git diff --check` passed.

## Runtime verifier plan

1. Rebase the candidate onto the current authoritative root and resolve only files owned by this claim.
2. Rerun the focused reminder suite and affected outbox regression tests after the rebase.
3. Package and install the signed QA build while holding the runtime lease.
4. Grant notification permission and configure a fixture work end a few minutes in the future with a quiet-hours boundary that can be observed during the run.
5. Confirm exactly one daily review notification and one weekly review notification are scheduled or delivered with the expected copy.
6. Restart the helper and confirm the durable outbox does not create or deliver duplicates for the same daily and weekly identifiers.
7. Switch to observation mode and confirm the factual review notifications still deliver while unrelated external writes remain blocked.
8. Open the app from the notification and confirm the user can reach the Reviews surface and complete the intended review workflow.
9. Update tracker statuses only after the signed installed-app proof is captured.

## Integration note

This candidate was built from `a3d1815cd182e59e72ccb325ded989a2738c66b6`.

The verifier must rebase it onto the current authoritative root before runtime acceptance.
