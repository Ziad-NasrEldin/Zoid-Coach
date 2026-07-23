# Coaching Response Actions Candidate

## Claim

- Scenario IDs: `ZC-034-001`, `ZC-034-002`, `ZC-034-003`, `ZC-034-004`, `ZC-034-009`, `ZC-034-012`, and `ZC-034-014`.
- Production files: `Sources/ZoidCoachCore/PromptInbox.swift`, `Sources/ZoidCoachInfrastructure/PromptResponseEffectRouter.swift`, and `Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift`.
- Test files: focused prompt response router and gaming drift prompt tests only.
- Excluded: gaming-budget transparency Today/GamingStatus files, rescheduling, blocking reasons, five-minute follow-up, notification delivery, tracker, registry, backlog, Lavish, root, and runtime.

## Acceptance Target

A coaching response can start the recommended task, start an exact 10-minute recovery sprint, start an exact 20-minute work sprint, resume the current task, pause it, or end the workday, with exactly-once durable task mutation and no replay after the prompt is already resolved.

## Implemented

- `startRecommendedTask` starts the payload task through the durable execution store.
- `startShortSprint` starts the payload task with an exact ten-minute bounded sprint.
- New `startWorkSprint` starts the payload task with an exact twenty-minute bounded sprint.
- `returnToActiveTask` resumes a paused task, preserving its paused sprint, or starts a ready task.
- `pauseTask` pauses the payload task or the actual active task when the prompt has no task payload.
- `endWorkday` records the durable end-of-day pause reason on the payload or active task.
- Every effect requires `wasApplied`, and the persisted response effect marker makes notification/dashboard replay return `.none` without repeating task mutation.
- Gentle gaming prompts offer the ten-minute recovery action, while accountability prompts offer the twenty-minute work action and retain break support when work is active.
- Each prompt retains one primary action and no more than three secondary choices.

## Focused Proof

- `coachingTaskActionsApplyExactDurationsAndNeverReplay` passed and covered all six commands plus cross-surface replay.
- `gamingDriftOffersBreakOnlyWhenATaskIsActivelyTracking` passed.
- `gamingDriftStaysQuietUntilBaselineCompletesThenQueuesEvidenceFirstPrompt` passed.
- The focused router suite compiled after the final throwing active-task fallback fix.
- `git diff --check` passed.

## Verifier Plan

1. Rebase onto the latest authoritative root and rerun the new action journey plus the affected gaming prompt tests.
2. Seed signed QA with one ready task, one paused bounded sprint, and eligible gentle and accountability prompts.
3. Click the ten-minute action and verify the exact countdown, durable task identity, prompt resolution, and relaunch state.
4. Click the twenty-minute action in a fresh episode and verify the same boundaries.
5. Exercise recommended start, paused-task return, pause, and end-workday through Today and notification response surfaces.
6. Replay each response token from the other surface and prove no extra interval, sprint, or pause row appears.
7. Verify prompt action counts, primary role, and refreshed Today state after every mutation.
8. Only after installed proof, update tracker, registry, backlog, and Lavish conservatively.
