# Bounded Sprint Lifecycle Candidate

## Scope

- Base commit: `2e20227`.
- Branch: `codex/bounded-sprint-lifecycle`.
- Primary scenarios: `ZC-017-002` through `ZC-017-011`, `ZC-018-001`, `ZC-018-002`, `ZC-034-002`, `ZC-034-003`, `ZC-037-002`, `ZC-037-003`, `ZC-038-006`, and `ZC-053-005`.
- Secondary scenarios: `ZC-015-004`, `ZC-023-002`, `ZC-033-007`, and `ZC-059-005`.

## Implemented user flow

- The Today focus card offers 10-minute recovery, 20-minute work, 25-minute focus, and custom 1-to-240-minute sprint choices.
- Invalid, empty, zero, negative, malformed, and greater-than-240 custom durations cannot be submitted and show a direct validation message.
- Starting a sprint starts or switches the underlying task atomically while preserving prior task time and pausing the previous task with the existing switching reason.
- A live countdown updates once per second and distinguishes active, paused, expired, and open-ended continuation states.
- Pausing a task freezes the sprint countdown, and resuming continues from the exact persisted remaining time.
- A restart preserves the selected duration, accumulated active seconds, paused state, and remaining time.
- Sleeping or remaining away past the boundary reconciles the sprint as expired when the snapshot refreshes.
- Sprint expiry never completes the task and exposes an explicit Continue Open-Ended action.
- Completing, blocking, rescheduling, or deliberately starting the task without a sprint closes the bounded sprint record safely.
- Repeating the same sprint-start command while it is already active is idempotent and does not reset the timer.

## Persistence and migration

- Migration 32 adds append-only `task_sprint_sessions` storage with bounded durations, accumulated active seconds, current active segment, constrained lifecycle states, and one-open-sprint enforcement per task.
- Migrations 28, 29, 30, and 31 remain unchanged.
- Existing persisted Today snapshots decode without sprint data because all new snapshot fields are optional.

## Verification

- `git diff --check` passed.
- Independent verification rebased the slice onto `1d2652f` before running the focused gate.
- `swift test --filter "TodayDashboardTests|TaskExecutionStoreTests|TodayDashboardAgentTests|AutonomousDatabaseMigratorTests"` passed with 44 tests after the verifier fix.
- Focused proof covers preset and custom durations, invalid bounds, duplicate starts, pause and resume, task switching, completion, restart, sleep and wake expiry, open-ended continuation, migration sequencing, and agent snapshot durability.
- The verifier closed a boundary defect that allowed open-ended continuation without an expired sprint, preserved duplicate continuation idempotence, and added an explicit accessibility announcement for the open-ended timer state.
- Full-suite, release-build, signed-QA packaging, and installed-app click-through were intentionally not run because the root orchestrator owns the shared runtime and signing lease.
- The authoritative tracker, registry, backlog, and Lavish report were not edited by this implementation lane.
