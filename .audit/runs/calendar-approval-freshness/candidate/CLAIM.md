# Calendar approval freshness claim

This isolated lane starts from authoritative commit `c51f860a15778891e1123a3ca4c0b00879ad737f`.

It owns the confirm-time freshness boundary for reviewed Calendar availability.

## Scenarios

- `ZC-008-017` - Approve the proposed plan.
- `ZC-009-007` - Approve a realistic revised plan.
- `ZC-009-008` - Avoid a vague warning with no useful next action.

## Owned files

- `Sources/ZoidCoachApp/CalendarPlanApprovalState.swift`
- `Sources/ZoidCoachApp/Views/CalendarPlanApprovalSheet.swift`
- Calendar approval and planning-capacity methods only in `Sources/ZoidCoachApp/AppModel.swift`
- Focused Calendar approval tests under `Tests/ZoidCoachAppTests/`
- `.audit/runs/calendar-approval-freshness/candidate/*`

This lane captures the reviewed Calendar revision, performs a fresh preflight before any XPC write, refuses stale or unavailable approval while preserving the current plan, and offers direct review-refresh and Source Health repair actions.
It will not touch Daily Review outcomes, Settings or user policy, shared runtime, tracker, registry, backlog, or Lavish.
