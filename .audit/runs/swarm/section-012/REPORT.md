# Section 012 implementation lane handoff

## Stop state

The user requested an immediate stop before verification or commit.
This worktree is detached at `2cba674f8370fc16f9555cdb6f115f18df1f8ced` after a successful fast-forward from `codex/full-system`.
No commit was created and no changes were pushed.

## Assigned scenarios

| ID | State | Work completed | Remaining proof |
| --- | --- | --- | --- |
| ZC-012-005 | CODE COMPLETE, UNVERIFIED | Fixed accepted learned estimates being recalculated into a new recommendation after restart. Added a focused persistence regression assertion. | Finish focused test run, full suite, release build, installed QA Use action, relaunch durability, and screenshot. |
| ZC-012-006 | CODE COMPLETE, VERIFICATION PENDING | Existing Keep action and presentation tests were inspected. No new source change was needed. | Installed QA Keep action, unchanged estimate after relaunch, and screenshot. |
| ZC-012-007 | CODE COMPLETE, VERIFICATION PENDING | Existing validated custom estimate input and focused parser tests were inspected. No new source change was needed. | Installed QA invalid input, valid input, relaunch durability, and screenshot. |
| ZC-012-008 | CODE COMPLETE, UNVERIFIED | Added a focused low-coverage rejection test at 0.74 coverage against the 0.75 policy threshold. | Finish focused test run and installed QA low-coverage suppression proof. |

## Changed files

- `Sources/ZoidCoachInfrastructure/TodayDashboardAgent.swift`
- `Tests/ZoidCoachAppTests/LearnedEstimateSuggestionTests.swift`
- `.audit/runs/swarm/section-012/REPORT.md`

## Root cause and fix

The dashboard agent ignored the immutable recommendation stored in the learned aggregate and reapplied its ratio to the current estimate on every snapshot.
After accepting 50 minutes, a relaunch could therefore turn the same evidence into a larger recommendation.
The uncommitted fix uses the aggregate's original `recommendedEstimateMinutes` and suppresses the card when the current estimate already matches it.

## Tests and evidence

The focused command was started with an isolated scratch path because another SwiftPM process held the normal build directory:

`swift test --scratch-path /private/tmp/zoid-section-012-build --filter LearnedEstimateSuggestionTests`

The build had not completed when the immediate stop arrived.
The lane-owned process was stopped.
No passing test claim, installed QA proof, or screenshot is available.

## Integration and rollback

Do not cherry-pick anything because no commit exists.
Resume in this exact worktree, inspect the three uncommitted files, complete verification, then commit the coherent change.
Rollback, if later required, is limited to reverting the eventual commit that changes the learned suggestion calculation and its focused tests.

## Blockers

- Immediate user stop prevented verification and commit.
- The Codex built-in Browser does not currently provide native macOS app control in this lane, so installed visible QA and the required screenshot still need an authorized supported path.
