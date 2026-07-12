# Background Agent Lifecycle Verification

## Scope

This batch implements backlog slice 19, background-agent lifecycle and Login Items repair.
It provides a dedicated Background Agent window reachable from the Zoid 666 application menu with Command-Shift-L and from the actual menu-bar popover through Agent Health.
It does not change planning, weekly review, Settings, app classification, migrations, or unrelated source-health behavior.

## End-user behavior

- The window inspects the current `SMAppService` registration whenever it opens and shows its evidence and last inspection time.
- Check Again refreshes the state without restarting the foreground app.
- A disconnected installation exposes Enable.
- An approval-required or disconnected installation explains the exact Login Items recovery path.
- Open Login Items opens System Settings directly at General, Login Items & Extensions.
- A stale or unhealthy registration can be repaired without deleting local plans, reviews, or history.
- A healthy agent exposes Disable only behind a destructive confirmation that names the background behavior that stops and the local data that remains.
- Production and QA use separate application, LaunchAgent, executable, defaults, and database identities.
- Every primary lifecycle control and status surface has a stable accessibility identifier.

## Focused and package gates

- `swift test --filter AgentLifecycleController` passed the four lifecycle controller tests after the final weekly-review rebase.
- `swift test --filter AgentLaunchServiceTests` passed the five production/QA isolation, registration, relocation, and disable tests after the final weekly-review rebase.
- All 42 registry and evidence tests passed before the final weekly-review rebase, whose own verifier passed the same suite after integration.
- The release build completed before the final weekly-review rebase, and the signed-QA package rebuilt the combined lineage successfully afterward.
- `verify-package.sh` passed package structure, LaunchAgent, Mach service, and signing-identity coherence for the final signed-QA package.
- One full Swift-suite attempt reached the known idle `swiftpm-testing-helper` defect at zero CPU and was stopped.
- No full-suite pass is claimed for this batch.

## Installed signed-QA journey

The final combined lineage was installed as `/Users/ziadnasreldin/Applications/Zoid 666 QA E2E.app` with isolated root `/private/tmp/zoid-666-agent-lifecycle-992e83f`.

- Command-Shift-L opened the Background Agent window from onboarding.
- The first live state was Healthy, with Check Again, Open Login Items, Repair Registration, and Disable exposed through accessibility.
- Check Again updated the visible inspection time while preserving Healthy.
- Open Login Items opened the correct System Settings page and exposed `Zoid 666 QA E2E` as the enabled background item.
- The packaged QA repair command replaced the live helper process from PID 73685 to PID 80074.
- A local-data preservation marker survived repair.
- Check Again returned Healthy after repair.
- Disable opened a confirmation sheet explaining that overnight planning and automatic source refreshes stop while local plans, reviews, and history remain.
- The final destructive button was not activated through Computer Use because changing a Login Item through the OS UI requires action-time user confirmation.
- The same installed package then unregistered its QA helper through its dedicated packaged lifecycle command.
- Launchd confirmed the QA label was absent and the preservation marker remained unchanged.
- Check Again visibly changed the window to Not Connected and exposed Enable plus exact Login Items guidance.
- The installed package re-registered the helper as PID 84969.
- Check Again visibly returned the window to Healthy.
- The simultaneously running production helper remained PID 77972 at `/Users/ziadnasreldin/Applications/Zoid Coach.app/Contents/MacOS/ZoidCoachAgent`.
- The QA helper ran independently at `/Users/ziadnasreldin/Applications/Zoid 666 QA E2E.app/Contents/MacOS/ZoidCoachAgentQA`.

## Conservative acceptance boundary

The normal enabled, repaired, disabled, and re-enabled runtime states are proven with the installed signed package, live launchd state, and visible accessibility refreshes.
The approval-required guidance and status mapping are covered by focused tests, and its System Settings deep link is proven live.
An actual approval-required Login Items state was not forced because that would require changing the user's macOS background-item switch through System Settings.
The final UI Disable and Enable actions were not clicked past their OS-changing boundary; their button-to-controller wiring is covered by focused tests while the equivalent installed-package lifecycle operations were exercised live.
Therefore `ZC-023-011` advances conservatively but does not qualify as fully complete because the menu-bar entry opens background-agent health rather than all source health.
The agent portion of `ZC-062-009` is complete, but the broader multi-source degraded-mode journey remains partial.
