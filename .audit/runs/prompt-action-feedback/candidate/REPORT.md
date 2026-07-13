# Prompt action feedback candidate

## Scope

- `ZC-038-005` - See all other surfaces update after responding once.
- `ZC-038-006` - Avoid having two surfaces start duplicate sprints or apply the same choice twice.

## End-user result

The selected prompt row now changes from Waiting or Returned to `APPLYING` as soon as a choice begins.
A compact progress indicator explains that the choice is being saved once and every surface will refresh from the durable result.
All prompt actions disable during the in-flight write, preventing repeat clicks or a second local prompt action from racing it.
Other rows retain their truthful Waiting or Returned label instead of falsely appearing to apply.
The destructive-action confirmation now explains that Today, notifications, and other open surfaces consume the same durable result.
The applying state has a stable prompt-specific accessibility identifier.

## Evidence

- Candidate implementation: `8307a77`.
- `swift test --filter PromptActionPresentationTests` passed the selected, other-row, replay, and idle presentation states.
- `swift test --filter PromptInboxTests` passed concurrent enqueue, idempotent response, token rejection, dismissal, snooze return, replay, and restart persistence coverage.
- `git diff --check` passed before the implementation commit.

## Verifier plan

A fresh verifier should rebase onto the authoritative root and run the two focused groups once.
In signed QA, create one prompt visible in Today and notification delivery, activate one action, confirm `APPLYING` and disabled duplicate controls, race the same token from the second surface, and confirm one response, one effect, and refreshed resolved state everywhere after app and helper restart.
The root, tracker, registry, runtime, and Lavish artifact remain untouched by this implementation lane.
