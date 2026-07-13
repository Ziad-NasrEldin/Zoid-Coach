# Unknown session review candidate claim

## Scenarios

- `ZC-045-011` - Review unknown sessions.
- `ZC-046-010` - See ambiguous activity remain unknown when AI fails.
- `ZC-061-004` - See the session remain unknown or request confirmation when evidence is insufficient.
- `ZC-061-006` - Correct the session if Zoid 666 is wrong.
- `ZC-061-007` - Save an appropriately scoped rule if the same context will recur.
- `ZC-061-008` - See future matching activity handled according to the correction.

## Owned files

- `Sources/ZoidCoachCore/DailyReview.swift`
- `Sources/ZoidCoachApp/Views/DailyReviewView.swift`
- `Tests/ZoidCoachAppTests/DailyReviewTests.swift`
- `.audit/runs/unknown-session-review/candidate/*`

## Boundaries

This lane owns the dedicated Unknown-session review queue, neutral uncertainty copy, correction entry point, future-rule explanation, focused state proof, and candidate evidence.
It will not touch screenshot consent, onboarding, Screenwatch archive, Settings, Today behavior evidence, tracker, registry, backlog, shared runtime, root, or Lavish.
