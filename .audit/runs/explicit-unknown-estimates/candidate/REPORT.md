# Explicit unknown task estimates candidate report

## Candidate scope

This candidate implements a durable end-user choice for tasks that cannot be estimated confidently yet.
It covers `ZC-011-008`, `ZC-011-009`, `ZC-011-010`, and `ZC-011-012` at implementation-candidate level only.
The tracker must remain unchanged until signed installed acceptance proves the complete selection, approval, restart, and replacement journey.

## End-user behavior

- Both the planning ledger and Today task controls expose an explicit `UNKNOWN` estimate choice.
- An untouched task with no estimate still blocks plan approval.
- A task explicitly marked Unknown uses a conservative 45-minute capacity placeholder and permits approval when the resulting plan fits.
- The selected state says `UNKNOWN`, shows the approximate 45-minute placeholder, and labels it uncertain.
- Calendar approval and the durable approval receipt retain the uncertainty label rather than presenting the placeholder as a confident estimate.
- Choosing any numeric or custom estimate later clears the uncertain state.
- The explicit choice persists through the agent-owned plan mutation path, the canonical database, app reload, and restart.
- Legacy persisted plan mutation payloads decode as confident when the new optional field is absent.

## Persistence and migration

The authoritative baseline `6cf2cd7` declared migration 37 and ended its registry at migration 37.
This lane therefore reserved additive migration 38 before implementation.
Migration 38 adds `daily_plan_entries.estimate_is_uncertain` with a non-destructive default of false.
The migration test proves an existing estimated plan row retains its exact estimate and receives the false default.
The verifier must inspect the current authoritative migration registry again before rebasing and renumber this additive migration if another integrated lane has since claimed 38.

## Automated evidence

`swift test --filter PlanningCapacityStateTests` passed 9 tests.
The focused suite proves untouched missing estimates remain blocking, explicit Unknown contributes 45 minutes, approval becomes available only when realistic, and the Calendar preview remains visibly uncertain.

`swift test --filter EventStoreTests` passed 7 tests.
The focused suite proves agent-to-app restart persistence and legacy mutation decoding.

`swift test --filter AutonomousDatabaseMigratorTests` passed 18 tests.
The focused suite proves migration 38 is additive, ordered, idempotent, and preserves prior plan data.

`swift test --filter BaselineObservationTests` passed 11 tests after the schema-version advance.

The four focused suites passed 45 tests with no failures.

`swift build -c release --product ZoidCoach` completed successfully.
Only the pre-existing `CodexJobCoordinator.swift` and `VoiceAudioEngine.swift` warnings were emitted.

`git diff --check` passed.

## Signed installed verifier plan

1. Rebase onto the current authoritative root and confirm or safely renumber migration 38 before integration.
2. Build and install a fresh signed QA app and helper without using this worktree as shared runtime.
3. Create or select one committed priority task with no estimate and prove plan approval is blocked with missing-estimate guidance.
4. Choose `UNKNOWN` from the planning ledger using the mouse and prove the selected state visibly says Unknown, uncertain, and approximately 45 minutes.
5. Confirm capacity increases by exactly 45 minutes and approval becomes available only when the full plan fits.
6. Open Calendar approval and prove the same task appears with an uncertain 45-minute placeholder rather than a confident estimate.
7. Confirm the plan, wait for the durable receipt, and prove the receipt retains the uncertainty label.
8. Restart both app and helper and prove the task is still explicitly Unknown with the same placeholder and approval semantics.
9. Change the estimate to 30 minutes from Today using only the keyboard and prove the Unknown marker disappears, capacity becomes 30 minutes, and the new value survives another restart.
10. Repeat with a custom estimate and verify no stale uncertainty remains.
11. Capture accessibility evidence for the Unknown controls, selected state, placeholder explanation, and approval preview.

## Conservative status recommendation

Keep all four scenarios at their current tracker status until the signed installed verifier succeeds.
If every verifier step succeeds, `ZC-011-008`, `ZC-011-009`, and `ZC-011-010` can become fully implemented.
`ZC-011-012` can become fully implemented only if the verifier also proves an untouched missing estimate cannot be approved while an explicit Unknown choice can.
