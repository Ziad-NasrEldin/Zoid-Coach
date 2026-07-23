# Quiet-hours delivery verification

## Result

The signed Zoid 666 QA app proved that a prompt created during quiet hours remains immediately usable in Today while its notification waits until the configured quiet-hours end.
The app and helper then restarted without duplicating either the unresolved prompt or its pending notification.

## Signed end-to-end evidence

- The installed build identity was `zoid-coach-7a216a88032234e5d7a442e46a8052a16b283b92-clean`.
- The persisted overnight quiet window contained the current local time and ended at 08:15 in Africa/Cairo.
- The onboarding notification verification created one durable `ONBOARDING_TEST` prompt.
- Today immediately displayed one waiting decision titled `Choose where coaching should continue` with both supported actions.
- The notification fixture scheduled that prompt for `2026-07-13T05:15:00Z`, which is exactly 08:15 in Africa/Cairo.
- The helper restart changed its process identifier from 83468 to 88742.
- After the app and helper restart, SQLite still contained exactly one queued prompt.
- After the restart, the notification ledger still contained exactly one row at attempt 1 for the stable request identifier.

## Deterministic boundary evidence

- `swift test --filter "QuietHoursDeliveryBoundaryTests|PromptNotificationCoordinatorTests"` passed once.
- The focused tests covered same-day quiet hours, overnight quiet hours, both sides of midnight, exact-end immediacy, daytime immediacy, invalid timezone fallback, explicit future delivery, and latest-policy reads through a retained coordinator closure.
- `swift build -c release` passed once.
- The signed QA package and installation passed once.

## Scenario decisions

- `ZC-005-008` is fully implemented because signed onboarding configuration and persistence were already proven, and this run traversed the remaining live delivery boundary end to end.
- `ZC-054-008` is fully implemented because the same unresolved prompt remained singular across signed app and helper restart, backed by the stable request identifier and focused replacement tests.
- `ZC-045-004` remains Touches remaining because the latest-policy implementation and deterministic test passed, but this run did not change quiet hours through the signed Settings UI and then create a second prompt without restarting the helper.
