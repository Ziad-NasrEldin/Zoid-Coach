# Zoid Coach MVP

**Date:** 2026-07-09

**Product name:** Zoid Coach
**Goal:** Turn Screenwatch from a passive behavior log into an interactive AI work coach that helps Ziad choose, start, finish, and review work every day.

## 1. Core thesis

Zoid Coach should close the loop between intention and behavior:

```text
Intent → Estimate → Observe → Nudge → Adjust → Review
```

It should not only analyze the past. It should know what Ziad meant to do, watch what is actually happening, and intervene at the right level when gaming, drifting, or avoidance appears.

The system should behave like a supportive but firm daily manager:

- knows today’s tasks;
- asks for estimates;
- recommends the next best action;
- detects when behavior does not match the plan;
- nudges through macOS notifications and the Today dashboard;
- creates end-of-day and weekly reviews;
- learns Ziad’s real task timing and procrastination patterns.

## 2. MVP scope

The first version should be useful without building the entire final system.

### MVP includes

- Today’s tasks from Apple Reminders.
- Estimated time per task.
- Deadline / urgency.
- Current active task.
- Time spent working.
- Time spent gaming / distracting apps.
- AI recommendation: **“Do this next.”**
- End-of-day review.
- notification prompts and dashboard decisions.
- Screenwatch app/window metadata classification.
- Interruption levels 0–5.
- Gaming budget/reward logic.
- Morning planning flow.
- Task start/stop tracking.
- Weekly AI coach review.

### MVP explicitly excludes for now

- Current focus score.
- Hard app blocking by default.
- Complex team/project management.
- Cloud syncing.
- Public/web-hosted dashboard.

## 3. Data sources

### Apple Reminders

Apple Reminders is the source of truth for Ziad’s tasks.

Read:

- task title;
- list/project;
- due date;
- completion status;
- notes;
- priority, if available.

Zoid Coach stores extra local metadata beside each reminder.

Example task metadata:

```json
{
  "reminder_id": "apple-reminder-id",
  "title": "Edit video intro",
  "user_estimate_minutes": 45,
  "ai_estimate_minutes": 60,
  "deadline": "2026-07-09T15:00:00",
  "urgency": "today",
  "status": "not_started",
  "active": false,
  "last_prompted_at": null,
  "blocked_reason": null,
  "actual_minutes": 0
}
```

### Screenwatch

Screenwatch provides behavior telemetry:

- current app;
- window title;
- URL where available;
- screenshot references;
- active/idle timing;
- daily metadata log.

### Full local app list

Zoid Coach should inspect the Mac’s installed apps and classify them into buckets:

- Work;
- Communication;
- Admin;
- Research;
- Creative;
- Gaming;
- Entertainment;
- Distracting;
- System/neutral;
- Unknown.

The first pass can be rule-based. Unknown apps can be shown to Ziad later for correction.

## 4. Daily dashboard

The dashboard should be local-first and simple.

### Dashboard sections

#### Header

```text
Zoid Coach — Today
Thursday, July 9
```

#### Main objective

Shows the one most important thing to complete today.

```text
Main objective:
Finish client edit before 3:00 PM
```

#### Today’s tasks

Each task row shows:

- checkbox/status;
- task title;
- estimate;
- deadline;
- urgency;
- active/inactive state.

Example:

```text
[ ] Edit video intro — 45m — due today — High
[ ] Reply to client — 15m — due today — Medium
[ ] Ship landing page copy — 1h 30m — due tomorrow — Medium
```

#### Current active task

```text
Active task:
Edit video intro — 18m elapsed / 45m estimated
```

If no task is active:

```text
No active task. Recommended next: Reply to client, 15m.
```

#### Behavior summary

```text
Working time today: 2h 15m
Gaming/distracting time today: 1h 04m
Idle time: 32m
```

#### AI recommendation

```text
Do this next:
Start “Reply to client” now. It is short, due today, and will reduce anxiety quickly.
```

#### Gaming status

```text
Gaming budget: 60m/day
Used: 37m
Unlocked remaining: 23m
Next unlock: finish one priority task
```

## 5. Estimate collection

Zoid Coach should ask for a user estimate whenever a new Reminder task has no estimate.

Prompt:

```text
Ziad, how long do you think this will take?
“Edit thumbnail pack”
```

Quick options:

- 15m;
- 30m;
- 45m;
- 1h;
- Custom.

The system should store both:

- Ziad’s estimate;
- later actual time from Screenwatch/task tracking.

Over time it learns calibration patterns:

```text
You estimated 30m, but similar editing tasks usually take you 70m.
I recommend blocking 75m.
```

## 6. Behavior classification

Zoid Coach should classify what Ziad is doing using both rules and AI.

### Categories

- Deep work;
- Admin;
- Communication;
- Research;
- Creative work;
- Gaming;
- Passive consumption;
- Distracting;
- Idle;
- Unknown.

### Rule examples

Gaming examples:

- League of Legends;
- Riot Client;
- Steam;
- Battle.net;
- Epic Games Launcher;
- Discord when used around gaming context;
- Twitch;
- YouTube Shorts / entertainment contexts.

Work examples:

- Cursor;
- VS Code;
- Terminal;
- Hermes;
- Figma;
- Notion;
- Apple Reminders;
- browser work URLs;
- design/video tools.

### AI classification

Rules alone are not enough. The same app can be work or distraction.

Examples:

- YouTube tutorial for Swift launchd debugging = work/research.
- YouTube Shorts for 40 minutes = distraction.
- Discord client chat = communication/work maybe.
- Discord gaming server after launching League = distraction/gaming context.

The AI classifier should use:

- app;
- window title;
- URL;
- active task;
- recent history;
- selected screenshots only when needed.

## 7. Interruption levels

Interventions should be graded. Zoid Coach should not jump immediately to blocking.

### Level 0 — Observe

No interruption. Just log behavior.

Use when:

- user is on plan;
- behavior is ambiguous;
- task just started;
- gaming is within allowed budget.

### Level 1 — Gentle nudge

Example:

```text
You planned to work on “Edit video intro.” Want to start now?
```

### Level 2 — Accountability question

Example:

```text
You’ve been in League for 25m. Is this intentional?
```

Options:

- Continue intentionally;
- Start task;
- 5 more min;
- Break;
- Reschedule.

### Level 3 — Commit mode

Example:

```text
Pick one: 20m work sprint or reschedule the task.
```

Options:

- Start 20m sprint;
- Start full task;
- Reschedule;
- Mark blocked.

### Level 4 — Soft block

Show stronger notification warning / overlay.

Example:

```text
Gaming is now past your planned limit. Finish one priority task to unlock more.
```

### Level 5 — Hard block, optional only

Optional future mode.

Can quit/block selected apps/sites for a chosen period, but only after Ziad explicitly enables it.

Default: off.

## 8. Morning planning flow

Every morning, Zoid Coach should ask:

```text
Good morning Ziad. What are the 3 things that would make today successful?
```

It pulls today’s Reminders and proposes a plan.

Example:

```text
Suggested plan:
1. Finish client task — 90m
2. Edit video — 45m
3. Clean inbox — 20m

Total focused work: 2h 35m
Buffer: 1h
Gaming allowed after: 2 completed tasks
```

Options:

- Approve;
- Edit;
- Too much;
- Add gaming reward;
- Pick different top 3.

## 9. Task start/stop tracking

Ziad should be able to start a task manually from:

- dashboard;
- notification;
- command/prompt;
- maybe Apple Reminders note/link later.

When a task starts:

```text
Active task: Edit video intro
Estimated: 45m
Started: 10:30 AM
```

Zoid Coach watches whether behavior matches the active task.

Example mismatch:

```text
You started “Edit video intro” 4m ago but switched to League.
Was that intentional?
```

Options:

- Intentional;
- Return to task;
- Pause task;
- Mark blocked;
- Reschedule.

## 10. Gaming control system

Gaming should be managed as a budget/reward system, not pure punishment.

### Default gaming rule

```text
Gaming budget: 60m/day
Unlocked after: 2 priority tasks complete
```

### Reward mode

```text
Finish 90m focused work → unlock 30m gaming.
```

### Gaming debt

If gaming happens before work:

```text
You used 42m gaming before completing priority work.
To unlock more, finish one 30m sprint.
```

### Escape hatch

Ziad should always be allowed to override.

Example:

```text
I choose to game anyway.
```

The system logs it without moralizing.

End-of-day review can then say:

```text
You overrode 3 gaming nudges today.
Pattern: first override happened after checking Discord.
```

## 11. Notifications and dashboard integration

The Today dashboard is the main interactive surface, with notifications for timely interventions.

### Passive notification state

Examples:

```text
Next: Reply to client
Work: 2h 15m
Gaming: 37m
```

or compact:

```text
Zoid: Client reply · 15m
```

### Alerts

Example:

```text
You’ve been in League for 25m.
Continue or switch to your 45m video task?
```

Buttons:

- 5 more min;
- Start task;
- I’m done today;
- This is intentional.

### Questions

Example:

```text
How long will “Edit thumbnail pack” take?
```

Buttons:

- 15m;
- 30m;
- 1h;
- Custom.

### Accountability prompts

Example:

```text
You said you’d start this by 11:00. It’s 11:12. Start now?
```

Buttons:

- Start;
- Reschedule;
- Break;
- Blocked.

## 12. End-of-day review

Every night, Zoid Coach should generate a short review.

Example:

```text
Today summary:
Focused work: 2h 15m
Gaming: 1h 42m
Idle: 50m
Tasks completed: 3/7

Best work block:
11:10–12:05, Cursor, landing page

Main drift:
League started at 2:14 after opening Discord.

Tomorrow recommendation:
Do hardest task before opening Discord/League.
Set gaming unlock after 2 completed tasks.
```

Then ask:

```text
What is tomorrow’s main task?
```

## 13. Weekly AI coach review

Once a week, Zoid Coach should analyze patterns.

Example:

```text
Patterns:
- You underestimate coding tasks by 1.8x.
- Gaming usually starts after unclear tasks.
- You complete more when first task is under 30m.
- You avoid tasks with vague titles like “work on project.”

Recommendation:
- Break vague tasks automatically.
- Require estimates.
- Block gaming until one concrete deliverable is complete.
```

## 14. MVP implementation phases

### Phase 1 — Daily Command Center

Build:

- Apple Reminders import;
- local task metadata file;
- estimate prompts;
- dashboard page;
- current active task;
- time spent working/gaming;
- “Do this next” recommendation.

Success criteria:

- dashboard shows today’s Reminders;
- missing estimates are detected;
- Ziad can set estimates;
- Ziad can mark active task;
- system shows working/gaming totals from Screenwatch metadata.

### Phase 2 - Notification prompts

Build:

- send notification alerts;
- ask estimate questions;
- show start/reschedule/snooze buttons;
- show active task and gaming status.

Success criteria:

- new task without estimate triggers notification question;
- gaming drift triggers notification alert;
- starting a task from the notification updates local state.

### Phase 3 — Classification engine

Build:

- installed app inventory;
- app category rules;
- local config for app classifications;
- AI classifier for ambiguous cases;
- daily behavior totals.

Success criteria:

- League/Riot/Steam classify as gaming;
- Cursor/Terminal/Hermes classify as work;
- unknown apps are logged for review;
- dashboard totals are believable.

### Phase 4 — Gaming budget/reward logic

Build:

- daily gaming budget;
- unlock rules;
- gaming debt;
- override logging;
- optional soft-block prompts.

Success criteria:

- gaming before priorities creates a nudge;
- completed priority work unlocks gaming time;
- overrides are logged and summarized.

### Phase 5 — Reviews

Build:

- end-of-day summary;
- tomorrow planning prompt;
- weekly pattern review;
- estimate calibration report.

Success criteria:

- nightly review is generated from real Screenwatch + Reminders data;
- weekly review identifies at least 3 useful patterns;
- recommendations are actionable.

## 15. First MVP recommendation

Start with this exact build:

**Zoid Coach Daily Command Center**

It should:

1. Pull today’s Apple Reminders.
2. Ask for missing time estimates.
3. Pick or ask for top 3 tasks.
4. Show a dashboard with tasks, estimates, deadlines, active task, work time, gaming time, and “do this next.”
5. Use Screenwatch metadata to detect if League/gaming is active.
6. If gaming is active for more than 10 minutes while top tasks are incomplete, send a notification:

```text
Ziad, you still have “Edit video intro” estimated at 45m.
Do a 20m sprint now?
```

Buttons:

- Start 20m sprint;
- 5 more min;
- Reschedule;
- Ignore.

This is small enough to build first and powerful enough to matter immediately.
