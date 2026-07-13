# Rules-only factual review candidate

## Scope

- `ZC-041-015` - Receive a complete factual review without AI.
- `ZC-046-001` - Use rules-only mode with all Release 1 functionality available.

## End-user result

Daily Review now reads the persisted AI provider and exposes a dedicated `LOCAL FACTS / NO AI REQUIRED` boundary when the provider is disabled.
The boundary states the exact factual session count produced from local activity and task history.
It confirms that correction, hypothesis rejection, and review confirmation remain available without configuring a model.
When coverage is limited, the copy says the gap is labeled instead of filled with an AI guess.
When coverage is sufficient, it states that the displayed factual totals have sufficient evidence.
The boundary has one stable accessibility identifier and never implies that configured intelligence changes the locality of observed facts or corrections.

## Evidence

- Candidate implementation: `16da3e6`.
- `swift test --filter RulesOnlyReviewStateTests` passed local-only, singular/plural, limited/sufficient, and configured-intelligence boundary copy.
- `swift test --filter DailyReviewTests` passed local session grouping, correction, hypothesis, confirmation, learned-rule, offline-work, completed-task, and restart persistence coverage without a model dependency.
- `git diff --check` passed before the implementation commit.

## Verifier plan

A fresh verifier should rebase onto the authoritative root and run the two focused groups once.
In signed QA, save Disabled AI, open a seeded factual review, confirm the local-only boundary and session count, correct and reject one hypothesis, confirm the review, restart app and helper, and verify the same corrected factual review remains without provider setup or network activity.
The root, runtime, tracker, registry, and Lavish artifact remain untouched by this implementation lane.
