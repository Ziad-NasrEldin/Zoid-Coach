# Calendar Local Plan Approval Candidate Report

`ZC-046-009` is ready for independent signed verification through the Calendar-unavailable planning path.
The user no longer has to abandon an already durable plan solely because Calendar availability cannot be read.

## End-user behavior

When Calendar availability is current, the existing `CONFIRM AND WRITE` workflow remains unchanged.
When availability is unavailable, the preview explains that capacity uses configured work windows and offers `USE PLAN LOCALLY` instead.
The accessibility hint states that this approves the reviewed plan without requesting Calendar or Reminder changes.

Choosing the local path moves the review to `LOCAL PLAN READY` and `Continue with your local plan`.
The result states that the plan remains on this Mac, no Calendar blocks or Reminder changes were requested, and Calendar access can be repaired later for conflict-aware placement.
The receipt summary repeats the same zero-write boundary instead of claiming that Calendar was confirmed or already matched.

The local receipt preserves the exact reviewed tasks, ranks, estimates, main objective, capacity basis, and approval time.
It contains no command identifiers and restores as an applied zero-write plan without reopening the modal or retrying external writes.
The state refuses local-only approval when Calendar-backed availability was successfully reviewed, so a normal write flow cannot be silently downgraded.

## Focused proof

`swift test --filter CalendarPlanApprovalState` passed.
The suite covers unavailable preflight, successful local approval, zero command identities, truthful summary, exact task restoration, no modal reopening, and refusal from a Calendar-backed review.
`swift build -c release` passed.

## Independent signed acceptance

Create a realistic two-task plan while Calendar availability is denied or unavailable.
Confirm the preview names configured-work-window capacity, exposes Source Health repair, and offers `USE PLAN LOCALLY` rather than `CONFIRM AND WRITE`.
Close the preview and confirm no receipt is created.
Reopen it, choose the local path, and confirm `LOCAL PLAN READY`, the exact reviewed tasks, and explicit zero-write copy.
Inspect the isolated action outbox and Calendar fixture and confirm no commands or events were created.
Restart the app and helper and confirm the same local-only receipt and plan restore without reopening the modal.
Repair Calendar access, request a fresh approval, and confirm the normal conflict-aware `CONFIRM AND WRITE` path returns without duplicating the local plan.
