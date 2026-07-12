# Required additions: Daily dashboard and execution loop

This document lists the dashboard requirements that must be added to the autonomous-coach implementation.
It is a companion delta, not a replacement for [AUTONOMOUS-COACH-IMPLEMENTATION-PLAN.md](AUTONOMOUS-COACH-IMPLEMENTATION-PLAN.md).

The autonomous plan remains the architecture authority.
The agent owns Core state, persistence, source ingestion, and all mutations.
The SwiftUI dashboard only renders agent snapshots and sends typed commands over XPC.

## 1. Today snapshot contract

Add one agent-owned `TodaySnapshot` returned to the app over XPC.

It must include:

- Local date and timezone.
- Main objective.
- Planned task rows.
- Current active task, if any.
- Recommended next task, if no task is active.
- Behavior summary and coverage state.
- Deterministic recommendation with reasons.
- Gaming budget status.
- Source freshness and degraded-state explanation.

The SwiftUI app must not calculate these values independently.

## 2. Exact dashboard reading order and sections

The Today command ledger must visibly render the following sections in order.

1. `Zoid 666 - Today`.
2. Formatted local date, such as `Thursday, July 9`.
3. Main objective.
4. Current active task, or the recommended-next fallback.
5. Today’s planned tasks.
6. Behavior summary.
7. `Do this next` recommendation.
8. Gaming budget status.
9. Raw or unplanned Reminders queue and source health below the action-first dashboard.

The first eight sections must be readable at the default app window size before the long unplanned Reminders inbox.

## 3. Required task-row fields

Each planned-task row must show:

- Completion or status control.
- Task title.
- Estimate.
- Relative deadline: overdue, due today, due tomorrow, or formatted date.
- Urgency: High, Medium, or Low.
- State: Ready, Active, Paused, Blocked, or Completed.

Use the agent’s normalized Reminder snapshot as the source of title, due date, priority, and completion.
Persist Zoid-owned metadata for estimate and optional urgency override.
Urgency must have a deterministic, documented mapping from deadline and EventKit priority.

## 4. Explicit active-task state machine

Add a Core-owned active-task lifecycle:

```text
ready -> active -> paused -> active
      -> blocked
      -> completed
      -> rescheduled
```

Requirements:

- Exactly one task can be active at a time.
- Starting a new task atomically pauses the existing active task.
- Persist append-only activity intervals.
- Elapsed time is closed intervals plus the current open interval.
- Relaunch or restart must restore the active task without double-counting time.
- Completing a task ends the active interval and refreshes the recommendation.
- Dashboard commands are Start, Pause, Resume, Complete, Block, and Reschedule.

Do not conflate an active task with a currently active Calendar block.
They are related but distinct user-intent states.

## 5. Behavior classification and truthful time totals

The autonomous plan needs an explicit first-pass classification taxonomy:

```text
work
gaming
distracting
idle
unknown
```

Add a deterministic sessionizer and daily aggregator:

- Session break after a configurable inactivity gap, initially five minutes.
- Cap abnormal observation duration.
- Never count absent telemetry as work, distraction, gaming, or idle.
- Retain `unknown` separately from `idle`.
- Show source coverage or `limited coverage` when Screenwatch is stale or unavailable.
- Allow user-editable application and domain classification rules later.

The dashboard behavior summary must show:

```text
Working time today
Gaming/distracting time today
Idle time
```

It may also show Unknown or limited coverage when relevant.

## 6. Deterministic next-task recommendation

The planner ranking is not enough.
Add a dedicated `NextTaskRecommendation` result for the live dashboard.

When no task is active, choose from incomplete planned tasks using deterministic inputs:

- Overdue or due-today pressure.
- Urgency.
- Estimate fit for the available time.
- Main-objective bonus.
- Explicit user locks.
- Blocked state.
- Recent relevant work context, when trustworthy.
- Stable deterministic tie-breaking.

Return:

- Recommended task ID.
- Short recommendation sentence.
- Structured reason codes.
- Source-coverage uncertainty.

Example UI:

```text
No active task. Recommended next: Reply to client, 15m.

Do this next:
Start “Reply to client” now. It is short, due today, and will reduce anxiety quickly.
```

The AI-provider boundary may later improve wording or bounded semantic inputs.
This result must always work without an AI provider.

## 7. Gaming policy and reward accounting

This is absent from the autonomous plan.

Add an agent-owned `GamingPolicy` and daily `GamingStatus`.

Initial policy:

```text
Daily budget: 60 minutes
Used: derived only from classified gaming sessions
Unlocked remaining: max(0, available allowance - used)
Next unlock: finish one priority task
```

Requirements:

- Timezone-safe daily reset.
- Persisted policy version and daily ledger.
- Gaming time comes from classified sessions, never raw app time directly.
- One configured priority-task reward can apply only once.
- Display `budget`, `used`, `unlockedRemaining`, and `nextUnlockReason`.
- No blocking or enforcement in this delivery.
- Source gaps lower confidence instead of inventing exact gaming time.

## 8. Dashboard data model

Add these Core types, or equivalents:

```text
TodaySnapshot
TodayTaskRow
TaskUrgency
TaskExecutionState
ActiveTaskSnapshot
BehaviorSummary
TelemetryCoverage
NextTaskRecommendation
GamingPolicy
GamingStatus
```

`TodaySnapshot` is read-only to the app.
Mutations go through typed XPC commands owned by `ZoidCoachAgent`.

## 9. Acceptance tests specific to the dashboard

Add deterministic tests for:

1. Task urgency mapping from due date and EventKit priority.
2. One-active-task invariant.
3. Pause, resume, and relaunch elapsed-time correctness.
4. Completing an active task ends its interval and changes the recommendation.
5. Stale or missing Screenwatch produces limited coverage, not fake totals.
6. Replay fixture produces correct work, gaming or distracting, idle, and unknown totals.
7. Gaming budget reset, used-time accounting, reward-once behavior, and remaining balance.
8. Stable recommendation tie-breaking and blocked-task exclusion.
9. `TodaySnapshot` carries all required fields through XPC.
10. Native visual pass: header through gaming status appears before the raw Reminders queue at default window size.

## 10. Scope guard

Gaming status is informational in this phase.
Do not add game blocking, enforcement, Calendar automation dependencies, WhatsApp dependencies, or AI-provider dependencies to deliver this dashboard.
