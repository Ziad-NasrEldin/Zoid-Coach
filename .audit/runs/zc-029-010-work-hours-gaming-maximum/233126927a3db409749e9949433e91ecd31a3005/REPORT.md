# ZC-029-010 signed acceptance report

## Result

Status: Touches remaining.

The installed signed candidate was `233126927a3db409749e9949433e91ecd31a3005`.

The external accessibility verifier correction is `f297d0d142fde85a604bf194d4a8f60f705cff1d`.

The scenario is not fully usable end to end because the required Settings save and relaunch journey and the downstream work-window states were not completed.

## Passed evidence

- The ZC-029-010 fixture contract verifier passed.
- All 21 focused `WorkHoursGamingMaximumTests` passed.
- The clean release candidate packaged, deep-signed, and installed successfully.
- Package identity, candidate ancestry, embedded application and helper QA roots, LaunchAgent registration, Mach/XPC readiness, and exact isolated database binding passed.
- The production-shaped ready state rendered current Screenwatch evidence and 20 meaningful gaming minutes in Today.
- Normal navigation reached the installed Settings policy surface and its real `settings.gaming.work-hours-maximum-enabled` accessibility target.
- The verifier-only correction selected the unique foreground matching window when two application windows exposed the same Settings identifier, and the corrected verifier passed Swift typechecking.

## Remaining acceptance gates

- Set the work-hours maximum to exactly 30 minutes through Settings and save it.
- Relaunch the installed signed application and confirm policy persistence and version advancement.
- Verify the exact 0-minute and 1,440-minute bounds.
- Verify inside-work-window capped allowance arithmetic and truthful Today and menu-bar copy.
- Verify outside-work-window normal allowance arithmetic and truthful Today and menu-bar copy.
- Verify disabled-policy omission after refresh.
- Verify partial-lock arithmetic.
- Verify overnight work windows use the start weekday after midnight.
- Verify conflicting two-window Settings behavior and labels.
- Complete recursive accessibility privacy checks and retain the required screenshots.

## Cleanup

The isolated application, runtime root, evidence scratch directory, release products, application and helper processes, LaunchAgent, and worktree were removed.

The canonical workspace, tracker, and production application were not modified during signed acceptance.
