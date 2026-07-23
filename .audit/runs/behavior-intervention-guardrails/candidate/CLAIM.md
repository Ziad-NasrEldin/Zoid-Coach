# Behavior intervention guardrails claim

This isolated lane starts from authoritative commit `db7db539c1e66a9bf983cf4e63d135a12b157f45`.

## Scenarios

- `ZC-035-001` - Receive no more than six behavior interventions during a default workday.
- `ZC-035-002` - Avoid having estimate requests and source warnings counted against the behavior cap.
- `ZC-035-003` - Receive no duplicate prompt during its cooldown.
- `ZC-035-004` - Receive a 15-minute pause after a gentle nudge.
- `ZC-035-005` - Receive a 20-minute pause after answering an accountability prompt.
- `ZC-035-008` - Receive no more prompts that day after choosing `I am done today`.

## Owned files

- `Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift`
- `Tests/ZoidCoachAppTests/GamingDriftPromptServiceTests.swift`
- `.audit/runs/behavior-intervention-guardrails/candidate/*`

## Boundaries

This lane does not touch next-task recommendation feedback, Today recommendation presentation, `AppModel.swift`, root, installed runtime, tracker, registry, backlog, or Lavish.
The implementation will keep behavior accounting scoped to `GAMING_DRIFT`, preserve existing five-minute and intentional-override behavior, enforce response-derived pause boundaries, and expose `I am done today` only where it fits the three-secondary-action limit.
