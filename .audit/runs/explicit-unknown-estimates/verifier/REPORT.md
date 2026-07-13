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

The installed acceptance flow remains intentionally deferred until the prompt-clarity runtime lease is released.
The verifier will use one capped journey with one committed priority task and sufficient capacity.

1. Confirm the untouched task has no estimate and Calendar approval is blocked with missing-estimate guidance.
2. Choose `UNKNOWN` through the visible control and confirm the task shows Unknown, uncertain, and an approximately 45-minute placeholder.
3. Confirm planned capacity increases by exactly 45 minutes and approval becomes available only while the plan fits.
4. Open Calendar approval and confirm the same task remains visibly uncertain rather than showing a confident 45-minute estimate.
5. Approve and confirm the durable receipt retains the uncertainty label.
6. Relaunch the app and helper and confirm the explicit Unknown state, placeholder, and approval semantics persist.
7. Replace Unknown with a numeric estimate and confirm the uncertainty marker disappears, capacity uses the numeric value, and the cleared state persists after another relaunch.

The verifier has not touched the installed runtime, tracker, registry, or Lavish artifact while another verifier owns that lease.
