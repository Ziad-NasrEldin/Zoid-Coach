# Reminder Completion Sync Recovery Evidence

## Scope

- Candidate tip: `84da415`.
- Integrated baseline: `f832c9e`.
- Primary scenarios: `ZC-020-005`, `ZC-020-006`, `ZC-020-007`, `ZC-020-010`, `ZC-051-005`, `ZC-051-006`, `ZC-051-007`, and `ZC-051-008`.

## End-user result

- Completing a Reminder-backed task records the local completion and durable history immediately without claiming that Apple Reminders already confirmed it.
- Completed work remains absent from the active Today task list while the dedicated `REMINDERS COMPLETION SYNC` ledger shows pending, retrying, failed, unavailable, or unknown source state.
- Only a source-confirmed `succeeded` command is presented as confirmed completion.
- A rejected source write keeps the task title and local completion history, explains that local history is safe, and exposes one task-specific `RETRY SYNC` action.
- Retry reuses the exact durable command identity, retains prior attempt evidence, and cannot be activated twice while another task mutation is pending.
- Exact per-task lookup remains available after the completion falls outside the general 50-entry action-audit window.
- Restart recovery identifies the completed task from its durable history title instead of exposing an opaque source identifier.

## Automated proof

- `ReminderCompletionSyncStateTests` passed for pending, retrying, failed, unavailable, confirmed, and unknown states.
- `ActionOutboxStoreTests` passed for explicit failed-command retry, invalid transition rejection, preserved attempt history, and exact lookup after 75 newer commands.
- `TodayDashboardAgentTests` passed for failure, exact retry, second-attempt identity, local history preservation, and active-list exclusion.
- `RuntimeSafetyAndCapturePolicyTests` passed and the retry XPC mutation remains protected by the database write circuit breaker.
- The ZoidCoachApp target compiled after the final verifier and signed-probe changes.
- The release build passed at candidate `dd63b60`; subsequent commits contain only verifier truthfulness fixes, the signed-QA probe, durable title recovery, and a SQLite busy timeout exercised by the signed package.
- A broad Swift test run was deliberately stopped after concurrent lanes started multiple SwiftPM runners against the same build directory and the runners became idle.
- No completion claim relies on that inconclusive broad run.

## Independent review

- A first parallel review found that an empty or truncated general audit could make a local completion look confirmed.
- The candidate now shows `Completion sync unknown` and an explicit confirmation-unavailable warning instead.
- Fresh verifier commit `005908a` prevents duplicate retry activation and keeps audit fallback truthful when exact lookup temporarily fails.
- Fresh verifier commit `e8fbed3` preserves the durable completed-task title for recovery after restart.
- The fresh verifier reported PASS for code merge after all focused suites.

## Signed QA proof

- `Scripts/verify-qa-reminder-completion-sync-xpc.sh` built and deep-verified the clean signed QA package at candidate `84da415`.
- The installed packaged app used the dedicated QA identity, QA LaunchAgent, QA Mach service, and an isolated run root.
- The probe seeded an external QA Reminder, synchronized it through the agent boundary, installed it in the daily plan, and started it.
- The probe revoked deterministic Reminders permission before completion so the real background action executor produced a terminal source-write failure.
- The task left active Today work, the exact XPC status became `failed`, attempt count remained one, and retry was explicitly available.
- After restoring Reminders permission, the packaged XPC retry requeued the same command and the background executor confirmed the source task on attempt two.
- Restart preserved the same command identity, confirmed state, source completion, readable task title, and exactly one local completion-history entry.
- The probe unregistered the QA helper and removed the installed probe app and isolated QA root during cleanup.

## Conservative tracker boundary

- The signed failure, repair, retry, confirmation, history, and restart journey provides end-to-end proof for the eight listed completion-sync and source-write recovery scenarios.
- A real user-owned Apple Reminder was not mutated because the signed QA proof intentionally uses the isolated deterministic EventKit boundary.
- General task completion and completed-history scenarios remain governed by their existing independent evidence.
