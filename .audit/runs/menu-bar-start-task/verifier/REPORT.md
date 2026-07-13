# Menu-bar task start verifier report

## Verdict

Scenario `ZC-016-002` advances from Not implemented to Touches remaining.

The implementation, focused tests, release package, and signed ready-state setup pass.

The scenario does not qualify as Fully implemented because the separate SwiftUI menu-bar status item did not enter the available accessibility tree, so the verifier could not honestly claim signed clicks through the Start journeys.

## Revisions

- Authoritative verification base: `d618680`
- Original candidate: `e38cea1`
- Independently verified cherry-pick: `b784dd7`
- Candidate replayed after the predecessor integrated: `852fcfb`
- Integration base after the predecessor: `c885dc7`

The candidate source and focused test files remained byte-identical when replayed after the predecessor.

## Automated verification

- `git diff --check` passed.
- `MenuBarCoachTests` passed all 14 focused tests in the single requested run.
- The release QA package completed once.
- Package signing, LaunchAgent coherence, Mach-service coherence, and designated-requirement validation passed.
- The verified artifact was `.build/app-qa/Zoid 666 QA.app`.

## Semantics inspected

- Start fetches the latest Today snapshot before any mutation.
- A changed recommendation, existing active task, or paused task prevents the stale Start mutation.
- `isApplying` blocks overlapping activations before the first suspension point can allow a second mutation.
- A successful response must identify the exact requested task as both the active task and an active task row.
- A malformed or unchanged response keeps the latest confirmed ready state visible and reports that Start was not confirmed.
- Fetch or apply failure keeps the last confirmed snapshot and exposes actionable failure copy.
- Every view-level Start attempt refreshes the main Today snapshot after the controller completes.
- The Start control has a stable identifier, task-specific accessibility label, and freshness hint.
- The canonical-agent focused journey proves one persisted task transition through restart.

## Installed signed evidence

- The exact signed QA package was installed with its isolated helper and QA run root.
- The verifier exited onboarding into Today and created the local planned task `Verify menu start` through the native UI.
- Today visibly showed one planned block, the recommendation `Verify menu start`, a 30-minute estimate, Ready state, and its normal Start action.
- The signed helper reported Running in the visible Today source freshness state.

## Accessibility boundary

- The application accessibility tree exposed the main window and standard application menus.
- Direct inspection of `SystemUIServer` by display name and bundle identifier timed out without exposing the status item tree.
- Keyboard focus traversal entered the macOS status-menu region and was attempted in both directions.
- None of those attempts exposed `menu-bar.coach` or `menu-bar.task.start` to Computer Use.
- Prior menu-bar verifier reports record the same external acceptance boundary.

## Remaining signed acceptance

- Open the actual status item on a harness that exposes SwiftUI MenuBarExtra content.
- Start the current recommendation and prove the exact task becomes active in both surfaces with one open activity interval.
- Rapidly activate Start and prove no duplicate interval or second mutation.
- Change the recommendation while the menu is stale and prove zero stale mutation plus visible replacement.
- Stop the helper, attempt Start, and prove last-state preservation with actionable error copy.
- Restart the app and helper and prove the same active interval remains durable.

No implementation defect was identified during this verification.
