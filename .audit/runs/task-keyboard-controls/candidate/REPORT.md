# Task keyboard controls candidate

## Scope

This candidate implements the keyboard task-control path for `ZC-016-005`, `ZC-018-006`, and `ZC-018-007`.
The authoritative tracker remains unchanged until a fresh signed verifier proves the application-menu shortcuts against the installed product.

## User-visible behavior

- The application menu now contains a dedicated `Task` menu.
- Command-Option-S starts only the explicit current recommendation when it is still Ready.
- The start command includes the recommended task title so the user knows exactly what the shortcut will start.
- Starting is disabled while another task is active, so a global shortcut cannot bypass the existing task-switch confirmation.
- Command-Option-P pauses the canonical active task with the existing neutral Done for now reason.
- The same Command-Option-P shortcut resumes one unambiguous ordinary paused task.
- Resume is unavailable when several paused tasks make the target ambiguous.
- Resume is unavailable for an accepted break or an ended workday, preserving their explicit end-break and restart-workday flows.
- Both commands disable during every in-flight task mutation and remain disabled during onboarding.
- Every action reuses `AppModel.applyTaskCommand`, the authenticated XPC path, the app-wide pending-command gate, and the last-confirmed-state recovery behavior.

## Focused proof

- `swift test --filter keyboard` passed four focused state and safety tests.
- `swift test --filter agentPauseSwitchResumeAndCompletePausedJourneySurvivesRestart` passed the canonical agent pause, switch, resume, completion, and restart journey.
- `swift test --filter startingAnotherTaskAtomicallyPausesTheExistingTask` passed the transactional single-active-task invariant.
- `swift build -c release --product ZoidCoach` passed.
- No shared signed runtime was used and no installed-product claim is made.

## Fresh verifier plan

1. Rebase once onto the current authoritative root and rerun only the keyboard tests and canonical task journey.
2. Package and install one isolated signed QA application under the runtime lease.
3. Seed one explicit Ready recommendation and prove the Task menu names it and Command-Option-S starts it exactly once.
4. Prove Today and the menu bar show the same single active task after the command and after relaunch.
5. While a task is active, prove Command-Option-S is disabled and cannot silently switch to another recommendation.
6. Use Command-Option-P to pause the active task, prove elapsed time is preserved, then use it again to resume the same task.
7. Prove repeated shortcut activation during an in-flight mutation creates only one durable command and one open interval.
8. Seed an accepted break, an ended workday, and two ordinary paused tasks and prove the generic resume shortcut remains disabled in each ambiguous or specialized state.
9. Capture the Task menu in Ready, Active, Paused, and disabled states before cleanup.

The verifier must keep all three scenario statuses conservative until the complete installed journey passes.
