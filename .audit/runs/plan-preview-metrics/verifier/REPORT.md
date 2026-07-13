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

## Signed verifier plan

After the shared signed-QA lease is released, open a deterministic first-plan proposal with known focused minutes and available capacity.
Confirm both accessible metrics, shorten or remove one proposed task, and verify both values update in place without leaving the proposal.
Keep both mapped scenarios conservative until that installed click-through completes.
