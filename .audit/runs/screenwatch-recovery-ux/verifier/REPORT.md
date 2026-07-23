# Screenwatch Recovery UX Verification

## Integrated lineage

The Screenwatch candidate was rebased onto authoritative root `27cc006` after the Today prompt-inbox and background-agent lifecycle integrations.
The rebased implementation commits are `1b23fa1`, `df8ed6f`, and `25be9ba` before this verifier evidence update.

## Code and focused verification

The independent code pass found no acceptance blocker in confirmed-state preservation, privacy-safe diagnostics, foreground recheck, alternate/default switching, or accessibility identifiers.
`swift test --filter Screenwatch` passed all 49 selected Screenwatch tests.
After the final rebase, `swift test --filter ScreenwatchConnectionController` passed all three controller seam tests.
The release build passed after an incremental continuation of the cold build.

## Signed installed verification

The signed QA package passed signing, designated-requirement, LaunchAgent, exact-helper, and isolated-root installation checks with QA root `/private/tmp/zoid-screenwatch-recovery-qa`.
The installed Zoid 666 Build 8 app exposed Settings, Signals, and the dedicated Screenwatch Connection card through stable accessibility identifiers.
The card first visibly reported `EXPECTED FOLDER, WAITING FOR TODAY'S LOG` with direct Choose Folder guidance.
After a valid current QA record appeared, Recheck visibly reported `EXPECTED FOLDER, STALE`, proving the distinct stale state and schema-valid explanation.
After the record timestamp was refreshed, Recheck visibly reported `EXPECTED FOLDER, HEALTHY`, `Screenwatch telemetry is connected and current`, and `Schema-valid local records were found`.
At no point did the card expose the seeded private title, URL, application content, screenshot flag, or filesystem location.
The visible Choose Folder action opened the native picker with the privacy-safe instruction to select a `YYYY-MM-DD/log.jsonl` days directory.

## Capped acceptance boundary

The native picker did not provide a reliable programmatic path-entry shortcut through the available macOS accessibility driver.
The verifier stopped at the explicit runtime cap rather than claim alternate-folder selection, restart persistence, unavailable-folder foreground recovery, outside-root rejection, or return-to-default as visibly proven.
Those states retain conservative statuses even though the focused repository and controller tests pass them.
Screenshot-analysis choice remains outside this batch as `ZC-003-009`.
