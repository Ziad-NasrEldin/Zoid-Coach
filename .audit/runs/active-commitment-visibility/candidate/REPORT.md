# Active Commitment Visibility Candidate Report

## Scope

This candidate owns `ZC-017-001`, `ZC-037-001`, `ZC-059-007`, and `ZC-062-004`.

It makes an active task's identity, timing contract, tracked duration, persistence, and manual controls explicit and consistent across Today and the menu bar.

## End-user behavior

Starting an ordinary task now produces an explicit `OPEN-ENDED SESSION` contract instead of only saying that a task is active.

Today states that manual tracking continues until the user chooses Pause or Complete and that no automatic end time is implied.

The Today heading combines the named active commitment, open-ended or bounded timing state, and tracked duration in one scannable line.

Bounded sprints show their configured duration, current remaining minutes, and the truthful promise that the task stays incomplete when the boundary arrives.

Continuing after a sprint boundary changes both surfaces to `OPEN-ENDED CONTINUATION` rather than leaving stale bounded-session language.

The menu bar uses the same timing model, exposes the timing mode with a stable accessibility identifier, and adds a direct Complete control beside Pause and Break.

The existing agent-owned command path remains the only mutation boundary for Start, Pause, Resume, Break, Complete, and End Workday.

## Focused evidence

`ActiveCommitmentPresentationTests` covers ordinary open-ended tracking, a live bounded countdown, continued-open-ended state, sprint-complete truthfulness, and rejection of inactive rows.

`activeMenuTaskCompletesThroughTheSameDurableCommandBoundary` proves that the menu Complete control issues exactly one `.complete` command for the named task and removes the active state only after the returned canonical snapshot confirms completion.

`menuBarBreakAndEndWorkdayPersistThroughTheCanonicalAgent` now proves that an open-ended task started through the real agent appears with the same timing contract in Today-derived and menu state, survives a new agent instance, and retains the existing break, resume, and end-day behavior.

The focused regex run for `ActiveCommitment`, `activeMenuTaskCompletes`, and `menuBarBreakAndEndWorkdayPersistThroughTheCanonicalAgent` completed successfully.

The build compiled the changed SwiftUI Today and menu-bar surfaces as part of the focused test build.

## Independent signed verifier plan

1. Rebase this candidate onto the current authoritative root and run the focused presentation and menu tests once.
2. Package one signed QA build with a deterministic incomplete Reminder and an accepted one-task plan.
3. Start the task from Today and confirm the named focus card visibly says `OPEN-ENDED SESSION`, explains Pause or Complete, and exposes both controls.
4. Open the actual menu-bar surface and confirm the same task, open-ended timing mode, tracked duration, Pause, Break, Complete, and Open Today controls are present.
5. Restart both app and helper and confirm Today and the menu still identify the same active open-ended task without creating a second activity interval.
6. Complete the task from the menu, confirm Today no longer shows an active commitment, and verify the canonical task history plus Reminder mutation remain singular after relaunch.
7. If the status item is still not addressable through macOS accessibility, retain Touches remaining for the cross-surface scenarios and record the exact platform boundary rather than substituting source inspection.

## File boundary

This candidate does not modify `AppModel.swift`, prompt inbox code, `GamingDriftPromptService.swift`, the scenario tracker, the scenario registry, the Lavish artifact, shared runtime state, or root history.
