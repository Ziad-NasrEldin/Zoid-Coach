# Prompt Task Reschedule Candidate Report

Scenario: `ZC-034-010`.

Candidate status: implementation complete and ready for independent runtime verification.

## End-User Journey Implemented

- Gaming-drift coaching prompts now offer a clearly named Reschedule action for the unfinished task.
- Choosing Reschedule opens a dedicated sheet without resolving the coaching decision.
- The sheet identifies the task, permits only tomorrow or a later local date, explains the local-first and Apple Reminders sequence, and supports cancellation.
- Confirming persists the selected local planning date before queuing the matching Apple Reminder due-date mutation.
- The coaching decision resolves only after the local persistence and Reminder mutation enqueue are accepted.
- If local persistence or Reminder enqueue fails, the decision remains open and the user receives actionable error copy.
- If the task is local-only, the local planning date is saved and the prompt can resolve without claiming an Apple Reminders write.
- If prompt resolution fails after the mutation is accepted, the saved date remains visible and the decision remains available for safe reconciliation.

## Product Boundaries

- The existing daily-plan reschedule flow remains available and now shares the same ordered persistence implementation.
- The action remains within the coaching presentation policy by using the destructive role for a choice that removes the task from today's objective set.
- The sheet exposes stable accessibility identifiers for the container, date control, validation error, and confirm action.

## Focused Proof

- `swift test --filter TaskRescheduleStateTests` passed on 13 July 2026.
- `swift test --filter ReminderRescheduleSyncStateTests` passed on 13 July 2026.
- `swift test --filter GamingDriftPromptServiceTests` passed on 13 July 2026.
- The debug test builds compiled the changed app, infrastructure, and test targets.
- `swift build -c release` passed on 13 July 2026.

## Independent Verifier Plan

1. Start a Reminder-backed task and produce a gaming-drift prompt in the signed QA app.
2. Confirm the prompt names that task and includes Reschedule.
3. Open the sheet, verify today cannot be chosen, cancel once, and confirm the decision remains open.
4. Reopen the sheet, choose a future date, and confirm it.
5. Verify the task's local planning date, the Apple Reminder due date, and the resolved coaching decision all agree.
6. Relaunch the app and verify the selected date and resolved decision remain durable.
7. Repeat with Reminders unavailable and verify the date is retained locally, the prompt remains open, and the recovery copy is truthful.

The tracker and registry should not be promoted to fully implemented until this signed runtime journey passes.
