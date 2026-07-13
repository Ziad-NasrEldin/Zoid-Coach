# Learned rule reset claim

This isolated lane starts from authoritative commit `8b7f100`.

Higher ready implementation items require serialized runtime proof or overlap the active custom-estimate files, so this disjoint lane pulls priority 17.

## Scenario

- `ZC-045-015` - Reset learned rules.

## Owned files

- `Sources/ZoidCoachInfrastructure/DailyReviewStore.swift`
- `Sources/ZoidCoachApp/Views/DailyReviewView.swift`
- `Tests/ZoidCoachAppTests/DailyReviewTests.swift`
- `.audit/runs/learned-rule-reset/candidate/*`
- The isolated backlog claim and handoff rows only.

The lane will expose a reviewed destructive reset for all active learned app-classification rules while preserving historical corrections and append-only audit history.
It will not touch custom estimate, Dashboard, runtime, tracker, registry, or Lavish.
