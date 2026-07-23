# Pause-controls end-workday review handoff candidate

## Claim

- Primary scenario `ZC-039-007`: end the workday from the coaching pause controls.
- Primary scenario `ZC-040-002`: open the daily review immediately after ending the workday manually.

## Owned files

- `Sources/ZoidCoachApp/EndWorkdayReviewController.swift`
- `Sources/ZoidCoachApp/Views/SettingsView.swift`
- `Tests/ZoidCoachAppTests/EndWorkdayReviewControllerTests.swift`
- `.audit/runs/pause-end-workday-review/candidate/REPORT.md`

## Exclusions

- `Sources/ZoidCoachAgent/AgentMain.swift` and `Sources/ZoidCoachInfrastructure/PromptNotificationCoordinator.swift` remain untouched for the break-end reminder lane.
- The root worktree, installed runtime, tracker, scenario registry, Lavish artifact, backlog, and active-work ledger remain untouched.
- `Sources/ZoidCoachApp/AppModel.swift` remains untouched because it is root-integrator owned.

## Planned acceptance

- The coaching pause card shows an end-workday action only when an active task exists.
- The action names the active task and requires an explicit destructive confirmation.
- Confirmation sends the existing durable `pauseForEndOfDay` task command exactly once.
- A failed command keeps the user in Settings and shows actionable error copy.
- A successful command refreshes Today state and navigates directly to Reviews.
- Repeated taps while the command is in flight cannot submit a duplicate end-workday command.

## Evidence

- The coaching pause card now shows `End workday and review` only when Today has an active task row.
- The supporting copy names the active task, explains that its timer stops, and states that ending the day does not complete the task.
- The action opens a destructive confirmation that names the task and offers an explicit `End and review` choice.
- `EndWorkdayReviewController` accepts only one in-flight request and sends the existing `pauseForEndOfDay` command with the exact active task identifier.
- A command failure returns false, restores the enabled state, leaves navigation unchanged, and shows that the active task remains unchanged.
- A successful command refreshes the canonical Today snapshot and changes the selected dashboard section directly to Reviews.
- The focused persistence journey starts a real task, ends the workday through the controller, reopens `TaskExecutionStore`, and confirms the task remains paused with reason `endingWorkday`, ninety tracked minutes, and no active task.
- The focused duplicate test holds the first async command open and proves a second request is refused with only one recorded command.
- `swift test --filter EndWorkdayReviewControllerTests` passed with exit code 0 after the final persistence test.
- `git diff --check` passed.

## Conservative status recommendation

- Keep `ZC-039-007` below fully implemented until a verifier uses the signed Settings pause card to cancel once, confirm once, and inspect the durable task state after relaunch.
- Keep `ZC-040-002` below fully implemented until a verifier proves the installed app navigates to today's populated review only after a successful command and remains in Settings after an injected failure.

## Independent verifier plan

- Rebase this candidate onto the latest authoritative integration commit before verification.
- Run `swift test --filter EndWorkdayReviewControllerTests` from the rebased candidate.
- Package and install a clean signed QA identity without touching production data.
- Seed one active local priority task with reviewable behavior evidence and open Settings.
- Confirm the coaching pause card names the active task and exposes one accessible end-workday action without clipping at supported window sizes.
- Open the confirmation and cancel it, then verify the task remains active and the app remains in Settings.
- Open the confirmation again, choose `End and review`, and verify exactly one `pauseForEndOfDay` command is applied.
- Confirm the app opens Reviews only after success and the current-day review contains the seeded evidence.
- Relaunch the app and helper, then confirm the task remains paused for end-of-day and no active timer resumed.
- Inject one bounded command failure and confirm the app remains in Settings with the actionable unchanged-task message.
- Update the tracker, registry, backlog, and Lavish artifact only from the authoritative root after signed proof passes.

## Known boundaries

- This batch opens the existing current-day review and does not add configured review times, delayed review drafts, next-launch reminders, or skip-review lifecycle state.
- The end-workday action is intentionally unavailable when there is no canonical active task to stop.
- Signed visual, accessibility, XPC, navigation, cancellation, failure, and restart proof remains assigned to the independent verifier.
