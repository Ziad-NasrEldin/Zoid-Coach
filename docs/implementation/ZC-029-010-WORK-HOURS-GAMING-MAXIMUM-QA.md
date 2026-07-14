# ZC-029-010 installed signed acceptance runbook

This runbook verifies the installed signed application through production Settings, policy persistence, the running agent, and the rendered Today state.
It does not inject a `TodaySnapshot`, patch SwiftUI state, or treat source-code presence as acceptance.

## Fixed acceptance data

Use [the namespaced fixture](../../Scripts/fixtures/zc-029-010-work-hours-gaming-maximum.json) as the expected policy and rendered-state contract.
Use [the namespaced ready-state fixture](../../Scripts/fixtures/zc-029-010-work-hours-gaming-maximum-ready-state.json) only through the existing QA ready-state preparer so reminders and Screenwatch data enter through their production fixture schemas.
The ready-state schema intentionally has no policy field, so configure and persist the policy through Settings instead of inventing a fixture-only policy mutation.
Run `Scripts/verify-zc-029-010-work-hours-gaming-maximum-fixture.sh` before starting.
Prepare the isolated root with `python3 Scripts/prepare-qa-ready-state.py Scripts/fixtures/zc-029-010-work-hours-gaming-maximum-ready-state.json "$QA_ROOT" --replace` immediately before launching the signed app.
The preparer rebases the five production-shaped Steam observations to the current `Africa/Cairo` day, keeps every adjacent gap at 300 seconds, and leaves the newest observation fresh.
It fails closed during the first 20 minutes of that local day rather than splitting the meaningful session across two daily archives.

Use an isolated signed QA root and the canonical installed-app lifecycle.
Complete onboarding, connect the real local sources required by Today, and keep the app and agent on the same database.
Record the installed build identity and signing result before acceptance.

## Settings and persistence

1. Open Settings > Command in the installed signed app.
2. Keep the gaming budget enabled, set the base to 60 minutes, and set the priority reward to 15 minutes.
3. Enable `Use a separate maximum during configured work hours` and set `MAXIMUM DURING WORK HOURS` to 30 minutes.
4. Confirm the separate total-allowance maximum cannot be decremented below zero or incremented above 1,440 minutes.
Set the value to zero and run the probe with `settings-lower-bound`.
Set the value to 1,440 and run the probe with `settings-upper-bound`.
Return the value to 30 before saving.
5. Confirm the enabled consequence explains that base plus unlocked rewards are capped only in configured work windows and that the normal allowance returns outside them.
6. Run `Scripts/zc-029-010-work-hours-gaming-maximum-ax-probe.swift <app-pid> settings-enabled`.
7. Quit the app normally, relaunch the same installed signed app, reopen Settings > Command, and run the probe with `settings-persisted`.
8. Confirm the toggle remains enabled, the value remains 30 minutes, and the consequence copy is unchanged.

## Real Today evidence

Confirm the freshly rebased production Screenwatch fixture produces exactly 20 meaningful gaming minutes.
Do not insert a `today_snapshots` row or replace the rendered snapshot payload.
Complete the real priority task so the production reward ledger records the configured 15-minute reward.
Wait for the agent to publish a fresh Today snapshot, then refresh the app.

Configure a work window containing the current local time in the saved `Africa/Cairo` policy time zone.
Before refreshing at the boundary, open the menu and run `menu-awaiting-refresh` so stale capped or uncapped minutes are never relabeled as current.
Repeat the awaiting-refresh assertion when leaving the work window and after changing the maximum.
In Today, confirm `Base 30m`, `Earned 0m`, `Used 20m`, `Locked 0m`, and `Remaining 10m`, plus the work-hours cap explanation.
Run the probe with `within-work-window`.

Open the menu-bar surface and use its Today action.
Confirm the read-only `WORK-HOURS GAMING` summary shows `30 MIN MAXIMUM`, `Active in the current work window`, and `10m remaining`.
Run the probe with `menu-within-work-window` against the menu popover.
Use its Today action, confirm it opens the same fresh Today state, then rerun `within-work-window` against the resulting main window.

Move the saved work window so the same instant is outside the window, wait for an agent refresh, and run `outside-work-window`.
Confirm the normal `Base 60m`, `Earned 15m`, and `Remaining 55m` allowance returns without changing observed gaming or the reward ledger.
Open the menu and run `menu-outside-work-window`.
Confirm it keeps the configured 30-minute maximum visible while truthfully saying it is not active and that the normal allowance has 55 minutes remaining.

Disable the separate work-hours maximum, save, wait for refresh, and run `disabled` while the instant is inside the configured work window.
Confirm the normal allowance still applies.
Open the menu and run `menu-omitted` to prove the read-only summary disappears when the separate maximum is disabled.
The menu must remain in `menu-awaiting-refresh` until a fresh snapshot confirms the disabled policy, then become omitted.

For the partial-lock boundary, set the base to 60, reward to 15, and separate work-hours maximum to 70.
The maximum is a total daily allowance, so 70 is valid even though it is above the 60-minute base and below the 75-minute base-plus-reward potential.
Use a fresh QA local day with no reward ledger entry and no meaningful gaming observation.
While inside the saved work window, confirm `Base 60m`, `Earned 0m`, `Locked 10m`, and `Remaining 60m`, then run `partial-locked-reward`.

## Time-zone boundary

Keep the Mac and policy on intentionally different time zones.
Set an `Africa/Cairo` work window whose start or end lies between the two zones' current local times.
Capture the saved schedule, system time, policy time zone, Today state before the Cairo boundary, and Today state after it.
Acceptance requires the cap to switch at the saved policy-time-zone boundary, not the Mac's current time zone, with no manual snapshot replacement.
Before the refresh, require `menu-awaiting-refresh`.
After the refresh, require `workHoursMaximumEvaluation.configuredMaximumMinutes` to remain unchanged while `isApplied` flips.
Save an overnight window, relaunch Settings to prove it persisted, and confirm its after-midnight portion belongs to the selected start weekday.

## Conflict and privacy proof

Open Settings from two signed app sessions against the same isolated QA database.
Change maximum enablement in one session and maximum minutes in the other, then confirm the conflict surface names `Work-hours gaming maximum enabled` and `Work-hours gaming maximum minutes` separately.
Keep the private Screenwatch title and raw-URL sentinels from the ready-state fixture in the source data.
Run `menu-privacy-scan` on the complete compact card and retain its recursive Accessibility output proving those sentinels are absent while all three work-hours identifiers remain present.

## Acceptance record

Retain the signed build identity, database path, policy version before and after Settings save, reward-ledger evidence, source freshness, probe output for every mode, and screenshots of Settings plus each Today state.
Any stale source, unsigned replacement build, read-only Settings state, missing reward ledger, or probe failure leaves ZC-029-010 unverified.
