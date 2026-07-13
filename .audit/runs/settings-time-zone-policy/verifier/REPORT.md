# Settings time-zone policy verifier report

## Rebase and source gate

The candidate commits `8423906`, `389ed26`, and `5375024` cherry-picked cleanly onto authoritative commit `4cc05de` as `33f5bda`, `409e3ae`, and `aedc669`.

The implementation presents the sorted `TimeZone.knownTimeZoneIdentifiers` collection, persists the selected identifier in `SchedulePolicy`, and provides a direct action that restores `TimeZone.current.identifier`.

The visible detail derives the selected zone's current UTC offset with hour and minute precision, identifies whether it matches the Mac, and explains that historical instants remain unchanged.

Time-zone edits participate in the existing three-way Settings merge so an independent concurrent edit survives, a competing zone keeps the current winner, and deliberate reapply retains the user's proposed zone.

The persistence test reopens both `PolicyStore` and `TaskHistoryStore` after a zone mutation and confirms that the exact historical completion `Date` remains unchanged.

No source blocker was found.

## Automated evidence

`swift test --filter SettingsPolicyDraftTests` passed all 29 selected tests in the verifier's single focused run.

The single signed QA package completed successfully at `.build/app-qa/Zoid 666 QA.app`.

Package verification confirmed coherent application, LaunchAgent, Mach service, and signing identities.

The verifier worktree was clean after packaging.

## Runtime lease boundary

No application installation, launch, helper registration, fixture mutation, tracker edit, registry edit, backlog edit, or Lavish edit was performed during the source gate.

The review-reminder verifier owns the shared signed runtime lease.

## Capped signed acceptance plan

1. Install the prepared signed QA application under a unique isolated root after orchestration grants the runtime lease.
2. Open Settings and capture the persisted zone, current UTC offset, Mac comparison, full IANA picker, and `USE MAC TIME ZONE` action.
3. Select `America/Los_Angeles`, save through the live helper, close and reopen Settings, and require the exact zone to persist.
4. Restart the application and helper, reopen Settings, and require the same saved zone.
5. Confirm Today derives its visible local date from `America/Los_Angeles` at a fixture instant whose Cairo and Los Angeles calendar dates differ.
6. Complete one local task at an exact fixture instant, change the zone, and require Review plus stored history to retain the same historical instant.
7. Apply an independent concurrent policy edit while the zone draft is open and require both changes to survive the safe merge.
8. Apply a competing time-zone mutation and require the conflict panel to name `Time zone`, preserve the current winner, and retain the user's zone for deliberate reapply.
9. Reapply the user's zone, save, restart, and require it to persist.
10. Select `USE MAC TIME ZONE`, save, restart, and require the policy to return to the Mac's exact current identifier.
11. Unregister the QA helper and remove the isolated application and runtime root before releasing the lease.

`ZC-053-010` remains outside this candidate because moving an existing plan across local-day boundaries still requires a separate explicit-confirmation implementation.
