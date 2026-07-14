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

No product build, package, install, launch, or runtime mutation was performed while the Screenwatch lane held the serialized leases.
The next verifier may compile the two small accessibility tools and build the exact clean signed QA package only after those leases transfer.
