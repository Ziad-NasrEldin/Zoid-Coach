# First-Plan Preview Metrics Verification

## Code result

The candidate calculations are correct.
Focused work uses committed, estimated, non-deferred tasks.
Buffer is the non-negative difference between available capacity and planned focused work.
Overloaded plans show the exact overage instead of a misleading zero-minute buffer.

## Blocker fixed

The candidate inserted the metric controls into `DailyPlanLedger`, but the capacity `state` and `planMetric` helper belong to `PlanningCapacityPanel`.
The original candidate therefore failed to compile with unresolved `state` and `planMetric` references.
The original location also applied dark metric text over a dark background.

The verifier moved the metrics into `PlanningCapacityPanel` immediately below the existing planned-versus-available summary.
This gives the controls the correct live capacity state, established panel contrast, and the intended update lifecycle.

## Accessibility

Focused Work exposes the complete spoken value and stable `planning-capacity-focused-work` identifier.
Planned Buffer or Over Capacity exposes the complete semantic value and stable `planning-capacity-buffer` identifier.
Each metric is one accessibility element rather than reading its label and value as disconnected fragments.

## Proof

- The candidate-focused run reproduced the compile blocker.
- After the scoped fix, `swift test --filter PlanningCapacityStateTests` passed.
- One release build passed.
- `git diff --check` passed.

## Signed acceptance

The installed signed QA app loaded a deterministic two-task proposal with 45 and 30 committed minutes.
The panel visibly and accessibly reported 75 focused minutes, 378 available minutes, and 303 buffer minutes.
The verifier shortened Review budget from 30 to 15 minutes through the visible estimate control.
Without leaving Today, the panel updated to 60 focused minutes and 318 buffer minutes.
The stable accessibility identifiers and full spoken values remained present after the update.

Both mapped scenarios are fully usable end to end.
