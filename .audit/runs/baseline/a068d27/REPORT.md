# Zoid Coach checked-scenario baseline verification

Baseline: `a068d2786c7725204cefa270a736e02f1a910b52`.

Branch: `codex/zc-baseline-verifier`.

Run date: 2026-07-12.

This is an independent, read-only verification of the 21 scenarios checked in `docs/zoid-coach-product-scenario-tracker.md`.

No production source, package metadata, migration, tracker, implementation document, Reminders data, Calendar data, permission state, or service state was mutated.

## Verdict

Retain 6 of the 21 checked scenarios.

Recommend downgrading 15 positive end-user scenarios to `Blocked from verification` until a current packaged-app UI journey is captured.

The 6 retained scenarios are negative Release 1 scope invariants rather than interactive flows.

They are supported by repository-wide negative searches, the macOS-only package manifest, and the installed bundle shape.

## Baseline health

- The starting worktree was clean, on the expected branch, and at the expected baseline.
- `swift test` passed 188 tests in 4 suites with no failures.
- `swift build -c release` completed successfully.
- Installed app version 0.1.0 Build 8 exists at `/Users/ziadnasreldin/Applications/Zoid Coach.app`.
- App and agent signatures validate and share Team ID `377QC32T9T`.
- The package verifier passed.
- The LaunchAgent and Mach service are active and the agent runs from the installed Build 8 bundle.
- The canonical database passes `PRAGMA integrity_check`, contains 44 tables, and is held by the live installed agent with no deleted or Trash handle observed.
- The canonical database contains 316 source tasks and 15,141 behavior records.
- The background verifier passed Screenwatch freshness, Zoid ingestion freshness, and agent heartbeat freshness during this run.

## Critical proof boundary

The installed main app was not running.

System Events returned `false` for process `Zoid Coach`, and `pgrep -x ZoidCoach` returned no PID.

Launching the app would initialize `AppModel`, refresh real EventKit data, communicate with the production XPC agent, and write source-check or snapshot state.

That would violate this run's non-mutation boundary.

Therefore no current main-window accessibility tree, screenshot, button activation, or packaged UI flow was claimed.

Source code and unit tests show that the positive UI behaviors are plausibly implemented.

They do not prove complete end-user usability in the installed app.

## Downgrade recommendations

Recommend changing these checked scenarios to `Blocked from verification` until they are proven in an isolated E2E environment or a supervised real-Mac acceptance run:

1. Avoid repeated Reminders permission dialogs after denial.
2. See detected Screenwatch health.
3. Open planning manually before the configured time.
4. Hide completed tasks from the active list.
5. Understand a Reminders refresh failure.
6. See connected source health.
7. See the main objective as the strongest task element.
8. See the active or next task prominently.
9. See gaming budget status.
10. Find remaining tasks below the priority plan.
11. See one next-task recommendation.
12. See one concise recommendation reason.
13. Receive a recommendation from today's selected tasks.
14. Open Zoid Coach at the start of the day.
15. Review eligible Reminders.

Each has supporting source or backend evidence.

None had current packaged UI E2E proof under the permitted read-only conditions.

## Retained negative invariants

Retain these six checked scope constraints:

1. No team workspace, manager, shared-permission, or monitoring-of-others system.
2. No public web dashboard.
3. No cloud screenshot synchronization subsystem.
4. No mobile companion or cross-device behavior correlation.
5. No automatic multi-task Reminder decomposition.
6. No hard application or website blocking.

The negative searches found no relevant implementation.

`Package.swift` declares macOS 14 only, no external dependencies, and only the native app, local agent, and core library products.

The installed bundle contains only the two native executables, Info.plist, LaunchAgent plist, and signature resources.

## Installed-build identity limitation

The installed app reports version 0.1.0 Build 8 and validates cryptographically.

Its Info.plist does not embed a Git commit identifier.

The baseline commit differs from its parent only by audit and documentation files, so application source matches the audited source baseline.

However, exact installed-binary-to-Git provenance cannot be independently proven from Build 8 metadata alone.

Future packages should embed a source commit and dirty-state marker.

## Required next proof

The positive scenarios need the planned isolated runtime environment and UI harness.

At minimum, proof should include the signed app, isolated database and EventKit fixtures, stable accessibility identifiers, screenshots, AX snapshots, durable database assertions, and exact build-to-commit identity.

The tracker itself was intentionally not edited.
