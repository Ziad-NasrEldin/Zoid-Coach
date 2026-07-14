# ZC-052-005 Full Mutation Lock Retry Verification

## Verdict

Candidate `14819bb0d2eff873cf2697cbd2a32a7bddc9e5b6` is rejected as-is.
The candidate improves preflight lock handling and Calendar lost-reply reconciliation, but it does not guarantee one logical task mutation across retries.
No tracker, registry, Lavish, backlog, or authoritative branch file was changed.
No signed runtime lease was requested after the blocking defect reproduced.

## Candidate scope and transplant

The candidate changed only `AppModel.swift`, `CalendarPlanApprovalState.swift`, `TodayDashboardAgent.swift`, their two focused test files, and the candidate report.
The verifier transplanted that single commit without conflict onto authoritative commit `066e4839ce0b4becb36ebddba5bb3afeca2307e3` as verifier commit `c5ce1a3`.

## Behavior that passed review

The preflight probe retries only while a second SQLite connection returns primary result `SQLITE_BUSY` or `SQLITE_LOCKED`.
The default delays are bounded at 100, 300, and 600 milliseconds.
A persistent preflight lock returns a truthful busy message without entering the task mutation.
A non-lock validation failure does not enter the delay schedule.
ActionOutboxStore already uses a deterministic idempotency key, so the repeated Reminder completion command remains one raw outbox command.

Calendar lost-reply reconciliation records the queue request time and considers only later commands for the exact reviewed task IDs.
It requires Calendar reconciliation, start notification, and Reminder priority commands for every reviewed task.
It includes an optional due-date command when present and does not accept an incomplete per-task command set.

## Blocking raw-store reproduction

The verifier added `downstreamFailureDoesNotDuplicateRawHistoryWhenTheUserRetries` to `TodayDashboardAgentTests.swift`.
The test creates a real Reminder-backed task and installs a SQLite trigger that rejects the later learning-sample insert.
The first completion call commits task execution, one completion outbox command, and one raw completed-history row before the downstream learning failure is returned.
The test removes the trigger and repeats the same user completion.
The outbox remains exactly one command, but raw SQL reports two completed `task_history` rows for the same logical mutation.
The required assertion was one and failed with actual value two.

The candidate test used `TaskHistoryStore.completedEntries`, which groups by task and returns only `MAX(id)`.
That read model hid duplicate raw history rather than proving exactly-once persistence.

## Root cause

`TodayDashboardAgent.applyOnce` is not one database transaction.
It invokes stores that own separate SQLite connections and commit independently.
The retry wrapper asks a new probe whether a competing write lock still exists after an error.
If the original lock clears between the failed write and that probe, the error no longer carries BUSY or LOCKED identity and the complete call is not retried.

The durable writes reachable from one task mutation are:

- TaskExecutionStore writes task state, time intervals, pause events, sprint sessions, and blocked-plan state.
- AutonomousPlanStore may promote a replacement main objective after Block.
- ReminderSnapshotStore may complete a local source task.
- ActionOutboxStore may enqueue a Reminder completion command.
- TaskHistoryStore appends selected, completed, or postponed history.
- TodaySnapshotStore may append a priority reward ledger row.
- LearningAggregateStore writes estimate and work-window samples plus aggregates.
- The final `snapshot` call can pause a deleted Reminder, complete an externally completed Reminder, append another history row, and save the Today snapshot.

Some individual writes are already naturally idempotent, but the entire set does not share an operation identity or atomic commit boundary.
Task history and some task-execution events remain append-only without a per-user-mutation uniqueness guard.

## Test evidence

- The candidate four-test selection passed.
- The CalendarPlanApprovalState suite passed.
- The new raw-history exactly-once regression failed with raw count two instead of one.
- `deletingActiveAppleReminderPausesVisibleTaskAndSurvivesRestart` independently reproduced the documented pre-existing `.write` failure at snapshot reconciliation.
- The candidate does not change the failing snapshot reconciliation hunk, and its report records the same failure after temporarily restoring authoritative TodayDashboardAgent source byte-for-byte.
- The broader TodayDashboardAgent suite did not finish within five minutes and was stopped after the candidate defect was already proven.
- An independent release build was not started after the defect rejection and while another lane held the serialized build lease for ENOSPC recovery.

## Smallest complete repair design

A stable operation-key saga is smaller and safer than trying to share one SQLite transaction across every current store connection.
The app must create one operation ID per explicit task action and reuse it for transport retries, lost replies, and relaunch recovery.
The agent must persist the operation before the first side effect and resume only missing durable steps.
Every append-only or transition side effect must commit its operation step receipt in the same local SQLite transaction as that side effect.

Migration 43 should add `task_mutation_operations` with an operation ID primary key, task ID, command, requested timestamp, state, and last diagnostic.
Migration 43 should add `task_mutation_steps` with a composite primary key of operation ID and step name.
Task history should receive an operation ID column with a partial unique index for non-null operation IDs.
Existing history can retain null operation IDs without rewriting history.

TaskExecutionStore must accept an operation ID and atomically record its execution step with the state, interval, pause, sprint, or blocked-plan writes.
TaskHistoryStore must atomically append history and its operation step exactly once.
ReminderSnapshotStore and AutonomousPlanStore must atomically record their operation steps with local completion or main-objective promotion.
ActionOutboxStore may reuse its current idempotency key, but the operation ID must be retained for receipt correlation.
TodaySnapshotStore reward writes already have a uniqueness boundary but must be linked to the operation step.
LearningAggregateStore must derive stable sample IDs from the operation ID and resume aggregate updates after a partial attempt.

The final Today snapshot must be separated into source reconciliation and read-model rendering.
Task mutation completion must not run unrelated source-reconciliation writes under an untracked operation.
Snapshot persistence can remain an idempotent day-key upsert after all required task-mutation steps are complete.

TodayDashboardXPC must carry the operation ID and expose a way to query or replay the same operation after a lost reply.
AppModel and the menu-bar controller must retain the pending operation ID until the agent returns a terminal receipt.
After app or helper relaunch, the same operation ID must return the durable completed receipt or resume the first missing step.

Persistent BUSY or LOCKED leaves the operation pending with the last confirmed user state and a truthful retry message.
A later retry uses the same operation ID and never replays a completed step.
Validation failures before any durable step may become terminal immediately.
A downstream non-lock failure after any durable step remains recoverable and cannot be reported as a clean rollback.

## Additional file claims required before repair

The minimum production claim is:

- `Sources/ZoidCoachCore/TodayDashboard.swift`
- `Sources/ZoidCoachInfrastructure/AutonomousDatabaseMigrator.swift`
- `Sources/ZoidCoachInfrastructure/TaskMutationOperationStore.swift` as a new file
- `Sources/ZoidCoachInfrastructure/TodayDashboardXPC.swift`
- `Sources/ZoidCoachInfrastructure/TodayDashboardAgent.swift`
- `Sources/ZoidCoachInfrastructure/TaskExecutionStore.swift`
- `Sources/ZoidCoachInfrastructure/TaskHistoryStore.swift`
- `Sources/ZoidCoachInfrastructure/ReminderSnapshotStore.swift`
- `Sources/ZoidCoachInfrastructure/AutonomousPlanStore.swift`
- `Sources/ZoidCoachInfrastructure/ActionOutboxStore.swift`
- `Sources/ZoidCoachInfrastructure/TodaySnapshotStore.swift`
- `Sources/ZoidCoachInfrastructure/LearningAggregateStore.swift`
- `Sources/ZoidCoachApp/AppModel.swift`
- `Sources/ZoidCoachApp/MenuBarCoachView.swift`

The minimum test claim is the matching store tests, migrator tests, TodayDashboardAgent tests, TodayDashboardXPC tests, AppModel tests, menu-bar controller tests, and the signed QA mutation lifecycle script and evidence directory.
The repair must keep the new raw-history regression and add mid-call BUSY release, persistent mid-call lock, lost XPC reply, helper restart, app relaunch, and raw-table cardinality assertions for every durable step.
