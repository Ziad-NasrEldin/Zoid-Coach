# Zoid Coach Product Specification

## Document control

| Field | Value |
| --- | --- |
| Product | Zoid Coach |
| Document type | Product requirements and reference architecture specification |
| Status | Draft with initial founder decisions incorporated |
| Version | 0.3.0 |
| Date | 2026-07-09 |
| Primary user | Ziad |
| Deployment model | Local-first macOS application |
| Canonical source | This document |
| Supersedes | None |
| Related concept | `docs/ZOID-COACH-MVP.md` |

### Decision labels

- **DECIDED** means the existing product concept or inspected source makes the direction sufficiently clear.
- **RECOMMENDED** means this specification proposes the direction because it best satisfies product and engineering goals.
- **OPEN** means founder input or source validation can materially change the implementation.
- **DEFERRED** means the capability is intentionally excluded from the first release.

### Purpose of this document

This document defines the product, behavior, user experience, data model, coaching policy, architecture, integration contracts, privacy model, failure handling, testing strategy, and release plan for Zoid Coach.

It is written to be implementable by a product and engineering team without requiring the original concept conversation.

It preserves the original MVP thesis while making implicit choices explicit.

It separates confirmed source capabilities from proposed product behavior.

It identifies inputs that should be provided by Ziad before particular milestones, without blocking initial implementation.

### Founder decisions incorporated on 2026-07-09

| Decision | Selected direction |
| --- | --- |
| Product shape | Standalone macOS application |
| Visual system | Use the Sumi-Ink Command System |
| Atoll actions | Extend AtollExtensionKit and Atoll with native action descriptors and callbacks |
| Release 1 AI | Rules only |
| Initial coaching intensity | Observe for one week, then enable level 2 coaching |
| Screenwatch ownership | Consolidate the Screenwatch source into the Zoid Coach repository |
| Reminders list structure | To be determined during implementation setup |
| Work schedule | Not fixed, so the product must support flexible planning and user-configurable work windows |
| Coaching language | Product team may define the appropriate language within the voice and safety rules in this specification |

All foundational product-shape decisions requested in the first review are now resolved.

## 1. Executive summary

Zoid Coach is a local-first macOS productivity coach that compares intended work with observed computer behavior and delivers the smallest useful intervention at the right time.

Apple Reminders represents intention.

Screenwatch represents observed behavior.

Zoid Coach combines those inputs into task state, behavior sessions, recommendations, interventions, and reviews.

Atoll provides a persistent and timely notch surface for passive status and interactive prompts.

The product closes this loop:

```text
Intent -> Estimate -> Observe -> Interpret -> Nudge -> Adjust -> Review -> Learn
```

The product is not a conventional task manager.

It is not a surveillance dashboard.

It is not a punitive app blocker.

It is a private behavioral feedback system designed to help one person choose, start, continue, finish, and learn from work.

The first release focuses on a Daily Command Center and one reliable coaching loop:

1. Import today's Apple Reminders.
2. Collect missing estimates.
3. Select the top three tasks and a main objective.
4. Start one active task.
5. Interpret Screenwatch telemetry into work, gaming, distraction, idle, and unknown sessions.
6. Detect sustained gaming while priority work is incomplete.
7. Present a graded Atoll prompt with explicit choices.
8. Record the response and update task or gaming state.
9. Produce an end-of-day review from actual events.

The system must remain useful when AI is unavailable.

Rules, local state, and deterministic fallbacks must support all critical flows.

AI improves ambiguity resolution, recommendations, summaries, and pattern discovery.

AI must not be the sole authority for task state, time accounting, permissions, blocking, or irreversible actions.

## 2. Product thesis

### 2.1 Problem statement

Task lists capture what a person intends to do, but they do not observe whether the person has started, drifted, become blocked, or switched to avoidance behavior.

Screen activity logs capture what happened, but passive logs arrive too late to change the day.

Generic productivity tools often require repeated manual maintenance, introduce guilt, or apply rigid blocking without understanding context.

Ziad needs a system that knows today's commitments, understands enough of the current computer context, and intervenes proportionally before a small drift becomes a lost afternoon.

### 2.2 Product hypothesis

If Zoid Coach combines explicit daily intent with low-latency behavioral telemetry, then it can identify meaningful divergence early enough to help Ziad recover.

If its interventions are brief, specific, respectful, and graded, then the coach can increase completed priority work without becoming annoying or adversarial.

If estimates, actions, overrides, and outcomes are recorded over time, then the coach can learn which task shapes and environmental triggers lead to completion or avoidance.

### 2.3 Core value proposition

Zoid Coach answers four questions continuously:

1. What matters today?
2. What is Ziad doing now?
3. Is current behavior aligned with the plan?
4. What is the smallest helpful next action?

### 2.4 Product promise

Zoid Coach should make the next responsible action easier to see and easier to begin.

It should increase awareness without creating shame.

It should help convert vague intentions into concrete, timed commitments.

It should use past behavior to improve future plans.

## 3. Goals and success outcomes

### 3.1 Primary product goals

- Help Ziad choose a realistic daily plan from Apple Reminders.
- Ensure every selected priority task has a usable time estimate or size classification.
- Make one active task visible across the dashboard and notch.
- Convert raw Screenwatch records into believable behavior sessions.
- Detect important mismatches between active task and observed behavior.
- Deliver timely interventions without excessive interruption.
- Treat gaming as an explicit budget and reward choice.
- Create factual end-of-day and weekly reviews.
- Learn estimation bias, avoidance triggers, and recovery patterns.
- Keep sensitive behavioral data local by default.

### 3.2 User outcomes

The product succeeds when Ziad can say:

- I know the most important task for today.
- I know what to do next without reopening multiple systems.
- I start priority work earlier.
- I notice gaming or drift before it consumes too much time.
- I can override the coach without being punished or moralized at.
- My estimates become more realistic.
- My weekly review tells me something useful that I did not already know.

### 3.3 Business and product outcomes

The first product is a single-user personal system.

It should prove that the closed-loop coaching model creates sustained value before introducing accounts, teams, cloud sync, or a commercial plan.

The architecture should keep a future multi-user product possible without making the MVP depend on cloud infrastructure.

### 3.4 Initial quantitative targets

These targets are hypotheses and must be reviewed after a two-week baseline period.

| Metric | Initial target |
| --- | --- |
| Daily plan completion | At least 5 planned days per week |
| Priority-task estimate coverage | At least 90 percent |
| Active-task tracking coverage | At least 70 percent of focused work time |
| Intervention response rate | At least 70 percent within 5 minutes |
| Useful intervention rate | At least 60 percent marked helpful or followed by work recovery |
| False gaming alert rate | Below 10 percent |
| End-of-day review completion | At least 4 days per week |
| Priority-task completion improvement | At least 20 percent over baseline after 4 weeks |
| Median telemetry-to-state latency | Below 15 seconds |
| Local data loss | Zero confirmed losses of task metadata or user decisions |

## 4. Non-goals

### 4.1 MVP non-goals

- Replacing Apple Reminders as the canonical task system.
- Building a general-purpose project management platform.
- Supporting teams, managers, shared workspaces, or permissions between users.
- Hosting a public web dashboard.
- Syncing behavioral screenshots to the cloud by default.
- Computing a single opaque focus score.
- Blocking applications without explicit configuration and consent.
- Diagnosing medical or psychological conditions.
- Claiming that activity classification is always correct.
- Automatically completing or deleting reminders based only on observed behavior.
- Making AI-generated judgments irreversible.
- Monitoring other people or devices.
- Capturing microphone, camera, keystrokes, message bodies, or document contents.

### 4.2 Deferred product directions

- Mobile companion application.
- Cross-device behavior correlation.
- Calendar auto-scheduling.
- Team accountability and social features.
- Public templates or coaching marketplace.
- Browser extension beyond metadata already available to Screenwatch.
- Hard website and application blocking as a default behavior.
- Automated task decomposition that writes multiple Reminders without review.

## 5. Product principles

### 5.1 Local-first by default

Task metadata, telemetry, screenshots, classifications, intervention history, and reviews remain on the Mac unless Ziad explicitly enables a remote AI request or future sync feature.

### 5.2 Intent before inference

The user's selected task and explicit choices outrank inferred behavior.

The system should ask when ambiguity matters.

### 5.3 Smallest useful intervention

The coach should begin with observation or a gentle nudge.

It should escalate only when evidence, timing, user settings, and recent response history justify escalation.

### 5.4 Firm without shame

Copy should be direct, factual, and action-oriented.

It must not use insults, guilt, disappointment, moral labels, or exaggerated claims.

### 5.5 Override is a valid decision

Ziad can choose to continue gaming, ignore a prompt, end the workday, or reschedule a task.

The system records the choice and adapts later rather than fighting immediately.

### 5.6 Explain important recommendations

Every recommended next task should show a short reason based on deadline, importance, duration, dependency, energy fit, or recent avoidance.

### 5.7 Deterministic core, AI-assisted edge

Critical state changes and policy enforcement use deterministic logic.

AI handles natural-language interpretation, ambiguity, summarization, and pattern generation within validated schemas.

### 5.8 Honest uncertainty

Unknown activity remains unknown until sufficient evidence or user correction exists.

The product must not fabricate confidence.

### 5.9 Attention is a limited resource

Prompts must have cooldowns, daily caps, deduplication, and quiet periods.

### 5.10 Data minimization

The product stores only the data required to provide coaching and explain its decisions.

## 6. Users and operating context

### 6.1 Primary persona

The initial primary user is Ziad, a macOS power user who works across software development, design, media, client communication, research, and administration.

He uses Apple Reminders for intended work, spends substantial time in desktop applications and browsers, and wants more control over gaming and ambiguous drift.

He is comfortable granting local permissions when the value and privacy boundary are clear.

He expects direct control, technical transparency, and evidence that integrations actually work.

### 6.2 Secondary future persona

A future user may be an independent knowledge worker who wants private behavioral coaching without employer monitoring or cloud-first tracking.

This persona is not a release requirement, but the product language and data model should avoid unnecessary hard-coding to one person's name.

### 6.3 Environmental assumptions

- The primary device is a Mac running macOS 14.6 or later.
- Apple Reminders is available and contains the user's actionable tasks.
- Screenwatch is installed and writing local telemetry.
- Atoll is installed for notch presentation.
- The Mac may sleep, change displays, lose network access, or restart during a work session.
- The user may work across multiple projects and browser profiles.
- The user may intentionally game during the day.
- Some work occurs away from the Mac and cannot be inferred from Screenwatch.

## 7. Jobs to be done

### 7.1 Plan the day

When I begin my workday, help me turn my due and available tasks into a realistic top three so I know what success looks like.

### 7.2 Start work

When I am hesitating or moving between apps, give me one concrete task and a short starting commitment so beginning feels manageable.

### 7.3 Stay aligned

When my observed behavior no longer matches my active task, help me decide whether to return, pause, reschedule, or continue intentionally.

### 7.4 Manage gaming deliberately

When I want to game, show me the budget and consequences clearly so gaming becomes a conscious choice rather than an untracked escape.

### 7.5 Recover from drift

When I have already drifted, help me recover through a small sprint instead of treating the day as lost.

### 7.6 Learn from the day

When the workday ends, summarize what happened accurately and help me choose one improvement for tomorrow.

### 7.7 Improve planning accuracy

When I estimate future tasks, use my actual history to identify recurring underestimation or overestimation.

## 8. Terminology

| Term | Definition |
| --- | --- |
| Active task | The single task Ziad has explicitly chosen to work on now |
| Priority task | A task selected as part of today's top three or main objective |
| Main objective | The most important outcome for the day |
| Behavior record | One raw Screenwatch JSONL observation |
| Behavior session | A contiguous normalized interval derived from behavior records |
| Classification | A category and confidence assigned to a behavior session |
| Alignment | The assessed relationship between observed behavior and the active task |
| Drift | Sustained behavior that is inconsistent with the current plan and is not an accepted break |
| Intervention | A coach message or surface intended to cause a user decision |
| Prompt episode | One intervention and its subsequent updates, response, timeout, or dismissal |
| Work sprint | A bounded active-task commitment, usually 10 to 45 minutes |
| Gaming budget | Time available for intentional gaming under the current daily policy |
| Gaming debt | Gaming time used before required work conditions were satisfied |
| Override | An explicit choice to continue behavior despite a recommendation |
| Evidence | The task, telemetry, policy, timing, and history used to support a decision |
| Review | A generated daily or weekly summary grounded in recorded events |

## 9. Scope and release strategy

### 9.1 Release 0: Instrumented foundation

Release 0 proves that data can be imported, normalized, persisted, inspected, and replayed safely.

It includes no autonomous coaching beyond developer-visible test notifications.

Required capabilities:

- Read Apple Reminders with EventKit.
- Consolidate the current Screenwatch capture source into the Zoid Coach repository under a clearly owned integration boundary.
- Read the Screenwatch JSONL stream incrementally.
- Persist local task metadata and normalized behavior sessions.
- Display data-source health.
- Replay a recorded day through the behavior pipeline.
- Verify Atoll authorization and present a test activity.

### 9.2 Release 1: Daily Command Center

Release 1 is the first useful product.

Required capabilities:

- Morning planning.
- Top three selection.
- Main objective.
- Missing estimate collection.
- Active task start, pause, resume, complete, block, and reschedule.
- Work, gaming, distraction, idle, and unknown totals.
- Deterministic next-task recommendation.
- Rules-only behavior classification and review generation.
- One gaming-drift coaching loop.
- Basic end-of-day review.

Release 1 must not depend on a local or remote language model.

The first seven complete days run in observation mode before level 2 accountability prompts become active.

### 9.3 Release 2: Adaptive coaching

Release 2 improves context and personalization.

Required capabilities:

- Richer contextual rules, with hybrid rule and AI classification only after a separate Release 2 approval.
- Alignment inference.
- Graded intervention state machine.
- Prompt cooldown and fatigue controls.
- Gaming budget and reward policies.
- Estimate calibration.
- Daily review improvements.

### 9.4 Release 3: Weekly learning

Release 3 adds longer-term pattern discovery.

Required capabilities:

- Weekly review.
- Pattern evidence and confidence.
- User corrections and learned app rules.
- Recommendation experiments.
- Configurable coaching modes.

### 9.5 Release 4: Optional enforcement

Release 4 may add explicit soft or hard blocking after the coaching model has proven useful.

Blocking remains opt-in, reversible, time-bounded, and protected by an escape hatch.

## 10. System context

```text
Apple Reminders ----> Task Sync Adapter -----+
                                             |
Screenwatch JSONL --> Telemetry Adapter ------+--> Local Event Store
                                             |          |
Installed Apps -----> App Inventory ----------+          v
                                                   Sessionization
                                                        |
                                                        v
                                                Classification Engine
                                                        |
                         +------------------------------+------------------+
                         |                              |                  |
                         v                              v                  v
                 Recommendation Engine         Intervention Policy    Review Engine
                         |                              |                  |
                         +------------------------------+------------------+
                                                        |
                                  +---------------------+------------------+
                                  |                     |                  |
                                  v                     v                  v
                              Dashboard          Atoll Notch         Local Reports
```

### 10.1 Source-of-truth boundaries

Apple Reminders is the source of truth for task identity, title, list, notes, due date, priority, and completion.

Zoid Coach is the source of truth for estimates, active-task history, daily selection, coaching settings, behavior sessions, intervention history, gaming policy, and reviews.

Screenwatch is the source of truth for raw local behavior observations.

Atoll is a presentation and interaction host, not a source of product state.

The local Zoid Coach database is the source of truth for all derived state.

## 11. Product surfaces

### 11.1 Menu bar status

The menu bar item is the persistent entry point when the main window is closed.

It shows one compact state indicator:

- Neutral when the system is healthy and no task is active.
- Active when a task or sprint is running.
- Warning when a source is unavailable or attention is needed.
- Paused when coaching is paused.

The menu includes:

- Open Today.
- Start recommended task.
- Pause or resume active task.
- Start a break.
- Pause coaching.
- End workday.
- Data-source health.
- Settings.

### 11.2 Today dashboard

The Today dashboard is the main command center.

It prioritizes action over analytics.

The default reading order is:

1. Current state and date.
2. Main objective.
3. Active task or recommended next task.
4. Top three tasks.
5. Remaining tasks.
6. Work, gaming, distraction, and idle totals.
7. Gaming budget status.
8. Recent coach decisions.
9. Source health and sync state.

### 11.3 Atoll notch surface

Atoll is the timely interaction surface.

It supports three product modes:

- Passive status for the active task and elapsed time.
- Sneak-peek intervention for short alerts.
- Expanded interactive prompt for decisions.

The notch must never become the only way to respond.

Every prompt must also be available in the dashboard and menu bar.

### 11.4 Planning surface

The planning surface guides top-three selection, estimates, total workload, breaks, and gaming rules.

It may appear as a dashboard mode rather than a separate window.

### 11.5 Review surface

The review surface presents factual summaries, patterns, corrections, and one recommended change.

The user can correct classification, timing, and causal claims before a review becomes part of learning history.

### 11.6 Settings surface

Settings contain permissions, data sources, work schedule, classification rules, coaching mode, gaming policy, privacy, AI configuration, data retention, exports, and diagnostics.

## 12. End-to-end daily lifecycle

### 12.1 Day states

The day follows this state model:

```text
Unplanned -> Planning -> Planned -> Active -> Reviewing -> Closed
                  |          |          |
                  |          |          +-> Paused
                  |          +-> Replan
                  +-> Skip planning
```

### 12.2 Start of day

The day begins at the configured planning time or when Zoid Coach first becomes active during the configured work window.

If the day is unplanned, the system presents a low-pressure planning invitation.

The system must not issue drift interventions before the user has either approved a plan or explicitly chosen to work without one.

### 12.3 Planned work

After planning, the system recommends the first task.

The user may start the recommendation, choose another task, or delay the plan.

When a task starts, Zoid Coach begins active-task tracking and waits through a configurable grace period before evaluating alignment.

### 12.4 Midday adaptation

The plan can change without treating the change as failure.

Triggers for replanning include:

- A task taking substantially longer than estimated.
- A priority task becoming blocked.
- A new urgent Reminder.
- A calendar or work-window change.
- The user marking the day as low energy.
- More than two ignored or overridden prompts.

### 12.5 End of day

The day enters review when the user ends the workday, the configured review time arrives, or no work activity occurs for a configurable late-day period.

The review summarizes evidence and asks for corrections.

After confirmation or timeout, the day closes and the next-day main task may be selected.

## 13. Onboarding and permissions

### 13.1 Onboarding goals

Onboarding must establish value before asking for every permission.

It must explain what each source contributes, what data remains local, and how to disable it.

### 13.2 Required onboarding steps

1. Welcome and product promise.
2. Local-first privacy explanation.
3. Apple Reminders permission.
4. Screenwatch source discovery.
5. Atoll installation and authorization check.
6. Installed-app inventory preview.
7. Initial work and gaming classifications.
8. Work schedule and quiet hours.
9. Initial gaming policy.
10. AI provider choice or rules-only mode.
11. Test task and test notch prompt.
12. Finish with the first daily plan.

### 13.3 Permission requirements

| Permission or authorization | Required | Purpose | Degraded behavior |
| --- | --- | --- | --- |
| Reminders full access | Required for core value | Read tasks and update completion | Manual local tasks only |
| Screenwatch folder read access | Required for behavior coaching | Read JSONL telemetry and optional screenshot references | Planning and task tracking only |
| Atoll extension authorization | Optional but strongly recommended | Show live activities and prompts in the notch | Dashboard and native notifications |
| Notifications | Optional | Deliver fallback prompts and reviews | In-app prompts only |
| Launch at login | Optional | Maintain timely coaching | User starts app manually |
| Network access | Optional | Remote AI calls and model updates | Rules-only and local model behavior |
| Accessibility | Not required for MVP | Future app control or blocking | No hard app control |

### 13.4 Permission denial behavior

The app must never loop permission dialogs.

After denial, the relevant screen shows the impact, current status, and a direct route to System Settings.

The user can continue in a degraded mode.

### 13.5 Source discovery

The Screenwatch adapter should check the default path first.

The default path is `~/screenwatch/days/YYYY-MM-DD/log.jsonl`.

If no valid stream exists, the user can choose a folder.

The app validates the schema without displaying sensitive titles or URLs during onboarding.

## 14. Apple Reminders integration

### 14.1 Integration approach

**RECOMMENDED:** Use EventKit directly from a native macOS process.

This provides supported authorization, stable reminder identifiers, list metadata, due dates, priorities, and completion updates.

### 14.2 Imported fields

The adapter imports:

- Calendar item identifier.
- External identifier where available.
- Title.
- Notes.
- List identifier and name.
- Due date components.
- Start date if available.
- Priority.
- Completion status and completion date.
- Creation and last-modified dates where available.
- Recurrence metadata.
- URL where available.

### 14.3 Task eligibility

A Reminder is eligible for the Today dashboard when any of the following is true:

- It is due today.
- It is overdue and incomplete.
- It is manually selected for today.
- It belongs to a configured Today list.
- It has no due date but was carried into today by the user.

Completed tasks are hidden from the active list but retained in the day's history.

### 14.4 Sync behavior

The app performs a full initial sync after authorization.

It then refreshes on EventKit store-change notifications, app activation, and a low-frequency fallback timer.

Sync must be idempotent.

The adapter stores source snapshots separately from local coaching metadata.

### 14.5 Conflict rules

Apple Reminders always wins for source-owned fields.

Zoid Coach always wins for local-only metadata.

If a Reminder is deleted while active, Zoid Coach pauses the task and asks whether to preserve it as a local historical task.

If a Reminder becomes complete outside Zoid Coach, the active task ends with reason `completed_externally`.

If Zoid Coach marks a Reminder complete and EventKit rejects the save, the task remains locally pending and a retry banner appears.

### 14.6 Recurring reminders

Each recurrence occurrence must be treated as a distinct logical task instance when EventKit provides a stable occurrence identity.

Local estimate history may be shared through a task-series key.

Completing one occurrence must not mutate future occurrence metadata.

### 14.7 Reminder writes

MVP writes are limited to completion status and, after explicit confirmation, due-date rescheduling.

The app must not rewrite titles, notes, lists, or priorities automatically.

## 15. Local task metadata

### 15.1 Required fields

Every task instance may have:

- User estimate in minutes.
- AI estimate in minutes.
- Estimate confidence.
- Actual active minutes.
- Actual aligned minutes.
- Daily rank.
- Main-objective flag.
- Planned start window.
- Energy requirement.
- Task type.
- Status.
- Blocked reason.
- Deferral reason.
- First-start timestamp.
- Last-start timestamp.
- Completion timestamp.
- Prompt counters.
- User tags.

### 15.2 Task statuses

```text
available -> selected -> active -> paused -> active
    |           |          |        |
    |           |          |        +-> blocked
    |           |          +-> completed
    |           +-> deferred
    +-> completed_externally
```

Valid statuses are:

- `available`
- `selected`
- `active`
- `paused`
- `blocked`
- `deferred`
- `completed`
- `completed_externally`
- `cancelled`
- `source_deleted`

### 15.3 Single active task invariant

At most one task may be active at a time.

Starting a new task requires pausing or completing the previous active task in the same transaction.

## 16. Morning planning

### 16.1 Triggering

Planning appears at the configured start time when the Mac is active.

If the Mac is inactive, it appears on the first active session within the work window.

The prompt can be snoozed without starting a coaching escalation.

### 16.2 Planning inputs

The planning engine considers:

- Overdue tasks.
- Tasks due today.
- User-selected available tasks.
- Reminder priority.
- Existing estimates.
- Historical actual duration.
- Planned work window.
- Calendar busy time when Calendar integration is later enabled.
- Carryover from yesterday.
- Blocked status.
- User energy selection.

### 16.3 Planning output

The default plan contains:

- One main objective.
- Three priority tasks.
- Estimated focused-work total.
- Buffer time.
- Suggested task order.
- First recommended task.
- Gaming unlock rule.

### 16.4 Capacity warning

If planned task estimates exceed available focus capacity, the system must say so before approval.

The product should offer concrete reductions rather than a generic warning.

Example:

```text
Your selected work totals 5h 40m, but your configured focus capacity is 3h 30m.
Move one 90m task to tomorrow or mark it optional.
```

### 16.5 Planning actions

- Approve plan.
- Reorder tasks.
- Change main objective.
- Add or remove a task.
- Add an estimate.
- Mark a task blocked.
- Mark a task optional.
- Reduce the day.
- Skip planning.
- Set a gaming unlock condition.

### 16.6 Skip behavior

If planning is skipped, Zoid Coach enters a limited `unplanned` coaching mode.

It may show overdue tasks and behavior totals, but it must not claim that behavior violates a plan that does not exist.

## 17. Estimate collection and calibration

### 17.1 Estimate prompt

Every selected priority task requires an estimate.

Quick choices are 15, 30, 45, 60, 90, and custom minutes.

The user can select `unknown`, but the planning engine assigns a conservative placeholder and marks uncertainty.

### 17.2 AI estimate

An AI estimate is advisory.

It may use task title, notes after redaction, project, task type, and historical similar-task durations.

It must not silently replace the user estimate.

### 17.3 Calibration ratio

For completed tasks with sufficient tracking coverage:

```text
calibration_ratio = actual_aligned_minutes / user_estimate_minutes
```

Ratios are grouped by task type, project, and optional semantic similarity.

Outliers caused by long pauses, abandoned tasks, or missing telemetry are excluded.

### 17.4 Calibration messages

The system may say:

```text
You estimated 30 minutes.
Your last four similar editing tasks took 55 to 80 minutes.
I recommend reserving 70 minutes.
```

The message must include sample size and uncertainty when making a historical claim.

## 18. Active task and sprint tracking

### 18.1 Start actions

A task can start from:

- Today dashboard.
- Menu bar.
- Atoll prompt.
- Recommended-next card.
- Keyboard shortcut.

### 18.2 Start transaction

Starting a task must:

1. Pause any active task.
2. Create an active-task session.
3. Record the chosen commitment duration if any.
4. Present or update the Atoll live activity.
5. Begin an alignment grace period.
6. Emit a `task_started` event.

### 18.3 Sprint modes

Supported commitments are:

- Open-ended task session.
- 10-minute recovery sprint.
- 20-minute work sprint.
- 25-minute focus sprint.
- Custom sprint.
- Full estimated task block.

### 18.4 Pause reasons

- Break.
- Blocked.
- Switching tasks.
- External interruption.
- Done for now.
- End of workday.

### 18.5 Completion

Completing a task ends its active session, records actual time, and attempts to complete the Apple Reminder.

The user may complete a task even if observed aligned time is low.

Observed behavior never vetoes explicit completion.

### 18.6 Away-from-Mac work

The user can mark a task session as `offline_work`.

Offline work counts toward actual task time but not Screenwatch-derived aligned time.

## 19. Screenwatch integration

### 19.1 Confirmed source behavior

The inspected Screenwatch capture loop writes one JSON object per active interval to a daily JSONL file.

Observed fields are:

```json
{
  "t": "10-21-09",
  "epoch": 1783581587,
  "app": "Application Name",
  "window": "Front Window Title",
  "url": "https://example.test/path",
  "img": true
}
```

The installed loop uses a five-second interval.

It skips records after 90 seconds of input idle time.

It records metadata every tick and captures an image on context change or every sixth unchanged tick.

It prunes day directories older than 30 days.

### 19.2 Adapter responsibilities

The adapter must:

- Discover the current daily log.
- Tail appended records without repeatedly parsing the whole file.
- Persist byte offset and source identity.
- Validate required fields.
- Tolerate truncated final lines.
- Detect file replacement and day rollover.
- Ignore exact duplicate records.
- Normalize timestamps to an absolute local instant.
- Record parse failures without exposing content in logs.
- Avoid opening screenshot files until a classification request explicitly needs one.

### 19.3 Cursor state

The adapter stores:

- Canonical file path.
- File system identifier where available.
- Last processed byte offset.
- Last processed epoch.
- Last record fingerprint.
- Last successful read time.
- Current health state.

### 19.4 Source health states

- `healthy`
- `waiting_for_first_record`
- `stale`
- `missing`
- `permission_denied`
- `schema_mismatch`
- `parse_error`
- `clock_anomaly`

### 19.5 Stale threshold

During an active Mac session, a stream is stale when no valid record arrives for 30 seconds and the system is not idle or asleep.

The threshold must be configurable for tests.

### 19.6 Screenshot policy

Screenshots are not required for routine classification.

The default pipeline uses app, title, URL host, URL path classification rules, active task, and recent history.

A screenshot may be inspected only when:

- The classification remains ambiguous.
- The result can materially change an intervention.
- The screenshot exists within the allowed retention period.
- The relevant privacy setting permits screenshot analysis.

Screenshot pixels must not be copied into the Zoid Coach database.

Only the source path, analysis timestamp, model identifier, redaction policy, and resulting structured evidence may be stored.

## 20. Behavior sessionization

### 20.1 Purpose

Raw five-second records are too granular for product reasoning.

The sessionizer converts records into contiguous behavior sessions.

### 20.2 Session boundary rules

A new session begins when any of the following occurs:

- The frontmost application changes.
- The normalized URL host or rule-relevant path changes.
- The window title changes materially.
- The record gap exceeds the continuity threshold.
- The device transitions into or out of idle or sleep.
- The current day changes.
- A manual correction creates an explicit boundary.

### 20.3 Title normalization

Normalization may remove volatile counters, timestamps, unread badges, progress percentages, and known document-save markers.

Raw titles remain in the raw record store only for the configured retention period.

### 20.4 Gap handling

Gaps under 20 seconds may be bridged when the surrounding normalized context matches.

Longer gaps become unknown or idle intervals depending on system evidence.

The system must not assume work continued across sleep.

### 20.5 Session correction

The user can reclassify a session, split it, merge adjacent sessions, or attach it to a task.

Corrections update derived totals and create auditable correction events.

## 21. Behavior classification

### 21.1 Classification taxonomy

Every behavior session has one primary category:

- `deep_work`
- `creative_work`
- `research`
- `communication`
- `administration`
- `gaming`
- `entertainment`
- `passive_consumption`
- `distraction`
- `system_neutral`
- `idle`
- `unknown`

It may also have secondary tags such as project, client, task type, browser context, or gaming context.

### 21.2 Classification result

A result contains:

- Primary category.
- Confidence from 0 to 1.
- Rule or model source.
- Evidence codes.
- Optional project or task association.
- Whether user confirmation is required.
- Model version or rule-set version.

### 21.3 Classification precedence

The order of authority is:

1. User correction for an exact or learned rule.
2. Explicit active-task application or domain mapping.
3. High-specificity local rule.
4. Contextual deterministic rule.
5. AI structured classification.
6. Unknown.

### 21.4 Rule examples

High-confidence gaming rules may include League of Legends, Riot Client game windows, Steam games, Battle.net games, and Epic Games launches.

High-confidence work rules may include configured IDE projects, terminals associated with known repositories, design tools, editing tools, and work domains.

Applications such as browsers, Discord, Slack, Notion, YouTube, and Preview remain context-dependent.

### 21.5 AI classifier input

The AI classifier receives the minimum required context:

- Normalized application name.
- Redacted window title.
- URL host and optionally a redacted path.
- Active task title or redacted semantic description.
- Previous and next session categories.
- Recent application transition sequence.
- Applicable local rules.
- Optional screenshot analysis result.

### 21.6 AI classifier output contract

```json
{
  "category": "research",
  "confidence": 0.82,
  "task_alignment": "likely_aligned",
  "evidence_codes": ["tutorial_topic_matches_task", "browser_context"],
  "requires_confirmation": false,
  "explanation": "The page topic matches the active Swift debugging task."
}
```

The output must validate against a closed schema.

Invalid or unrecognized output becomes `unknown`.

### 21.7 Confidence thresholds

- At or above 0.85 may be used for automatic totals and intervention evidence.
- From 0.60 through 0.84 may be used for totals but requires corroborating evidence before escalation above level 1.
- Below 0.60 remains unknown unless a deterministic rule applies.

Thresholds must be adjustable after baseline evaluation.

### 21.8 Learning from corrections

A user correction may create:

- An exact application rule.
- An application and window-title pattern.
- A URL-host rule.
- A URL-path prefix rule.
- A project association.
- A one-time correction.

The user must see the proposed rule scope before saving a persistent rule.

## 22. Task alignment

### 22.1 Alignment states

- `aligned`
- `likely_aligned`
- `neutral`
- `likely_misaligned`
- `misaligned`
- `unknown`
- `accepted_break`

### 22.2 Alignment evidence

Alignment may use:

- Active-task project mapping.
- Known application or repository mapping.
- URL or window-title semantic match.
- Task type and application category.
- Recent manual task start.
- User-declared break.
- User correction.
- AI semantic comparison.

### 22.3 Grace periods

The first three minutes after task start are a default grace period.

Application switching during this period does not create a drift intervention unless high-confidence gaming begins.

The first 60 seconds after waking, unlocking, or returning from idle are also protected.

### 22.4 Neutral activity

System settings, password managers, file dialogs, downloads, short communication checks, and task-supporting administration may be neutral rather than misaligned.

Neutral time should not automatically pause a task.

### 22.5 Alignment coverage

Reviews must distinguish active-task elapsed time from aligned time.

If more than 30 percent of an active-task session is unknown, the review should flag low tracking coverage rather than assert precise productivity.

## 23. Recommendation engine

### 23.1 Responsibilities

The recommendation engine selects one next task or one recovery action.

It must provide a concise explanation.

### 23.2 Candidate eligibility

A task is eligible when it is incomplete, not cancelled, not source-deleted, and not blocked without a known unblocking action.

Selected daily tasks receive preference over unselected tasks.

### 23.3 Deterministic score

The initial score is:

```text
score = urgency
      + importance
      + overdue_weight
      + main_objective_weight
      + quick_win_fit
      + dependency_unblock_weight
      + energy_fit
      + continuity_bonus
      - duration_mismatch
      - blocked_penalty
      - recent_failure_fatigue
```

Exact weights must live in versioned configuration rather than application code.

### 23.4 Duration fit

The engine compares the task estimate with the current available commitment window.

When a large task is important but the available window is short, it recommends a bounded sprint rather than replacing it with a low-value small task.

### 23.5 Recommendation reasons

Allowed primary reasons include:

- Due soon.
- Overdue.
- Main objective.
- Short task that clears a dependency.
- Continue existing momentum.
- Best fit for available time.
- Best fit for current energy.
- Previously avoided and now needs a concrete start.
- Required before gaming unlock.

### 23.6 AI role

AI may rank close candidates, rewrite the explanation, or suggest a task split.

The deterministic candidate set and policy constraints remain authoritative.

### 23.7 Recommendation feedback

The user can select:

- Start.
- Not now.
- Wrong priority.
- Too large.
- Blocked.
- Already done.
- Hide for today.

Feedback becomes recommendation evidence and may update task state.

## 24. Drift detection

### 24.1 Definition

Drift is a sustained, sufficiently confident mismatch between intended activity and observed behavior outside a protected context.

### 24.2 Drift episode inputs

- Current active task.
- Current behavior category.
- Alignment confidence.
- Session duration.
- Workday state.
- Break state.
- Gaming budget.
- Prompt cooldown.
- Recent intervention responses.
- User quiet mode.
- Time of day.

### 24.3 Default gaming trigger

The first release trigger is true when:

```text
behavior.category == gaming
AND gaming_session.duration >= 10 minutes
AND at_least_one_priority_task_incomplete
AND not accepted_break
AND not coaching_paused
AND current_time within work_window
AND no equivalent prompt in cooldown
```

### 24.4 Other future triggers

- Passive consumption for a sustained period after task start.
- Repeated context switching without a stable work session.
- Missed planned start time.
- Active task with prolonged unknown activity.
- Task estimate exceeded without progress confirmation.
- Repeated reopening of a distraction after returning to work.

### 24.5 Drift false-positive safeguards

The detector must suppress an episode when:

- The user declared a break.
- Gaming is intentionally unlocked and within budget.
- The task is paused.
- The workday is closed.
- The current context is uncertain.
- A recent prompt already captured the same ongoing session.
- The app or domain was corrected for this context.

## 25. Intervention policy

### 25.1 Intervention levels

| Level | Name | Purpose | Example |
| --- | --- | --- | --- |
| 0 | Observe | Record without interrupting | No visible message |
| 1 | Gentle nudge | Offer an easy return | `Ready to return to the client edit?` |
| 2 | Accountability | Ask whether behavior is intentional | `League has been active for 25m. Is this intentional?` |
| 3 | Commit mode | Require a concrete choice | `Start a 20m sprint or reschedule the task.` |
| 4 | Soft block | Strong visual friction without preventing override | `Gaming is beyond today's plan. Finish one priority sprint to unlock more.` |
| 5 | Hard block | Optional enforcement after explicit enablement | Quit or deny selected apps for a bounded period |

### 25.2 Default release limits

Release 1 supports levels 0 through 2.

The first seven complete days of Release 1 are locked to level 0 observation for behavior-triggered coaching.

After the baseline week, level 2 accountability prompts become the default ceiling with a maximum of six behavior interventions per workday.

Release 2 supports level 3.

Level 4 requires a dedicated setting and policy review.

Level 5 is deferred.

### 25.3 Escalation rules

Escalation considers:

- Duration of the current drift episode.
- Confidence and evidence quality.
- Number of ignored prompts in the episode.
- Previous explicit choice.
- Importance and deadline of incomplete work.
- Gaming budget state.
- Time remaining in the workday.
- User-selected coaching mode.

### 25.4 De-escalation rules

The policy returns to level 0 when:

- Aligned work resumes for at least two minutes.
- The user starts an accepted break.
- The user explicitly continues intentionally.
- The active task is paused or rescheduled.
- The workday closes.
- Evidence confidence drops below the threshold.

### 25.5 Cooldowns

Default cooldowns are:

- 15 minutes after a gentle nudge.
- 20 minutes after an accountability response.
- Until the chosen snooze expires.
- 45 minutes after an intentional override for the same behavior class.
- The rest of the day after `I am done today`.

### 25.6 Daily prompt caps

The default maximum is six behavior interventions per workday.

Estimate requests, source-error notices, and user-initiated task controls do not count toward this cap.

After the cap, the system records drift silently and mentions it only in the review.

### 25.7 Prompt episode state

```text
detected -> queued -> presented -> responded
                       |       |
                       |       +-> timed_out
                       +-> dismissed
```

Every prompt response must be idempotent.

Repeated action delivery must not start duplicate task sessions or apply budget changes twice.

### 25.8 Prompt actions

Standard actions are:

- Start recommended task.
- Start a short sprint.
- Return to active task.
- Five more minutes.
- Start break.
- Continue intentionally.
- Pause task.
- Reschedule task.
- Mark blocked.
- End workday.
- Ignore.

## 26. Coaching voice and copy

The founder has delegated detailed coaching-language decisions to the product team.

The voice and safety rules in this section are therefore a decided product contract rather than an open copy direction.

### 26.1 Voice

The voice is concise, calm, perceptive, and direct.

It sounds like a trusted coach who respects autonomy.

### 26.2 Copy rules

- State observed facts before interpretation.
- Name the relevant task.
- Offer one primary action and no more than three secondary actions.
- Avoid moral language.
- Avoid claiming intent.
- Avoid unnecessary exclamation marks.
- Avoid vague encouragement without a concrete action.
- Use elapsed time only when reliable.
- Use `I may be wrong` or a confirmation choice when context is ambiguous.

### 26.3 Good copy

```text
League has been active for 18 minutes.
Your main objective is still incomplete.
Start a 20-minute client-edit sprint?
```

### 26.4 Unacceptable copy

```text
You are wasting time again.
You failed to stay focused.
Stop being lazy and get back to work.
```

## 27. Gaming budget and reward system

### 27.1 Purpose

The gaming system converts unbounded avoidance into an explicit, reviewable choice.

It must support enjoyment and recovery rather than treating all gaming as failure.

### 27.2 Policy modes

- `observe_only`
- `daily_budget`
- `unlock_after_tasks`
- `earn_by_focus_time`
- `hybrid`

### 27.3 Default recommendation

**RECOMMENDED:** Start with a hybrid policy.

```text
Base budget: 30 minutes
Unlock condition: complete 2 priority tasks
Additional reward: 30 minutes after 90 aligned work minutes
Daily maximum: 90 minutes during the configured workday
```

All values remain configurable.

### 27.4 Budget accounting

Gaming time is counted from behavior sessions classified as gaming with sufficient confidence.

Short launcher transitions under 30 seconds may be excluded.

The budget tracks:

- Base available minutes.
- Earned minutes.
- Used minutes.
- Locked minutes.
- Debt minutes.
- Manual adjustments.

### 27.5 Gaming debt

Gaming before an unlock condition creates debt only when the selected policy enables debt.

Debt is informational and affects same-day unlock calculations.

Debt must never carry into another day unless the user explicitly enables carryover.

Default carryover is off.

### 27.6 Intentional override

`Continue intentionally` suppresses prompts for the configured override window.

It records time, context, and incomplete priority state.

It does not add moral language to the review.

### 27.7 Reward integrity

Only completed tasks or aligned work with sufficient telemetry coverage can earn automatic rewards.

The user may manually grant time.

The system must show manual adjustments separately.

## 28. Atoll integration

### 28.1 Confirmed Atoll capabilities

The inspected Atoll installation is version 2.2.0.

The official AtollExtensionKit is a Swift package for third-party macOS applications.

It supports XPC authorization and APIs to present, update, and dismiss:

- Live activities.
- Lock-screen widgets.
- Notch experiences.

Notch experiences may include a standard tab, a minimalistic replacement, native text and metric elements, and sandboxed web content.

Atoll limits default simultaneous notch experiences and allows the user to disable extension experiences or interactive web content.

### 28.2 Passive active-task activity

Zoid Coach should present one stable live activity ID for the active task.

It shows:

- Task title.
- Elapsed time.
- Estimate or sprint duration.
- Progress where meaningful.
- Zoid icon or SF Symbol.
- Priority appropriate to the state.

It updates no more than once per second and normally every five seconds.

It dismisses when no task is active and no summary state is useful.

### 28.3 Expanded notch experience

The standard Zoid tab shows:

- Active task or recommended next task.
- Work and gaming totals.
- Gaming budget.
- Current coaching state.
- One primary action.

The minimalistic configuration shows only the active task and elapsed or remaining commitment.

### 28.4 Native action gap

The current public AtollExtensionKit exposes dismissal callbacks but does not expose a general native action callback from content buttons.

Structured native notch content includes text, icons, progress, graphs, gauges, dividers, spacers, and web views, but not a first-class action element.

### 28.5 Production integration decision

**DECIDED:** Extend AtollExtensionKit and Atoll with a native action contract.

The contract should add:

- `AtollActionDescriptor` with stable ID, title, role, icon, and optional confirmation requirement.
- Button or action-row content elements.
- XPC callback `notchExperienceActionInvoked`.
- Bundle and experience identity validation.
- At-most-once action event identifiers.
- Accessibility labels and keyboard activation.
- Rate limits and payload limits.

Zoid Coach remains responsible for validating the action against current prompt state.

### 28.6 Temporary MVP interaction bridge

If native action callbacks are not ready, an interactive Atoll web payload may send requests to a loopback-only Zoid action service.

The bridge must use:

- `127.0.0.1` only.
- An ephemeral random port.
- Short-lived single-use action tokens.
- Prompt ID and action ID binding.
- POST requests only.
- Strict origin and content-type checks.
- A small request-body limit.
- No remote network requests.
- Automatic shutdown when Zoid Coach exits.

This bridge is temporary and must be removable behind one adapter boundary.

### 28.7 Atoll failure fallback

If Atoll is unavailable, unauthorized, rate-limited, or disabled, Zoid Coach falls back to:

1. Native macOS notification when authorized.
2. Menu bar badge.
3. In-dashboard prompt inbox.

State and response handling must be identical across surfaces.

## 29. End-of-day review

### 29.1 Review trigger

The review is generated at the configured time, when the workday is ended manually, or on next launch if the previous day remained unreviewed.

### 29.2 Required facts

The review includes:

- Planned main objective.
- Priority tasks completed.
- Total active-task time.
- Aligned work time.
- Work by category.
- Gaming time.
- Distraction time.
- Idle time where reliably observed.
- Unknown or missing coverage.
- Best work block.
- Main drift episode.
- Intervention count and responses.
- Gaming overrides.
- Estimate-versus-actual comparisons.

### 29.3 Review narrative

The generated narrative must separate facts from hypotheses.

Example:

```text
Fact: League began at 2:14 PM and remained active for 42 minutes.
Context: Discord was active immediately before it.
Hypothesis: The switch may have followed uncertainty about the next task.
```

### 29.4 Review corrections

The user can:

- Reclassify a session.
- Mark away-from-Mac work.
- Correct task completion.
- Reject a causal hypothesis.
- Add a note.
- Change tomorrow's main task.

### 29.5 Review completion

A review is complete after the user confirms it or explicitly skips it.

Unconfirmed AI hypotheses must not become learned facts.

## 30. Weekly review

### 30.1 Minimum evidence

A weekly review requires at least three days with acceptable telemetry coverage.

If evidence is insufficient, the product provides a data-quality summary instead of strong behavioral conclusions.

### 30.2 Weekly sections

- Outcomes completed.
- Planned versus completed work.
- Estimate calibration.
- Best work windows.
- Frequent drift triggers.
- Gaming timing and budget adherence.
- Recovery success after prompts.
- Prompt effectiveness.
- Repeated blocked or vague tasks.
- One recommended experiment for next week.

### 30.3 Pattern evidence

Every pattern includes:

- Plain-language statement.
- Sample size.
- Date range.
- Supporting event examples.
- Confidence.
- Alternative explanation when relevant.

### 30.4 Weekly experiment

The coach recommends no more than one primary behavioral experiment per week.

Examples include:

- Start with a task under 30 minutes.
- Break vague tasks before planning.
- Delay Discord until the main objective begins.
- Reserve a longer block for coding tasks based on calibration.

The user can accept, edit, or reject the experiment.

## 31. Today dashboard requirements

### 31.1 Header

The header shows:

- Date.
- Day state.
- Coaching pause state.
- Source health summary.
- End-workday action.

### 31.2 Main objective card

The card shows:

- Task title.
- Deadline.
- Estimate.
- Status.
- Start or resume action.
- Reason it is the main objective.

### 31.3 Active-task card

When active, it shows:

- Task title.
- Elapsed time.
- Sprint remaining time where applicable.
- Estimate progress.
- Current alignment state.
- Pause, complete, block, and switch actions.

Alignment should use neutral language such as `Working context matches` or `Context uncertain`.

### 31.4 Task list

Each row shows:

- Completion control.
- Daily rank.
- Title.
- List or project.
- Estimate.
- Deadline.
- Urgency.
- Status.
- Start action.

### 31.5 Behavior summary

The summary shows time totals and coverage.

It must not show totals with minute-level precision when source gaps make that precision misleading.

### 31.6 Recommendation card

The card contains one action, one reason, and a feedback menu.

### 31.7 Gaming card

The card shows:

- Policy mode.
- Available budget.
- Used time.
- Locked or earned time.
- Debt where enabled.
- Next unlock condition.
- Manual adjustment action.

### 31.8 Coach history

The last five prompt episodes are visible with their response and resulting action.

## 32. Settings requirements

### 32.1 General

- Launch at login.
- Workday start and end.
- Planning time.
- Review time.
- Time zone behavior.
- Keyboard shortcuts.

### 32.2 Data sources

- Reminders authorization and selected lists.
- Screenwatch path and health.
- Atoll installation, version, authorization, and test action.
- Notifications authorization.

### 32.3 Coaching

- Coaching mode.
- Intervention level ceiling.
- Prompt cap.
- Quiet hours.
- Cooldowns.
- Grace period.
- Pause duration.

### 32.4 Classification

- Application rules.
- Domain rules.
- Project mappings.
- Unknown-session review.
- Screenshot-analysis permission.
- Rule import and export.

### 32.5 Gaming

- Policy mode.
- Base budget.
- Unlock tasks.
- Focus-time reward.
- Daily maximum.
- Debt behavior.
- Override cooldown.
- Managed applications.

### 32.6 AI

- Rules-only mode.
- Provider.
- Model.
- Local versus remote processing.
- Redaction preview.
- Monthly or daily request budget.
- Clear AI cache.

### 32.7 Privacy and data

- Retention by data class.
- Screenshot-analysis setting.
- Export data.
- Delete date range.
- Delete all Zoid Coach data.
- Open local data folder.
- Diagnostics export with redaction.

## 33. Reference architecture

### 33.1 Architecture decision

**RECOMMENDED:** Build Zoid Coach as a native Swift and SwiftUI macOS application with a bundled background agent and a local SQLite database.

Reasons:

- EventKit integration is native and direct.
- AtollExtensionKit is a Swift package.
- Background lifecycle, menu bar, notifications, launch-at-login, sleep and wake handling, and macOS permissions are first-class.
- A native process avoids a second bridge layer around the two most important integrations.
- Local security controls and code signing remain coherent.

### 33.1.1 Screenwatch source consolidation

**DECIDED:** The Screenwatch source becomes part of the Zoid Coach repository instead of remaining an independently located personal script.

The first consolidation step imports the current capture loop, setup metadata, and fixtures under an explicit `Integrations/ScreenwatchLegacy` boundary while preserving the existing `~/screenwatch/days/YYYY-MM-DD/log.jsonl` runtime contract.

The target architecture moves capture ownership into `ZoidCoachAgent` after parity tests prove that cadence, idle skipping, metadata fields, screenshot behavior, permissions, and retention remain equivalent.

The legacy script remains available only as a migration and rollback path until the native agent has completed a verified baseline period.

### 33.2 Process model

The product contains:

- `ZoidCoach.app`, which owns UI, permissions, settings, and user actions.
- `ZoidCoachAgent`, a bundled launch-at-login helper that tails telemetry and evaluates scheduled policies.
- A shared application group or explicitly controlled local storage directory.
- An optional local AI worker process when a local model is enabled.

The agent must remain lightweight and must not render UI independently.

The main app and agent communicate through XPC or an equivalent authenticated local channel.

### 33.3 Module boundaries

| Module | Responsibility |
| --- | --- |
| TaskSource | EventKit reads, writes, and source snapshots |
| TelemetrySource | Screenwatch discovery, tailing, parsing, and health |
| AppInventory | Installed application discovery and identity normalization |
| EventStore | Immutable domain events and processing checkpoints |
| TaskStore | Task source cache and local task metadata |
| Sessionizer | Raw observation to behavior-session conversion |
| Classifier | Rules, AI classification, corrections, and confidence |
| AlignmentEngine | Active-task and behavior relationship |
| RecommendationEngine | Next-task and recovery selection |
| InterventionEngine | Triggering, escalation, cooldowns, and prompt state |
| GamingPolicy | Budget, rewards, debt, and overrides |
| ReviewEngine | Daily and weekly aggregation and narratives |
| AtollAdapter | Live activity, notch experience, and action transport |
| NotificationAdapter | macOS notification fallback |
| AIProvider | Structured model requests, redaction, and budgets |
| SettingsStore | Versioned user configuration |
| Diagnostics | Health, redacted logs, replay, and export |

### 33.4 Dependency rule

Domain modules must not import SwiftUI, EventKit, AtollExtensionKit, or model-provider SDKs directly.

Platform integrations implement protocols at the application edge.

This allows deterministic replay and unit testing without macOS permissions or live applications.

### 33.5 Event-driven processing

Adapters emit normalized domain events.

Reducers and policy engines derive state from those events.

Important state transitions write their event and state update in one database transaction.

### 33.6 Replayability

The telemetry and coaching pipeline must support replaying a recorded day against a chosen rule-set version.

Replay never sends live prompts or writes Apple Reminders.

Replay output is isolated from production-derived state.

## 34. Local persistence

### 34.1 Database choice

**RECOMMENDED:** SQLite in WAL mode with explicit migrations.

A thin, typed repository layer should be used.

GRDB is acceptable if dependency policy allows it.

### 34.2 Data classes

| Data class | Example | Default retention |
| --- | --- | --- |
| Source task snapshot | Reminder fields | Current plus 90 days of relevant history |
| Raw behavior metadata | App, title, URL, epoch | 30 days |
| Screenshot references | Source file path only | Same as source availability |
| Behavior sessions | Normalized intervals | 365 days |
| Task sessions | Starts, pauses, completions | Indefinite until user deletion |
| Prompt episodes | Trigger, message, response | 365 days |
| Daily reviews | Confirmed summary | Indefinite until user deletion |
| Weekly reviews | Confirmed patterns | Indefinite until user deletion |
| AI request metadata | Model, token count, redaction policy | 90 days |
| AI prompt content | Redacted request body | Off by default |
| Diagnostics | Health and errors | 14 days |

Retention values are defaults and remain configurable.

### 34.3 Core tables

The initial schema contains:

- `source_tasks`
- `task_metadata`
- `daily_plans`
- `daily_plan_tasks`
- `task_sessions`
- `raw_behavior_records`
- `behavior_sessions`
- `classification_results`
- `classification_rules`
- `alignment_results`
- `gaming_ledger`
- `prompt_episodes`
- `prompt_actions`
- `reviews`
- `review_patterns`
- `domain_events`
- `source_checkpoints`
- `settings`
- `ai_requests`
- `diagnostic_events`

### 34.4 Identifiers

Local entities use UUIDv7 or another sortable unique identifier.

Source identifiers remain separate and namespaced by adapter.

User-visible prompt actions use opaque single-use tokens rather than database IDs.

### 34.5 Timestamps

All persisted event times use UTC instants.

The applicable local time zone and offset are stored for daily-boundary interpretation.

Display uses the current or event-local time zone as appropriate.

### 34.6 Migrations

Every schema change has a forward migration and a tested backup strategy.

The app creates a local database backup before a destructive or long-running migration.

Migration failure must leave the previous database readable.

## 35. Data model

### 35.1 Source task

```json
{
  "id": "local-source-task-id",
  "source": "apple_reminders",
  "source_id": "eventkit-calendar-item-id",
  "series_key": null,
  "title": "Edit video intro",
  "notes": null,
  "list_id": "eventkit-list-id",
  "list_name": "Client Work",
  "due_at": "2026-07-09T15:00:00+03:00",
  "priority": 1,
  "completed": false,
  "source_updated_at": "2026-07-09T08:10:00Z",
  "snapshot_hash": "sha256"
}
```

### 35.2 Task metadata

```json
{
  "task_id": "local-source-task-id",
  "user_estimate_minutes": 45,
  "ai_estimate_minutes": 60,
  "estimate_confidence": 0.72,
  "task_type": "video_editing",
  "energy_requirement": "medium",
  "status": "selected",
  "blocked_reason": null,
  "actual_active_minutes": 0,
  "actual_aligned_minutes": 0,
  "prompt_count_today": 0
}
```

### 35.3 Daily plan

```json
{
  "id": "plan-id",
  "local_date": "2026-07-09",
  "state": "planned",
  "main_objective_task_id": "task-id-1",
  "priority_task_ids": ["task-id-1", "task-id-2", "task-id-3"],
  "planned_focus_minutes": 155,
  "buffer_minutes": 60,
  "gaming_policy_snapshot_id": "policy-id",
  "approved_at": "2026-07-09T07:45:00Z"
}
```

### 35.4 Behavior session

```json
{
  "id": "behavior-session-id",
  "started_at": "2026-07-09T11:10:00Z",
  "ended_at": "2026-07-09T12:05:00Z",
  "app_id": "com.todesktop.230313mzl4w4u92",
  "app_name": "Cursor",
  "normalized_context": "project:landing-page",
  "url_host": null,
  "category": "deep_work",
  "classification_confidence": 0.94,
  "alignment": "aligned",
  "alignment_confidence": 0.91,
  "task_id": "task-id-3",
  "coverage": "complete"
}
```

### 35.5 Prompt episode

```json
{
  "id": "prompt-id",
  "trigger": "gaming_drift",
  "level": 2,
  "state": "responded",
  "task_id": "task-id-1",
  "behavior_session_id": "behavior-session-id",
  "message_version": "gaming-drift-v1",
  "presented_surfaces": ["atoll", "dashboard"],
  "presented_at": "2026-07-09T11:35:00Z",
  "response_action": "start_20m_sprint",
  "responded_at": "2026-07-09T11:36:12Z",
  "deduplication_key": "gaming-drift:behavior-session-id:2"
}
```

### 35.6 Gaming ledger entry

```json
{
  "id": "ledger-id",
  "local_date": "2026-07-09",
  "kind": "usage",
  "minutes": -12,
  "source": "behavior_session",
  "source_id": "behavior-session-id",
  "created_at": "2026-07-09T11:42:00Z"
}
```

### 35.7 Review pattern

```json
{
  "id": "pattern-id",
  "review_id": "weekly-review-id",
  "type": "estimate_bias",
  "statement": "Coding tasks were underestimated by a median of 1.6x.",
  "sample_size": 7,
  "confidence": 0.86,
  "evidence_event_ids": ["event-1", "event-2"],
  "confirmed_by_user": true
}
```

## 36. Domain event taxonomy

### 36.1 Task events

- `task_imported`
- `task_source_updated`
- `task_selected`
- `task_estimated`
- `task_started`
- `task_paused`
- `task_resumed`
- `task_blocked`
- `task_deferred`
- `task_completed`
- `task_completed_externally`
- `task_source_deleted`

### 36.2 Plan events

- `planning_started`
- `plan_proposed`
- `plan_approved`
- `plan_updated`
- `planning_skipped`
- `workday_started`
- `workday_paused`
- `workday_resumed`
- `workday_ended`

### 36.3 Behavior events

- `behavior_record_ingested`
- `behavior_session_started`
- `behavior_session_updated`
- `behavior_session_ended`
- `behavior_classified`
- `behavior_corrected`
- `alignment_evaluated`
- `source_became_stale`
- `source_recovered`

### 36.4 Coaching events

- `drift_detected`
- `intervention_queued`
- `intervention_presented`
- `intervention_updated`
- `intervention_responded`
- `intervention_dismissed`
- `intervention_timed_out`
- `coaching_paused`
- `coaching_resumed`

### 36.5 Gaming events

- `gaming_session_started`
- `gaming_minutes_used`
- `gaming_minutes_earned`
- `gaming_override_started`
- `gaming_override_ended`
- `gaming_budget_adjusted`

### 36.6 Review events

- `daily_review_generated`
- `review_corrected`
- `daily_review_confirmed`
- `daily_review_skipped`
- `weekly_review_generated`
- `weekly_experiment_selected`

## 37. Internal command contracts

### 37.1 Command principles

Commands represent user or scheduler intent.

Every command has an idempotency key, actor, timestamp, and expected state version.

Commands either commit fully or return a typed failure.

### 37.2 Core commands

- `ApproveDailyPlan`
- `SetTaskEstimate`
- `StartTask`
- `PauseTask`
- `ResumeTask`
- `CompleteTask`
- `BlockTask`
- `RescheduleTask`
- `StartBreak`
- `EndBreak`
- `RespondToPrompt`
- `AdjustGamingBudget`
- `PauseCoaching`
- `EndWorkday`
- `CorrectBehaviorSession`
- `ConfirmReview`

### 37.3 Prompt response command

```json
{
  "command": "RespondToPrompt",
  "command_id": "uuidv7",
  "prompt_id": "prompt-id",
  "action_id": "start_20m_sprint",
  "action_token": "opaque-single-use-token",
  "surface": "atoll",
  "expected_prompt_state": "presented",
  "issued_at": "2026-07-09T11:36:12Z"
}
```

### 37.4 Idempotency

The same command ID returns the original result.

A used action token cannot be applied again.

If state has advanced incompatibly, the command returns `stale_action` and the UI refreshes.

## 38. AI system specification

### 38.0 Release boundary

**DECIDED:** Release 1 uses rules only and makes no local or remote model calls.

AI integrations begin no earlier than Release 2 and require a separate provider, privacy, evaluation, and cost decision.

Every Release 1 workflow, total, intervention, and review must remain complete without AI.

### 38.1 AI use cases

Starting in Release 2, AI may be used for:

- Ambiguous behavior classification.
- Task-type inference.
- Estimate comparison and suggestion.
- Next-task explanation.
- Task decomposition suggestions.
- End-of-day narrative.
- Weekly pattern generation.
- Natural-language settings or commands in a later release.

### 38.2 AI non-authority

AI may not directly:

- Complete or delete a task.
- Change a due date without confirmation.
- Apply hard blocking.
- Grant permissions.
- Override user corrections.
- Invent missing telemetry.
- Treat hypotheses as confirmed patterns.

### 38.3 Provider abstraction

The domain layer depends on task-specific interfaces rather than one general chat interface.

Suggested interfaces are:

- `BehaviorClassifier`
- `EstimateAdvisor`
- `RecommendationExplainer`
- `DailyReviewWriter`
- `WeeklyPatternAnalyst`

### 38.4 Structured output

Every AI call uses a versioned JSON schema.

The application validates the response and rejects unknown enum values, missing evidence, impossible timestamps, or excessive text.

### 38.5 Redaction

Before a remote call, the redaction layer may:

- Replace user names and client names with stable aliases.
- Remove query strings and fragments from URLs.
- Reduce URLs to host and approved path components.
- Remove file-system home paths.
- Remove tokens, email addresses, phone numbers, and detected secrets.
- Truncate long window titles and notes.
- Exclude screenshot pixels unless explicitly needed.

### 38.6 Model budgets

Classification requests should be batched when possible and cached by normalized context and rule-set version.

Reviews should use aggregated evidence rather than replaying raw screenshots or every raw record.

The user can set daily request and cost limits.

### 38.7 AI failure behavior

Timeout, provider failure, invalid JSON, quota exhaustion, or offline state falls back to deterministic behavior.

The UI may show that an explanation is unavailable, but core task and coaching state must remain operational.

### 38.8 Local model mode

A future local model adapter may perform classification and summarization without network access.

The same schema and evaluation suite must apply to local and remote providers.

## 39. Privacy and security

### 39.1 Threat model

Sensitive data includes task names, client names, window titles, URLs, screenshot references, behavior history, work patterns, and AI requests.

Threats include unintended cloud disclosure, local data exposure, malicious prompt actions, loopback request forgery, excessive logging, stale permissions, and unsafe exports.

### 39.2 Local storage protection

The database and settings reside under the application container or an application-group directory with user-only permissions.

Secrets and provider credentials reside in Keychain.

Exports require an explicit destination and show included data classes before creation.

### 39.3 Logging policy

Production logs must not contain raw window titles, full URLs, Reminder notes, screenshot paths, AI prompts, or credentials.

Sensitive values use hashes or redacted aliases in diagnostics.

Debug logging that includes content must be temporary, visibly enabled, and automatically expire.

### 39.4 Loopback service security

If the temporary Atoll web bridge is enabled:

- Bind only to `127.0.0.1` and not all interfaces.
- Reject requests without a valid single-use token.
- Bind the token to one prompt and action.
- Expire tokens after five minutes or prompt resolution.
- Reject replay.
- Reject unexpected methods and content types.
- Enforce a body-size limit.
- Never expose task or telemetry queries through the bridge.

### 39.5 AI privacy boundary

Remote AI is opt-in during onboarding or settings.

The user can preview a representative redacted payload.

The provider adapter must document whether data is retained or used for training.

Provider-specific policy can change, so current terms must be verified before production release.

### 39.6 Data deletion

The user can delete:

- One behavior session.
- One day.
- A date range.
- All raw metadata.
- All AI request metadata.
- All reviews and learned rules.
- All Zoid Coach data.

Deletion must also remove derived records that no longer have valid evidence.

### 39.7 Consent boundaries

The app is for self-monitoring on the user's own device.

It must not include hidden monitoring, remote administrator access, or multi-user capture.

## 40. Failure and degraded-mode behavior

### 40.1 Design principle

Every external dependency has an explicit degraded mode.

The product should explain what is unavailable and preserve unrelated functions.

### 40.2 Failure matrix

| Failure | User impact | Required behavior |
| --- | --- | --- |
| Reminders permission denied | Tasks cannot sync | Offer manual local planning and permission repair |
| EventKit write rejected | Completion or reschedule not synced | Keep pending operation, show retry, never pretend success |
| Screenwatch folder missing | Behavior coaching unavailable | Preserve planning and active-task tracking |
| JSONL schema changes | Telemetry cannot parse safely | Stop ingestion, retain checkpoint, show schema mismatch |
| Screenwatch becomes stale | Totals and drift detection become unreliable | Suppress behavior interventions and show source warning |
| Atoll not installed | No notch experience | Use native notification and dashboard |
| Atoll authorization revoked | Notch updates fail | Dismiss local adapter state and show reauthorization path |
| Atoll capacity reached | Zoid content may not present | Queue only the latest relevant prompt and use fallback |
| Local database locked | State changes cannot commit | Retry briefly, show read-only mode, do not issue actions |
| Database migration fails | App cannot use new schema | Restore backup and keep previous version data intact |
| AI provider offline | AI classification and narrative unavailable | Use rules and deterministic summaries |
| Remote model returns invalid output | Result unsafe to use | Reject output and log a redacted validation error |
| Mac sleeps during sprint | Timer continuity ambiguous | Pause display updates and reconcile elapsed policy on wake |
| Time zone changes | Day boundaries may shift | Preserve event instants and ask before moving daily plans |
| Clock moves backward | Negative durations possible | Use monotonic elapsed time for live sessions |
| Duplicate Atoll action arrives | Duplicate state mutation risk | Enforce command and token idempotency |

### 40.3 Sleep and wake

The agent observes system sleep and wake events.

Active-task elapsed time may continue across short screen locks if configured, but aligned time does not accrue without telemetry.

After a long sleep, the task is presented as `still active?` rather than silently continuing precise timing.

### 40.4 Crash recovery

Open task sessions, prompt episodes, and ingestion checkpoints are recovered on launch.

An open task session with no heartbeat is reconciled against the last valid telemetry and system shutdown evidence.

The app asks for confirmation when recovery cannot determine an accurate end time.

### 40.5 Partial-day telemetry

Reviews show coverage windows.

They must not extrapolate missing periods.

## 41. Notifications and scheduling

### 41.1 Scheduler responsibilities

The scheduler triggers:

- Morning planning.
- Planned task start reminders.
- Break end.
- End-of-day review.
- Weekly review.
- Source health checks.
- Deferred prompt expiry.

### 41.2 Quiet hours

No behavioral intervention may appear outside the configured work window unless explicitly enabled.

Critical source errors remain visible in the dashboard but do not wake the user.

### 41.3 Notification grouping

Only one unresolved coaching notification may exist for the same prompt episode.

Updates replace previous content instead of creating a notification stack.

## 42. Accessibility and localization

### 42.1 Accessibility requirements

- Full keyboard operation for planning, task controls, settings, and reviews.
- VoiceOver labels for every interactive control and state indicator.
- No status conveyed by color alone.
- Reduced-motion support.
- Sufficient contrast in light and dark appearance.
- Text resizing without clipped task titles or actions.
- Clear focus order.
- Accessible alternatives to compact notch interactions.

### 42.2 Atoll accessibility

Native Atoll action elements should expose labels, roles, state, and keyboard activation.

If the temporary web bridge is used, its HTML must use semantic buttons, visible focus, and appropriate labels.

### 42.3 Localization

Release 1 may ship in English.

All user-facing strings must use localization resources from the start.

Dates, durations, calendars, week starts, and number formats must respect locale.

## 43. Visual and interaction design direction

### 43.1 Design-system status

**DECIDED:** Zoid Coach uses the Sumi-Ink Command System as its canonical visual direction.

The current dark violet and cyan HTML concept is historical exploration only and must not guide new product UI.

Canonical roles are white paper surfaces, black sumi ink structure, pale rules, restrained red seal accents, serif English and Japanese typography, boxed operational rails, and zero-radius controls.

Blue architecture, blue selected states, decorative gradients, glassmorphism, warm gold, and generic SaaS card styling are not current guidance.

### 43.2 Functional visual principles

Within Sumi-Ink:

- The active task is the strongest visual element.
- The recommendation is more prominent than historical analytics.
- Risk and drift states use restrained emphasis.
- Gaming information is visible without dominating the dashboard.
- Unknown and missing data look different from zero.
- Prompt actions remain easy to scan under time pressure.
- Dense history belongs below the fold or in review screens.

### 43.3 Motion

Motion should confirm state changes and draw attention to a newly presented prompt.

It must not create a reward loop around interruption.

Reduced-motion preference disables nonessential transitions.

## 44. Performance, reliability, and resource targets

### 44.1 Performance targets

| Measure | Target |
| --- | --- |
| App cold launch to usable Today view | Under 2 seconds on target Mac |
| Warm launch | Under 500 milliseconds |
| Screenwatch record ingestion | Under 2 seconds after file append |
| Derived behavior update | Under 5 seconds after ingestion |
| Drift prompt eligibility | Under 15 seconds after threshold crossing |
| Task action commit | Under 200 milliseconds locally |
| Atoll update dispatch | Under 500 milliseconds after state change |
| Dashboard interaction response | Under 100 milliseconds for local actions |
| Daily review generation without remote AI | Under 2 seconds |

### 44.2 Resource targets

The idle background agent should average below 1 percent CPU on the target machine.

The agent should remain below 150 MB resident memory under normal use.

The product must not duplicate Screenwatch screenshot storage.

Database growth must be observable and bounded by retention policies.

### 44.3 Reliability targets

- No duplicate task sessions from repeated actions.
- No silent loss of user estimates or prompt responses.
- No behavior intervention when the telemetry source is stale.
- No Reminder write reported as successful before EventKit confirms it.
- At least 99 percent successful ingestion of valid JSONL records during an active source window.

## 45. Observability and diagnostics

### 45.1 Health dashboard

Diagnostics show:

- Reminders permission and last sync.
- Screenwatch path, last record, checkpoint, and parse-error count.
- Atoll installed version, authorization, and last presentation result.
- Database path, schema version, size, and last migration.
- AI mode, provider health, and recent request failures.
- Agent heartbeat.

### 45.2 Structured logs

Logs use event codes and redacted identifiers.

Each significant operation includes a correlation ID.

### 45.3 Diagnostic export

The export includes configuration metadata, schema versions, health history, and redacted error events.

Raw task titles, URLs, window titles, screenshots, and AI content are excluded by default.

The user sees a manifest before export.

### 45.4 Replay tool

Development builds include a replay command that consumes a copied and sanitized JSONL fixture.

It can print sessions, classifications, drift episodes, and prompts without affecting live state.

## 46. Product analytics and evaluation

### 46.1 Local-first analytics

Initial evaluation metrics are calculated locally.

No remote product analytics are required for MVP.

### 46.2 Daily metrics

- Plan approved.
- Number of priority tasks.
- Priority tasks completed.
- Main objective completed.
- Estimate coverage.
- Active-task coverage.
- Aligned work minutes.
- Gaming minutes.
- Distraction minutes.
- Unknown coverage.
- Interventions by level.
- Intervention responses.
- Recovery after intervention.

### 46.3 Recovery definition

An intervention produces a recovery when aligned work begins within ten minutes and continues for at least ten minutes.

The threshold is configurable and must be versioned.

### 46.4 Usefulness feedback

The user can mark a prompt or review recommendation as helpful, neutral, or unhelpful.

Feedback is optional and should be requested sparingly.

### 46.5 Baseline period

The first seven to fourteen days may operate in observation-heavy mode.

Baseline results should calibrate alert thresholds, prompt caps, work capacity, and gaming patterns before stronger coaching is enabled.

## 47. Testing strategy

### 47.1 Testing principles

The core domain must be deterministic under a fixed event stream, clock, rule set, and model fixture.

External dependencies require contract tests and end-to-end tests on macOS.

### 47.2 Unit tests

Unit coverage includes:

- Reminder eligibility.
- Daily plan capacity.
- Estimate calibration.
- JSONL parsing.
- Cursor recovery.
- Session boundaries.
- Rule precedence.
- Classification thresholds.
- Alignment grace periods.
- Recommendation scoring.
- Drift conditions.
- Escalation and cooldowns.
- Gaming ledger accounting.
- Prompt idempotency.
- Review aggregation.
- Retention deletion.
- Redaction.

### 47.3 Property and invariant tests

Important invariants include:

- At most one active task.
- Behavior-session end is not before start.
- Gaming ledger totals equal the sum of immutable entries.
- A prompt action token applies at most once.
- A completed Reminder is never automatically reopened.
- Missing telemetry never becomes productive time.
- User corrections outrank AI classifications.

### 47.4 Integration tests

- EventKit test-store import and completion.
- Screenwatch log append, rotation, truncation, and rollover.
- SQLite migration and crash recovery.
- Atoll authorization, presentation, update, dismissal, and fallback.
- Loopback action-token validation if the temporary bridge ships.
- Notification action routing.
- AI schema validation and fallback.

### 47.5 End-to-end scenarios

#### Scenario A: Planned work succeeds

The user approves a plan, starts the main task, works in an aligned application, completes the task, and sees the Reminder completed.

No drift prompt appears.

#### Scenario B: Gaming drift and recovery

The user starts League while a priority task remains incomplete.

After the threshold, one prompt appears.

The user starts a 20-minute sprint.

Gaming time stops, the task becomes active, and aligned work produces a recovery event.

#### Scenario C: Intentional gaming

The user selects `Continue intentionally`.

The prompt resolves, the cooldown begins, gaming remains tracked, and no moralizing copy appears.

#### Scenario D: Ambiguous YouTube work

The user watches a technical tutorial related to the active task.

The classifier marks it research or asks for confirmation.

No high-level drift intervention occurs without sufficient misalignment evidence.

#### Scenario E: Screenwatch outage

The telemetry file stops updating during active use.

The health state becomes stale.

Behavior prompts stop while task tracking and planning remain available.

#### Scenario F: Atoll unavailable

Atoll exits before prompt presentation.

The same prompt appears through native notification and dashboard.

The action resolves the same prompt episode exactly once.

#### Scenario G: Sleep during sprint

The Mac sleeps during an active sprint.

On wake, elapsed and aligned time reconcile correctly and the user confirms whether the task remained active.

#### Scenario H: Remote AI failure

The provider times out during classification and review generation.

Rules classify known apps, ambiguous sessions remain unknown, and a deterministic factual review still renders.

### 47.6 Visual quality tests

Dashboard and prompt surfaces require screenshot coverage for representative states and screen sizes.

Tests should check clipped text, overlapping controls, long task names, large text, reduced motion, dark mode, light mode, source errors, and missing data.

### 47.7 Performance tests

Replay at least 30 days of representative telemetry.

Measure ingestion latency, database growth, classification cache hit rate, review generation time, and background CPU.

## 48. Release plan and acceptance gates

### 48.1 Milestone 0: Product decisions

Exit criteria:

- Technical stack confirmed.
- Relationship to the existing Zoid repository confirmed.
- Atoll integration ownership confirmed.
- Screenwatch source contract accepted.
- AI mode chosen for Release 1.
- Privacy and retention defaults approved.
- Visual direction approved.

### 48.2 Milestone 1: Source adapters

Exit criteria:

- EventKit tasks render from real Reminders.
- Completion round trip works.
- Screenwatch records tail incrementally from the live path.
- Day rollover and stale detection pass.
- Atoll test activity presents on the installed app.
- Data-source diagnostics are visible.

### 48.3 Milestone 2: Command Center

Exit criteria:

- Morning planning works with real tasks.
- Estimates persist.
- One active task invariant holds.
- Work and gaming totals are believable on a reviewed sample day.
- Recommended next task is explainable.
- End-of-day factual review renders.

### 48.4 Milestone 3: Coaching loop

Exit criteria:

- Gaming drift triggers exactly once under the specified conditions.
- Atoll or fallback presentation works.
- All actions are idempotent.
- Start-sprint action updates task and prompt state.
- Intentional override suppresses further prompts for the cooldown.
- Source staleness suppresses drift prompts.

### 48.5 Milestone 4: Adaptive classification

Exit criteria:

- Rules and AI use the defined precedence.
- User corrections persist and apply predictably.
- Ambiguous apps do not create excessive false prompts.
- AI failure falls back safely.
- Screenshot analysis remains opt-in and auditable.

### 48.6 Milestone 5: Weekly learning

Exit criteria:

- Weekly patterns cite evidence and sample size.
- Estimate calibration excludes low-coverage tasks.
- One experiment can be accepted and tracked.
- Rejected hypotheses do not become future facts.

## 49. Detailed Release 1 acceptance criteria

### 49.1 Planning

- Given Reminders permission, the dashboard shows all eligible tasks for today.
- Given a selected task without an estimate, the plan cannot finalize without estimate or explicit `unknown`.
- Given total estimates beyond capacity, the plan shows a concrete capacity warning.
- Given an approved plan, the same plan restores after app restart.

### 49.2 Task tracking

- Starting a task creates one task session.
- Starting another task pauses the first in the same transaction.
- Completing a task attempts an EventKit completion write.
- An EventKit failure remains visible and retryable.
- A task started before restart can be recovered without duplicate sessions.

### 49.3 Telemetry

- Valid appended JSONL records are processed without reading the full file each time.
- A partial last line is retried after more bytes arrive.
- A repeated record does not create duplicate duration.
- A stale stream changes health state and stops behavior interventions.
- Day rollover creates a new checkpoint safely.

### 49.4 Classification

- Configured game applications classify as gaming.
- Configured work applications classify into their assigned work category.
- Ambiguous applications remain unknown in Release 1 unless a deterministic contextual rule resolves them.
- The UI shows unknown time separately from zero.

### 49.5 Coaching

- During the first seven complete days, gaming drift is recorded without behavior-triggered prompts.
- After the baseline week, level 2 becomes the default intervention ceiling.
- Gaming under ten minutes does not trigger the default drift prompt.
- Gaming over ten minutes with incomplete priority tasks triggers one prompt during the work window.
- An accepted break suppresses the prompt.
- A completed priority plan suppresses the prompt when policy allows gaming.
- `Five more minutes` schedules one follow-up after the snooze.
- `Continue intentionally` begins the configured cooldown.
- `Start 20m sprint` starts the selected task and resolves the prompt.
- Duplicate action delivery does not create duplicate sessions.

### 49.6 Review

- The review reports actual data coverage.
- The review separates observed facts from hypotheses.
- Corrections update totals.
- The user can select tomorrow's main task.

## 50. Rollout safeguards

### 50.1 Coaching progression

The recommended rollout is:

1. Observe only.
2. Gentle nudges.
3. Accountability prompts.
4. Commit mode.
5. Optional soft block.

Each level requires sufficient prior data and explicit user enablement above level 2.

### 50.2 Kill switches

The product includes:

- Pause coaching for one hour.
- Pause until tomorrow.
- End workday.
- Disable Atoll prompts.
- Disable AI.
- Disable screenshot analysis.
- Stop Screenwatch ingestion without deleting data.
- Reset learned rules.

### 50.3 Safe defaults

- Hard blocking off.
- Remote AI off until configured.
- Screenshot analysis off until configured.
- Gaming debt carryover off.
- Quiet hours enabled.
- Prompt cap enabled.
- Unknown activity does not count as distraction.

## 51. Risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Prompts become annoying | Product abandonment | Caps, cooldowns, graded levels, usefulness feedback |
| Behavior classification is wrong | Loss of trust | Confidence, unknown state, corrections, rule precedence |
| Gaming system feels punitive | Avoidance or disabling | Explicit overrides, neutral language, reward framing |
| Screenwatch data is too sensitive | Privacy harm | Local storage, retention, redaction, opt-in screenshots |
| Atoll action path is incomplete | Prompts cannot close the loop | Native action extension, temporary secured loopback adapter |
| EventKit identifiers change | Metadata orphaning | External identifier fallback and reconciliation UI |
| AI makes unsupported causal claims | Misleading coaching | Evidence requirements, hypothesis labels, confirmation |
| Long-running agent consumes resources | Battery and performance harm | Resource budgets, profiling, event-driven tailing |
| Inaccurate time accounting | Untrustworthy reviews | Coverage reporting, monotonic timers, correction tools |
| Scope expands before core loop works | Delayed value | Release gates centered on one gaming-drift loop |
| Sumi-Ink is applied inconsistently | Rework and brand drift | Reuse canonical roles and reject legacy blue or dark-violet guidance |
| Atoll or extension API changes | Integration breakage | Version checks, adapter boundary, fallback surfaces |

## 52. Open decisions and requested founder input

These inputs improve the specification but do not block source-adapter implementation.

### 52.1 Product identity

**DECIDED:** Zoid Coach is a standalone macOS application.

It may reuse the canonical Sumi-Ink system and integrate with related Zoid components, but it owns its application lifecycle, permissions, local database, background agent, settings, release process, and user-facing identity.

### 52.2 Visual system

**DECIDED:** Zoid Coach inherits the Sumi-Ink Command System.

### 52.3 Atoll ownership

**DECIDED:** Modify and maintain Atoll and AtollExtensionKit to add native action callbacks.

The official Atoll repository is `https://github.com/Ebullioscopic/Atoll.git`.

### 52.4 Screenwatch source ownership

**DECIDED:** Move the Screenwatch source into the Zoid Coach repository.

The current local capture loop is the migration baseline until another source is provided.

### 52.5 Work schedule

**OPEN BY DESIGN:** The work schedule is not fixed.

Release 1 must support user-configurable work windows, manual day start, manual day end, and planning without assuming a fixed weekday schedule.

### 52.6 Gaming policy

Please confirm:

- Games and related apps that should count as gaming.
- Whether Discord and Twitch count only in gaming context.
- Preferred base budget.
- Preferred unlock tasks or focus-time rule.
- Whether weekends differ.
- Whether gaming after the workday should be ignored.

### 52.7 Task selection

**OPEN BY DESIGN:** The Apple Reminders list structure is not yet determined.

Onboarding must therefore discover lists and let the user include or exclude each list without requiring a predefined structure.

### 52.8 AI provider

**DECIDED FOR RELEASE 1:** Use rules only.

Provider, model, privacy, and request-budget decisions are deferred until Release 2.

### 52.9 Retention

Please confirm whether the proposed 30-day raw metadata and 365-day derived-session retention matches your privacy preference.

### 52.10 Coaching intensity

**DECIDED:** Observe for one complete week, then enable level 2 with a cap of six behavior interventions per workday.

### 52.11 Definition of successful work

Please describe whether completed deliverables, aligned time, priority-task completion, or another outcome should dominate weekly evaluation.

### 52.12 Source materials requested

Useful optional sources include:

- Any Atoll fork or extension roadmap you control.
- A sanitized export or screenshot of your Apple Reminders list structure.
- A future example of desired work hours and gaming rules when those preferences stabilize.
- Any prior notes about Zoid Coach behavior that are not in this repository.

## 53. Confirmed source inventory

### 53.1 Repository concept sources

- `README.md`
- `docs/ZOID-COACH-MVP.md`
- `docs/zoid-coach-mvp.html`

### 53.2 Screenwatch sources inspected

- `~/screenwatch/bin/capture-loop.sh`
- `~/screenwatch/days/2026-07-09/log.jsonl`
- `~/Applications/Screenwatch.app/Contents/Info.plist`

The live sample contained 1,848 metadata records across 13 application names.

The sample was used only to confirm schema, scale, and field availability.

Task, title, URL, and screenshot content were not copied into this specification.

### 53.3 Atoll sources inspected

- Installed `/Applications/Atoll.app`, version 2.2.0.
- Official `Ebullioscopic/Atoll` repository at `https://github.com/Ebullioscopic/Atoll.git`, main branch at the inspected revision.
- Official `Ebullioscopic/AtollExtensionKit` repository at commit `2965620`.
- AtollExtensionKit API documentation and descriptor models.
- Atoll XPC service and notch-experience implementation.

### 53.4 Sumi-Ink sources inspected

- `/Users/ziadnasreldin/Zoid/DESIGN.md`
- `/Users/ziadnasreldin/Zoid/Docs/design-systems/sumi-ink-command-system.md`
- `/Users/ziadnasreldin/Zoid/tokens.json`
- `/Users/ziadnasreldin/Zoid/src/App.css`

### 53.5 Source limitations

The AtollExtensionKit implementation-status document contains stale or internally inconsistent sections.

This specification therefore relies on current source types and service methods rather than status prose when they conflict.

## 54. Example prompt catalog

### 54.1 Planning

```text
Good morning.
These three tasks would make today successful.
They total 2h 35m, plus a 60m buffer.
```

### 54.2 Missing estimate

```text
How long do you expect “Edit thumbnail pack” to take?
```

### 54.3 Start recommendation

```text
Do this next: Reply to the client.
It is due today and should take about 15 minutes.
```

### 54.4 Gentle gaming nudge

```text
League has been active for 12 minutes.
Ready to return to “Edit video intro”?
```

### 54.5 Accountability prompt

```text
League has been active for 25 minutes.
Your main objective is still incomplete.
Is this intentional?
```

### 54.6 Commit mode

```text
Choose the next step.
Start a 20-minute sprint or move the task to a realistic time.
```

### 54.7 Estimate calibration

```text
You estimated 30 minutes.
Four similar tasks took 55 to 80 minutes.
Reserve 70 minutes?
```

### 54.8 Source warning

```text
Screenwatch has not reported activity for 2 minutes.
Behavior coaching is paused until the source recovers.
```

### 54.9 Review hypothesis

```text
Discord appeared immediately before two gaming sessions this week.
This may be a trigger, but the sample is small.
Test delaying Discord until the main task starts?
```

## 55. Example deterministic daily review

```text
Today

Main objective: Completed
Priority tasks: 2 of 3 completed
Active-task time: 3h 05m
Aligned work: 2h 28m
Gaming: 1h 12m
Distraction: 24m
Unknown coverage: 18m

Best work block
11:10 AM to 12:05 PM
Cursor, landing page project

Largest drift episode
League, 2:14 PM to 2:56 PM

Coach responses
1 sprint started
1 intentional override

Tomorrow
The unfinished client task is due first.
```

## 56. Definition of done

Zoid Coach Release 1 is done when it works with real local Reminders, real Screenwatch telemetry, and the installed Atoll application for at least seven consecutive days without data loss or misleading intervention behavior.

The product must demonstrate the full loop from planning through observation, one gaming-drift intervention, user response, task-state change, and review.

The dashboard and notch must remain understandable under missing data and integration failure.

The user must be able to pause, override, correct, export, and delete data.

The system must provide enough evidence to explain every behavior intervention and every learned weekly pattern.
