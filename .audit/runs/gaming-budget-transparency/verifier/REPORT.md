# Gaming Budget Transparency Verifier Report

## Scope

This verifier independently reviewed the candidate for `ZC-030-001` through `ZC-030-005` in an isolated worktree.

The candidate was rebased without conflict onto authoritative root `8a754d6`.

The verified implementation commits are `921c207` and `1237c58`.

## Defects Fixed During Verification

- Fixed SwiftUI modifier placement that prevented `TodayDashboardCommandOverview.swift` from compiling.
- Preserved factual raw observed gaming minutes instead of replacing them with threshold-filtered allowance use.
- Added backward-compatible `meaningfulGamingMinutes` decoding so old snapshots keep their previous observed value.
- Renamed ambiguous `debtMinutes` presentation to truthful same-day `overageMinutes`.
- Routed Today allowance calculation and proactive voice decisions through meaningful gaming time while leaving raw app usage intact.
- Reused one `allowanceBreakdown` value across the primary and compact ledger implementations.

## Automated Proof

`swift test --filter TodayDashboardTests` passed after the verifier fixes.

The two new journeys prove that a separated one-minute launcher visit remains in raw observed usage but is excluded from the three-minute meaningful allowance session.

The focused suite also proves base, earned, used, locked, remaining, positive same-day overage, legacy `GamingStatus` decode, legacy `BehaviorSummary` decode, and exact shared ledger copy.

The rebased release package completed successfully.

Packaging validation passed for the app, embedded helper, LaunchAgent contract, Mach service, and signing identities.

## Signed Installed-App Proof

The signed QA runtime was installed at `/private/tmp/zoid-666-gaming-transparency-install/Zoid 666 QA E2E.app`.

The canonical helper `qa.ziadnasreldin.ZoidCoach.agent` was running from that installation.

The verifier inserted six privacy-safe observations into the isolated canonical database: one minute of Steam, one minute of Xcode, three further minutes of Steam, and a final Xcode boundary.

After kickstarting the helper and fully terminating and relaunching the exact installed app, Today showed `Base 60m · Earned 0m · Used 3m · Locked 15m · Remaining 57m · Same-day overage 0m`.

Today also showed the explanation that gaming sessions under two continuous minutes are observed but do not use the allowance.

The observed-use popover simultaneously showed Steam at `4 MIN OBSERVED` and Xcode at `1 MIN OBSERVED`.

This proves that the brief launcher visit remains visible to the user as factual observation while only the meaningful three-minute session consumes allowance.

The visible state survived the app and helper restart.

The signed screenshot is `signed-ui-observed-vs-meaningful.jpeg` beside this report.

## Scenario Decisions

- `ZC-030-001` is fully implemented because the installed Today UI exposes the complete ledger and automated proof covers non-zero earned and overage states.
- `ZC-030-002` remains touches remaining because the visible next-unlock condition is still fixed rather than user configured.
- `ZC-030-003` remains touches remaining because classified observations now visibly accumulate into raw and meaningful gaming totals, but confidence policy is still limited to app classification and source coverage.
- `ZC-030-004` is fully implemented because the signed installed app proves separated brief-launch exclusion without hiding the raw observation.
- `ZC-030-005` remains partially implemented because this verifier did not complete the configured-condition task-unlock journey in the signed app.

## Cleanup

The isolated signed QA runtime was uninstalled after evidence capture.
