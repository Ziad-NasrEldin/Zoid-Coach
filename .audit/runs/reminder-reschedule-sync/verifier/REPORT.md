# Reminder reschedule sync verifier report

## Verdict

Scenario `ZC-020-009` advances from Not implemented to Touches remaining.

The candidate and its awaited ordering fix pass focused automated and release-package verification.

The scenario does not qualify as Fully implemented because the signed deterministic Reminders fixture failed before the reschedule UI journey became reachable.

## Revisions

- Original candidate: `423b921`
- Candidate rebased onto the authoritative verifier base: `746fbc7`
- Durable local-plan ordering fix and verifier tip: `a03d73b`

## Automated and package evidence

- `ReminderRescheduleSyncStateTests` passed 3 of 3 tests after the ordering fix.
- `TaskRescheduleStateTests`, `ActionOutboxStoreTests`, `ActionCommandExecutorTests`, and `LocalTaskCreationControllerTests` passed 29 of 29 affected regressions before the ordering fix.
- The focused three-test sync group passed again after the ordering fix.
- `git diff --check` passed.
- One release QA package completed successfully.
- Package signing, helper identity, LaunchAgent coherence, Mach-service coherence, and designated-requirement validation passed.
- The installed signed app was `/Users/ziadnasreldin/Applications/Zoid 666 QA E2E.app` with isolated root `/private/tmp/zoid-666-reminder-reschedule-sync-qa`.

## Implementation semantics inspected

- The reviewed sheet names the task and future date before confirmation.
- Cancel performs no local or Apple Reminders mutation.
- Confirm first waits for durable local-plan persistence.
- A failed local-plan write restores the last durable plan and prevents the Apple Reminders enqueue.
- A Reminder-backed task queues one explicit-user `setReminderDueDate` command only after the local date is safe.
- A newer desired date supersedes an older pending due-date command for the same Reminder.
- Local-only tasks persist their local date and create no Apple Reminders command.
- Pending, retrying, rejected, unavailable, and confirmed states are derived from the action ledger.
- Confirmed is shown only for a succeeded source-write command.
- Failure states retain the local date and history and provide direct Reminders repair guidance.
- The task-specific sync row has a stable accessibility identifier.

## Signed run and blocker

- The installed signed app launched and exited onboarding into Today.
- The packaged QA helper was loaded and Today visibly reported Agent Running.
- The handed-off fixture request was renamed to `os-fixture-request.processing.json` but never applied.
- The request used `operation` even though the runtime decoder requires `op`.
- After correcting that key, the request still used an object for `permissions`, while this Codable dictionary requires its supported alternating-array encoding.
- After correcting both encodings and relaunching, the processing request still failed the runtime decoder within the strict UI cap.
- Source Health visibly reported `QA fixture startup failed` and explained that deterministic QA Reminders, Notifications, and Calendar adapters were unavailable.
- Today therefore truthfully remained Reminders Not Connected with zero available fixture tasks.

No signed cancel, confirm, Pending, revoked rejection, restart persistence, repaired superseding date, confirmed source write, local-only no-op, helper-failure, or accessibility-ledger state is claimed.

## Remaining signed acceptance

- Generate the fixture request through the canonical encoder or a verified helper rather than hand-authored JSON.
- Exercise Cancel and prove zero mutation.
- Confirm a future date and prove local persistence precedes a Pending source command.
- Revoke deterministic Reminders access and prove Rejected plus restart-safe local date and history.
- Restore access, select a newer date, and prove the newer command supersedes the obsolete pending date.
- Prove Confirmed appears only after the fixture due-date write succeeds.
- Reschedule a local-only task and prove zero Apple Reminders command.
- Disconnect the helper and prove explicit queue-failure copy while the durable local date remains.
- Inspect the task-specific accessibility identifier and all status copy in the installed app.

The signed blocker is an acceptance-fixture encoding failure, not an identified product-code regression.
