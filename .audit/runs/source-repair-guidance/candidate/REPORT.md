# Source repair guidance candidate

## Scope

- `ZC-048-008` - Understand the impact of each unhealthy source.
- `ZC-048-009` - Open a direct repair action when one is available.

## End-user result

Every unhealthy source row now states the exact capability affected and the safe fallback that remains available.
Reminders preserves local plans and tracking, Notifications preserves Today decisions, Calendar falls back to configured work windows, Screenwatch preserves manual tracking, and Agent failure preserves existing local data.
Each existing source action now has a source-specific accessibility hint explaining what it checks or repairs.
Every impact label and repair control has a stable source-specific accessibility identifier.
Repair controls disable while that source is already checking, preventing duplicate requests.
Healthy rows stay concise and do not display an outage impact.

## Evidence

- Candidate implementation: `246f44b`.
- `swift test --filter SourceRepairGuidanceTests` passed all three new all-source, fallback, and checking-state tests.
- `swift test --filter SourceHealthTests` passed the existing complete source inventory and health-state coverage.
- `git diff --check` passed.

## Verifier plan

A fresh verifier should rebase the candidate onto the authoritative root and run the two focused groups once.
In signed QA, traverse healthy, checking, denied, unavailable, and attention states for each source, inspect the impact copy, activate each repair control, and confirm the control cannot duplicate an in-flight check.
The tracker, registry, runtime, and Lavish artifact remain untouched by this implementation lane.
