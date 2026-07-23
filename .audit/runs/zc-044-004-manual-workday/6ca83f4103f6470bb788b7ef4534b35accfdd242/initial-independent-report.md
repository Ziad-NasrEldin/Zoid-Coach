# ZC-044-004 independent current-base signed verification

## Strict verdict

ZC-044-004 is not eligible for Fully implemented from this run.

The five focused tests, release package, signed runtime, and exact app/helper/database binding passed.

The repaired product AX journey did not begin because the installed app did not expose the Settings navigation target required to reach the Command chapter before the hard cap.

## Assembly identity

- Canonical base: `36bc8e48b5ea5258320e543be10e49737f63d49c`
- Product candidate: `03ed2a3ef6e14bd91cb0903d4c8b98be6ecdfa87`
- Repaired verifier/tooling descendant: `8ad5ca2c8c85ec5cc6964a3a9a9a774209a2f900`
- Current-base combined candidate: `b3ff3d3e8eff70f60301c5be3faffb9c00ccfc2a`

The product delta and verifier/tooling delta were applied explicitly onto current canonical.

The combined commit preserves the original candidate ancestry required by the repaired signed preflight.

## Passed focused tests

`swift test --filter ManualWorkdayControlTests` passed exactly five tests.

The focused proof covered legacy scheduled defaults, Settings/manual control semantics, persistence state, menu accessibility identifiers, and conflict resolution preserving the independent manual-workday choice.

## Passed package and runtime prerequisites

- Clean release QA package completed.
- Nested helper and app deep strict code-sign verification passed.
- Package identity, LaunchAgent, Mach service, and signing identities passed.
- QA XPC registration reported a writable runtime and prompt timeline.
- The installed QA app launched from the isolated install root.
- The signed preflight bound the exact installed app PID and helper PID to the isolated bundle.
- The signed preflight bound the app and helper to `/private/tmp/zoid-666-zc044004-runtime/Application Support/Zoid 666/zoid-coach.sqlite`.
- The helper held the exact isolated database open.
- The fixture prepared the scheduled baseline and owned ready task successfully.

## Repaired tooling issue

Directly invoking `qa-zc044004-signed-preflight.sh` rejected the valid 40-character commit as malformed because its zsh repetition pattern requires `extendedglob` but the script does not enable that option.

Running the same script through `zsh -o extendedglob` passed every identity and database assertion.

This is a verifier tooling defect, not product acceptance evidence.

## Blocking AX result

The installed app process was reachable through exact-PID accessibility.

The `settings-select-manual` probe could not find `settings.schedule.workday-control` because the Command Settings chapter was not open.

A bounded accessibility attempt could not find a `Settings` navigation element in the current application tree.

The hard cap arrived before a safe supported navigation route could be established.

## Unproven product gates

- Scheduled Settings baseline visible in the signed app.
- Selecting Manual start and end through the production segmented control.
- Fixed-hours controls becoming disabled.
- Saving and observing `All changes saved`.
- App and helper relaunch persistence of Manual mode and disabled controls.
- Ready owned task with Start present and End absent.
- Start Workday activating the task and exposing End without Start.
- Confirmed End Workday producing the ended/resume state.
- Relaunch persistence of the ended state.
- Honest stale Start rejection with no illegal mutation.
- Honest stale End rejection with no illegal mutation.
- Invalid controls omitted at every lifecycle state.
- Recursive accessibility privacy scan through every required phase.

## Cleanup and restoration

- The fixture cleanup command completed successfully before runtime removal.
- The fixture-owned policy backup and rows were restored or removed before deleting the isolated database.
- Signed QA runtime uninstall passed.
- QA LaunchAgent was absent after cleanup.
- Isolated QA app was absent after cleanup.
- Isolated QA runtime root was absent after cleanup.
- Production database contained zero `qa-zc044004-*` task, plan, execution, and interval rows.
- Canonical, tracker, production app, production database, and user permissions were not changed.

## Evidence

- Report: `/private/tmp/zoid-666-zc044004-evidence/REPORT.md`
- Package/install log: `/private/tmp/zoid-666-zc044004-evidence/install.log`
