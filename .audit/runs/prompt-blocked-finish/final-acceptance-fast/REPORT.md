# ZC-034-011 Fast Final Acceptance Harness

## Purpose

This verifier-only harness front-loads package, signing, native accessibility tooling, and fixture preparation so the next serialized runtime lease spends less than two minutes on the final acceptance journey.
It does not modify product source or the scenario tracker.

## Candidate identity

The target candidate is exact canonical commit `f28ad1087623bd308fc410f78ab6215cf1b69131`.
The release QA package must report `zoid-coach-f28ad1087623bd308fc410f78ab6215cf1b69131-clean` before runtime use.

## Runtime journey

The harness installs the prebuilt signed QA app once into an isolated install root.
It proves the installer-created helper exposes a writable XPC prompt timeline and heartbeat.
It stops the foreground app and helper, replaces only the isolated QA root with the canonical ready-state fixture, materializes the canonical schema, seeds the two-task plan plus six-action presented prompt, and re-registers the helper without cleaning that root.
It then drives the approval preset and Save Blocker through native accessibility identifiers.
It records pixels, accessibility output, and exact SQLite assertions for one response, blocked reason, closed interval, replacement-main promotion, answered history, app relaunch, and helper relaunch.
Finally, it repeats from a fresh presented fixture, unregisters the helper immediately before Save, and requires the specific recovery message plus an unchanged database.

## Safety

The default invocation refuses to run without `ZOID_ACCEPT_RUNTIME_LEASE=granted`.
`--dry-run` validates only the package identity, signatures, compiled tools, manifest, and paths.
The compiled verifier tools live under the ignored `.build/zc034011-fast` directory and are not committed as source artifacts.
The exit trap always stops the isolated app, unregisters the QA LaunchAgent, and removes only the harness-owned install and QA roots.

## Preparation status

The exact clean package, signing evidence, and both compiled verifier tools are ready.
The guarded non-runtime dry run passed without installing or launching the app or helper.
Detailed preparation evidence is recorded in `PREPARATION.md` and the `evidence` directory.

## Latest signed result

The final bounded signed acceptance did not reach the blocker sheet from the off-screen Mark blocked accessibility node.
`ZC-034-011` therefore remains `Touches remaining`.
The exact failure and cleanup evidence are recorded in `RUNTIME-RESULT.md`.
