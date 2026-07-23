# Reminders Outage Continuity Verification

## Code result

The candidate exposes a dedicated Today continuity banner for denied, disconnected, unavailable, and attention-required Reminders states.
The banner reports retained planned-task count and estimated minutes from the canonical Today snapshot.
It explicitly confirms local tracking when a task session is active.
It offers direct New Local Task and Open Source Health actions with stable accessibility identifiers.
The banner is removed when Reminders becomes healthy and is suppressed during an in-progress health check to avoid a false outage flash.

The retained facts are truthful because canonical task rows always carry a positive estimate and the banner does not claim that Apple synchronization succeeded.
Local task creation and source repair are separate explicit actions.

## Proof

- `swift test --filter RemindersOutageContinuityTests` passed.
- `swift test --filter LocalTaskCreationControllerTests` passed.
- `swift test --filter TodayDashboardAgentTests` passed.
- One release build passed.
- `git diff --check` passed.

## Signed acceptance boundary

The single signed install/package attempt exited without creating an installed app, registering a QA helper, mutating the shared runtime, or emitting diagnostic output.
No retry was performed under the package-once and UI timebox.

The installed revoke, banner counts, local-task creation, app/helper restart, restore, and banner-removal journey therefore remains unverified.
Both mapped scenarios remain conservative.
