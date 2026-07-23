# Menu Bar Task Controls Verification

## Decision

The menu-bar implementation is integrated as a usable foundation, with all eight owned scenarios conservatively retained at `Touches remaining` rather than claimed as fully implemented.
The macOS status item was not addressable through the available Computer Use accessibility surface, so the verifier did not fabricate visible click evidence.

## Verified implementation

- The menu icon derives neutral, active, paused-task, and source-attention states from the canonical Today snapshot.
- The compact popover prefers the explicit recommendation, excludes optional fallback work, and retains the existing Voice controls.
- Start, Pause, and Resume use the authenticated Today XPC client and install only the returned persisted snapshot.
- Mutation failure preserves the last confirmed snapshot and gives truthful recovery copy.
- Open Today, Source Health, and Settings select the exact section and activate the main application.
- Verification found and fixed a real closed-window defect by assigning the main `WindowGroup` the stable `main` identifier and calling `openWindow(id: "main")` before activation.
- Refresh reloads both the popover controller and the shared application snapshot.
- Stable accessibility identifiers cover the popover, status, task, commands, navigation, attention, empty, refresh, and error states.

## Signed QA evidence

The clean signed QA package installed at `/private/tmp/zoid-menu-bar-apps/Zoid 666 QA E2E.app` with isolated root `/private/tmp/zoid-menu-bar-qa` and its exact registered helper executable.
The real installed application was inspected through macOS accessibility, exited onboarding into Today, created a local task named `Verify menu task controls` through the authenticated helper, and visibly showed it as the main objective, ready recommendation, and next action.
The package therefore proved the canonical recommendation substrate and installed helper boundary used by the menu controller.
Computer Use could inspect the application windows but could not address the separate macOS status item process, so neutral, active, paused, attention, navigation, and command states retain a visible-click acceptance remainder.

## Automated proof

- `swift test --filter MenuBarCoach` passed after the closed-window fix.
- `swift test` passed all 582 tests across 7 suites.
- `swift build -c release` passed.
- Signed QA packaging, deep signing validation, isolated installation, LaunchAgent registration, and helper launch passed.

## Lineage

- Authoritative base: `4d5eef7`.
- Rebased candidate: `a45fe84`.
- Closed-window fix: `7ef113b`.
