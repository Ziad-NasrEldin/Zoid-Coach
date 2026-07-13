# Latest Relevant Notification Candidate Report

Scenarios: `ZC-038-007` and the notification-replacement portion of `ZC-033-011`.

Candidate status: implementation complete and ready for independent signed notification verification.

## End-User Behavior Implemented

- A newly accepted prompt notification removes older notifications from the same relevance group.
- Plan-ready and plan-changed prompts share one planning relevance group, so an obsolete plan notification cannot remain beside the current plan decision.
- Meeting, wake-intervention, onboarding, and gaming-drift notifications replace only older notifications in their own groups.
- A meeting notification is not removed by a newer plan or coaching notification.
- Notification replacement never resolves or deletes the underlying prompt episode.
- Every older unresolved decision remains available in the Today dashboard even after its notification disappears.
- Scheduling the new notification happens before obsolete notifications are removed, so a scheduling refusal does not discard the last accepted notification.
- The same behavior applies to deterministic signed-QA fixtures and the real macOS notification center.

## Focused Proof

- `swift test --filter PromptNotificationRelevanceTests` passed on 13 July 2026.
- `swift test --filter PromptNotificationCoordinatorTests` passed on 13 July 2026.
- `swift test --filter disabledPromptNotificationsRemainInAppAndCanBeReenabledWithoutRestart` passed on 13 July 2026.
- `swift test --filter fixtureReschedulingSamePromptReplacesObsoleteContentWithoutStacking` passed on 13 July 2026.
- `swift build -c release` passed on 13 July 2026.
- The deterministic end-to-end test schedules earlier plan, meeting, changed-plan, and two gaming prompts, verifies only the latest notification per relevance group remains, and verifies all five prompt episodes still appear as unresolved dashboard decisions.

## Independent Verifier Plan

1. Install and launch the signed QA app with notification permission granted.
2. Produce a plan-ready notification, then produce a newer plan-changed notification.
3. Open Notification Center and verify only the newer planning notification remains.
4. Open Today and verify both unresolved plan decisions remain available.
5. Produce a meeting notification and two successive gaming-drift notifications.
6. Verify the meeting notification remains while only the latest gaming notification is visible.
7. Resolve an older notification-replaced decision from Today and verify it resolves once without affecting the latest notification.
8. Relaunch and verify unresolved dashboard decisions remain durable.

The tracker and registry should not promote these scenarios until the real Notification Center sequence passes.
