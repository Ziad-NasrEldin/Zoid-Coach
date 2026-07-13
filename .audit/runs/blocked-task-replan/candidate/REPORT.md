# Blocked-task replan candidate report

## Candidate

- Baseline: `292f34f`
- Claim commit: `2fac687`
- Implementation commit: `1a5e6cc`
- Scenarios: `ZC-019-010`, `ZC-034-011`

## End-user result

The existing Today blocker sheet still requires a concrete reason between 3 and 240 characters.
When the blocked task was the main objective, Zoid 666 now promotes the next usable planned commitment instead of leaving the day centered on blocked work.
The blocker remains visible on the blocked task, the replacement becomes the main objective and next recommendation, and Today names the replacement in its success message.
The replan survives app and agent restart.
If no usable replacement exists, Zoid 666 saves the blocker but does not invent a replacement or leave the plan with no main objective.

## Implementation evidence

- `AutonomousPlanStore.promoteReplacementMainObjective` performs one atomic main-objective update after saving an undo revision.
- Replacement selection respects plan order and excludes missing reminders, blocked tasks, completed tasks, rescheduled tasks, active tasks, and future-deferred work.
- `TodayDashboardAgent` runs replacement selection only after the blocker mutation succeeds.
- `AppModel` reports the exact newly promoted main objective when a replan occurred.
- No schema migration or external source mutation was introduced.

## Verification completed

- `git diff --check` passed.
- `swift test --package-path /private/tmp/zoid-666-fresh-after-notification-preference --filter TodayDashboardAgentTests` passed.
- Exact focused tests `blockingMainObjectiveDurablyPromotesNextUsableTask` and `blockingMainObjectiveWithoutUsableReplacementKeepsPlanHonest` passed.
- Focused proof covers saved blocker text, execution state, replacement promotion, next recommendation, restart durability, undo revision restoration, and the no-replacement edge case.
- Release QA packaging passed with coherent app, LaunchAgent, Mach service, and signing identities.
- Packaged artifact: `/private/tmp/zoid-666-fresh-after-notification-preference/.build/app-qa/Zoid 666 QA.app`

## Verifier plan

1. Rebase or cherry-pick the candidate onto the current authoritative integration head and rerun `TodayDashboardAgentTests`.
2. Install the signed QA app with an isolated QA root containing at least two planned tasks.
3. Start the main objective from Today.
4. Open `Pause`, choose `Task is blocked`, enter a specific reason, and confirm.
5. Verify the task becomes blocked, the reason remains visible, the next usable task becomes the main objective, and the success message names it.
6. Verify `Do this next` recommends the same replacement and no timer remains active for the blocked task.
7. Restart both app and helper, then verify the blocker, replacement main objective, and recommendation remain unchanged.
8. Repeat with a one-task plan and verify the blocker is saved without a fabricated replacement.
9. Exercise the plan undo action and verify the prior main-objective assignment can be restored without losing the blocker reason.

The tracker and scenario registry remain verifier-owned and were not changed by this candidate.
