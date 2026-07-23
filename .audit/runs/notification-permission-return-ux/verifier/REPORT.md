# Notification permission return verification

## Result

`ZC-050-002` remains Touches remaining.
The implementation and focused controller tests pass, and the signed QA app now exposes a truthful fixture-only repair action without opening production System Settings.
The actual foreground return loses the pending repair message, so the journey is not completely usable end to end.

## Verified lineage

- Candidate commit: `622c822f11f6285846f747b7242dd18114c58ce8`.
- Verifier fix commit: `f46e32b36a3c4eb208f4eae4be7483ecf4b719bf`.
- Signed build identity: `zoid-coach-f46e32b36a3c4eb208f4eae4be7483ecf4b719bf-clean`.
- Installed application: `/private/tmp/zoid-666-notification-return-install/Zoid 666 QA E2E.app`.
- Isolated QA root: `/private/tmp/zoid-666-notification-return-runtime`.

## Implementation verification

The candidate records a pending return only after a real production Settings URL opens and keeps unrelated foreground activation passive.
The verifier added the exact manual breadcrumb `System Settings > Notifications > Zoid 666 > Allow notifications` and made the QA repair action start the same pending round trip without touching production System Settings.
The focused seven-test permission return suite passed, including restored, still-denied, manual failure, unrelated foreground, and QA fixture paths.
One release QA package completed successfully and passed the package signing checks.

## Signed end-to-end result

The signed ready-state app launched with fixture notification permission denied.
Settings > Signals showed native `ACCESS NEEDED` health and an `APPLY QA REPAIR` action.
Pressing the repair action showed the prepared QA permission-control instructions, named Today as the fallback, and confirmed that no production System Settings page was opened.
After switching to Finder and returning to Zoid 666, the status message disappeared instead of showing the required still-denied breadcrumb and Today fallback.
The failure reproduced twice, including a direct application activation.
The granted transition, unrelated second foreground activation, and relaunch were not claimed after this blocking state failed.

## Evidence

- `signed-qa-return-blocker.png` captures the signed denied repair surface used during the failing foreground round trip.
- `Sources/ZoidCoachApp/Views/NotificationDeliveryHealthView.swift` contains the candidate and verifier behavior.
- `Tests/ZoidCoachAppTests/NotificationDeliveryHealthTests.swift` contains the focused controller proof.

## Remaining acceptance work

Persist or otherwise retain the pending repair return across the real signed foreground lifecycle.
Then repeat the denied return, fixture grant return, unrelated foreground, and relaunch sequence before promoting the scenario to Fully implemented.
