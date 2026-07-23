# ZC-050-002 Candidate Report

## Outcome

The notification permission repair flow now retains its context across the System Settings round trip and gives the user a truthful next step after the automatic return check.

## Behavior

- Opening Notification Settings records one pending repair round trip.
- Returning to Zoid 666 automatically checks current authorization without requesting permission again.
- Restored access produces explicit success copy and confirms both Notification Center delivery and the durable Today fallback.
- Still-denied access produces the exact `Notifications > Zoid 666 > Allow notifications` path and confirms that Today remains usable.
- A failed System Settings launch retains the existing exact manual path.
- An ordinary foreground activation refreshes health without pretending the user attempted repair.
- The existing stable `settings.notifications.status-message` accessibility identifier exposes every result.

## Verification

- `swift test --filter NotificationDeliveryHealthTests` passed.
- Focused tests cover restored access, still-denied return, no second permission request, failed settings launch, and unrelated foreground refresh.
- `swift build -c release` passed.
- `git diff --check` passed before handoff.

## Remaining Acceptance

An independent verifier must revoke notification access for the installed signed app, open the repair path, return once without granting and inspect the retained guidance, grant access, return again and inspect success, verify Today remains available throughout, and relaunch to confirm truthful current status.
Only the root integrator may update the authoritative tracker and registry after that verification.
