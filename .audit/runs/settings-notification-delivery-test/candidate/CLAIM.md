# Settings notification delivery test claim

This isolated lane starts from authoritative commit `4a62a967fd87e1e9e819db9c7de49a221fe137fa`.

## Scenario

- `ZC-044-012` - Send a test notification.

## Owned files

- `Sources/ZoidCoachApp/SettingsNotificationDeliveryTestController.swift`
- The notification delivery card only in `Sources/ZoidCoachApp/Views/SettingsView.swift`
- `Tests/ZoidCoachAppTests/SettingsNotificationDeliveryTestControllerTests.swift`
- `.audit/runs/settings-notification-delivery-test/candidate/*`
- The matching delivered-batch entry in `docs/impl/666-BACKLOG.md`

This lane reuses the canonical delivery-test service to give Settings one direct, retryable test action with exact delivered, scheduled, unavailable, and failed feedback.
It does not touch gaming unlock, dashboard, prompt blocker, tracker, registry, Lavish, or runtime files.
