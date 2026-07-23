# Zoid 666 Settings And Safety Signed E2E Acceptance

Candidate `6038cc65e0ede965071cbb616bf3316b26f635ba` was independently verified from a clean isolated worktree and integrated into `codex/full-system` without touching the production application or runtime.

## Shared gates

- PASS: 42 focused tests passed across Screenwatch repair, Domain Rules, Discord and Twitch contextual settings, and ambiguous-drift behavior.
- PASS: the signed-QA installer readiness check, package identity, deep signing, bundled LaunchAgent, Mach service, and runtime-root isolation passed.
- PASS: the installed helper launched from the isolated app and exposed writable XPC prompt state.
- PASS: signed XPC policy mutation, replay, and stale-rejection checks passed.
- PASS: the foreground signed app exposed real accessibility content.

## Scenario decisions

- `ZC-003-006` is Fully implemented.
  The signed UI completed alternate Screenwatch folder selection, a healthy recheck, persistence across relaunch, and privacy-safe presentation.
- `ZC-045-009` is Fully implemented.
  The signed UI exposed the exact 14 ordered built-in domain rules and privacy explanation without visited browsing data.
- `ZC-029-007` is Fully implemented.
  The signed UI exposed Discord and Twitch contextual defaults, persisted explicit changes across relaunch, and restored both to Automatic.
- `ZC-025-005` is Partially implemented.
  Tests and a deterministic fixture prove ambiguity suppression transitions, but an installed-helper produce-cycle hook and visible prompt withdrawal and recovery proof are still missing.

## Cleanup and production isolation

The isolated QA process, LaunchAgent, app root, runtime root, and lease were removed.

The production app and helper remained running, and their executable hashes matched preflight values.
