# Prompt action feedback claim

This isolated lane starts from authoritative commit `a3b4553`.

Higher ready implementation items either require serialized runtime proof or overlap active AI-boundary and source-repair work, so this lane pulls priority 13.

## Scenarios

- `ZC-038-005` - See all other surfaces update after responding once.
- `ZC-038-006` - Avoid having two surfaces start duplicate sprints or apply the same choice twice.

## Owned files

- `Sources/ZoidCoachApp/PromptActionPresentation.swift`
- `Sources/ZoidCoachApp/Views/TodayPromptInboxLedger.swift`
- `Tests/ZoidCoachAppTests/PromptActionPresentationTests.swift`
- `Tests/ZoidCoachAppTests/PromptInboxTests.swift`
- `.audit/runs/prompt-action-feedback/candidate/*`
- The isolated backlog claim and handoff rows only.

The lane will make an in-flight choice unmistakable, prevent repeat activation, explain that every surface refreshes from the durable decision, and strengthen same-token duplicate-response proof.
It will not touch AI settings, remote evidence, source repair, runtime, tracker, registry, or Lavish.
