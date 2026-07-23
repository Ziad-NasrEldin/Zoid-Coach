# Configurable behavior grace controls verifier report

## Verdict

Candidate `7d17dbc` was independently replayed and then rebased once onto authoritative root `9fad08e` as verifier commit `62a5760`.
The candidate is accepted for integration with no verifier code fixes.
Installed end-to-end acceptance fully qualifies `ZC-045-006` and adds signed suppression evidence without over-claiming the remaining wake, unlock, idle, or sustained-bypass scenarios.

## Focused verification

- The focused User Policy, Settings Policy Draft, and Gaming Drift Prompt Service groups passed 67 of 67 tests.
- The release build passed once.
- One clean release-configured signed QA package passed package structure, deep signing, designated requirement, LaunchAgent, Mach-service, embedded QA runtime identity, and clean-commit coherence checks.
- The signed package was installed at `/private/tmp/zoid-grace-controls-install/Zoid 666 QA E2E.app` with isolated root `/private/tmp/zoid-grace-controls-qa-runtime`.
- The installed Settings UI visibly exposed the legacy three-minute task-start grace and one-minute return-from-idle grace with stable accessibility identifiers and explanations.
- The UI saved 12-minute and four-minute grace values through the running agent as policy V2.
- Closing and reopening Settings restored both exact values.
- Restarting the app and helper changed the helper PID from 35702 to 39543 and restored policy V2 with both exact values.
- The signed isolated runtime evaluated a fresh ten-observation gaming fixture inside the 12-minute task boundary and retained zero prompts, zero quiet-drift records, one active task, one open task interval, and all ten behavior records.
- The UI then shortened task-start grace to ten minutes through the running agent as policy V3 without restarting the helper.
- The helper PID remained 46242 across the live-shortened recheck and the runtime checkpoint advanced, but no prompt was enqueued.
- The capped run therefore does not claim installed proof for the shorter-boundary prompt, return-from-idle boundary, or sustained pre-task bypass.

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

## Remaining installed acceptance

The next verifier should target only the remaining behavior decisions.

1. Diagnose why the otherwise eligible policy V3 fixture did not enqueue after the confirmed agent loop.
2. Prove a reliable idle or telemetry-gap return inside the saved four-minute boundary without prompt or task mutation.
3. Prove a ten-minute high-confidence gaming session that began before the active task creates exactly one eligible prompt.
4. Keep `ZC-027-002` and `ZC-027-003` conservatively unchecked until those installed decisions pass.

## Integration boundary

The tracker, registry, and Lavish audit record only the fully qualified Settings scenario.
The parent integrator should integrate the rebased chain after cleanup.
