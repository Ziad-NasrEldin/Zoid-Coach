# Menu bar prompt fallback verifier report

## Revisions

- Authoritative base: `7dde802af9d6b08cb12de50e32d73908f1ad6448`.
- Candidate report after rebase: `aa443fb`.
- Candidate implementation after rebase: `116f0d9`.
- Verifier freshness fix: `dc9ef9132b28f863212d5ce5af298e36b08f17d9`.

## Independent implementation review

- The candidate derives notification unavailability from attention, not-connected, and unavailable source states.
- The menu badge activates only when notification delivery is unavailable and at least one unresolved prompt is waiting.
- The exact accessibility label is singular for one decision and plural for larger counts.
- The fallback menu keeps coaching pause, task start, pause, resume, break, end-workday, source health, and Settings controls.
- The original candidate refreshed Today on popover presentation but did not refresh notification authorization or the prompt inbox.
- The verifier added `AppModel.refreshMenuBarPromptFallback()` and invokes it when the popover opens, so new prompts and repaired notification permission do not leave stale badge state.

## Automated verification

- `swift test --filter MenuBarCoachTests` passed once before the final authoritative rebase.
- The authoritative guardrails delta touched only `GamingDriftPromptService.swift` and its focused tests, so the passing menu-bar seam was not rerun.
- The focused suite covers denied notifications with two unresolved prompts, `exclamationmark.bubble.fill`, the exact `2 decisions are waiting in Today` label, direct fallback copy, retained active-task controls, healthy-delivery suppression, and zero-decision suppression.
- One release build passed on the rebased verifier tip.
- One release QA package passed on the rebased verifier tip.
- Package verification reported coherent app, LaunchAgent, Mach service, and signing identities.
- `codesign --verify --deep --strict` passed on the installed isolated app.

## Signed installed verification

- The isolated app was installed as `/Users/ziadnasreldin/Applications/Zoid 666 QA Menu Prompt Fallback.app`.
- Today first rendered `DECISIONS 0 WAITING` with no prompt history.
- Two durable prompts then rendered as `DECISIONS 2 WAITING` with both exact actionable rows.
- Resolving the first prompt through its signed Today action immediately rendered `DECISIONS 1 WAITING` and retained the answered choice in recent history.
- Resolving the second prompt removed all waiting rows and retained both answered choices in recent history.
- Quitting and relaunching the signed app preserved the cleared waiting state and both durable responses.
- Restoring the QA notification permission and relaunching rendered `QA Notifications` as `HEALTHY` with `Fixture notifications are available`.
- Creating a signed local task exposed start, bounded sprint, begin focus, estimate, defer, block, remove, and recommendation controls while notification delivery had been unavailable.
- Killing helper PID `32119` caused LaunchAgent to relaunch helper PID `43413` immediately.

## Remaining acceptance gap

- The installed app accessibility tree exposes the main app menu but not the SwiftUI `MenuBarExtra` status item.
- SystemUIServer accessibility inspection timed out within the capped acceptance window.
- Therefore the signed status symbol, exact count label, fallback copy, Today navigation button, and compact task controls were not directly clicked.
- Scenarios `ZC-038-002` and `ZC-038-008` remain conservatively at **Touches remaining** until one addressable signed menu-bar acceptance run proves those controls.
