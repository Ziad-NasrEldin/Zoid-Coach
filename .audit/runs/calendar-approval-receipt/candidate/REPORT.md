# Calendar approval receipt candidate report

## Scope

- `ZC-008-017` - Approve the proposed plan.
- `ZC-008-018` - Restart the app and see the approved plan restored correctly.
- `ZC-058-005` - Approve the plan.

## End-user behavior

- Confirming a reviewed plan now persists one local approval receipt containing the exact reviewed tasks, order, main objective, estimates, available minutes, fixed Calendar commitments, availability basis, command identifiers, approval time, and current outcome.
- Restart restores the receipt without reopening the modal and without issuing or duplicating any Calendar or Reminder write.
- The initial action-audit refresh reconciles a restored pending receipt against its exact command identifiers and persists applied or failed status.
- Today shows a compact Last Plan Approval summary with an accessible Review Receipt action.
- Review Receipt shows the original task list, estimates, main objective, approval time, and pending, confirmed, or repair-required outcome.
- Closing the receipt hides the modal but does not erase the durable proof.
- Starting a new approval replaces the review contents only after the user reaches the existing explicit confirmation boundary.

## Focused proof

- `swift test --filter CalendarPlanApprovalStateTests` passed after the final UI and persistence changes.
- The focused suite proves exact command reconciliation, duplicate command collapse, failed and cancelled outcomes, JSON round-trip, exact task restoration, approval timestamp preservation, closed-on-restart behavior, deliberate receipt reopening, and receipt retention after dismissal.
- The focused build compiles the new store, AppModel restoration path, Today receipt summary, and receipt-details sheet.
- `git diff --check` passed.

## Verifier plan

1. Rebase onto the current authoritative root and rerun `CalendarPlanApprovalStateTests` once.
2. Under the serialized runtime lease, install a fresh signed QA candidate with Calendar fixture access.
3. Create a realistic reviewed plan, open Accept Blocks, inspect the exact preview, and confirm once.
4. Record the Last Plan Approval pending receipt and exact task details, then relaunch the app before command completion.
5. Verify the receipt restores closed, Review Receipt opens the same tasks and timestamp, and no duplicate outbox commands appear.
6. Complete the exact fixture commands, refresh, and verify the same receipt changes to confirmed and remains confirmed after another relaunch.
7. Repeat with one terminal failure or cancellation and verify the locally saved plan plus direct repair language.
8. Only after installed proof, update tracker, registry, backlog, and Lavish conservatively.
