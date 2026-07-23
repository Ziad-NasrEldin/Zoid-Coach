# Plan preview metrics claim

This isolated lane starts from authoritative commit `171d24a`.

Priorities 4, 5, 7, and 8 require serialized signed runtime proof or are already functionally complete, so this non-runtime implementation lane pulls priority 11.

## Scenarios

- `ZC-008-005` - See the estimated focused-work total.
- `ZC-008-006` - See the planned buffer time.

## Owned files

- `Sources/ZoidCoachApp/Views/DashboardView.swift`
- `Sources/ZoidCoachApp/PlanningCapacityState.swift`
- `Tests/ZoidCoachAppTests/PlanningCapacityStateTests.swift`
- `.audit/runs/plan-preview-metrics/candidate/*`
- The isolated backlog claim and handoff rows only.

The lane will expose exact planned focus, available focus capacity, and remaining or exceeded buffer in the first-plan review, with useful missing-estimate and overload states.
It will not touch gaming policy, shared runtime, the product tracker, registry, or Lavish artifact.
