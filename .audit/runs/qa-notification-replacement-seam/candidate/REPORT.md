# ZC-054-009 QA Notification Replacement Seam Candidate

## Purpose

This candidate adds the minimum signed-QA-only path needed to exercise actual macOS notification replacement without exposing a production debug control.
The probe is unavailable unless the runtime is both isolated QA mode and embedded in a QA package.

## Implemented boundary

`QANotificationReplacementProbe` creates an original unresolved prompt through `PromptInboxStore` and schedules it through the real `PromptNotificationCoordinator`.
The replacement operation dismisses the original episode, creates a new unresolved episode with the same logical decision key and changed title, body, and action copy, then schedules it through the same coordinator.
The stable decision identity therefore reaches the production notification request path while the new episode identifier remains available for newest-action routing.

The live controller deliberately constructs the coordinator without a deterministic fixture adapter.
In a later serialized runtime run, the signed QA application therefore uses its isolated QA bundle identifier, QA database, QA notification namespace, and the real `UNUserNotificationCenter` path.
Production mode and unpackaged QA mode render no control and cannot construct the probe.

## Prepared visible control

The new view provides Create Original, Replace With Update, and Refresh Result controls with stable accessibility identifiers.
It reports whether macOS accepted each request and whether the newest notification action was durably recorded.
After the time-zone lane integrated at `69fd38fcbb4969063abe1532d5dbaae9ad733cd8`, the candidate rebased onto that exact tip and added one `SettingsView` insertion.
The signed-QA-only view now appears inside Notification Delivery while production and unpackaged QA render nothing.

## Deterministic coverage

Focused tests were written red before the service existed.
They cover production and unpackaged-QA refusal, different episode identifiers with one stable request identity, changed content replacement, distinct logical decisions, newest notification action routing, persisted response state, and reconstructed-store relaunch without obsolete-notification resurrection.

The first post-implementation compile found one controller initialization defect because retained optional dependencies were immutable across success and failure branches.
The fix made only those two private optionals mutable.
The next test run exposed that the fixed test clock was later than the probe's default expiry clock and that probe episodes had not opted into safe dismissal before supersession.
The test now injects the same deterministic clock, and the QA-only prompt payload explicitly permits dismissal.

`swift test --filter "QANotificationReplacementProbeTests|PromptNotificationCoordinatorTests"` then passed all focused probe and coordinator tests.
`swift build -c release` passed.
`git diff --check` passed.

The real Notification Center and TCC journey remains pending a separate runtime lease and explicit user-controlled permission handling.

## Owned files

- `Sources/ZoidCoachInfrastructure/QANotificationReplacementProbe.swift`
- `Sources/ZoidCoachApp/Views/QANotificationReplacementProbeView.swift`
- `Sources/ZoidCoachApp/Views/SettingsView.swift`
- `Tests/ZoidCoachAppTests/QANotificationReplacementProbeTests.swift`
- `.audit/runs/qa-notification-replacement-seam/candidate/REPORT.md`
