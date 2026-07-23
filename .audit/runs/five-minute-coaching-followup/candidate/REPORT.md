# Five-minute coaching follow-up candidate

## Claim

- Primary scenario `ZC-034-005`: choose `Five more minutes` from a gentle gaming-drift prompt.
- Primary scenario `ZC-034-006`: receive exactly one follow-up when that five-minute snooze ends while the gaming drift remains eligible.
- Related scenario `ZC-035-006`: provide partial evidence that the selected five-minute duration is honored, without claiming configurable snooze durations.

## Owned files

- `Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift`
- `Tests/ZoidCoachAppTests/GamingDriftPromptServiceTests.swift`
- `.audit/runs/five-minute-coaching-followup/candidate/REPORT.md`

## Exclusions

- The root worktree, installed runtime, tracker, scenario registry, Lavish artifact, backlog, and active-work ledger remain untouched.
- `AgentPlanScheduler.swift` and `ActionCommandExecutor.swift` remain untouched for the disjoint task-start reminder lane.

## Planned acceptance

- The initial gentle prompt visibly offers `Five more minutes`.
- Choosing it creates a durable response through the existing prompt response store.
- Eligible coaching remains quiet until the full five minutes have elapsed.
- A process restart during the snooze does not lose or shorten the selected duration.
- Continued eligible gaming receives one follow-up with explicit elapsed-snooze copy and duration payload.
- Repeated producer passes do not create a second follow-up.

## Evidence

- `GamingDriftPromptService` now derives a five-minute snooze from the durable prompt response instead of introducing a second persistence system.
- The service uses the response timestamp as the timer anchor, suppresses coaching before five minutes, and uses a deterministic response-epoch decision key for the follow-up.
- The follow-up bypasses the generic cooldown and daily prompt cap because it is the completion of an action the user explicitly selected.
- The follow-up says `Your five minutes are up`, records `snoozeDurationMinutes=5`, links back to the original prompt, and does not offer a second `Five more minutes` action.
- Repeated producer passes find the same deterministic follow-up and do not create another episode.
- A pre-existing focused test used `fiveMoreMinutes` against an accountability prompt that never offered that action and failed with `invalidActionToken` before this batch.
- That test now resolves through the accountability prompt's offered `startWorkSprint` action so it continues to test restart-safe generic cooldown behavior.
- `swift test --filter GamingDriftPromptServiceTests` passed with exit code 0 after the implementation.
- `git diff --check` passed.

## Conservative status recommendation

- Keep `ZC-034-005` below fully implemented until a verifier chooses the visible action in the signed app and observes successful resolution.
- Keep `ZC-034-006` below fully implemented until a verifier keeps eligible gaming active across five minutes and proves exactly one notification or Today follow-up in the signed app.
- Treat `ZC-035-006` as touches remaining because this batch honors the fixed selected five-minute duration but does not add arbitrary configurable snooze durations.

## Independent verifier plan

- Rebase this candidate onto the latest authoritative integration commit before verification.
- Run `swift test --filter GamingDriftPromptServiceTests` and the prompt notification focused tests.
- Package and install a clean signed QA identity without touching production data.
- Seed one gentle gaming-drift prompt with an incomplete priority task and exhausted gaming allowance.
- Choose `Five more minutes` from the visible notification or Today surface and verify that the original prompt resolves once.
- Restart the helper before the five-minute boundary and verify that no replacement coaching prompt appears early.
- Continue eligible gaming through the boundary and verify one visible follow-up with the elapsed-snooze copy.
- Re-run agent production and notification delivery after the follow-up and verify that no second follow-up is created or delivered.
- Update the tracker, registry, backlog, and Lavish artifact only from the authoritative root after that proof passes.

## Known boundary

The follow-up producer still requires the normal gaming-drift eligibility gates, including continued qualifying gaming and an incomplete priority task, so returning to aligned work does not create an unnecessary follow-up.
