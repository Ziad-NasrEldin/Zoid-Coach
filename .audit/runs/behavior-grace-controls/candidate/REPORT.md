# Configurable behavior grace controls candidate report

## Scope

This candidate implements configurable behavior-coaching grace controls for `ZC-027-001`, `ZC-027-002`, `ZC-027-003`, and `ZC-045-006`.

It changes only the Gaming Policy grace fields, policy validation, conflict-safe Settings controls, the existing gaming-drift decision boundary, focused tests, backlog ownership, and candidate evidence.

It does not touch AgentMutation, AppModel, Dashboard views, rescheduling, root, runtime installation, tracker, registry, or Lavish.

## End-user behavior

Settings now exposes `AFTER STARTING A TASK` from No Grace through 60 minutes.

Settings now exposes `AFTER RETURNING FROM IDLE` from No Grace through 30 minutes.

The defaults remain three minutes after task start and one minute after returning from idle, so legacy policies preserve the existing behavior.

Both controls save through the existing authenticated versioned-policy boundary and reconstruct their exact values when Settings reopens.

Independent concurrent edits merge safely, while overlapping edits keep the winning values and preserve the user's values for explicit reapply.

The task-start accessibility hint explains that sustained high-confidence gaming which began before the task can bypass the grace.

The return-from-idle accessibility hint explains that reliable idle activity or a telemetry gap activates the selected grace.

## Runtime semantics

The behavior producer reads both durations from the supplied latest policy for every decision.

Changing a duration therefore affects the next evaluation without recreating the service or restarting the helper.

A positive task-start grace suppresses normal coaching while the active task is younger than the configured boundary.

A zero task-start grace disables only that guard.

A positive return-from-idle grace suppresses coaching while the latest reliable return remains within its configured boundary.

A zero return-from-idle grace disables only that guard.

Sustained high-confidence gaming that began before the active task still bypasses both grace checks when the other prompt conditions are met.

No task state is paused or mutated by either suppression result.

## Compatibility and validation

Legacy Gaming Policy payloads decode to the established three-minute and one-minute defaults.

Round-trip encoding preserves customized values.

Policy validation accepts task-start grace from 0 through 60 minutes and return-from-idle grace from 0 through 30 minutes.

Values outside those ranges fail the existing policy validation boundary.

## Focused verification

- `git diff --check` passed.
- The focused User Policy, Settings Policy Draft, and Gaming Drift Prompt Service test groups passed.
- Four directly targeted save, conflict, legacy, and live-decision tests passed with `--skip-build` after the focused build.
- The live-decision test proves a 15-minute task-start grace suppresses at minute 12 and a newly saved 10-minute grace permits the next eligible decision without restart.
- The same test proves a two-minute return-from-idle grace suppresses the current transition and No Grace immediately falls through to the truthful below-threshold result.
- Existing focused coverage continues to prove sustained high-confidence gaming bypasses task-start grace.

## Parallel verifier plan

The verifier should rebase the candidate onto the latest authoritative root and rerun only the affected focused groups.

The verifier should install one signed QA package under an isolated run root.

The verifier should open Settings, set task-start grace to 12 minutes and return-from-idle grace to four minutes, save through the helper, reopen Settings, and confirm both values and accessibility descriptions persist.

The verifier should start a task, seed an otherwise eligible fresh gaming session inside the 12-minute boundary, and confirm the agent reports `taskStartGrace` with no prompt or task mutation.

The verifier should save a shorter boundary without restarting the helper, repeat the decision after that boundary, and confirm the next evaluation uses the new value.

The verifier should seed a reliable idle or telemetry-gap return and confirm the selected return grace suppresses coaching without changing the active task.

The verifier should seed sustained high-confidence gaming that began before the task and confirm the existing bypass still produces exactly one eligible prompt.

The verifier should relaunch the app and helper, reopen Settings, and confirm both values remain durable.

Only the parallel verifier should update the tracker, registry, or Lavish audit after installed end-to-end proof.
