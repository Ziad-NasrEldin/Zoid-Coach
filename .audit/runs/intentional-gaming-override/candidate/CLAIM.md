# Intentional Gaming Override Claim

## Owned scenarios

- `ZC-036-001` - Choose to continue gaming intentionally.
- `ZC-036-002` - See the current prompt close immediately.
- `ZC-036-003` - Avoid another equivalent prompt during the override window.
- `ZC-036-007` - Return to work before the override ends.
- `ZC-036-008` - Receive normal coaching again after the override expires if conditions still apply.

## File ownership

- `Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift`
- `Tests/ZoidCoachAppTests/GamingDriftPromptServiceTests.swift`
- `.audit/runs/intentional-gaming-override/candidate/`
- `docs/impl/666-BACKLOG.md`

## Boundary

This lane does not own notification authorization, notification repair, Today fallback, tracker, registry, Lavish, signed runtime, or root integration.
It uses the existing visible Continue intentionally action and durable prompt response as the source of truth for a bounded override.
