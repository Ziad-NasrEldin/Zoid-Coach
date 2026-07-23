# Notification prompt preference claim

This isolated lane starts from authoritative commit `40b14908f652ab4dbee32b513d5e1ca0d290c892`.

The higher ready onboarding item is acceptance-only, notification permission fallback overlaps the active TodayDashboard lane, and schedule onboarding is already fully delivered in the authoritative tracker.

This lane claims the first coherent unimplemented notification-control gap that is disjoint from active-task context files.

## Scenario

- `ZC-039-008` - Disable notification prompts while retaining dashboard access.

## Owned files

- Notification-prompt preference only in `Sources/ZoidCoachCore/UserPolicy.swift`.
- Notification-prompt delivery gating only in `Sources/ZoidCoachInfrastructure/PromptNotificationCoordinator.swift`.
- Exact fixture notification cancellation support only in `Sources/ZoidCoachInfrastructure/DeterministicOSFixtureAdapters.swift`.
- Notification preference composition only in `Sources/ZoidCoachAgent/AgentMain.swift`.
- Notification preference only in `Sources/ZoidCoachApp/Views/SettingsPolicyDraft.swift`.
- Notification preference merge only in `Sources/ZoidCoachApp/Views/SettingsPolicyConflict.swift`.
- Notification preference control only in `Sources/ZoidCoachApp/Views/SettingsView.swift`.
- `Tests/ZoidCoachAppTests/NotificationPromptPreferenceTests.swift`.
- Candidate evidence under `.audit/runs/notification-prompt-preference/candidate/`.

## Boundaries

This lane does not touch root, runtime, tracker, registry, backlog, Lavish, AppModel, TodayDashboard, DashboardView, TodayDashboardCommandOverview, or any active-task context source.

Disabling notification prompts must leave prompt episodes persisted and available to the existing in-app inbox while suppressing only system notification delivery.

The disabled preference is policy intent rather than a failed delivery attempt, so it does not add a misleading delivery-ledger event.

Task-start, break-end, review, and other non-prompt notification services remain outside this preference.
