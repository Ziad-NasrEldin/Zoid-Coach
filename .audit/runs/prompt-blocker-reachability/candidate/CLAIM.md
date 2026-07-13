# Prompt Blocker Reachability Claim

## Scope

- Scenario: `ZC-034-011`, Mark the task blocked.
- Base: authoritative `7758ca6`.
- Branch: `codex/prompt-blocker-reachability`.
- Worktree: `/private/tmp/zoid-666-prompt-blocker-reachability`.

## Owned files

- `Sources/ZoidCoachApp/Views/TodayPromptInboxLedger.swift`
- `Sources/ZoidCoachApp/PromptTaskBlockState.swift`
- `Tests/ZoidCoachAppTests/PromptTaskBlockStateTests.swift`
- `.audit/runs/prompt-blocker-reachability/candidate/CLAIM.md`
- `.audit/runs/prompt-blocker-reachability/candidate/REPORT.md`
- `docs/impl/666-BACKLOG.md`

## Acceptance

In a constrained Today window, the end user can reach the single Mark blocked action before the longer recovery controls, open the blocker sheet with keyboard or accessibility navigation, understand and satisfy the reason contract, cancel without resolving the prompt, or save a meaningful blocker through the existing durable mutation path.
Tracker, registry, Lavish, packaging, and installed runtime are outside this candidate lane.
