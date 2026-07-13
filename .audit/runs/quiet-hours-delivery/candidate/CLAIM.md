# Quiet-hours notification delivery claim

This isolated lane starts from authoritative commit `0123875` and pulls the highest unowned non-runtime implementation slice.

## Scenario ownership

- `ZC-005-008` - Configure quiet hours.
- `ZC-045-004` - Change quiet hours.

## File ownership

- `Sources/ZoidCoachInfrastructure/QuietHoursDeliveryBoundary.swift`
- `Sources/ZoidCoachInfrastructure/PromptNotificationCoordinator.swift`
- `Sources/ZoidCoachAgent/AgentMain.swift`
- `Tests/ZoidCoachAppTests/QuietHoursDeliveryBoundaryTests.swift`
- Focused prompt-notification tests only if required.
- Candidate evidence under `.audit/runs/quiet-hours-delivery/candidate/`.

## Boundaries

This lane makes every agent-scheduled prompt honor the currently persisted quiet-hours policy, including same-day and overnight windows, while keeping the unresolved prompt available in Today.
It does not touch Calendar approval receipt files, root, runtime installation, tracker, registry, Lavish, Settings UI, or shared QA state.
