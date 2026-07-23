# ZC-047-012 Candidate Report

## Outcome

The existing confirmation-backed `Delete reviews and learned rules` command now deletes the real review and learning product state instead of only three legacy learning tables.
The operation is atomic and preserves factual source behavior plus task execution history.

## Deleted State

- Daily review confirmations, deferrals, skips, personal notes, and hypothesis decisions in `daily_reviews`.
- Session corrections in `daily_review_corrections`.
- Weekly review experiments in `weekly_review_experiments`.
- Active and removed learned app-classification rules in `app_classification_correction_rules`.
- Estimate and schedule learning samples in `learning_samples`.
- Derived learning aggregates in `learning_aggregates`.
- Planner trust cycles in `planner_trust_cycles`.

## Preserved State

- Raw and classified behavior source records remain intact.
- Task execution state remains intact.
- The operation does not touch plans, prompts, meetings, voice records, AI request metadata, settings, or source-owned files.

## Verification

- `swift test --filter PrivacyDataServiceTests` passed.
- The focused restart-safe deletion test seeded all seven review and learning stores, deleted exactly seven records, confirmed every target table empty, confirmed behavior and task rows preserved, reopened the service, and proved a repeated deletion returns zero.
- `swift build -c release` passed.
- `git diff --check` passed before handoff.

## Remaining Acceptance

An independent verifier must use the signed Settings confirmation, cancel once, confirm once, observe the refreshed review and learned-rule empty states while factual activity remains, relaunch the app and helper, and confirm the deletion remains complete.
Only the root integrator may update the authoritative tracker and registry after that verification.
