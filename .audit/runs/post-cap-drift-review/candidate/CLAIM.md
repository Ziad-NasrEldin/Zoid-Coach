# Post-cap drift review claim

This isolated lane starts from authoritative commit `7dde802af9d6b08cb12de50e32d73908f1ad6448`.

## Scenarios

- `ZC-035-009` - See later drift recorded quietly after reaching the prompt cap.
- `ZC-035-010` - See quietly recorded drift summarized only during review.

## Owned files

- Migration 39 only in `Sources/ZoidCoachInfrastructure/AutonomousDatabaseMigrator.swift`.
- Post-cap recording only in `Sources/ZoidCoachInfrastructure/GamingDriftPromptService.swift`.
- Quiet-drift review model only in `Sources/ZoidCoachCore/DailyReview.swift`.
- Quiet-drift loading only in `Sources/ZoidCoachInfrastructure/DailyReviewStore.swift`.
- Quiet-drift summary presentation only in `Sources/ZoidCoachApp/Views/DailyReviewView.swift`.
- Focused migration, gaming-drift, and daily-review tests under `Tests/ZoidCoachAppTests/`.
- Candidate evidence under `.audit/runs/post-cap-drift-review/candidate/`.

## Boundaries

This lane does not touch root, runtime, tracker, registry, backlog, Lavish, `AppModel.swift`, or any `MenuBar` source.

The ledger records only otherwise-eligible gaming drift suppressed by the behavior daily cap.

It remains local, factual, idempotent for one continuing session, and invisible outside the end-of-day review.
