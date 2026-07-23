# Source repair guidance claim

This isolated lane starts from authoritative commit `a3b4553`.

Priorities 4, 7, and 8 require serialized installed proof, priority 9 overlaps active gaming policy work, and priority 10 overlaps active rules-only work, so this implementation lane pulls priority 12.

## Scenarios

- `ZC-048-008` - Understand the impact of each unhealthy source.
- `ZC-048-009` - Open a direct repair action when one is available.

## Owned files

- `Sources/ZoidCoachApp/SourceRepairGuidance.swift`
- `Sources/ZoidCoachApp/Views/DashboardView.swift`
- `Tests/ZoidCoachAppTests/SourceRepairGuidanceTests.swift`
- `.audit/runs/source-repair-guidance/candidate/*`
- The isolated backlog claim and handoff rows only.

The lane will give every unhealthy source an exact user-impact explanation, a clear next action, stable accessibility identifiers, and safe no-impact behavior while healthy.
It will not touch rules-only settings, remote evidence, gaming policy, runtime, tracker, registry, or Lavish.
