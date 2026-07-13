# Configurable behavior grace controls verifier report

## Verdict

Candidate `7d17dbc` was independently replayed and then rebased once onto authoritative root `9fad08e` as verifier commit `62a5760`.
The candidate is accepted for integration with no verifier code fixes.
Installed end-to-end acceptance remains intentionally pending because the reschedule-sync verifier owns the signed QA runtime and tracker lease.

## Focused verification

- The focused User Policy, Settings Policy Draft, and Gaming Drift Prompt Service groups passed 67 of 67 tests.
- The release build passed once.
- One clean release-configured signed QA package passed package structure, deep signing, designated requirement, LaunchAgent, Mach-service, embedded QA runtime identity, and clean-commit coherence checks.
- The signed package is at `.build/app-qa/Zoid 666 QA.app` and embeds isolated root `/private/tmp/zoid-grace-controls-qa-runtime`.
- The package was not installed and no shared runtime, tracker, registry, or Lavish files were touched.

## Semantic audit

- Legacy Gaming Policy payloads decode task-start grace to three minutes and return-from-idle grace to one minute.
- Settings accepts task-start grace from 0 through 60 minutes and return-from-idle grace from 0 through 30 minutes.
- User Policy validation rejects values above those maxima, while the Gaming Policy initializer clamps negative inputs to zero consistently with existing policy fields.
- Settings draft reconstruction and encoding preserve both values.
- Conflict resolution merges independent edits and retains the winning value for overlapping edits while preserving the local value for explicit reapply.
- The production agent loop loads the current policy before every gaming-drift decision and passes it directly to the existing service, so saved grace changes affect the next evaluation without a helper restart.
- A zero duration bypasses only its matching grace guard because each guard requires a strictly positive interval.
- Sustained high-confidence gaming of at least ten minutes bypasses both grace checks only when the gaming session began before the active task.
- Both grace suppressions return before prompt enqueueing, behavior-record creation, or task mutation.
- Focused tests explicitly retain one active task and an empty prompt inbox for the new suppression paths.

## Capped installed acceptance plan

The next verifier with the signed runtime lease should perform one capped installed run.

1. Install the already verified clean QA package under its isolated runtime root.
2. Open Settings, save task-start grace at 12 minutes and return-from-idle grace at four minutes, close Settings, reopen it, and confirm both values and their accessibility descriptions persist.
3. Start a task, seed an otherwise eligible fresh gaming session inside the 12-minute boundary, and confirm `taskStartGrace` with no prompt, no behavior record, and no task mutation.
4. Shorten task-start grace below the elapsed duration without restarting the helper and confirm the next eligible decision uses the new value.
5. Seed a reliable idle or telemetry-gap return inside the four-minute boundary and confirm `returnFromIdleGrace` with no prompt or task mutation.
6. Seed a ten-minute high-confidence gaming session that began before the active task and confirm exactly one eligible prompt.
7. Restart the app and helper, reopen Settings, and confirm the saved 12-minute and four-minute values remain durable and still govern the next decisions.
8. Update the tracker, registry, and Lavish audit only after this installed evidence passes, then uninstall the isolated runtime and release the lease.

## Integration boundary

This verifier report is the only source change made on the verifier branch.
The parent integrator should cherry-pick the candidate and this report after the predecessor verifier finishes and releases shared ownership.
