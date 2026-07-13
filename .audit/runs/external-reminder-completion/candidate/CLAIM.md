# Candidate claim

Scenario: `ZC-021-002`.

When the active Zoid 666 task is completed directly in Apple Reminders, the next source refresh must end its tracked session instead of silently dropping the task.
Today must preserve the completed row with a clear explanation that Apple Reminders ended it.
Repeated refreshes and agent restart must preserve the reason and stopped elapsed time without creating another completion.
The remaining plan must stay available, and Zoid 666 must not request a redundant Reminder completion.

This candidate does not claim signed external Apple Reminders completion or visible installed Today acceptance.
