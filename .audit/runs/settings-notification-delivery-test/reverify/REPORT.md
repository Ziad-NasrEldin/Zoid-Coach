# Settings Notification Delivery Test Native-AX Reverification

## Verdict

`ZC-044-012` remains conservatively unverified end to end.
The corrected native accessibility oracle disproved the earlier empty-window classification and successfully completed onboarding through the signed installed app.
The hard runtime cap arrived after Settings navigation but before the Signals tab and Send Test Notification action were exercised.
The tracker, registry, and Lavish status must remain unchanged.

## Code and package proof

The verifier ran from authoritative commit `bd13ee2`.
The single focused invocation `swift test --filter SettingsNotificationDeliveryTestController` passed both selected async tests with zero failures.
The one release QA package completed successfully.
The release app completed in 94.5 seconds and the helper completed in 9.7 seconds.
Package identity, LaunchAgent identity, Mach service identity, and deep code-sign validation passed.

## Corrected native accessibility proof

The verifier followed `docs/SIGNED-QA-WINDOW-VERIFICATION.md` and did not use System Events descendant counts.
`Scripts/verify-signed-qa-window-content.sh` returned:

```text
GREEN: non-minimized 1180x760 Zoid window exposes 42 AX content nodes after onboarding continuation
```

The native pixel capture is `native-window.png` beside this report.
Its SHA-256 is `c32c8c22eebabf93f126f66c9055ec1ac3ffe08e4f334f5939c7c685a40b4d8d`.
The native traversal and activation helper used for this run is `native-ax-driver.swift` beside this report.

## Signed onboarding journey

Native AX completed all 12 setup steps.
Reminders, Screenwatch, and Notifications used the explicit defer controls.
Rules-only coaching was selected.
The local test task was completed.
The bounded delivery test produced the exact signed result:

```text
RESULT - TODAY FALLBACK, Notifications are unavailable. The same prompt is ready here and in Today.
```

The harmless setup prompt was resolved through its native accessibility action.
The local starter plan was visibly prepared and setup completed into Today.
Today retained the answered setup decision and showed the unavailable notification action audit without claiming successful delivery.

## Final navigation state and cap boundary

Native AX activated the Settings navigation control.
The Settings view exposed its four chapter controls, including `Signals, Apps and calendars`, plus stable Settings accessibility identifiers.
The hard runtime cap arrived before the Signals chapter was selected.
The following required acceptance remains unverified:

- Reach `settings.notifications.send-test` and prove its stable accessibility contract.
- Rapidly activate the action twice and prove one request plus in-progress suppression.
- Capture exact delivered or scheduled feedback.
- Exercise unavailable or failed feedback plus Retry through the Settings action.
- Relaunch and prove no false success state remains.

## Classification

This run proves that the signed app is visible, natively accessible, onboarding-completable, and capable of truthful notification-unavailable fallback.
It does not prove the Settings action itself.
`ZC-044-012` must not be promoted to fully implemented from this run.

