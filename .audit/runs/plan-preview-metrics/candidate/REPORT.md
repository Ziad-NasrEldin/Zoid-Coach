# First-plan preview metrics candidate

## Scope

- `ZC-008-005` - See the estimated focused-work total.
- `ZC-008-006` - See the planned buffer time.

## End-user result

The first-plan capacity panel now presents focused work and planned buffer as separate, prominent metrics.
Focused work uses only committed tasks, so optional and future-deferred tasks do not inflate the value.
The planned buffer shows the exact available minutes left after committed work.
When the proposal is overloaded, the same position changes to `OVER CAPACITY` and shows the exact overage instead of a misleading zero buffer.
Both metrics have stable accessibility identifiers and complete spoken labels.
The values update through the existing numeric transition whenever the proposal changes.

## Evidence

- Candidate implementation: `47033ac`.
- Focused command: `swift test --filter PlanningCapacityStateTests`.
- Result: passed.
- The focused suite covers missing estimates, optional and deferred tasks, realistic plans, exact buffer, exact overage, plan reduction, zero capacity, calendar overlap, and configured work-window capacity.
- `git diff --check` passed before the implementation commit.

## Verifier plan

A fresh verifier should rebase the candidate onto the current authoritative root and run the focused planning-capacity suite once.
In a later serialized signed-QA review, the verifier should open the first-plan proposal, confirm the exact focused-work and buffer labels, remove or shorten a task, and confirm both values update without leaving the review.
The tracker, registry, runtime, and Lavish artifact remain untouched by this implementation lane.
