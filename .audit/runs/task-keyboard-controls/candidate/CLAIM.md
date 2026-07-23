# Task keyboard controls claim

## Baseline

- Authoritative baseline: `1c9d5466ebec2c505ee5bb11ad07b3f9e14598e9`.
- Branch: `codex/keyboard-task-start`.

## Scenarios

- `ZC-016-005` - Start a task with a keyboard shortcut.
- `ZC-018-006` - Pause the task.
- `ZC-018-007` - Resume the task.

## Files

- `Sources/ZoidCoachApp/TaskKeyboardCommands.swift`.
- Commands registration only in `Sources/ZoidCoachApp/ZoidCoachApp.swift`.
- `Tests/ZoidCoachAppTests/TaskKeyboardCommandsTests.swift`.
- Candidate evidence under `.audit/runs/task-keyboard-controls/candidate/`.

## Boundaries

This lane owns discoverable application-menu keyboard commands for starting the current recommended task and pausing or resuming the canonical current task.
It reuses the existing globally serialized XPC task-command path and never bypasses switch confirmation when another task is active.
It does not touch Daily Review, Unknown-session review, task persistence, Dashboard views, menu-bar controls, root, runtime, tracker, registry, backlog, or Lavish.
