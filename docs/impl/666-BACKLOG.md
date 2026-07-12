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
| 5 | Finish Reminders permission grant, denial, repair, and recovery UX | ready | Unowned | Real or deterministic signed-QA flows prove grant, denial, System Settings repair, recheck, no prompt loop, and useful local fallback |
| 6 | Finish Screenwatch healthy, invalid, alternate-folder, denial, and repair UX | ready | Unowned | Signed-QA flows prove each state without exposing screenshot content and preserve the selected source through restart |
| 7 | Finish notification permission and Today fallback UX | ready | Unowned | Grant and denial both leave coaching actionable, repair is discoverable, and no prompt becomes inaccessible |
| 8 | Complete flexible work-window and quiet-hours onboarding | ready | Unowned | User can configure, validate, persist, edit, and observe both policies in runtime behavior after restart |
| 9 | Complete gaming-policy onboarding and runtime enforcement | ready | Unowned | Flexible and firm policies persist, affect planning and recovery behavior, remain non-punitive, and are editable |
| 10 | Finish rules-only mode and optional-AI boundary | ready | Unowned | The full daily workflow remains usable with AI disabled and clearly explains local behavior, privacy, and later opt-in |
| 11 | Complete first-plan preview, edit, install, and conflict recovery | ready | Unowned | User can inspect and alter the proposed plan, install atomically, recover from conflicts, and see identical Today state after restart |
| 12 | Complete Today source-health and repair actions | ready | Unowned | Every source card reflects current state and each action reaches a useful repair or inspection surface |
| 13 | Complete Today prompt inbox lifecycle | ready | Unowned | Pending, snoozed, answered, expired, and replayed prompts remain understandable and actionable across restart |
| 14 | Complete daily-plan task lifecycle | ready | Unowned after pause-and-switch batch `78ca9f9` | Start, pause, resume, complete, skip, defer, reorder, and revise all persist and reconcile with the underlying plan |
| 15 | Complete drift detection and compassionate recovery | ready | Unowned | Real activity drift produces a timely, non-shaming recovery choice whose result changes the plan durably |
| 16 | Complete meeting-aware planning and calendar boundaries | ready | Unowned | Calendar grant, denial, changes, overlap, cancellation, and offline states produce usable plans and repair paths |
| 17 | Complete app-classification management in Settings | verify | App-classification lane on `codex/app-classification-management` | User can search, classify, bulk-edit, reset, and verify runtime use of work, gaming, communication, and automatic categories |
| 18 | Complete Settings policy mutation conflict UX | verify | Settings conflict lane at `87f326f` | Concurrent edits never silently overwrite; the user sees the winning state and can retry safely without duplicates |
| 19 | Complete background-agent lifecycle and Login Items repair | ready | Unowned | Install, enable, approval-required, update, crash recovery, disable, and uninstall are understandable and preserve data integrity |
| 20 | Complete privacy, export, deletion, and local-data controls | verify | Lane C at `f4085ed` | User can inspect stored-data classes, export supported data, delete safely, understand retention, and verify no silent cloud dependency |
| 21 | Complete daily behavior review and correction | verify | Lane D at `7b96623` | User can review grouped activity sessions, correct or split classifications, attach work to a task, reject unsupported explanations, confirm the review, and see durable corrected totals after restart |

## Pull Rules

An implementation lane takes the first `ready` item that does not overlap another lane's files or runtime lease.

If the top item is temporarily blocked, the lane records the blocker and immediately pulls the next independent item.

After a substantial batch, the orchestrator rotates the agent before assigning further work.

Every completed item adds its commit, tests, end-to-end evidence, and affected scenario IDs to this file before tracker integration.

## Delivered Batches Awaiting Parallel Verification

### App-classification management - `codex/app-classification-management`

- Added a distinct Communication application rule that is persisted separately and explicitly counts as work at runtime.
- Preserved schema-5 and idempotency compatibility by omitting the new optional key when no Communication rules exist and decoding older policies with an empty list.
- Added search and All, Auto, Work, Communication, and Gaming filters with per-app editing.
- Added confirmation-backed bulk classification for the current filtered result and confirmation-backed reset of every explicit app rule.
- Added reviewed JSON import and atomic JSON export containing classification rules only.
- Import rejects blank, duplicate, conflicting, oversized, symbolic-link, wrong-type, malformed, and unsupported-schema inputs before changing the Settings draft.
- Imported, bulk-edited, and reset rules remain drafts until the existing conflict-safe Save Settings flow persists them.
- Focused four-worker tests passed for policy compatibility, draft mutation, runtime classification, and import/export safety.
- The serial full suite passed 476 tests after the repository-wide four-worker run exposed an existing Swift Testing parallel-runner hang and was terminated with a sampled idle stack preserved in worktree-local evidence.
- Release and 41 Python registry/evidence gates passed.
- Evidence is recorded in `.audit/runs/app-classification-management/candidate/REPORT.md`.
- A fresh verifier must complete the signed-QA import, bulk edit, save, relaunch, export, and reset journey before authoritative tracker statuses advance.

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
