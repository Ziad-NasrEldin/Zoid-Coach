# Daily review plan outcomes candidate

## Claim

- Primary scenario `ZC-041-001`: see whether the day's main objective was completed.
- Primary scenario `ZC-041-002`: see how many planned priority tasks were completed.
- Related scenario `ZC-041-013`: provide partial estimate context per planned task without claiming estimate-versus-actual comparison.

## Owned files

- `Sources/ZoidCoachCore/DailyReview.swift`
- `Sources/ZoidCoachInfrastructure/DailyReviewStore.swift`
- `Sources/ZoidCoachApp/Views/DailyReviewView.swift`
- `Tests/ZoidCoachAppTests/DailyReviewTests.swift`
- `.audit/runs/daily-review-plan-outcomes/candidate/REPORT.md`

## Exclusions

- The end-workday review Settings and controller files remain untouched.
- The root worktree, installed runtime, tracker, scenario registry, Lavish artifact, backlog, active-work ledger, and migration registry remain untouched.

## Planned acceptance

- Daily Review loads the exact priority plan recorded for the selected local day.
- The main objective is named and labeled completed or unfinished from same-day durable task history.
- The review shows completed priority count against the planned priority count.
- Each planned priority task shows its title, main-objective role when applicable, completion state, and recorded estimate when available.
- A task completed on another day does not retroactively change the selected day's completion count.
- A day with no recorded plan shows an explicit factual empty state instead of inventing an objective.
- Plan outcomes survive store and app restart because they are derived from durable plan and task-history records.

## Evidence

- `DailyReviewSnapshot` now carries stable per-task plan outcomes with title, main-objective role, recorded estimate, and same-day completion state.
- `DailyReviewStore` reads only non-optional entries from the exact selected `day_key` and keeps the plan's main-objective and rank order.
- Completion is derived by intersecting those planned task identifiers with durable `TaskHistoryStore` completions from the selected local day.
- The production Daily Review now uses the configured policy time zone for both the selected source day and completion-history boundaries.
- The main-objective summary distinguishes `Completed`, `Unfinished`, and `Not designated` without inferring an objective.
- The priority summary shows the factual completed count against the recorded non-optional plan count and states that only same-day durable completion history is counted.
- Each planned task row shows `Done` or `Open`, its title, main-objective role, and the recorded estimate when one exists.
- A no-plan day displays explicit copy that no objective or completion count was invented.
- The focused journey records a main objective, another priority, and an optional task, then completes them across different days.
- That journey proves the optional task is excluded, the same-day main objective is completed, the next-day priority remains open for the selected review, the count is one of two, and reopening the store returns the identical outcomes.
- `swift test --filter DailyReviewTests` passed with exit code 0 after the final configured-time-zone integration.
- `swift test --filter dailyReviewShowsMainObjectiveAndSameDayPriorityCompletionAcrossRestart` passed with exit code 0.
- `git diff --check` passed.

## Conservative status recommendation

- Keep `ZC-041-001` below fully implemented until a verifier sees completed, unfinished, and not-designated main-objective states in the signed app and confirms restart persistence.
- Keep `ZC-041-002` below fully implemented until a verifier sees the signed priority count exclude an optional task and a completion recorded on another day.
- Treat `ZC-041-013` as touches remaining because recorded estimates are visible per task, but this batch does not calculate task-level actual time or estimate accuracy.

## Independent verifier plan

- Rebase this candidate onto the latest authoritative integration commit before verification.
- Run `swift test --filter DailyReviewTests` from the rebased candidate.
- Package and install a clean signed QA identity without touching production data.
- Seed one selected-day plan with a named main objective, a second priority task, one optional task, and recorded estimates.
- Record same-day completion for the main objective, next-day completion for the second priority, and same-day completion for the optional task.
- Open the selected day in Reviews and confirm the main objective visibly says completed and the priority summary visibly says one of two.
- Confirm the optional task is absent and the second priority remains open despite its next-day completion.
- Inspect each visible row, estimate label, main label, status, and accessibility identifier at supported window sizes.
- Relaunch the app and helper, then confirm the same selected-day outcomes remain.
- Open a planned day with an unfinished main objective and verify the unfinished state.
- Open a day with priority tasks but no designated main objective and verify `Not designated`.
- Open a day with no plan and verify the explicit factual empty state.
- Update the tracker, registry, backlog, and Lavish artifact only from the authoritative root after signed proof passes.

## Known boundaries

- This batch shows recorded estimates as context but does not claim estimate-versus-actual accuracy.
- Only durable task-history completion within the configured local day counts, so later completion does not rewrite the historical selected-day outcome.
- Signed visual, accessibility, local-time-zone, cross-day, empty-plan, and restart proof remains assigned to the independent verifier.
