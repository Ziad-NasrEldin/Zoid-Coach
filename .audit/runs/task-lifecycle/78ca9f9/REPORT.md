# Task Pause And Switch Lifecycle Evidence

## Scope

This run verifies commit `78ca9f9` on branch `codex/daily-plan-lifecycle`, based on `586d8db`.

The implementation covers dashboard start, pause, resume, explicit switch, persistent pause reasons, single-command serialization, restart-safe elapsed time, blocked state, and explicit completion of a paused task.

The affected scenario IDs are `ZC-016-001`, `ZC-016-007`, `ZC-016-008`, `ZC-016-010`, `ZC-018-001`, `ZC-018-006` through `ZC-018-011`, `ZC-019-001` through `ZC-019-009`, and `ZC-020-002`.

This batch does not claim menu-bar parity, sprint timing, completed-history presentation, Reminder outbox confirmation, retry, rescheduling, or contextual replanning.

## End-User Contract

The prominent Today focus card and the detailed task row both expose pause choices instead of hiding pause behind backend-only support.

A user can identify a pause as a break, an external interruption, done for now, or the end of the workday.

Marking a task blocked records that reason as part of the local task lifecycle.

Starting a different task presents an explicit confirmation that the active task will pause, its time will be preserved, and the new task will start.

The prior task receives the durable `switchingTasks` reason atomically with the task switch.

The Today UI shows tracked minutes, current paused reason, and the most recent pause reason after work resumes.

A paused task exposes both Resume and Complete, so completion does not require a fake resume.

While a command is pending, every task action is disabled to prevent duplicate or racing task transitions.

A successful command produces explicit confirmation copy, while failure keeps the last confirmed snapshot visible and offers an actionable Agent-health recovery path.

## Persistence And Recovery Proof

`pauseReasonPersistsAcrossRestartAndClosesWhenWorkResumes` proves a break reason and five tracked minutes survive store reconstruction, then resume adds time without double counting.

`switchingTasksRecordsReasonAndPreservesEarlierElapsedTime` proves a switch pauses the earlier task with the exact switching reason, preserves its four minutes, and leaves only the second task active.

`completingPausedTaskRetainsTimeAndEndsItsPauseEpisode` proves explicit completion from paused preserves tracked time and closes the pause episode.

`agentPauseSwitchResumeAndCompletePausedJourneySurvivesRestart` proves the full agent-facing journey across start, reasoned pause, resume, switch, agent reconstruction, done-for-now pause, and completion of a paused task.

Migration 29 creates append-only `task_pause_events` with constrained reason values, one open episode per task, and restart-safe timestamps.

## Verification Results

- `swift test` passed all 460 Swift tests in five suites.
- `swift build -c release` passed.
- `python3 -m unittest discover -s Tests/ScenarioRegistryTests -p "test_*.py"` passed all 41 registry, package, lifecycle, identity, and evidence tests.
- `ZOID_COACH_PACKAGE_MODE=qa ZOID_COACH_QA_RUN_ROOT=/private/tmp/zoid-666-task-lifecycle-proof Scripts/package-app.sh` produced and verified a clean signed `Zoid 666 QA.app` at commit `78ca9f9`.
- Deep code signing, designated requirements, LaunchAgent identity, and Mach-service coherence passed through `Scripts/verify-package.sh`.
- `git diff --check` passed before the implementation commit.

## Remaining Acceptance Proof

An independent verifier should click through the pause-reason menu, switch confirmation, resume action, and paused-task completion in the installed signed-QA app before the root tracker upgrades any row to Fully implemented.

The broader backlog item still needs skip, defer, reorder, and revise behavior, so priority 14 returns to `ready` after this delivered sub-slice.

## Independent Integration Verification

The verifier rebased this slice onto canonical commit `586d8db`, where daily review already owns migration 28, and confirmed that task lifecycle correctly owns migration 29 without renumbering or collision.

Focused `TaskExecutionStoreTests`, `AutonomousDatabaseMigratorTests`, and `TodayDashboardAgentTests` passed.

The full suite passed all 460 Swift tests in five suites, all 41 Python registry and evidence tests, the release build, registry validation for exactly 666 scenarios, and `git diff --check`.

A fresh clean signed-QA package passed package, deep-signing, LaunchAgent identity, and Mach-service verification from the integration worktree.

The Mac was locked during the independent acceptance attempt, so no scenario was promoted to Fully implemented from deterministic evidence alone.

The tracker retains Touches remaining or Partially implemented status until the installed pause, switch, resume, and paused-completion click-through is captured.
