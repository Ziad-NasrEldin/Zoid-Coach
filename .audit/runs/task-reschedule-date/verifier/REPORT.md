# Local Task Reschedule Verification

## Semantics

The candidate correctly prevents immediate mutation from the More menu.
Cancel leaves the current plan unchanged.
Confirmation validates a future local date, normalizes it to local midnight, removes the entry from today's capacity, and persists the deferral without issuing an Apple Reminders command.
Stale task IDs produce an explicit refresh instruction.

## Truth fix

The candidate called the selected date the next local planning date, but the implementation stores a local deferral on today's plan and does not automatically insert the task into a future plan.
The verifier corrected the sheet copy to state that the date is a local deferral, removes today's capacity, does not automatically add a future plan, and does not change the Apple Reminder due date.

## Proof

- `swift test --filter TaskRescheduleStateTests` passed.
- `swift test --filter DailyPlanRevisionTests` passed.
- One release build passed.
- `git diff --check` passed.

## Acceptance boundary

This batch provides confirmed local deferral, not full future-plan scheduling or Apple Reminder rescheduling.
The single package/install attempt exited without creating an installed app, registering a QA helper, mutating the shared runtime, or emitting diagnostic output.
No retry was performed under the package-once and UI cap.

The signed cancel, confirmation, capacity, Reminder-boundary, and restart journey remains unverified.
