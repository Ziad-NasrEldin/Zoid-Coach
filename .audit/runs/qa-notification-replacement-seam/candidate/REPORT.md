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
The view is not yet inserted into `SettingsView` because that shared file remains exclusively leased to the active time-zone lane.
Wiring is intentionally a one-line follow-up after that lease transfers.

## Deterministic coverage

Focused tests were written red before the service existed.
They cover production and unpackaged-QA refusal, different episode identifiers with one stable request identity, changed content replacement, distinct logical decisions, newest notification action routing, persisted response state, and reconstructed-store relaunch without obsolete-notification resurrection.

The focused green run and release build are pending the serialized build lease.
The real Notification Center and TCC journey remains pending a separate runtime lease and explicit user-controlled permission handling.

## Owned files

- `Sources/ZoidCoachInfrastructure/QANotificationReplacementProbe.swift`
- `Sources/ZoidCoachApp/Views/QANotificationReplacementProbeView.swift`
- `Tests/ZoidCoachAppTests/QANotificationReplacementProbeTests.swift`
- `.audit/runs/qa-notification-replacement-seam/candidate/REPORT.md`

