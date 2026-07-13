# Onboarding System of Record Copy Candidate

## Scope

This candidate completes the visible product-positioning gap in `ZC-001-005` without changing the tracker, registry, Lavish audit, runtime fixtures, or onboarding persistence.

## User behavior

- The first welcome screen now says directly that Zoid 666 is a coach, not a replacement task manager.
- The same screen states that Apple Reminders remains the system of record for connected tasks.
- It tells users to keep creating, organizing, and editing connected tasks in Reminders while using Today for planning, source status, and coaching decisions.
- The existing non-punitive boundary remains visible.
- One stable accessibility element announces the complete positioning without splitting the meaning across unrelated nodes.

## Verification

- `welcomeExplicitlyPositionsZoidAsCoachAndRemindersAsSystemOfRecord` passed.
- `welcomeAccessibilitySummaryRetainsPositioningAndDefaultSafetyBoundary` passed.
- `onboardingProgressAdvancesInOrderAndRequiresAnExplicitCoachingMode` passed.
- `freshOnboardingPersistsEachStepAndResumesAfterRestart` passed.
- `swift build -c release` passed.

## Verifier handoff

Independent signed verification should open a fresh first launch and confirm the exact coach, non-replacement, Apple Reminders system-of-record, Today boundary, and non-punitive copy through native accessibility and pixels.
