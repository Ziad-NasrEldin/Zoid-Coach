# Settings notification delivery test candidate

## Scope

This candidate covers `ZC-044-012` without changing authoritative scenario status.
Settings now exposes `SEND TEST NOTIFICATION` in the existing Notification Delivery card.
The action uses the same local production and isolated-QA delivery boundary already used during onboarding.
While a test is in flight, the control becomes `SENDING TEST`, disables repeated activation, and runs exactly once.
After completion, the control becomes `SEND ANOTHER TEST` so the user can retry without leaving Settings.
The result distinguishes delivered, scheduled, unavailable, failed, and Today-fallback states instead of reporting generic success.
Unavailable and failed states explicitly preserve Today as the reliable coaching-decision surface.
The action, result status, and detail expose stable accessibility identifiers.

## Focused verification

- `swift test --filter SettingsNotificationDeliveryTestController` passed two async state tests.
- Focused proof covers exact outcome presentation, retry, in-flight duplicate suppression, and truthful Today fallback copy.
- `swift build -c release` passed.
- `git diff --check` passed.

## Independent verifier plan

1. Rebase or cherry-pick the candidate onto the current authoritative root and build a signed QA package.
2. Open Settings, select Signals, and prove Send Test Notification is keyboard and accessibility reachable.
3. Activate it twice rapidly and prove only one isolated fixture notification is created while the button reads Sending Test.
4. Prove the delivered result and exact fixture delivery ledger entry, then use Send Another Test successfully.
5. Change the fixture permission to denied and prove the action reports Test Unavailable and directs the user to Today without invoking production notification APIs.
6. Relaunch Settings and confirm the persistent notification health ledger reflects the test outcomes without creating an unresolved coaching decision.
