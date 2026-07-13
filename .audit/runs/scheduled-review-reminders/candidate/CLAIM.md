# Scheduled review reminders claim

This isolated lane starts from authoritative commit `a3d1815cd182e59e72ccb325ded989a2738c66b6`.

## Scenarios

- `ZC-054-004` - Receive the end-of-day review reminder.
- `ZC-054-005` - Receive the weekly review reminder.

## Owned files

- Scheduled-review action origin only in `Sources/ZoidCoachCore/ActionCommand.swift`.
- Observe-mode exemption only for scheduled review notifications in `Sources/ZoidCoachInfrastructure/ActionOutboxStore.swift`.
- `Sources/ZoidCoachInfrastructure/ReviewReminderService.swift`.
- Review-reminder composition and reconciliation only in `Sources/ZoidCoachAgent/AgentMain.swift`.
- `Tests/ZoidCoachAppTests/ReviewReminderServiceTests.swift`.
- Candidate evidence under `.audit/runs/scheduled-review-reminders/candidate/`.

## Boundaries

This lane does not touch root, runtime, tracker, registry, backlog, Lavish, migrations, GamingDrift, DailyReview, AppModel, or any MenuBar source.

Daily reminders use the end of the next configured workday.

Weekly reminders use the end of the final configured workday in the ISO week.

Both reminders use the existing quiet-hours boundary and durable action outbox so restart and repeated agent cycles do not duplicate delivery.

Scheduled review notifications remain available in observation mode because they summarize evidence and do not mutate external task or Calendar state.
