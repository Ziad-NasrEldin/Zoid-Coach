# Zoid Coach Full-System Implementation Program

## Document purpose

This program defines how to move the current Zoid Coach app from 21 fully implemented end-user scenarios to a complete, independently verified product across the full 666-scenario tracker.

The authoritative acceptance source is `docs/zoid-coach-product-scenario-tracker.md`.

The program treats the 666 scenarios as one acceptance system rather than 666 unrelated tickets.

Many scenarios are alternate states, permission outcomes, failure paths, accessibility variants, or full-journey repetitions of the same underlying capability.

Implementation therefore proceeds through dependency-ordered vertical slices, with independent verification against every affected scenario.

## Current baseline

| Status | Count |
| --- | ---: |
| Fully implemented | 21 |
| Touches remaining | 120 |
| Frontend only left | 27 |
| Partially implemented | 156 |
| Barely started | 49 |
| Not implemented | 275 |
| Blocked from verification | 18 |
| Total | 666 |

The current source baseline is branch `codex/remove-atoll-integration` at `f519b2bd28ce`.

The current installed app is version 0.1.0 Build 8.

The repository currently passes 188 Swift tests and the release build.

The product already has meaningful domain, persistence, agent, Screenwatch, Reminders, planning, task, gaming-budget, notification, privacy, and settings primitives.

It does not yet have the complete user journeys required by the tracker.

## What “full implementation” means

Full implementation does not mean that a type, database table, service, or button exists.

A scenario is complete only when all applicable conditions below are proven against the exact integrated commit:

- The user can discover the entry point.
- Every required step is available through the UI.
- The copy and visible state are understandable.
- The action produces the correct result.
- The result persists or synchronizes as promised.
- Permission denial, failure, and recovery behavior are usable when the scenario requires them.
- Keyboard and accessibility behavior are complete when applicable.
- The installed QA or release build was exercised.
- Independent evidence exists for the exact commit and build.
- No material usability gap remains.

Builders may declare `Code complete, verification pending`.

Builders may never declare their own scenarios fully implemented.

Only an independent verifier may recommend moving a scenario to fully implemented.

Only the root integrator updates the authoritative tracker.

## First product decision gate

Before implementation, every scenario must receive a stable ID and a product disposition.

Recommended IDs use the section and item position, for example `ZC-016-004`.

IDs remain stable even if wording changes.

Each scenario receives one disposition:

- `Required now`
- `Required in a later release`
- `Negative invariant`
- `Deferred guardrail`
- `Superseded by a newer product decision`

This gate is essential because not every unchecked scenario should become a feature.

For example, `Keep calendar auto-scheduling outside the MVP` conflicts with the current autonomous Calendar direction.

That scenario needs an explicit superseded decision rather than implementation.

The no-team, no-public-dashboard, no-cloud-screenshot, no-mobile, and no-hard-blocking scenarios are negative product invariants.

Their completion means those capabilities remain absent or safely constrained.

## Critical dependency chain

```text
Canonical scope and stable scenario IDs
  -> isolated QA runtime and deterministic test seams
  -> complete planning and task execution
  -> truthful behavior sessions and user correction
  -> gaming accounting and drift detection
  -> coaching episode state machine
  -> daily review and correction
  -> weekly learning
  -> resilience, accessibility, localization, and performance
  -> installed multi-day release acceptance
```

The order is deliberate.

Coaching cannot be trustworthy until task state and observed behavior are truthful.

Reviews cannot be trustworthy until behavior corrections and prompt outcomes are durable.

Weekly insights cannot be accepted until daily facts are stable.

## Phase 0: Freeze the baseline and build the proof substrate

### Objectives

- Approve the remove-Atoll product baseline.
- Commit the scenario tracker and audit separately from feature work.
- Assign stable IDs and dispositions to all 666 scenarios.
- Create a machine-readable scenario manifest.
- Build a completely isolated QA runtime.
- Automate the 21 current regression scenarios.
- Refactor integration hotspots enough to permit safe parallel development.

### Scenario manifest

The machine-readable manifest should map each scenario to:

- Stable scenario ID
- Section and exact user-facing wording
- Product disposition
- Capability epic
- Dependencies
- Current audit status
- Delivery status
- Automated unit or contract tests
- Automated UI tests
- Supervised real-Mac tests
- Evidence directory
- Last verified commit
- Last verified build
- Verification timestamp

The user-facing audit status and delivery workflow status remain separate.

Delivery workflow statuses are:

```text
Backlog
Ready
In implementation
Code complete
Verification pending
Verification failed
E2E proven
Integrated
Release proven
```

`Code complete` never automatically becomes `Fully implemented`.

### Isolated QA runtime

The QA app must not share the production app’s identifiers or data.

It needs:

- A dedicated QA bundle identifier
- A dedicated Application Support directory
- A dedicated SQLite database
- A dedicated launchd label
- A dedicated Mach or XPC service identity
- Dedicated notification identifiers
- A dedicated Screenwatch fixture directory
- A dedicated Reminders list and Calendar for supervised EventKit testing
- A visible build and commit identity in the UI

Database, Screenwatch archive, app-support directory, agent service identity, notification namespace, and bundle identity must be configurable rather than hard-coded.

### Deterministic test seams

Add injectable boundaries for:

- Clock and local time zone
- Sleep and wake events
- Reminders source and writes
- Calendar source and writes
- Screenwatch records and freshness
- Notification authorization and delivery
- App inventory
- Network and AI providers
- Database location and failure injection
- Launch-at-login state

Test fixtures must represent:

- Granted, denied, restricted, and revoked permissions
- Healthy, missing, stale, malformed, and recovering Screenwatch streams
- Empty, overloaded, and realistic task days
- Partial and complete plans
- Active, paused, blocked, completed, and deleted tasks
- Gaming within budget, before unlock, beyond budget, and intentionally overridden
- Notification delivery, denial, duplication, interruption, and fallback
- Database lock, read-only, migration failure, and recovery
- Sleep, wake, restart, time-zone change, and backward clock movement

### UI testability

Add stable accessibility identifiers to every actionable control and meaningful visible state.

Add a signed QA build mode that can seed a named scenario fixture without touching production data.

Create an automated macOS UI-test target.

The UI harness must drive the installed QA application through visible user controls rather than calling domain services directly.

### Modularization prerequisite

Parallel development is unsafe while the main UI remains concentrated in a few files.

Current hotspots include:

- `DashboardView.swift`, approximately 1,702 lines
- `SettingsView.swift`, approximately 1,290 lines
- `AppModel.swift`, approximately 774 lines
- `AutonomousDatabaseMigrator.swift`, approximately 782 lines

Phase 0 should extract focused feature views, coordinators, and protocols without changing behavior.

`AppModel` should compose planning, execution, behavior, coaching, review, settings, and diagnostics coordinators.

The root integrator retains the small composition layer.

### Exit gate

- The baseline decisions and audit are committed.
- Every scenario has a stable ID and disposition.
- The QA app and QA agent cannot touch production data or identities.
- Existing tests and release builds pass.
- The current 21 completed scenarios have repeatable evidence.
- An independent verifier can rebuild, install, seed, run, restart, and capture evidence from one command.

No large feature wave starts before this gate passes.

## Phase 1: First-run trust and source setup

### Scope

Primary sections are 1 through 5.

Include related permission, privacy, repair, and source-health scenarios from sections 47 through 51.

### Vertical slices

1. First-launch explanation and resumable onboarding.
2. Reminders pre-permission explanation, denial, recovery, and manual fallback.
3. Screenwatch discovery, custom-folder selection, bookmark persistence, validation, and repair.
4. Notification explanation, denial, repair, and dashboard fallback.
5. Initial work schedule, privacy, coaching, classification, and gaming preferences.
6. Automatic refresh after returning from System Settings.

### Exit gate

A fresh user can install the app, understand its value and privacy boundary, grant or deny every permission, recover later, restart onboarding, and reach a useful dashboard even when Reminders, Screenwatch, or notifications are unavailable.

## Phase 2: Daily planning and complete task execution

### Scope

Primary sections are 6 through 23 and 37.

The phase culminates in the complete planning-to-completion journey in section 58.

### Vertical slices

1. Morning planning trigger, manual planning, snooze, skip, and later recovery.
2. Eligible Reminder inventory and manual local tasks.
3. Main objective, top-three selection, ordering, capacity warning, and approval.
4. Quick, custom, and unknown estimates.
5. Historical calibration with evidence and uncertainty.
6. One-active-task invariant and visible task state.
7. Open-ended work and bounded sprint modes.
8. Pause, resume, switch, block, defer, and done-for-now states.
9. Breaks and away-from-Mac work.
10. Completion, rescheduling, pending source sync, retry, and confirmed synchronization.
11. Menu-bar task status and controls.
12. Restart and sleep restoration for an active session.

### Exit gate

The installed QA app passes section 58 from planning through Apple Reminder completion, including restart, permission-loss, and source-write-failure variants.

This is the first complete daily productivity milestone.

## Phase 3: Truthful behavior and correction

### Scope

Primary sections are 24 through 28 and the ambiguous-work journey in section 61.

### Vertical slices

1. Sessionization and accurate behavior totals.
2. Classification provenance, confidence, and unknown states.
3. Task alignment, neutral activity, grace periods, and accepted breaks.
4. Ambiguous browser, communication, media, and system contexts.
5. Reclassify, split, merge, and task-attach corrections.
6. Immediate recalculation after correction.
7. Learned-rule preview, approval, undo, editing, deletion, import, export, and reset.
8. Clear handling of stale, partial, and missing telemetry.

### Exit gate

The user can inspect every displayed activity total, understand its evidence, correct a mistake, see totals and conclusions update immediately, and verify that future matching activity follows an explicitly approved rule.

## Phase 4: Gaming and coaching closed loop

### Scope

Primary sections are 29 through 39.

The phase culminates in the gaming-recovery and intentional-gaming journeys in sections 59 and 60.

### Vertical slices

1. Gaming policy modes, budgets, unlocks, rewards, debt, and manual adjustment.
2. First-week observation mode and baseline completion.
3. Drift detection with confidence and false-positive safeguards.
4. Prompt episode state machine.
5. Dashboard and notification delivery.
6. Start task, start sprint, return, snooze, break, intentional override, block, reschedule, and end-day actions.
7. Cooldown, escalation, de-escalation, quiet hours, and daily caps.
8. Global and temporary coaching pause.
9. Recovery detection and visible credit.
10. Evidence and explanation behind every intervention.

### Exit gate

Both complete gaming journeys pass in the installed QA app.

The recovery journey must prove:

```text
Gaming drift -> one prompt -> explicit response -> work recovery -> updated budget and history
```

The intentional journey must prove:

```text
Gaming drift -> intentional override -> bounded cooldown -> tracked gaming -> expiry -> voluntary return
```

No intervention may appear during protected breaks, quiet hours, observation mode, active cooldowns, or insufficient evidence.

## Phase 5: Daily review and adaptive learning

### Scope

Primary sections are 40 through 42 and the daily parts of section 63.

### Vertical slices

1. Scheduled, manual, next-launch, delayed, resumed, and skipped review entry.
2. Deterministic daily facts for planning, task work, behavior, gaming, and prompts.
3. Clear separation of facts, context, and hypotheses.
4. Behavior, offline-work, timing, task, and hypothesis corrections.
5. Recalculation after correction.
6. Estimate calibration and recommendation feedback.
7. Confirmed, unfinished, skipped, and reopened review state.
8. Safe learning proposals with evidence, approval, rejection, editing, and undo.

### Exit gate

The user can complete a day, review accurate facts, correct them, distinguish inference from fact, and see tomorrow’s planning improve without opaque autonomous changes.

## Phase 6: Weekly review

### Scope

Primary section is 43, plus the weekly and seven-day requirements in sections 63 and 64.

### Vertical slices

1. Minimum-evidence and data-quality gates.
2. Planned-versus-completed work and estimate accuracy.
3. Best work windows, drift triggers, gaming patterns, and prompt effectiveness.
4. Evidence-backed hypotheses with sample size, date range, examples, confidence, and alternatives.
5. One suggested weekly experiment.
6. Accept, edit, reject, track, and evaluate the experiment.
7. Partial-week and missing-data behavior.

### Exit gate

Both a deterministic synthetic seven-day run and a controlled real seven-day shadow run pass.

The weekly review must not invent certainty from incomplete days.

## Phase 7: Settings, privacy, resilience, accessibility, and polish

Settings for each capability should ship with that capability.

Phase 7 closes the remaining cross-cutting matrix in sections 44 through 57.

### Required areas

- Every preference persists and visibly changes behavior.
- Export preview, explicit destination, selective deletion, complete deletion, and retention work safely.
- AI evidence, provider, offline, budget, cache, and privacy controls are understandable.
- Database lock, read-only, migration failure, and recovery are visible and safe.
- Reminders, Screenwatch, notification, AI, and agent outages have usable fallbacks and repairs.
- Sleep, wake, restart, time-zone, and day-boundary behavior are correct.
- Quiet hours and scheduled triggers are reliable.
- Keyboard, VoiceOver, focus order, contrast, Reduce Motion, Dynamic Type, and large text pass complete journeys.
- Localization and long-text layouts remain usable.
- Responsiveness, resource use, storage growth, and perceived reliability meet targets.
- Diagnostic exports do not leak sensitive content.

### Exit gate

Every supported failure has a visible explanation, useful fallback, and repair action.

Accessibility and privacy are proven through complete user flows rather than isolated controls.

## Phase 8: Release acceptance

### Scope

Run sections 58 through 64 as integrated release journeys.

Preserve section 65 as negative invariants, deferred guardrails, and superseded decisions.

### Required installed-package journeys

- Planning to completion
- Gaming drift and recovery
- Intentional gaming
- Ambiguous work and correction
- Degraded mode
- Correction and learning
- Seven consecutive days
- Restart and sleep
- Denied and revoked permissions
- Screenwatch loss and recovery
- Notification loss and fallback
- Database migration and recovery
- Time-zone and day-boundary changes

### Exit gate

Every `Required now` scenario is independently E2E proven.

Every later-release scenario has an explicit disposition and remains unchecked until its release.

Every negative invariant is proven absent or safely constrained.

No unchecked scenario is represented as complete from code, tests, or screenshots alone.

## Multi-agent team model

The recommended topology uses the four available concurrency slots:

| Slot | Role | Responsibility |
| --- | --- | --- |
| 1 | Root integrator | Product decisions, dependency graph, locks, merges, tracker updates, and release gate |
| 2 | Builder A | One bounded vertical slice |
| 3 | Builder B | A non-overlapping vertical slice |
| 4 | Independent verifier | Adversarial verification of a previously completed slice |

Do not run three builders continuously.

Two builders plus one verifier produce better throughput because proof and integration stay current.

The verifier must never verify its own implementation.

Roles rotate between waves so no agent becomes the sole authority over a subsystem.

## Git branch and worktree protocol

After baseline approval, create the dedicated integration branch:

```text
codex/full-system
```

Every vertical slice receives a sibling branch and worktree from the exact current integration SHA.

Examples:

```text
codex/zc-onboarding-reminders
codex/zc-daily-planning-capacity
codex/zc-task-sprints
codex/zc-behavior-corrections
codex/zc-gaming-drift
codex/zc-daily-review
```

Rules:

1. No two agents work in the same worktree.
2. Every task prompt includes the absolute worktree path, branch, and baseline SHA.
3. Every agent verifies `pwd`, branch, baseline SHA, and clean status before editing.
4. Only the root writes or merges into `codex/full-system`.
5. A branch is never merged while its author is still editing it.
6. The author updates from the current integration branch before handoff.
7. The author resolves feature conflicts inside its worktree.
8. The root does not guess at feature semantics during conflict resolution.
9. Merge each vertical slice with a merge commit so it remains independently revertible.
10. Delete a feature worktree only after merge, post-merge tests, and evidence preservation.

## Shared-file ownership and locks

The root owns the following integration hotspots unless it grants a temporary exclusive lock:

- `Package.swift`
- `AppModel.swift`
- `ZoidCoachApp.swift`
- `DashboardView.swift`
- `SettingsView.swift`
- `AgentMain.swift`
- Migration registration and schema versioning
- Shared Sumi-Ink tokens
- Scenario tracker and manifest
- Packaging and installation scripts

Feature agents should add focused views, coordinators, services, stores, domain types, and test files.

The root performs the small final composition patch into navigation, `AppModel`, settings routing, or the agent loop.

When an agent genuinely needs a hotspot, the root grants a lock containing:

- File path
- Agent and branch
- Exact intended change
- Starting SHA
- Expected diff size
- Lock expiry at handoff

Only one lock may exist per file.

Database migrations are always serialized and append-only.

Existing migrations must never be reordered or rewritten.

## Subagent task size

Each builder task should cover one user-visible vertical slice, normally 5 to 20 scenarios.

Recommended change budget:

- At most 10 to 12 production files
- At most one migration
- Preferably under 800 changed production lines
- One to three intentional commits
- New focused test files rather than unrelated expansion

Split a slice when it exceeds the budget.

Never assign an agent `finish the backend`, `finish the frontend`, or multiple broad tracker sections.

Frontend and backend should be completed inside the same vertical slice so the user outcome remains coherent.

## Builder handoff contract

A builder handoff is incomplete without:

- Scenario IDs claimed
- Branch, worktree, baseline SHA, and final commit SHA
- Files changed
- Ownership locks used
- User journey before and after
- Dependencies and migration effects
- Focused tests
- Full test output
- Release build output
- Exact QA seed or fixture
- Exact E2E steps attempted
- Screenshots and accessibility snapshots
- Database assertions before and after
- Restart or recovery proof when relevant
- Known gaps
- Scenarios explicitly not claimed
- Diff statistics
- Rollback instructions

Evidence is stored under an immutable SHA-specific directory:

```text
.audit/runs/<slice>/<commit-sha>/
```

Never overwrite an older evidence run.

## Independent verifier contract

The verifier must:

1. Start from the claimed integrated commit.
2. Rebuild instead of reusing the builder’s binary.
3. Install the exact QA build it compiled.
4. Confirm visible version and commit identity.
5. Seed the declared fixture.
6. Reproduce the journey only through user-visible controls.
7. Verify persisted state independently.
8. Close and relaunch the app.
9. Restart the helper when persistence is part of the claim.
10. Exercise one adjacent failure or recovery path.
11. Confirm nearby regression scenarios.
12. Produce independent screenshots, accessibility snapshots, logs, and database assertions.
13. Recommend scenario status changes without editing the tracker.

The root then applies verified tracker changes.

## E2E verification architecture

Use four test levels.

### Level 1: Branch tests

- Focused deterministic unit tests
- Store and state-machine tests
- Full `swift test`
- Debug and release builds

### Level 2: Contract and integration tests

- Temporary SQLite database
- Fixture Reminders and Calendar adapters
- Fixture Screenwatch stream
- Fixture notification authorization and delivery
- Deterministic clock and sleep events
- Exact permission, failure, retry, and recovery states
- App and agent restart persistence

### Level 3: Isolated QA UI E2E

- Signed packaged QA app
- Dedicated bundle, data, XPC, launchd, notification, Screenwatch, and EventKit namespaces
- Automated UI controls through stable accessibility identifiers
- Assertions against visible state and accessibility values
- Screenshots at meaningful states
- Database assertions after UI actions
- Relaunch and helper restart checks

### Level 4: Supervised real-Mac boundary acceptance

Run these serially on a disposable macOS account or dedicated test Mac:

- Real TCC permission dialogs and revocation
- Real EventKit reads and writes in dedicated QA lists and calendars
- Real notification authorization and actions
- Real launch-at-login behavior
- Real sleep, wake, restart, and time-zone changes
- Real Screenwatch outage and recovery
- Real package signing and installation
- Real multi-day and seven-day shadow runs

Real-boundary acceptance is never parallelized.

Never mutate the user’s real Reminders or Calendar to prove E2E behavior.

## Evidence manifest

Every verification run produces a manifest containing:

- Scenario IDs
- Integrated commit SHA
- Installed build identity
- QA fixture version
- Test command and environment
- Start and end timestamps
- Visible actions performed
- Expected and actual results
- Screenshots
- Accessibility snapshots
- Database assertions
- Notification evidence
- Restart and recovery evidence
- Failures and blockers
- Verifier identity

The tracker is updated only from a passing manifest for the current integrated SHA.

Evidence from another branch, build, or commit is invalid.

## Merge cadence

- Merge one slice at a time.
- Run the full suite after every merge.
- Run a release build after changes to app composition, persistence, XPC, or the agent.
- Run the isolated QA smoke test after every merge.
- Run affected complete journeys after every second merge or at the end of a wave.
- Run package, signing, launchd, fresh-database migration, legacy migration, database integrity, and full acceptance at every wave boundary.
- Never accumulate many branches for a bulk merge.

If a merge breaks another slice, revert the merge commit and return it to the author.

Do not stack emergency semantic fixes directly on the integration branch.

## Permanent regression gates

The 21 scenarios currently checked must remain green after every wave.

The positive UI scenarios should become automated QA regression tests.

The six negative product invariants should become absence and release-review tests.

The permanent regression set includes:

- No repeated Reminders permission dialog after denial
- Visible Screenwatch health
- Manual planning access
- Completed tasks hidden from active work
- Clear Reminders refresh failure
- Visible source health
- Strong main-objective hierarchy
- Prominent active or recommended task
- Visible gaming budget
- Non-priority tasks available without dominating
- Exactly one recommendation
- One concise recommendation reason
- Preference for today’s selected tasks
- App opens to a usable Today view
- Eligible Reminders are reviewable
- No team monitoring
- No public web dashboard
- No cloud screenshot synchronization
- No mobile or cross-device behavior correlation
- No automatic multi-task Reminder decomposition
- No hard application or website blocking

## Anti-patterns to prohibit

- Multiple agents editing the same checkout
- Multiple agents testing against the same QA or production runtime identity
- Assigning one agent frontend and another backend for the same user flow
- Concurrent edits to `AppModel`, `DashboardView`, `SettingsView`, `AgentMain`, or migrations
- Letting builders edit the tracker
- Letting builders verify their own completion
- Treating unit tests as installed-product proof
- Running destructive tests against real user data
- Long-lived feature branches
- Bulk merges at the end of a wave
- Reusing screenshots or logs from another commit
- Large refactors disguised as prerequisite cleanup
- Treating explicitly deferred scenarios as feature work
- Accepting `works on my branch` after integration changes

## Recommended first execution wave

Do not begin with onboarding or gaming features immediately.

Begin with these four tasks:

1. Root integrator freezes and commits the baseline, adds stable scenario IDs and dispositions, and creates `codex/full-system`.
2. Builder A implements isolated QA runtime identities, paths, service names, and deterministic external-source adapters.
3. Builder B implements the scenario runner, accessibility identifiers, UI-test target, and evidence manifest format.
4. Independent verifier reproduces the 21 currently checked scenarios against the isolated QA runtime and downgrades any claim that cannot be repeated.

Only after this proof substrate is green should Phase 1 feature work begin.

## Recommended decision

Adopt this program and begin with Phase 0.

Do not try to maximize simultaneous coding agents.

Use two builders and one independent verifier, keep shared composition serialized, and let only integrated installed-product evidence move scenarios to fully implemented.
