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
| 1 | Standardize signed-QA app installation, LaunchAgent registration, and cleanup | verify | Lane A at `343310a` | Installed signed QA app and dedicated running helper are proven in `.audit/runs/signed-qa-runtime/343310a/REPORT.md`; full visible 12-step classification persistence remains the parallel acceptance check |
| 2 | Rebrand the complete product from Zoid Coach to Zoid 666 | active | Lane B | App bundle display names, visible UI, packaging, docs, scripts, tests, and installed artifact use Zoid 666 while durable identifiers and migrations remain compatible |
| 3 | Complete the canonical onboarding test-prompt loop | ready | Unowned | A user can generate a harmless prompt, receive it through notification or Today fallback, choose an action, see durable resolution, and resume setup after relaunch |
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
| 14 | Complete daily-plan task lifecycle | ready | Unowned | Start, pause, resume, complete, skip, defer, reorder, and revise all persist and reconcile with the underlying plan |
| 15 | Complete drift detection and compassionate recovery | ready | Unowned | Real activity drift produces a timely, non-shaming recovery choice whose result changes the plan durably |
| 16 | Complete meeting-aware planning and calendar boundaries | ready | Unowned | Calendar grant, denial, changes, overlap, cancellation, and offline states produce usable plans and repair paths |
| 17 | Complete app-classification management in Settings | ready | Unowned | User can search, classify, bulk-edit, reset, and verify runtime use of work, gaming, communication, and automatic categories |
| 18 | Complete Settings policy mutation conflict UX | ready | Unowned | Concurrent edits never silently overwrite; the user sees the winning state and can retry safely without duplicates |
| 19 | Complete background-agent lifecycle and Login Items repair | ready | Unowned | Install, enable, approval-required, update, crash recovery, disable, and uninstall are understandable and preserve data integrity |
| 20 | Complete privacy, export, deletion, and local-data controls | ready | Unowned | User can inspect stored-data classes, export supported data, delete safely, understand retention, and verify no silent cloud dependency |

## Pull Rules

An implementation lane takes the first `ready` item that does not overlap another lane's files or runtime lease.

If the top item is temporarily blocked, the lane records the blocker and immediately pulls the next independent item.

After a substantial batch, the orchestrator rotates the agent before assigning further work.

Every completed item adds its commit, tests, end-to-end evidence, and affected scenario IDs to this file before tracker integration.

## Delivered Batches Awaiting Parallel Verification

### Signed-QA persistent runtime - `343310a`

- Added identity-driven install and uninstall commands with no hardcoded bundle, executable, or LaunchAgent identity.
- Added a packaged-QA-only command that registers the dedicated SMAppService helper and deliberately leaves it enabled for visible end-to-end testing.
- Proved that the app is signed, installed outside `.build`, launched from the installed path, bound to an isolated QA root, and backed by the running QA Mach service.
- Focused `XPCSigningIdentityTests` and `AgentLaunchServiceTests` pass.
- The authoritative tracker remains owned by the root integrator and must only be upgraded after the parallel verifier completes classification persistence through the remaining onboarding steps.
