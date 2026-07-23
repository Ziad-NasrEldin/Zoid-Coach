# ZC-034-011 Prompt Reachability Acceptance Harness

## Purpose

This verifier-only harness reuses the previous isolated two-task prompt fixture and signed lifecycle assertions.
It removes the unreliable scroll step and instead requires every one of the six direct prompt buttons to have a complete native accessibility frame inside the initial 1180x760 Today viewport.
It does not modify product source or the scenario tracker.

## Candidate identity

The rebased source candidate is `3537b8eff2ce460fca9b7015a69caa831cbdb75e` on canonical base `cb27c619b415c6a6adef103b0690cf6068b98f73`.
The verifier-only source test strengthening is `1cc6b852f3f3cdaf9672885f8abadbcd9952a74a`.
The release QA package must report `zoid-coach-1cc6b852f3f3cdaf9672885f8abadbcd9952a74a-clean` before runtime use.
The package may be built in a separate clean worktree at that exact commit and supplied through `ZOID_ACCEPT_PACKAGE_APP`.

## Runtime journey

The harness installs the prebuilt signed QA app once into an isolated install root.
It proves the installer-created helper exposes a writable XPC prompt timeline and heartbeat.
It stops the foreground app and helper, replaces only the isolated QA root with the canonical ready-state fixture, materializes the canonical schema, seeds the two-task plan plus six-action presented prompt, and re-registers the helper without cleaning that root.
It first requires the Today window probe to prove the unminimized 1180x760 initial viewport.
It then requires exactly six direct `AXButton` controls and verifies that every full frame is inside that viewport before any scrolling or mutation.
It activates Mark blocked, the approval preset, and Save Blocker through native pointer clicks.
It records pixels, accessibility output, and exact SQLite assertions for one response, blocked reason, closed interval, replacement-main promotion, answered history, app relaunch, and helper relaunch.
Finally, it repeats from a fresh presented fixture, unregisters the helper immediately before Save, and requires the specific recovery message plus an unchanged database.

## Safety

The default invocation refuses to run without `ZOID_ACCEPT_RUNTIME_LEASE=granted`.
`--dry-run` validates only the package identity, signatures, compiled tools, manifest, and paths.
The exit trap always stops the isolated app, unregisters the QA LaunchAgent, and removes only the harness-owned install and QA roots.

## Lease state

The serialized build, package, and runtime leases transferred for this bounded run.

## Verification result

All three exact focused filters passed independently.
The exact clean `1cc6b852f3f3cdaf9672885f8abadbcd9952a74a` release QA package passed signing and package-identity verification.
The harness dry-run passed.
The first two signed invocations stopped before product mutation because the reused ready-state manifest no longer satisfied the stricter Screenwatch fixture contract.
The manifest now uses a matching unavailable and missing Screenwatch state, and the exit cleanup now disarms its trap only after disabling immediate shell exit.

The final bounded signed run reached the candidate with a writable XPC helper, a presented `qa-block-1` episode containing six persisted actions, an active primary task, an eligible replacement task, one open interval, and zero responses.
The launched Today accessibility tree exposed zero direct action buttons matching `today.prompt.qa-block-1.action.` instead of six.
The harness stopped before clicking Mark blocked or mutating the database.
Therefore the Save, exact database mutation, replacement objective, relaunch persistence, and helper-down gates remain unverified.
`ZC-034-011` must remain `Touches remaining`.

## Cleanup result

The foreground app, helper, QA LaunchAgent, isolated install root, and isolated QA root were all absent after the failed gate.
No tracker, registry, Lavish artifact, canonical user database, or canonical branch was modified.
