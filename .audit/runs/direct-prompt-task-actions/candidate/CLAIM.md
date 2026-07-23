# Direct Prompt Task Actions Claim

## Scope

- Scenario: `ZC-034-011`, Mark the task blocked.
- Base: authoritative `5f4a758`.
- Branch: `codex/direct-prompt-task-actions`.
- Worktree: `/private/tmp/zoid-666-direct-prompt-task-actions`.

## Owned files

- `Sources/ZoidCoachApp/Views/TodayPromptInboxLedger.swift`
- `.audit/runs/direct-prompt-task-actions/candidate/CLAIM.md`
- `.audit/runs/direct-prompt-task-actions/candidate/REPORT.md`
- `docs/impl/666-BACKLOG.md`

## Acceptance

The Reschedule and Mark blocked controls are direct accessibility-reachable children of the prompt row rather than children of a virtualized collection.
The end user can activate Mark blocked without coordinate guessing and continue through the existing reason, Cancel, success, failure, and persistence flow.
Tracker, registry, Lavish, packaging, and installed runtime are outside this candidate lane.
