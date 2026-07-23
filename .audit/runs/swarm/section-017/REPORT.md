# Section 017 Stop Handoff

## Assignment

Section 17: Choosing a work commitment.
Assigned IDs: ZC-017-001 through ZC-017-011.

## Repository state

Worktree: `/Users/ziadnasreldin/.codex/worktrees/ece6/Zoid Coach`.
Branch: detached HEAD.
HEAD: `2cba674f8370fc16f9555cdb6f115f18df1f8ced`.
The required `git merge --ff-only codex/full-system` succeeded before work began.
No commit was created.

## Work completed before stop

The authoritative tracker and registry were read and left unchanged.
ZC-017-006 was selected as the highest-value incomplete scenario because it was the only assigned scenario still marked Partially implemented with a concrete code gap.
The root cause was traced to the Today sprint menu, which exposed fixed and custom bounded durations but did not pass the known task estimate to the existing bounded-sprint path.
A focused test file was added for an exact known estimate and for unknown, zero, and over-limit estimates.
A small `FullEstimateSprintOption` presentation type and a Today menu action were added.
The menu action uses the existing `AppModel.startSprint` path and adds a stable accessibility identifier.

## Per-ID state

| ID | Lane result | Notes |
| --- | --- | --- |
| ZC-017-001 | BLOCKED | Immediate stop arrived before installed QA proof. |
| ZC-017-002 | BLOCKED | Immediate stop arrived before installed QA proof. |
| ZC-017-003 | BLOCKED | Immediate stop arrived before installed QA proof. |
| ZC-017-004 | BLOCKED | Immediate stop arrived before installed QA proof. |
| ZC-017-005 | BLOCKED | Immediate stop arrived before installed QA proof. |
| ZC-017-006 | BLOCKED | Coherent implementation is present but uncommitted and unverified because the immediate stop interrupted the first isolated Swift build. |
| ZC-017-007 | VERIFIED COMPLETE | Already verified in the inherited baseline at `81937fd46828ce27786f668a004cd9248307b88a`; this lane made no changes for it. |
| ZC-017-008 | BLOCKED | Immediate stop arrived before installed QA proof. |
| ZC-017-009 | BLOCKED | Immediate stop arrived before installed QA proof. |
| ZC-017-010 | BLOCKED | Immediate stop arrived before installed QA proof. |
| ZC-017-011 | BLOCKED | Immediate stop arrived before installed QA proof. |

## Changed files

- `Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift`
- `Sources/ZoidCoachApp/FullEstimateSprintOption.swift`
- `Tests/ZoidCoachAppTests/FullEstimateSprintOptionTests.swift`
- `.audit/runs/swarm/section-017/REPORT.md`
- `.audit/runs/swarm/section-017/red.log`

## Tests and evidence

The focused command was `swift test --scratch-path /private/tmp/zoid-section-017-build --filter FullEstimateSprintOptionTests`.
The isolated build was still compiling when the stop arrived and was terminated without a result.
`red.log` is empty and must not be treated as proof.
No installed-app Browser QA or proof screenshot was completed.

## Remaining work

Review the uncommitted diff before continuing.
Run the focused test to completion and fix any compiler or behavior failures.
Run the relevant Today dashboard and task execution suites.
Build and install the isolated QA app.
Use only the Codex built-in in-app Browser to exercise the full-estimate menu action, confirm the exact countdown, and capture a proof screenshot.
Commit only after automated and installed QA proof pass.

## Integration and rollback

There is no commit to integrate.
The root integrator should cherry-pick a future verified commit, not this uncommitted worktree state.
Rollback, if later required, is the single future commit that contains these section 17 changes.
No reset, revert, discard, push, or tracker update was performed.
