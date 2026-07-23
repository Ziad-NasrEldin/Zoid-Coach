# Explicit Unknown estimate verifier report

## Integration identity

- Authoritative base: `6cf2cd7`.
- Candidate source: `aaddd3f`.
- Replayed claim: `734182a`.
- Replayed implementation: `e27029b`.

## Migration decision

The authoritative base ends with migration 37 for the non-destructive baseline observation ledger.
The candidate adds estimate uncertainty as migration 38.
The registry remains strictly ordered and no renumbering is required.
The migration preserves existing numeric estimates and initializes existing rows as not uncertain.

## Focused verification

The verifier ran the four requested suites together exactly once.
The command was `swift test --filter "PlanningCapacityStateTests|EventStoreTests|AutonomousDatabaseMigratorTests|BaselineObservationTests"`.
All 45 tests passed with exit code 0.

Code and test inspection confirmed these semantics:

- An untouched nil estimate remains missing and blocks approval.
- An explicit Unknown choice stores nil minutes plus `estimateIsUncertain = true`.
- Explicit Unknown contributes a conservative 45-minute capacity placeholder.
- Calendar approval includes the task and visibly preserves the uncertainty flag.
- The durable Calendar approval receipt stores the same uncertainty-bearing item.
- A numeric preset or valid custom estimate replaces nil minutes and clears the uncertainty flag.
- Event-store reopening restores explicit Unknown without converting it to a confident 45-minute estimate.

## Release package proof

The verifier ran one clean release QA package command.
The command was `CONFIGURATION=release ZOID_COACH_PACKAGE_MODE=qa ZOID_COACH_QA_RUN_ROOT="$PWD/.build/qa-explicit-unknown-verifier" Scripts/package-app.sh`.
The command passed with exit code 0.
The package, LaunchAgent, Mach service, embedded helper, and signing identities were coherent.
The signed output is `.build/app-qa/Zoid 666 QA.app` inside this verifier worktree.

## Capped signed acceptance flow

The signed installed run used `/private/tmp/zoid-666-explicit-unknown-apps/Zoid 666 QA E2E.app` with isolated state at `/private/tmp/zoid-666-explicit-unknown-qa`.
The exact embedded QA helper was registered, enabled, and running from the installed application.

1. An untouched committed task with nil minutes showed `ESTIMATE NEEDED`, zero planned minutes, one remaining estimate, and a disabled approval button.
2. The run found and fixed one real blocker where the active-commitment header and Reminders continuity banner silently presented the missing estimate as 45 minutes.
3. The corrected signed app showed `ACTIVE COMMITMENT · ESTIMATE NEEDED` and zero estimated minutes for the same untouched task.
4. Choosing the visible `UNKNOWN` control selected it on both Today representations and rendered `~45 MIN PLACEHOLDER · UNCERTAIN`.
5. Capacity changed from zero to exactly 45 planned minutes and approval became available because the plan fit within 378 available minutes.
6. Calendar approval showed `Investigate production issue`, `~45 MIN`, and `UNCERTAIN PLACEHOLDER` before any write.
7. With the deterministic QA Calendar healthy, confirmation created a durable receipt that listed `Investigate production issue · MAIN ~45m placeholder`.
8. App and helper relaunch restored the selected Unknown controls, 45-minute capacity placeholder, and last approval receipt.
9. Selecting 30 minutes cleared both Unknown selections, removed all uncertainty copy, changed the header to `30 MIN ESTIMATE`, and changed capacity to 30 planned minutes.

The signed run also proved the environment-safe refusal path before Calendar permission was granted.
No Calendar write occurred until source health was healthy and the reviewed preview was confirmed.
