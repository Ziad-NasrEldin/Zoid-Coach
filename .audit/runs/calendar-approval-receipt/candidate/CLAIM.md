# Calendar approval receipt claim

This isolated lane starts from authoritative commit `7e61bef` and pulls the highest unowned implementation-ready Calendar slice without touching the active gaming-drift files.

## Scenario ownership

- `ZC-008-017` - Approve the proposed plan.
- `ZC-008-018` - Restart the app and see the approved plan restored correctly.
- `ZC-058-005` - Approve the plan.

## File ownership

- `Sources/ZoidCoachApp/CalendarPlanApprovalState.swift`
- `Sources/ZoidCoachApp/CalendarPlanApprovalReceiptStore.swift`
- `Sources/ZoidCoachApp/AppModel.swift`
- `Sources/ZoidCoachApp/Views/DashboardView.swift`
- `Sources/ZoidCoachApp/Views/CalendarPlanApprovalSheet.swift`
- Focused Calendar approval receipt tests.
- Candidate evidence under `.audit/runs/calendar-approval-receipt/candidate/`.

## Boundaries

This lane makes the user's exact approval receipt durable across app restart and reconciles its command outcome without repeating writes.
It does not touch gaming drift, root, runtime installation, tracker, registry, Lavish, or shared QA state.
