# Autonomous Coach Specification

## Document control

| Field | Value |
| --- | --- |
| Product | Zoid 666 |
| Document type | Founder-approved product direction addendum |
| Status | Approved for phased implementation planning |
| Date | 2026-07-10 |
| Supersedes | The Calendar auto-scheduling and message-content exclusions in `docs/ZOID-COACH-PRODUCT-SPEC.md` |
| Canonical scope | Autonomous daily planning, Apple Reminders and Calendar actions, and WhatsApp meeting capture |

## 1. Intent

Zoid 666 will become a private, local-first executive function layer that works continuously, including while Ziad is asleep.

It will analyze prior and current evidence to construct a realistic daily plan, maintain that plan through the day, and learn from outcomes.

The system is not limited to making suggestions.

Within the policies described here, it may reprioritize Apple Reminders, create and move calendar work blocks, and surface high-value decisions through macOS and the Today dashboard surface.

The long-term direction includes explicitly authorized wake-up interventions for critical commitments.

## 2. Approved authority model

### 2.1 Automatic actions

Zoid 666 may automatically create, reprioritize, and reschedule its own Apple Reminders and work blocks in Apple Calendar.

It may adjust its own existing work blocks when new evidence makes the plan stale.

It should preserve existing non-Zoid commitments, avoid calendar collisions, respect configured work and quiet hours, and retain an undoable action record.

The intended operating mode is fully automatic daily planning, not a manual productivity dashboard.

### 2.2 Confirmed actions

Zoid 666 must request a fast, explicit confirmation before creating a calendar event inferred from a WhatsApp conversation.

This protects against natural-language ambiguity and prevents the system from representing an unconfirmed external commitment as fact.

The confirmation should be available from the Today dashboard and macOS notification.

Example:

> Meeting detected: Sarah proposed Tuesday, 15:00-15:30. Add to Work calendar? [Add] [Edit] [Ignore]

### 2.3 Future escalation actions

Wake-up interventions are intentionally deferred until the daily planner has accumulated trustworthy response and completion evidence.

Any wake-up action must be limited by explicit wake windows, a maximum intervention budget, a concrete reason, quiet-day exceptions, and a visible dismissal path.

## 3. Evidence model

The coach may use all locally available computer evidence that Ziad has authorized, including raw Screenwatch screenshots and historical activity, Apple Reminders, Apple Calendar, previous plans, completions, deferrals, overrides, and WhatsApp conversation evidence visible in Screenwatch screenshots.

All sensitive evidence should remain local by default.

Recommendations and automated actions must retain a compact evidence trail that explains why the action was selected without exposing more private content than necessary.

The evidence trail should state source coverage and uncertainty instead of fabricating precision.

## 4. Daily autonomous loop

```text
Observe -> normalize -> infer commitments -> rank work -> reserve time -> request decisions -> learn
```

### Overnight preparation

The coach ingests new evidence, detects ongoing projects and unresolved commitments, estimates task effort and urgency, selects a realistic set of three to five finish-today commitments, reprioritizes eligible reminders, and creates or adjusts calendar work blocks around existing commitments.

### Morning commitment

The coach sends a concise macOS notification and presents the full decision in the Today dashboard.

The morning surface shows the selected commitments, the schedule, the reason for each task, and a quick override path.

### Daytime maintenance

The coach watches for drift, missed blocks, emerging commitments, or changed urgency.

It silently maintains its own plan where safe and asks only when interpretation or external impact requires a decision.

### Evening learning

The coach records completion, deferral, dismissal, override, and actual work evidence.

These outcomes improve next-day ranking, task-size estimates, intervention timing, and confidence calibration.

## 5. WhatsApp meeting capture

### Acquisition

The first viable path is local screenshot OCR and vision analysis of WhatsApp content visible through Screenwatch.

This avoids depending on an unofficial or unavailable consumer WhatsApp message API.

The system should analyze incremental screenshot evidence rather than repeatedly processing an entire chat history.

### Extraction

The extractor identifies candidate commitments, participants, date, start time, duration, location or call link, timezone, and the quoted conversation evidence.

It resolves relative phrases such as "tomorrow" against the message timestamp and local timezone.

### Guardrails

The system must deduplicate candidate meetings against existing Calendar events.

Incomplete or low-confidence detections become editable drafts.

Conflicting events should show the collision before an event is added.

The system must never send WhatsApp messages, accept a meeting on Ziad's behalf, or infer consent from a vague conversation without a separate future approval.

## 6. Product experience

The active surface remains a small, ruled daily ledger in the existing Sumi-Ink Command System.

The most important information is the next commitment and the next responsible action, not productivity analytics.

Red seal is reserved for decisions that need attention, including a meeting confirmation or an overloaded plan.

Every automated action must have a written state label, a short why, and an undo route.

Coaching language stays factual, firm, and non-judgmental.

## 7. Required states

| State | Required behavior |
| --- | --- |
| No or stale telemetry | Show limited coverage and avoid confident behavioral claims. |
| Sparse or conflicting evidence | Create a draft or ask a narrow question instead of acting. |
| Calendar collision | Offer an alternative time or retain the conflict as a decision. |
| Ambiguous WhatsApp commitment | Present an editable draft, not a final event. |
| Duplicate meeting | Suppress the prompt and record the match. |
| Calendar or Reminders write failure | Preserve the proposed action, explain the failure, and offer retry. |
| Overloaded day | Reduce the plan to the smallest credible finish-today list. |
| Manual override | Respect it immediately and use it as future preference evidence. |

## 8. Delivery phases

### Phase 1: Overnight plan and morning confirmation

Build the evidence-backed daily ranking, three-to-five-task plan, Today dashboard and notification confirmation, action audit, and learning signals.

### Phase 2: Autonomous Apple automation

Add safe automatic reprioritization of Reminders plus creation and rescheduling of Zoid 666 work blocks while preserving calendar commitments.

### Phase 3: WhatsApp meeting capture

Add screenshot-based OCR and extraction, calendar deduplication, conflict detection, and the shared dashboard and notification confirmation flow.

### Phase 4: High-trust escalation

Use validated learning data to introduce configured wake-up policy and other time-sensitive interventions.

## 9. Non-negotiable constraints

Critical state, time accounting, calendar collision detection, permission handling, and audit history must remain deterministic and testable without an AI provider.

AI may interpret ambiguity, summarize evidence, rank alternatives, and explain recommendations.

AI must not be the sole authority for irreversible actions or silently create externally meaningful commitments from conversational inference.

All actions must be local-first, reversible where the platform allows it, and attributable to evidence and policy.
