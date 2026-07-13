# Zoid 666 Durable Implementation Backlog

This is the independently grabbable work queue for finishing all 666 end-user scenarios.

The authoritative scenario status remains `docs/zoid-coach-product-scenario-tracker.md` and `docs/scenario-registry.json`.

## Status Vocabulary

- `ready` means independently grabbable now.
- `active` means owned by one implementation lane.
- `verify` means implementation is complete and parallel proof is running.
- `done` means integrated, proven end to end, and reflected in the tracker and registry.
- `blocked` means an external dependency prevents meaningful progress and the blocker is documented.

## Next 20 Executable Slices

| Priority | Slice | Status | Owner | Acceptance proof |
| --- | --- | --- | --- | --- |
| 1 | Standardize signed-QA app installation, LaunchAgent registration, and cleanup | done | Repeat-install verifier at `c8ea825` | First install, same-path replacement, changed-path replacement, uninstall/reinstall, final cleanup, exact helper ownership, and production isolation passed in `.audit/runs/signed-qa-repeat-install/10cc1da/REPORT.md` |
| 2 | Rebrand the complete product from Zoid Coach to Zoid 666 | active | Lane B | App bundle display names, visible UI, packaging, docs, scripts, tests, and installed artifact use Zoid 666 while durable identifiers and migrations remain compatible |
| 3 | Complete the canonical onboarding test-prompt loop | done | Canonical verifier at `0920a29` before final rebase | Agent-owned idempotent creation, notification delivery and action resolution, denied Today fallback, dashboard response, exact-step Resume Setup, and relaunch durability passed in `.audit/runs/onboarding-test-prompt/signed-acceptance/REPORT.md` |
| 4 | Prove all 12 onboarding steps in one fresh signed-QA journey | ready | Unowned | One evidence run completes every step, persists app classifications and preferences through XPC, creates the first plan, reaches Today, and survives restart |
| 5 | Finish Reminders permission grant, denial, repair, and recovery UX | verify | Reminders outage continuity candidate at `8a49afb` | `ZC-051-001` and `ZC-051-004`; Today explains preserved plan, estimates, active tracking and local history, with direct local-task and repair actions plus focused continuity proof in `.audit/runs/reminders-outage-continuity/candidate/REPORT.md` |
| 6 | Finish Screenwatch healthy, invalid, alternate-folder, denial, and repair UX | verify | Screenwatch recovery candidate at `1fde15e` | Signed-QA flows prove each state without exposing screenshot content and preserve the selected source through restart |
| 7 | Finish notification permission and Today fallback UX | ready | Unowned after verifier `9a13467` | `ZC-004-002`, `ZC-004-004`, `ZC-050-002`, `ZC-050-005`, and `ZC-050-007`; denied fallback, repair, replacement, and exactly-once response seams pass, while real Notification Center and the signed repaired response journey remain |
| 8 | Complete flexible work-window and quiet-hours onboarding | ready | Unowned | User can configure, validate, persist, edit, and observe both policies in runtime behavior after restart |
| 9 | Complete gaming-policy onboarding and runtime enforcement | ready | Unowned | Flexible and firm policies persist, affect planning and recovery behavior, remain non-punitive, and are editable |
| 10 | Finish rules-only mode and optional-AI boundary | active | Rules-only factual review lane `codex/prompt-cap-observability` | `ZC-041-015` and `ZC-046-001`; owned files are Daily Review local-only boundary/state, focused tests, candidate evidence, and isolated claim/handoff rows |
| 11 | Complete first-plan preview, edit, install, and conflict recovery | verify | Plan preview metrics candidate at `47033ac` | `ZC-008-005` and `ZC-008-006`; exact focused-work and planned-buffer metrics, overload state, accessibility identifiers, and focused state proof are recorded in `.audit/runs/plan-preview-metrics/candidate/REPORT.md` |
| 12 | Complete Today source-health and repair actions | verify | Source repair guidance candidate at `246f44b` | `ZC-048-008` and `ZC-048-009`; every unhealthy source names its exact safe impact and direct repair action with focused proof in `.audit/runs/source-repair-guidance/candidate/REPORT.md` |
| 13 | Complete Today prompt inbox lifecycle | verify | Prompt action feedback candidate at `8307a77` | `ZC-038-005` and `ZC-038-006`; selected-row progress, Today duplicate controls, and prompt-store token idempotency proof are recorded in `.audit/runs/prompt-action-feedback/candidate/REPORT.md` |
| 14 | Complete daily-plan task lifecycle | verify | Local reschedule confirmation candidate at `a069230` | `ZC-020-008` and `ZC-034-010`; future-date review, cancellation, local-day normalization, stale-plan refusal, Apple due-date boundary, durable plan mutation, and focused proof are recorded in `.audit/runs/task-reschedule-date/candidate/REPORT.md` |
| 15 | Complete drift detection and compassionate recovery | ready | Unowned | Real activity drift produces a timely, non-shaming recovery choice whose result changes the plan durably |
| 16 | Complete meeting-aware planning and calendar boundaries | ready | Unowned | Calendar grant, denial, changes, overlap, cancellation, and offline states produce usable plans and repair paths |
| 17 | Complete app-classification management in Settings | verify | Learned-rule reset candidate at `c62aa88` | `ZC-045-015`; reviewed destructive reset, active count, append-only tombstones, restart persistence, historical-correction preservation, and focused proof are recorded in `.audit/runs/learned-rule-reset/candidate/REPORT.md` |
| 18 | Complete Settings policy mutation conflict UX | verify | Settings conflict lane at `87f326f` | Concurrent edits never silently overwrite; the user sees the winning state and can retry safely without duplicates |
| 19 | Complete background-agent lifecycle and Login Items repair | verify | Agent lifecycle candidate at `57a7f54` | `ZC-048-007` through `ZC-048-009` and `ZC-057-008`: live heartbeat, impact, Login Items repair, force-restart, disable continuity, and read-only proof passed in `.audit/runs/agent-lifecycle-recovery/57a7f54/REPORT.md` |
| 20 | Complete privacy, export, deletion, and local-data controls | verify | Lane C at `f4085ed` | User can inspect stored-data classes, export supported data, delete safely, understand retention, and verify no silent cloud dependency |
| 21 | Complete daily behavior review and correction | verify | Lane D at `7b96623` | User can review grouped activity sessions, correct or split classifications, attach work to a task, reject unsupported explanations, confirm the review, and see durable corrected totals after restart |
| 22 | Complete away-from-Mac work recording and correction | verify | Offline-work lane at `55fcca3` | Reviews supports add, edit, delete, restart-safe persistence, actual-time inclusion, explicit separation from Screenwatch coverage, and honest missing-telemetry copy; active-task entry remains a separate follow-up |
| 23 | Complete morning-planning invitation and limited-unplanned controls | verify | Morning-planning lane at `27ad4f3` | Manual planning, snooze and return, temporary dismissal, explicit unplanned mode, direct unplanned task start, drift gating, restart recovery, full suites, release, and signed candidate UI inspection are recorded in `.audit/runs/morning-planning/27ad4f34c23d4a77e36ae3f065e9c70cda7f6f4d/REPORT.md`; isolated installed-helper mutation proof remains |
| 24 | Complete evidence-gated weekly review and next-week experiment | done | Weekly-review verifier at `b98464e` | Signed QA proved limited and sufficient evidence states, corrected factual patterns, expandable dated evidence, exactly one editable experiment, accept and reject actions, and restart-safe next-week tracking; final proof is recorded in `.audit/runs/weekly-review/verifier/REPORT.md` |

## Pull Rules

An implementation lane takes the first `ready` item that does not overlap another lane's files or runtime lease.

If the top item is temporarily blocked, the lane records the blocker and immediately pulls the next independent item.

After a substantial batch, the orchestrator rotates the agent before assigning further work.

Every completed item adds its commit, tests, end-to-end evidence, and affected scenario IDs to this file before tracker integration.

## Delivered Batches Awaiting Parallel Verification

### Intentional override duration policy - candidate

- Owns `ZC-029-013`, `ZC-036-003`, and `ZC-036-008`.
- Owns only the GamingPolicy field and validation, Gaming Allowance Settings controls and conflicts, gaming-drift override timing, focused tests, and candidate evidence.
- Today task eligibility, root, runtime, tracker, registry, and Lavish remain outside this lane.
- The persisted duration now replaces the prior fixed 45-minute suppression while preserving 45 minutes for legacy policy decoding.
- Focused Settings conflict/round-trip and gaming-drift restart/expiry tests pass.
- Evidence is recorded in `.audit/runs/intentional-override-policy/candidate/REPORT.md`.

### Notification permission and Today fallback recovery - `0d6ec2d`

- Adds automatic authorization recheck after returning from System Settings without repeating the permission request.
- Keeps denied copy explicit that every unresolved coaching choice remains available in Today.
- Replaces pending and delivered notifications using the stable prompt request identifier instead of stacking obsolete content.
- Prevents interrupted or repeated notification response processing from invoking the response effect twice.
- Adds one deterministic denial, Today fallback, repair, repeated delivery, single notification, response, replay, and exactly-once effect journey.
- Focused health, coordinator, and end-to-end recovery tests pass.
- Evidence is recorded in `.audit/runs/notification-permission-recovery/0d6ec2d/REPORT.md`.
- A fresh verifier owns signed-QA traversal, tracker and registry integration, and Lavish refresh.

### Intentional gaming override - candidate

- Owns `ZC-036-001`, `ZC-036-002`, `ZC-036-003`, `ZC-036-007`, and `ZC-036-008`.
- Owns only `GamingDriftPromptService.swift`, its focused tests, candidate evidence, and this backlog entry.
- Notification permission, notification repair, Today fallback, tracker, registry, Lavish, runtime, and root remain outside this lane.
- Continue intentionally now creates a restart-safe response-derived override for the configured coaching cooldown.
- A work observation ends the override early, while expiry permits a new eligible decision for the same continuing gaming session.
- Focused `GamingDriftPromptServiceTests` pass and candidate evidence is recorded in `.audit/runs/intentional-gaming-override/candidate/REPORT.md`.

### Background-agent lifecycle and Login Items repair - `57a7f54`

- Distinguishes an enabled ServiceManagement registration from a fresh canonical runtime heartbeat.
- Shows missing, stale, and running helper states with direct repair and honest local-data impact.
- Forced repair unregisters and registers an enabled-but-stale installed helper instead of returning the unchanged registration state.
- The visible lifecycle window refreshes every five seconds while open and retains the exact manual Login Items path.
- Heartbeat inspection is read-only, never creates a missing database, never migrates, and caps lock waiting at 250 milliseconds.
- Focused service and controller tests pass, including a filesystem-backed canonical-checkpoint fixture.
- Evidence is recorded in `.audit/runs/agent-lifecycle-recovery/57a7f54/REPORT.md`.
- A fresh verifier owns signed-QA lifecycle traversal, bounded resource sampling, tracker and registry integration, and Lavish refresh.

### Screenwatch recovery and source management - `1fde15e`

- Added a complete Screenwatch Connection card to Settings so recovery is available after onboarding rather than trapped in first-run setup.
- Shows privacy-safe healthy, stale, waiting, incompatible-format, expired-access, unavailable, and unsafe-folder states with direct next-step guidance.
- Lets the user recheck, select a direct alternate days folder, renew a moved or expired folder, and return to the expected location.
- Foreground activation rechecks the selected source without opening or reading captured titles, URLs, screenshots, or file locations into the UI.
- Failed folder selection preserves the last confirmed source state and exposes only redacted actionable copy.
- Deferred screenshot-analysis policy remains outside this batch as `ZC-003-009`.
- Three focused connection-controller tests and the complete focused Screenwatch setup suite pass.
- Evidence and exact signed-QA verifier instructions are recorded in `.audit/runs/screenwatch-recovery-ux/candidate/REPORT.md`.

### Evidence-gated weekly review and next-week experiment - candidate

- Added a stable previous-calendar-week review window so the review and its experiment identity do not shift every day.
- Requires at least three confirmed days with at least 30 minutes of observed coverage before showing conclusions or proposing an experiment.
- Added planned-versus-completed outcomes plus corrected estimate, work-window, drift, gaming, prompt, and blocked-task evidence where the local database supports each pattern.
- Every pattern shows its sample size, date range, privacy-safe examples, confidence, and an alternative explanation.
- Added exactly one proposed experiment per review week with explicit edit, accept, reject, and restart-safe next-week tracking states.
- Added migration 31 without changing daily review, task pause, offline work, or historical behavior records.
- Five focused weekly-review tests and the focused migrator suite pass.
- Full-suite, release, and signed-QA click-through are pending the root-owned runtime lease and fresh parallel verifier.
- Evidence is recorded in `.audit/runs/weekly-review/candidate/REPORT.md`.
- A separate scheduler lane still owns `ZC-054-005` because truthful weekly reminder delivery requires the serialized background-agent composition seam.

### Planning capacity warning and direct reduction - `codex/capacity-warning-flow`

- Implements `ZC-009-001` through `ZC-009-008` as one complete Today planning flow.
- Shows planned minutes, Calendar-adjusted available minutes, exact overage, and honest Calendar-unavailable fallback copy.
- Suggests the lowest-ranked task by name and lets the user remove it directly from the warning.
- Recalculates immediately after estimate, add, remove, and direct-reduction changes.
- Prevents Calendar acceptance until all estimates exist and the revised plan fits capacity.
- Merges overlapping external Calendar commitments, clips them to configured work intervals, ignores Zoid-owned blocks, and respects visible-calendar policy.
- Five focused capacity tests and affected source-health and QA Calendar composition tests pass.
- Evidence is recorded in `.audit/runs/planning-capacity/capacity-warning/REPORT.md`.
- A fresh verifier must complete the signed-QA overload, reduction, recalculation, realistic approval, and restart-safe click-through before tracker integration.

### Away-from-Mac work recording and correction - `55fcca3`

- Added a dedicated Reviews flow for intentional away-from-Mac work with start time, bounded duration, optional task attachment, and optional note.
- Added migration 30 and restart-safe create, correction, and scoped deletion without rewriting Screenwatch observations.
- Added separate Actual Time, Screenwatch-observed, and Away From Mac totals so intentional offline work never disguises missing telemetry.
- Reopens a confirmed review after every offline-work mutation so changed totals cannot silently influence learning.
- Added focused migration, persistence, idempotency, validation, correction, deletion, and review-reopening tests.
- All 469 Swift tests, 41 registry and evidence tests, the release build, and a clean signed-QA package passed.
- Evidence is recorded in `.audit/runs/offline-work/55fcca39050d1ce92f9a712d7421421e763fe441/REPORT.md`.
- A fresh verifier must complete the signed-QA Reviews click-through before the authoritative tracker advances.
- Active-task entry scenarios `ZC-022-001` and `ZC-022-002` remain ready because this batch deliberately avoided the concurrently owned task-lifecycle surface.

### Morning-planning invitation and limited-unplanned controls - `27ad4f3`

- Added a low-pressure Today invitation with Plan Now, Work Unplanned, snooze, and temporary-dismiss recovery.
- Added durable response-derived planning state without a new migration or overlap with the active review and classification lanes.
- Added hidden deferred prompts, one-time due delivery, plan-created cancellation, restart-safe unplanned mode, and an explicit drift-intervention gate.
- Added direct Start Without Planning controls that preserve an empty plan while making the selected Reminder the durable active task.
- Focused planning and notification tests passed.
- All 473 Swift tests, the release build, 41 Python evidence tests, and signed-QA packaging passed.
- The signed app visibly exposed the complete banner, copy, task inventory, and controls with stable accessibility identifiers.
- The final installed-helper mutation click-through remains assigned to a fresh verifier because another concurrent lane owned the single QA Mach-service registration.
- Evidence is recorded in `.audit/runs/morning-planning/27ad4f34c23d4a77e36ae3f065e9c70cda7f6f4d/REPORT.md`.

### Settings policy mutation conflict UX - `87f326f`

- Added field-level three-way merging for every Settings policy control so independent edits survive while concurrent winning values remain authoritative.
- Added a global Sumi-Ink conflict panel that identifies the winning policy version, changed groups, and overlapping groups.
- Added explicit `KEEP CURRENT VALUES` and `REAPPLY MY CHANGES` actions with stable accessibility identifiers.
- Reapply uses the refreshed policy version and repeats the conflict decision if another writer wins before the retry.
- Extracted the Settings controller from the monolithic view so the mutation state machine and its UI can be verified independently.
- Added focused proof for disjoint merging, overlapping winner preservation, deliberate reapply, repeated races, and duplicate-free policy history.
- All 462 Swift tests, the release build, 41 Python registry and evidence tests, and a clean signed-QA package passed.
- Evidence is recorded in `.audit/runs/settings-policy-conflict/87f326f4ba78ef2e9ba08b0f4c6e3eb77f7cca01/REPORT.md`.
- A fresh parallel verifier must complete the visible signed-QA two-writer click-through before the authoritative tracker advances.

### Task pause and switch lifecycle - `78ca9f9`

- Added visible reasoned pause controls to the primary Today focus card and detailed task rows.
- Added explicit switch confirmation, atomic previous-task pausing, durable switch reasons, preserved elapsed time, and global command serialization.
- Added restart-safe pause-event history, visible tracked time and last-pause context, recoverable failure copy, and explicit completion of a paused task.
- Added migration 29 and four focused store and agent journey tests.
- All 460 Swift tests, the release build, 41 Python evidence tests, and clean signed-QA packaging passed.
- Evidence is recorded in `.audit/runs/task-lifecycle/78ca9f9/REPORT.md`.
- The broader daily-plan lifecycle item remains ready because skip, defer, reorder, revise, completed history, and source-sync confirmation remain separate work.
- The authoritative tracker remains owned by the root integrator and must only advance after the parallel verifier completes the signed-QA UI click-through.

### Daily behavior review and correction - `7b96623`

- Added the first real Reviews navigation surface with local, privacy-safe grouped activity sessions and corrected category totals.
- Added whole-session and midpoint split corrections, optional task attachment, durable restart-safe overrides, and correction-aware totals.
- Added explicit accept and reject controls for causal hypotheses, review confirmation, and automatic reopening when a confirmed review changes.
- Added empty, loading, retry, storage failure, confirmation, and privacy explanation states with stable accessibility identifiers.
- Added migration 28 without rewriting behavior evidence and added five focused sessionization, correction, split, persistence, hypothesis, confirmation, and migration tests.
- All 455 Swift tests, the release build, 41 Python evidence tests, and signed QA packaging passed.
- Evidence is recorded in `.audit/runs/daily-review/7b96623/REPORT.md`.
- The visible signed-QA click-through remains assigned to the parallel verifier because the Mac was locked during the implementation lane's acceptance attempt.

### Canonical onboarding test-prompt loop - Lane D

- Added one agent-owned, idempotent `ONBOARDING_TEST` prompt per setup flow.
- Added the same harmless Continue Setup and Use Today actions to notification, onboarding, and Today surfaces.
- Added notification-denial fallback without bypassing the required prompt resolution.
- Persisted the local test task and restored the canonical prompt after restart.
- Added a visible Resume Setup strip and foreground prompt reconciliation.
- Focused service, category, restart, and gating tests pass.
- Release build proof is recorded in `.audit/runs/onboarding-test-prompt/canonical-loop/REPORT.md`.
- Independent installed-product notification, Today fallback, Resume Setup, and relaunch acceptance passed in `.audit/runs/onboarding-test-prompt/signed-acceptance/REPORT.md`.

### Signed-QA repeat-install lifecycle - `10cc1da`

- Reconciles the dedicated QA SMAppService registration before every app replacement instead of treating stale `enabled` state as proof that the replacement helper owns the registration.
- Stages and verifies the replacement app before mutation, swaps it atomically, restores the prior app on registration failure, and recovers a prior interrupted replacement on the next run.
- Adds an explicit packaged-QA unregister command so uninstall and repeat install operate through the owning app while preserving the production registration.
- Covers first install, repeat install, stale enabled state, replacement helper path changes, interrupted registration and replacement recovery, and uninstall/reinstall with deterministic tests.
- Signed runtime proof passed twice in place, passed uninstall/reinstall, and preserved the running production helper.
- Evidence is recorded in `.audit/runs/signed-qa-repeat-install/10cc1da/REPORT.md`.
- Independent integration verification passed at `c8ea825` after correcting shell quoting for repository paths containing spaces.
- The full suite passed with 450 Swift tests and 41 registry/evidence tests.
- A fresh signed runtime pass proved first install, same-path repeat install, changed-path re-registration, uninstall/reinstall, final cleanup, and an untouched running production helper.

### Privacy, export, deletion, and retention controls - `73c77ec`

- Added a visible local-data inventory with privacy-safe counts for every stored-data class.
- Added reviewed redacted export with an explicit native macOS destination chooser.
- Added exact-session, one-day, inclusive-range, targeted-category, and delete-all controls with scoped confirmations.
- Added independent retention policies and background enforcement for behavior records, task sessions, prompts, reviews and learning, screenshots, extracted text, and diagnostics.
- Preserved unresolved prompts, source-owned screenshots, Keychain credentials, and the migrated restart-safe schema.
- Focused privacy, DST-boundary, exact-session, and retention tests pass.
- Full-suite and release-build proof are recorded in `.audit/runs/privacy-data/73c77ec/REPORT.md`.
- Independent integration fixed canonical-plan leakage from date-range deletion and recorded proof in `.audit/runs/privacy-data/f4085ed/REPORT.md`.
- The Records chapter still requires a destructive signed-QA UI pass before the remaining tracker rows become fully implemented.

### Signed-QA persistent runtime - `343310a`

- Added identity-driven install and uninstall commands with no hardcoded bundle, executable, or LaunchAgent identity.
- Added a packaged-QA-only command that registers the dedicated SMAppService helper and deliberately leaves it enabled for visible end-to-end testing.
- Proved that the app is signed, installed outside `.build`, launched from the installed path, bound to an isolated QA root, and backed by the running QA Mach service.
- Focused `XPCSigningIdentityTests` and `AgentLaunchServiceTests` pass.
- The authoritative tracker remains owned by the root integrator and must only be upgraded after the parallel verifier completes classification persistence through the remaining onboarding steps.
