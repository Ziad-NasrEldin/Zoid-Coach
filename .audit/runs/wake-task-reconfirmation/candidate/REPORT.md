# Active-task wake reconfirmation candidate report

## Candidate scope

This candidate implements the missing end-user decision after a real Mac or display sleep while a task is active.
It covers `ZC-053-002`, `ZC-053-003`, and `ZC-053-004` at implementation-candidate level only.
The tracker must not promote any scenario until the signed installed verifier completes the physical sleep and wake journey.

## End-user behavior

- Zoid 666 records the first real workspace or display sleep notification.
- A wake after less than five minutes keeps the active task running and shows an understandable reconciliation notice.
- A wake after five minutes or more opens a non-dismissible decision sheet for the current active task.
- The sheet states the observed absence duration and explains that task-clock time and observed activity are separate.
- The sheet explicitly states that time without telemetry is not counted as aligned work.
- `YES, CONTINUE` retains the active task and leaves a visible reconciliation notice.
- `PAUSE TASK` sends the existing external-interruption pause command and closes the wake decision only after the user chooses it.
- App focus changes do not trigger this flow because it listens to macOS workspace and display sleep or wake notifications rather than SwiftUI scene inactivity.
- Both actions are keyboard accessible and expose stable accessibility identifiers.

## Files

- `Sources/ZoidCoachApp/WakeTaskReconfirmationController.swift` owns deterministic absence classification and user-decision state.
- `Sources/ZoidCoachApp/Views/WakeTaskReconfirmationView.swift` owns the decision sheet and the short-absence reconciliation notice.
- `Sources/ZoidCoachApp/ZoidCoachApp.swift` contains only the macOS sleep and wake integration hook plus task-command wiring.
- `Tests/ZoidCoachAppTests/WakeTaskReconfirmationControllerTests.swift` covers the state boundaries and outcomes.

## Automated evidence

`swift test --filter WakeTaskReconfirmationControllerTests` passed 6 tests with 0 failures.
The tests cover short absence, long absence, explicit continue, explicit pause, no-active-task behavior, and duplicate sleep notification handling.

`swift build -c release --product ZoidCoach` completed successfully.
The release compiler emitted only the pre-existing `VoiceAudioEngine.swift` concurrency warnings.

`git diff --check` passed.

## Signed installed verifier plan

1. Rebase this candidate onto the current authoritative root and build a fresh signed QA package without using the shared runtime from this worktree.
2. Seed or create one visible task, start it, and record its task title, elapsed time, and behavior totals.
3. Put the display to sleep for less than five minutes, wake it, and prove the reconciliation notice appears without a confirmation sheet.
4. Confirm the task remains active and that the missing-telemetry interval does not increase aligned-work totals.
5. Put the Mac or display to sleep again for more than five minutes, wake it, and prove the non-dismissible confirmation sheet names the correct task and absence duration.
6. Choose `YES, CONTINUE`, prove the sheet closes, the task remains active, and the reconciliation notice appears.
7. Repeat the long-absence journey and choose `PAUSE TASK`.
8. Prove the task becomes paused with the external-interruption reason and remains paused after app relaunch.
9. Repeat a normal app focus switch longer than five minutes without sleep and prove no wake sheet appears.
10. Capture accessibility evidence for the sheet, both actions, the notice, and keyboard-only completion.

## Conservative status recommendation

Keep all three scenarios at their current tracker status until the signed installed verifier succeeds.
If the full verifier plan succeeds, `ZC-053-003` can become fully implemented.
`ZC-053-002` and `ZC-053-004` still require the verifier to compare visible timing and aligned-work totals before they can become fully implemented.
