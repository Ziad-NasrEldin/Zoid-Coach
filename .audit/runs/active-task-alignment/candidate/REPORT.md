# Active-task time comparison candidate

## Scope

This candidate covers `ZC-024-008` without changing authoritative scenario status.
The active Today focus now shows cumulative Task elapsed and Observed aligned as separate values.
Observed aligned includes only work-classified Screenwatch time at or after the current active-session start.
Earlier observations are excluded so the UI does not attribute pre-task activity to the active task.
The visible evidence copy states that classification is a signal rather than proof of task match.
Missing or stale Screenwatch evidence preserves the task timer and explains the limitation without guessing.
The combined comparison has the stable accessibility identifier `today.focus.active-time-comparison` and an exact spoken summary of both values and the limitation.

## Focused verification

- `swift test --filter 'activeTaskTimeComparison|agentSnapshotShowsOnlyObservedAlignmentFromTheCurrentActiveSession'` passed three selected Swift Testing tests.
- Domain proof covers elapsed and aligned separation, pre-session exclusion, missing evidence, limitation copy, and the accessibility summary.
- Persistence-backed agent proof starts a real task, inserts pre-session and current-session observations, and verifies three elapsed minutes remain separate from two observed-aligned minutes.
- `swift build -c release` passed.
- `git diff --check` passed.

## Independent verifier plan

1. Rebase or cherry-pick the candidate onto the current authoritative root and build a signed QA package.
2. Start a task after at least one earlier work observation exists.
3. Produce a controlled current session containing both work-classified and non-work-classified observations.
4. Open Today and prove Task elapsed and Observed aligned are simultaneously visible and differ as expected.
5. Inspect accessibility and prove `today.focus.active-time-comparison` announces both values and the evidence limitation.
6. Relaunch the app and helper, return to Today, and prove the active-session comparison remains truthful.
7. Repeat without Screenwatch observations and prove the task timer continues while Observed aligned remains zero with missing-evidence copy.
