# ZC-002-008 Evidence Requalification

## Verdict

The existing signed installed-app, accessibility, and XPC lifecycle proof is requalified for `ZC-002-008` at signed commit `b9d3f458809c75f5f1b79467cce0f161f462c391`.
The current canonical commit `ed5d07a363e0f64049c07b0e1d309d754caa035b` retains the same scenario behavior through byte-identical primary UI, controller, verifier, and focused test blobs plus stable later patches covered by current focused tests.
This report and its companion manifest only package evidence.
They do not edit the tracker or registry, mark the scenario Fully implemented, or replace the root integrator's status decision.

## Canonical binding

- Scenario: `ZC-002-008`, use manual local planning while Reminders access is unavailable.
- Current canonical commit: `ed5d07a363e0f64049c07b0e1d309d754caa035b`.
- Current tracker SHA-256: `cc6987a31ed83048ad1cb2bce042739ff119824e9310c9367c6a70bc6af2499b`.
- Current registry SHA-256: `a01686098a07e33f5280177149348bc92ac6065e68831b0d8dbb99dd5ef307b4`.
- Current registry validation: `Validated 666 scenarios with no tracker drift`.
- Current tracker and registry status: `Touches remaining` / `touches_remaining`.
- Current tracker and registry criterion: the installed UI and signed lifecycle are already accepted, and the only stated strict qualification gap is the missing immutable scenario-bound evidence manifest.

## Original signed proof

The original report is `.audit/runs/manual-local-task/eb0866b/REPORT.md` with SHA-256 `44b38cc04e8289258bed8fc9456ca68aee3f40d198d29f2748610c65f4796130`.
The original report records implementation commits `eac9441` and `eb0866b`, signed probe commit `0a23b80`, and final accessibility package commit `b9d3f45`.
The final signed package identity is deterministically `zoid-coach-b9d3f458809c75f5f1b79467cce0f161f462c391-clean` because the package script rejects dirty QA packages and the signed report records the rebuilt package at `b9d3f45`.
The signed installed app showed Reminders as Not Connected while keeping New Local Task available.
It kept Create Local Task disabled for an empty title, enabled it after entry, closed the sheet after saving, and immediately showed the new task as Today's main objective and in capacity calculations.
Its accessibility pass exposed distinct `local-task-title`, `local-task-notes`, `local-task-estimate`, `local-task-add-to-today`, and `local-task-save` controls.
The authenticated XPC lifecycle created the local task, replayed the exact command idempotently, restarted the agent, started and completed the task, restarted again, retained completion history, and produced zero Apple Reminders outbox mutation.

## Blob identity and stable-patch equivalence

The signed reference is `b9d3f458809c75f5f1b79467cce0f161f462c391` and the current canonical reference is `ed5d07a363e0f64049c07b0e1d309d754caa035b`.

| File | Signed blob | Current blob | Qualification |
| --- | --- | --- | --- |
| `Sources/ZoidCoachApp/LocalTaskCreationController.swift` | `935628f64dee1e1bf88b3b28dce30e274ea150fd` | `935628f64dee1e1bf88b3b28dce30e274ea150fd` | Byte-identical |
| `Sources/ZoidCoachApp/Views/LocalTaskCreationView.swift` | `fe72fe42b541537c2173cf38b004e500797f3d5c` | `fe72fe42b541537c2173cf38b004e500797f3d5c` | Byte-identical |
| `Sources/ZoidCoachApp/Views/DashboardView.swift` | `ef147848b4cef4705f9e6404dd19913aca24eb88` | `99e92ff5f892d46bcd44551952046602eb5f5aab` | Stable later patch |
| `Sources/ZoidCoachCore/AgentMutationCommand.swift` | `c860337982a971375c8d278bea8cf8f1cc654365` | `4cf52afb2b55a074244db295169f48a9d6b96f79` | Stable later patch |
| `Sources/ZoidCoachInfrastructure/AgentMutationRouter.swift` | `b9bff378a9e37dd3daf6e9b0ddf3d32f8111761e` | `2c85cbb0b6ad4fee51e29e0cad1490f807a30ad4` | Stable later patch |
| `Sources/ZoidCoachInfrastructure/AgentOwnedStateStore.swift` | `e20e1a75560bee43eb5e46805d15901e7faacb5e` | `4786e3e6034637751aed3477d601c1e3c6fc0d90` | Stable later patch |
| `Sources/ZoidCoachInfrastructure/ReminderSnapshotStore.swift` | `4466863170ac614265c536eb5085759816ea03ea` | `bf3793dfbce399f430b666094b0a9dfceb09cbc6` | Stable later patch |
| `Sources/ZoidCoachInfrastructure/TodayDashboardAgent.swift` | `51ded9e98cc6421195e31bdbcc2f5940d969c872` | `8f80512c1d6cdc60237908f1817f28744396a319` | Stable later patch |
| `Tests/ZoidCoachAppTests/LocalTaskCreationControllerTests.swift` | `05a473e7f495b081253bca3f0134e7a1826c07d1` | `05a473e7f495b081253bca3f0134e7a1826c07d1` | Byte-identical |
| `Tests/ZoidCoachAppTests/SourceSnapshotStoreTests.swift` | `a3838c778511ffea88699fb3066500e446ea50ed` | `a3838c778511ffea88699fb3066500e446ea50ed` | Byte-identical |
| `Tests/ZoidCoachAppTests/TodayDashboardAgentTests.swift` | `f44e7a10b1cc667448da1d69a420edac306ed0b3` | `d7bc846cb105c8a126cb571f15bdf01064d94681` | Stable later patch with byte-identical scenario test body |
| `Scripts/verify-qa-manual-local-task-xpc.sh` | `c86ff1f4ea8432e37b977af08e37741e30cf02ad` | `c86ff1f4ea8432e37b977af08e37741e30cf02ad` | Byte-identical |

The current SHA-256 values are recorded in `evidence.json`.
The `DashboardView` drift adds later product surfaces, including an additional local-task shortcut during a Reminders outage, while the scenario's creation sheet remains in the byte-identical `LocalTaskCreationView`.
The `AgentMutationCommand` drift adds unrelated command cases while preserving the `createLocalTask` case.
The `AgentMutationRouter`, `AgentOwnedStateStore`, and `ReminderSnapshotStore` diffs preserve their local-task branches and add later routing, validation, scheduling, and Reminder behavior.
The `TodayDashboardAgent` drift strengthens task mutation durability and still explicitly bypasses the Apple Reminders outbox for `.local` tasks.
The exact `completingLocalTaskStaysLocalRecordsHistoryAndSurvivesRestart` test body has the same SHA-256 at signed and current commits: `5752ca9180ca04c19d8609c79bac49421aea19edf6bb7b5cfce18124a6109f1d`.
The current focused tests exercise creation, retry identity, durable plan insertion, local-only completion, restart recovery, completion history, and zero external Reminder mutation across the stable patches.

## Current canonical checks

All checks ran from a clean isolated worktree at exact commit `ed5d07a363e0f64049c07b0e1d309d754caa035b`.

- `swift test --filter agentOwnedLocalTaskCreationIsIdempotentDurableAndPartOfTodaysPlan` passed.
- `swift test --filter localTaskControllerTrimsDraftAndPreservesItsIdentityAcrossRetry` passed.
- `swift test --filter localTaskCompletionIsDurableAndNeverMutatesAnExternalReminder` passed.
- `swift test --filter completingLocalTaskStaysLocalRecordsHistoryAndSurvivesRestart` passed.
- `python3 Scripts/scenario_registry.py validate` passed with exactly 666 scenarios and no tracker drift.

The first focused build from the shared root was discarded because an unrelated concurrent lane left an uncommitted conflict marker in `Tests/ZoidCoachAppTests/DailyReviewTests.swift`.
No result from that contaminated root build is used here.

## Privacy and cleanup

The signed verifier uses a per-process isolated root matching `/private/tmp/zoid-666-qa-manual-local-task-$PPID` and installs only `~/Applications/Zoid 666 QA Manual Task Probe.app`.
Its `EXIT` trap boots out the QA LaunchAgent and removes both the installed probe and isolated QA root on success or failure.
The verifier script is byte-identical to the signed version and has current SHA-256 `edf62a11083934f0ad54726d3c9cea36b466abdc89bf7dcbd7fc7e64e0cb4b3c`.
The requalification inspection found no matching temporary manual-local-task root and found the installed probe absent.
The shared QA LaunchAgent label was present during inspection because another signed-QA lane was active, so this lane did not mutate it.
The lifecycle proof asserts zero Apple Reminders outbox mutation and uses no production Reminders data.
No title, notes, task identifier, database contents, or other personal payload is copied into this report or manifest.

## Scope boundary

This requalification does not rerun the signed package or mutate any QA or production runtime.
It binds the original exact signed proof to its signed commit, proves current stable equivalence with hashes and focused tests, and supplies the previously missing immutable scenario-bound manifest.
The root integrator remains responsible for deciding whether the tracker and registry should advance.
