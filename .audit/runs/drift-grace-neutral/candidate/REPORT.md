# Drift Grace And Neutral Activity Candidate

## Claim

- Scenario IDs: `ZC-027-001`, `ZC-027-002`, `ZC-027-003`, `ZC-027-004`, `ZC-027-005`, `ZC-027-006`, and `ZC-027-007`.
- Production file: `Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift` only.
- Test file: `Tests/ZoidCoachAppTests/GamingDriftPromptServiceTests.swift` only.
- Excluded: accepted-break lifecycle files, task execution mutations, onboarding, tracker, registry, backlog, Lavish, root, and runtime.

## Acceptance Target

Normal uncertain drift is suppressed during the first three minutes of a newly started task and the first minute after a real idle gap, while an already sustained high-confidence gaming session can bypass those grace periods.

System Settings, password managers, file dialogs, downloads, and short communication checks are treated as neutral supporting activity and never create or extend a drift decision or pause the task.

## Implemented

- A new gaming session that begins after an active task starts receives an explicit three-minute task-start grace result before the normal ten-minute threshold is considered.
- A fresh observation after an idle classification or a telemetry gap longer than five minutes receives a one-minute return grace.
- A sustained certain gaming session of at least ten minutes that began before the new task bypasses task-start grace and keeps the existing eligibility gates, allowing direct accountability when the user starts a task while already gaming.
- Current activity in System Settings, password managers, Finder, file open/save surfaces, local file URLs, Slack, Messages, Mail, Teams, or Zoom is classified as neutral supporting context for prompt eligibility.
- Neutral suppression is read-only: it creates no prompt and does not pause or otherwise mutate the active task.
- Neutral matching uses bounded application and file-dialog rules, avoiding broad substring matching such as treating every title containing `open` as neutral.

## Focused Proof

- `newTaskAndIdleReturnReceiveExplicitGraceWhileSustainedGamingBypassesIt` passed.
- `neutralSupportingActivitySuppressesCoachingWithoutMutatingTheActiveTask` passed across System Settings, 1Password, Finder Downloads, and Slack fixtures.
- The complete `GamingDriftPromptServiceTests` run compiled and exercised all 13 tests; two pre-existing clock-reuse cases collided on fixture primary keys under parallel execution, then each passed independently without source changes.
- `intentionalGamingOverrideUsesConfiguredDurationAcrossRestart` passed independently.
- `configuredCooldownAndDailyPromptLimitApplyAcrossSeparateSessions` passed independently.
- `git diff --check` passed.

## Verifier Plan

1. Rebase onto the latest authoritative branch and rerun the two new focused cases plus the existing gaming-drift gate tests.
2. Seed an active priority task and a two-minute post-start gaming session in signed QA, then prove no prompt and inspect the grace decision through the isolated database.
3. Seed a ten-minute gaming session before starting the task and prove that the normal accountability prompt is created despite the new task age.
4. Exercise an idle-to-gaming transition inside and outside sixty seconds.
5. Exercise each neutral application family and a non-neutral similarly named application such as OpenTTD to rule out overmatching.
6. Confirm the active task interval remains open and no prompt row is created during neutral activity.
7. Only after installed evidence, update tracker, registry, backlog, and Lavish conservatively.
