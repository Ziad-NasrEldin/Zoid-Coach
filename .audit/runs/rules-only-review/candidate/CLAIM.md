# Rules-only factual review claim

This isolated lane starts from authoritative commit `a4a257b`.

Higher ready work requires serialized runtime proof or overlaps accepted-break prompt/router work, so this disjoint lane pulls priority 10.

## Scenarios

- `ZC-041-015` - Receive a complete factual review without AI.
- `ZC-046-001` - Use rules-only mode with all Release 1 functionality available.

## Owned files

- `Sources/ZoidCoachApp/RulesOnlyReviewState.swift`
- `Sources/ZoidCoachApp/Views/DailyReviewView.swift`
- `Tests/ZoidCoachAppTests/RulesOnlyReviewStateTests.swift`
- `Tests/ZoidCoachAppTests/DailyReviewTests.swift`
- `.audit/runs/rules-only-review/candidate/*`
- The isolated backlog claim and handoff rows only.

The lane will make the local-only review boundary visible, derive it from the saved AI provider, preserve factual correction and confirmation controls, and explain that no remote model is required.
It will not touch accepted-break prompts/router, runtime, tracker, registry, or Lavish.
