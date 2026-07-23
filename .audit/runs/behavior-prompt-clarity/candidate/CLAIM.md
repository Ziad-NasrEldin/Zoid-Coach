# Behavior prompt clarity claim

This isolated lane starts from authoritative commit `4e3a703`.

## Scenarios

- `ZC-033-006` - See no more than three secondary actions.
- `ZC-033-007` - See reliable elapsed time when included.
- `ZC-033-008` - See uncertainty acknowledged when context is ambiguous.
- `ZC-033-009` - Avoid guilt, insults, moral labels, disappointment, or exaggerated claims.
- `ZC-033-010` - Avoid being told what the user's intent must be.

## Owned files

- `Sources/ZoidCoachCore/PromptInbox.swift`
- `Sources/ZoidCoachInfrastructure/PromptInboxStore.swift`
- `Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift`
- `Tests/ZoidCoachAppTests/PromptInboxTests.swift`
- `Tests/ZoidCoachAppTests/GamingDriftPromptServiceTests.swift`
- `.audit/runs/behavior-prompt-clarity/candidate/*`

The lane will enforce a durable behavior-prompt presentation contract before any dashboard or notification surface can receive a prompt.
It will keep elapsed evidence factual, treat limited coverage as uncertainty rather than intent, reject coercive copy, and cap secondary choices without touching wake reconfirmation, root, runtime, tracker, registry, backlog, or Lavish.
