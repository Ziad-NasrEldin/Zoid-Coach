# Phase 0 foundation independent verification

Baseline: `0091652ff15ca9e7f31e6428e4220f71d06348c9`.

Branch: `codex/zc-phase0-verifier`.

## Verdict

The foundation is reproducible but is not safe for full QA app or agent execution.

The two builders may continue source development and isolated unit testing on this foundation only if they treat the current QA runtime as unsafe to launch against real macOS services.

They must not run a packaged QA app, watch-mode QA agent, permission request, fixture-seeded outbox execution, or any QA flow that assumes XPC, EventKit, notifications, Keychain, UserDefaults, capture, or ServiceManagement are isolated.

Independent reverification is required after the critical containment findings are fixed.

## Reproducibility result

- The worktree started clean on the expected branch and commit.
- `swift test` passed 193 tests in 4 suites.
- The five focused RuntimeEnvironment tests passed.
- The seven Python scenario-registry tests passed.
- `python3 Scripts/scenario_registry.py validate` reported 666 scenarios with no tracker drift.
- `swift build -c release --quiet` exited 0.
- The installed package, signing identities, LaunchAgent, Mach service, Screenwatch freshness, Zoid ingestion, and heartbeat checks passed without changing their state.

## Registry result

The registry contains exactly 666 scenarios with 666 unique IDs across 65 numbered sections.

Its tracker SHA-256 exactly matches the authoritative tracker.

Disposition counts are 658 required now, 6 negative invariants, 1 superseded candidate, and 1 deferred guardrail.

Delivery counts add to 666 and align with the current tracker: 6 fully implemented, 120 touches remaining, 27 frontend only left, 156 partially implemented, 49 barely started, 275 not implemented, and 33 blocked from verification.

The registry correctly reflects the Phase 0 baseline downgrade from 21 checked scenarios to 6 checked negative invariants.

However, the custom validator is not a complete implementation of `docs/scenario-registry.schema.json`.

It accepted invalid top-level schema metadata, unverifiable commit and build claims, and an evidence line beyond the end of a real file.

All six checked scenarios declare installed-app, live-runtime, negative-invariant, and UI-automation proof requirements but have empty `evidence_paths` arrays.

Fifteen unchecked blocked scenarios retain the older Build 8 verification metadata after their downgrade.

These gaps prevent the registry from acting as a trustworthy automated release gate.

## Runtime isolation result

Production defaults remain correct for the database and Screenwatch paths tested by `RuntimeEnvironmentTests`.

The basic guard rejects a sibling-prefix escape, a direct outside path, a parent traversal, a relative QA root, and using filesystem root as a general escape container.

The guard does not resist an existing symlink directory below the QA root when the final file does not exist.

The verifier created only temporary directories, placed `run/link` as a symlink to a temporary `outside` directory, passed `run/link/escaped.sqlite` as the QA database, and successfully wrote `outside/escaped.sqlite` through the accepted runtime URL.

No production path was used in that proof.

The guard also accepts a QA root that aliases a production Library location and accepts the production UserDefaults suite name.

Containment is therefore relative to a caller-selected root, not separation from production.

## Runtime consumer result

Only the AppModel database readers and Screenwatch reader consume the app runtime environment.

App Settings, App inventory, capture configuration, voice Keychain, voice UserDefaults, AgentLaunchService, notifications, and XPC still instantiate production defaults.

The app's QA model therefore still sends XPC requests to `com.ziadnasreldin.ZoidCoach.agent` and can reach the production agent.

The agent consumes the isolated database and Screenwatch paths, but native capture configuration and native capture output remain production-derived.

The QA agent still constructs real EventKit task and calendar sources and real notification actions.

Its QA argument parser also accepts permission request and watch behavior without a fail-closed QA policy.

The declared `userDefaultsSuiteName`, `keychainServiceSuffix`, and `exportRoot` are not consumed anywhere outside `RuntimeEnvironment.swift`.

This makes the current runtime environment a partial path configuration object, not a complete safety boundary.

## Findings

### Critical

1. A parent-directory symlink can escape the QA root and write outside it.
2. QA permits protected production roots and production identity domains.
3. Sensitive app consumers bypass RuntimeEnvironment and remain connected to production state.
4. The QA agent still uses production EventKit, notifications, capture configuration, and control surfaces.

### High

1. Registry validation does not enforce the committed schema or evidence referential integrity.
2. The six checked scenarios have no machine-linked evidence despite requiring four proof classes.

### Medium

1. Fifteen downgraded scenarios retain historical verification metadata that can be mistaken for current proof.

## Builder decision

Builders may safely compile, add protocols, wire dependency injection, create deterministic fixtures, and run pure unit or temporary-directory integration tests.

Builders may not safely exercise the current full QA app or agent.

The containment guard, unique QA XPC service, fixture-only OS adapters, runtime propagation to every consumer, and evidence validator must be completed before any claim that QA is isolated.

No production data, Reminders, Calendar, TCC state, service registration, or service lifecycle was mutated during this audit.
