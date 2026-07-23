# Reminders Recovery Verification

## Accepted revision

The implementation was verified on the clean signed-QA code revision `a3d6c8fef28d79fe4afd660b9a1d92af0481eddd`, rebased from authoritative tip `0fb950708b106cad66ce8332dadf739d923f9af4`.

The final source batch also adds selected-state feedback for the local-only fallback at `32b2ad1133f99f4b567225d78b5e524c142eede5`.

## Installed end-to-end proof

- The signed application ran from `/private/tmp/zoid-reminders-recovery-apps/Zoid 666 QA E2E.app` with its exact registered helper and isolated root `/private/tmp/zoid-reminders-recovery-a3d6c8f`.
- Opening Settings > Signals passively showed Ready to Connect and did not request permission.
- Request Access changed the card to Connected and stored a visible last-success timestamp.
- Restarting the application retained the same timestamp.
- A deterministic signed-QA task-fetch failure changed the card to Refresh Failed, retained the prior timestamp, explained the stale-data impact, and exposed Refresh Reminders.
- Removing the failure and choosing Refresh Reminders returned the card to Connected and advanced the timestamp only after task data was available.
- A denied fixture changed the card to Access Needed and visibly exposed Recheck Access, Open System Settings, and Use Local-Only Planning.
- Choosing the local-only fallback saved policy version 2 through the installed helper.
- Restart visibly restored policy version 2, and the database independently stored `reminderLists.isConfigured = true` with zero included decisions.

## Safety and automated proof

- The Settings card composes only deterministic fixture adapters in QA and cannot fall back to production EventKit.
- Passive inspection never calls the permission-request API.
- Focused controller, fixture, and Settings policy tests passed.
- All Scenario Registry tests and exact-666 validation passed before tracker synchronization.
- A clean release package passed signing, embedded identity, LaunchAgent, Mach-service, and build-identity verification.

## Conservative boundary

`ZC-051-001` remains Not implemented.

Excluding Apple Reminder lists is durable, but the product still lacks a general user-created local-task flow after permission denial.

The repository-wide Swift test runner entered its known idle-helper state during this lease, so that attempt was terminated and is not claimed as a pass.
