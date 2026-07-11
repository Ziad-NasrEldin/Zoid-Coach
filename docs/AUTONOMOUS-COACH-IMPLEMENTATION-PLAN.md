# Autonomous Coach Implementation Plan

## Document control

| Field | Value |
| --- | --- |
| Product | Zoid Coach |
| Document type | Full implementation plan |
| Status | Ready for implementation |
| Date | 2026-07-10 |
| Product authority | `docs/AUTONOMOUS-COACH-SPEC.md` |
| Existing product reference | `docs/ZOID-COACH-PRODUCT-SPEC.md` |
| Target platform | macOS 14 and later |
| Delivery model | Native Swift and SwiftUI app with bundled background agent |

## 1. Outcome

Zoid Coach will become an autonomous, local-first executive function system that prepares a daily plan overnight, maintains that plan throughout the day, and learns from actual behavior.

It will use Apple Reminders, Apple Calendar, Screenwatch metadata and screenshots, prior plans, outcomes, overrides, and visible WhatsApp conversations as evidence.

It may automatically manage Zoid-owned Reminders and Calendar work blocks.

It must request confirmation before turning an inferred WhatsApp conversation into an external calendar commitment.

The first complete delivery ends when the following loop works reliably:

```text
Observe -> normalize -> rank -> draft -> schedule -> confirm -> maintain -> review -> learn
```

## 2. Current repository baseline

The current implementation is a Swift 6 package with one macOS 14 executable target named `ZoidCoachApp`.

The app currently has these working foundations:

- Apple Reminders full-access authorization.
- Reading incomplete reminders through EventKit.
- Completing an existing reminder.
- A manual three-task daily plan with estimates and one main objective.
- SQLite persistence for source checks, daily plan entries, and reminder-list display order.
- Incremental health inspection of the Screenwatch JSONL stream.
- notification authorization and one-way test notification delivery.
- A Sumi-Ink SwiftUI dashboard.
- Nine passing Swift tests as of 2026-07-10.

The current implementation does not yet have:

- A background process that survives the main app closing.
- Calendar authorization, reads, free-busy calculation, or writes.
- Automatic Reminder priority or due-date updates.
- Persistent Screenwatch record ingestion.
- Screenshot indexing, OCR, or semantic extraction.
- An AI provider boundary or structured model-output validation.
- An automatic planner, scheduler, action outbox, or learning loop.
- Shared dashboard and notification action handling.
- macOS notification categories and action handling.
- A versioned database migration runner.
- A deterministic day-replay test harness.

`AppModel` currently coordinates UI state, source access, persistence, and business actions directly.

That shape is appropriate for the current foundation but must not become the autonomous runtime.

## 3. Key implementation decisions

### 3.1 Runtime ownership

Use two processes and shared domain modules:

- `ZoidCoach.app` owns settings, permissions, visible review, manual decisions, and recovery UI.
- `ZoidCoachAgent` runs as a bundled LaunchAgent while the user is logged in and the Mac is awake.
- `ZoidCoachAgent` owns ingestion, scheduled planning, action execution, prompt expiry, and recovery.
- The agent is the only production database writer.
- The app sends typed commands to the agent over an authenticated local XPC connection.
- The app may open a read-only SQLite connection for fast snapshots, but mutations always go through XPC.

This prevents the main SwiftUI process from becoming a scheduler and avoids competing write paths.

### 3.2 Sleep semantics

“Ziad is asleep” and “the Mac is asleep” are different runtime states.

The background agent can process overnight while the Mac is awake and the user is logged in.

Normal app code cannot continue running while the Mac itself is in system sleep.

If the Mac sleeps through the configured planning time, the agent must run the missed plan immediately after wake and label it as delayed.

Guaranteed system wake scheduling is deferred to the high-trust escalation phase because it requires separate power-management behavior and stronger user safeguards.

### 3.3 Automation ownership boundary

Create a dedicated Apple Calendar named `Zoid Coach`.

The scheduler may freely create, move, resize, or delete only events that both live in that calendar and carry a Zoid block identifier.

Existing events in other calendars are fixed constraints unless Ziad edits them manually.

Zoid Coach ranks existing Reminders internally and may update supported EventKit fields such as priority, due date, and notes.

It must not rely on Apple Reminders exposing an arbitrary visual ordering API.

### 3.4 AI boundary

AI interprets ambiguous evidence and proposes structured facts.

Deterministic code owns permissions, time accounting, collision detection, capacity limits, idempotency, action execution, and audit history.

Every AI response must validate against a versioned schema before it can affect planning.

Invalid, incomplete, or contradictory output is rejected and recorded as a redacted diagnostic.

The default inference path remains local.

Remote model use is an explicit setting with a visible data policy and must never be silently enabled by the autonomous agent.

### 3.5 WhatsApp boundary

Screenshot analysis can only read WhatsApp content that was visibly rendered and captured.

It cannot guarantee access to hidden chats, unloaded history, disappearing messages, or conversations never shown on screen.

The first implementation uses Screenwatch metadata to select WhatsApp screenshots, Apple Vision for local OCR, and structured extraction for meeting candidates.

An optional Accessibility adapter may be added if WhatsApp exposes useful visible text through the macOS accessibility tree.

The implementation must not scrape WhatsApp internal databases or send messages on Ziad's behalf.

## 4. Target architecture

```text
Apple Reminders ------\
Apple Calendar --------\
Screenwatch JSONL ------- > Source adapters -> normalized evidence -> planner -> action policy
Screenwatch images ------/                                      |               |
Visible WhatsApp text --/                                       |               |
                                                                  v               v
                                                           SQLite event log   action outbox
                                                                  |               |
                                                                  v               v
Zoid Coach app <------ authenticated XPC ------> ZoidCoachAgent -> EventKit / Notifications
```

### 4.1 Package targets

Update `Package.swift` to define these boundaries:

| Target | Type | Responsibility |
| --- | --- | --- |
| `ZoidCoachCore` | Library | Domain models, policies, planner, scheduler, reducers, protocols, and deterministic replay |
| `ZoidCoachInfrastructure` | Library | SQLite, EventKit, Screenwatch, Vision OCR, AI providers, notifications, XPC, and system lifecycle |
| `ZoidCoachApp` | Executable | SwiftUI dashboard, settings, onboarding, audit, prompt inbox, and XPC client |
| `ZoidCoachAgent` | Executable | LaunchAgent entry point, ingestion loops, scheduler, outbox executor, and XPC server |

Domain code must not import SwiftUI, EventKit, Vision, UserNotifications, or provider SDKs.

### 4.2 Planned source layout

```text
Sources/
  ZoidCoachCore/
    Domain/
    Planning/
    Scheduling/
    Meetings/
    Policies/
    Replay/
  ZoidCoachInfrastructure/
    Persistence/
    EventKit/
    Screenwatch/
    Vision/
    AI/
    Dashboard/
    Notifications/
    XPC/
    System/
  ZoidCoachAgent/
    AgentMain.swift
    AgentRuntime.swift
  ZoidCoachApp/
    AppModel.swift
    Views/
    Design/
    AppClient/
```

Existing files move only when the new targets compile and tests protect their behavior.

## 5. Domain model

### 5.1 Core entities

Implement these domain types as immutable, `Sendable`, and persistence-independent values:

- `SourceTask` for normalized Apple Reminder state.
- `CalendarCommitment` for fixed and Zoid-owned events.
- `BehaviorRecord` for one Screenwatch metadata observation.
- `ScreenshotArtifact` for an indexed screenshot reference and fingerprint.
- `ExtractedFact` for an evidence-backed semantic fact.
- `TaskEvidence` for recent work, carryover, deferral, deadline, and estimate signals.
- `PlanRun` for one deterministic or AI-assisted planning execution.
- `DailyPlan` and `DailyPlanItem` for the proposed or accepted day.
- `ScheduledBlock` for one Zoid-owned calendar reservation.
- `ActionCommand` for a requested side effect.
- `ActionAttempt` for an execution result.
- `PromptEpisode` and `PromptResponse` for one user decision.
- `MeetingCandidate` and `MeetingEvidence` for WhatsApp-derived proposals.
- `ModelRun` for structured AI input metadata, output metadata, and validation state.
- `UserPolicy` for autonomy, schedule, quiet hours, privacy, and escalation settings.

### 5.2 Important state machines

Daily plan:

```text
draft -> proposed -> accepted -> active -> reviewed -> closed
                 \-> overridden
                 \-> expired
```

Action command:

```text
pending -> executing -> succeeded
                    \-> retryable_failure -> pending
                    \-> terminal_failure
                    \-> cancelled
```

Meeting candidate:

```text
detected -> needs_clarification -> ready_for_confirmation -> accepted -> scheduled
         \-> low_confidence                             \-> edited
         \-> duplicate                                  \-> ignored
         \-> expired                                    \-> failed
```

### 5.3 Invariants

- A daily plan contains between zero and five active items.
- An accepted non-empty plan has exactly one main objective.
- Every automated mutation has one unique idempotency key.
- Only Zoid-owned Calendar events can be automatically changed.
- A WhatsApp-derived event cannot enter `scheduled` without an accepted or edited response.
- Every suggestion references at least one evidence identifier or explicitly says evidence is unavailable.
- Missing telemetry never counts as focused work or distraction.
- All persisted instants use UTC and retain the relevant local date and timezone identifier.

## 6. Persistence and migrations

### 6.1 Migration runner

Replace the current `CREATE TABLE IF NOT EXISTS` block with ordered migration files or typed migration functions.

Each migration must:

- Run inside a transaction.
- Record its version only after success.
- Create a timestamped backup before destructive changes.
- Leave the previous database readable if it fails.
- Have an upgrade test from the current version-two schema.

### 6.2 Initial autonomous schema

Create these tables in the first new schema series:

| Table | Purpose |
| --- | --- |
| `domain_events` | Immutable source and coaching events with schema version |
| `source_tasks` | Latest normalized Reminder snapshot plus source hash |
| `behavior_records` | Parsed Screenwatch metadata and ingestion checkpoint |
| `screenshot_artifacts` | Path, timestamp, source record, fingerprint, OCR state, and retention state |
| `extracted_facts` | Structured evidence with extractor version and confidence |
| `daily_plans` | Plan identity, date, timezone, state, capacity, and generation metadata |
| `daily_plan_items` | Rank, task, estimate, reason, confidence, and main-objective flag |
| `scheduled_blocks` | Plan item to EventKit event mapping and ownership token |
| `action_commands` | Transactional outbox with unique idempotency key |
| `action_attempts` | Retry history, platform response, and redacted error |
| `prompt_episodes` | Prompt state shared across dashboard and notifications |
| `prompt_responses` | Idempotent user decisions and source surface |
| `meeting_candidates` | Extracted meeting data, lifecycle state, and dedup fingerprint |
| `meeting_evidence` | Candidate-to-screenshot and OCR evidence links |
| `model_runs` | Provider, model, schema version, timing, and validation result |
| `settings` | Versioned policy values |
| `processing_checkpoints` | Per-source offsets and last successful scheduled job |

Retain the existing source-check and manual-plan data through migration.

### 6.3 Sensitive text

Store screenshot files by reference rather than duplicating image blobs in SQLite.

Encrypt retained OCR text and conversation extracts with an application key stored in Keychain.

Default raw OCR retention is 30 days and remains configurable.

Long-lived meeting records keep only the minimal accepted event facts and evidence hashes after raw text expires.

## 7. Source ingestion

### 7.1 Apple Reminders

Refactor `RemindersService` behind a `TaskSource` protocol.

Extend the normalized snapshot to include title, notes, list, due date, priority, completion, modification date, and stable source identifier.

Add source-diff ingestion so unchanged reminders do not create duplicate events.

Add commands for supported automatic changes:

- Set EventKit priority.
- Set or clear a due date.
- Append or update a bounded Zoid metadata marker in notes when needed.
- Complete only after an explicit user action or confirmed completion policy.

The app's internal rank remains canonical because EventKit does not provide a reliable arbitrary Reminder ordering contract.

### 7.2 Apple Calendar

Add `CalendarService` behind a `CalendarSource` protocol.

Update `App/Info.plist` with full Calendar access usage descriptions.

The service must:

- Request and inspect full Calendar access.
- Create or locate the dedicated `Zoid Coach` calendar.
- Read fixed commitments from configured calendars.
- Calculate free intervals in the configured planning horizon.
- Create, update, and delete Zoid-owned blocks.
- Persist EventKit identifiers and a secondary ownership token in event notes.
- Detect external edits and reconcile rather than overwrite them blindly.

### 7.3 Screenwatch

Split the current `ScreenwatchReader` into discovery, tailing, decoding, indexing, and health components.

Persist every valid new JSONL record once using the file identity and byte offset checkpoint.

Resolve an image path from the day directory and `t` timestamp when `img` is true, supporting both JPEG and WebP.

Compute a content hash and a perceptual fingerprint before scheduling expensive OCR.

Keep the legacy capture loop as a parity and rollback path until the native agent proves equivalent cadence, idle skipping, metadata, screenshots, and retention.

### 7.4 Native capture consolidation

After ingestion is stable, move Screenwatch capture into `ZoidCoachAgent`.

The native capture implementation must preserve the existing five-second metadata cadence and ninety-second idle skip.

It must expose clear Screen Recording, Accessibility, and Automation permission health.

It should support configured displays because the current main-display-only capture cannot observe WhatsApp on another display.

## 8. Evidence and AI pipeline

### 8.1 Pipeline stages

```text
Raw source -> normalized record -> deterministic features -> selective OCR -> structured extraction -> validated fact
```

Metadata classification runs before screenshot analysis so the system does not OCR every image indiscriminately.

WhatsApp OCR runs only for new, non-duplicate images whose active application is identified as WhatsApp or whose window evidence strongly indicates WhatsApp.

### 8.2 Local OCR

Use Apple Vision `VNRecognizeTextRequest` with accurate recognition for meeting-candidate screenshots.

Persist text blocks with bounding boxes, recognition confidence, locale hints, screenshot identifier, and extractor version.

Normalize bidirectional Arabic and English text without losing the original string.

### 8.3 AI provider protocol

Define one provider-neutral structured generation protocol.

Initial adapters should be:

- A deterministic rules provider used in tests and fallback mode.
- A loopback local-model adapter for a configured local runtime.
- A conditional Apple on-device model adapter where the installed macOS version supports it.
- An optional remote provider adapter enabled only by an explicit privacy setting.

Do not make the first autonomous release depend on one provider being available.

### 8.4 Structured extraction contracts

Use separate schemas for:

- Task features and effort hints.
- Activity-to-project interpretation.
- Daily-plan narrative and evidence explanation.
- WhatsApp meeting extraction.

Meeting extraction output must include participants, title, start expression, resolved start, duration, location, call link, timezone, evidence spans, ambiguity flags, and confidence.

### 8.5 Model safety

- Cap input by time window and evidence relevance.
- Never allow model-generated EventKit identifiers or action tokens.
- Validate dates against the screenshot timestamp and current timezone.
- Reject times in the past unless the message clearly describes a historical event.
- Record prompt-template and schema versions for replay.
- Cache by normalized evidence hash to avoid repeated processing.
- Apply a concurrency and daily request budget even for local models.

## 9. Daily planner

### 9.1 Capacity model

Calculate planning capacity from work windows minus fixed Calendar commitments, configured breaks, and a default buffer.

Do not fill more than 70 percent of remaining flexible time in the first automatic release.

The remaining capacity protects against estimation error and unobserved obligations.

### 9.2 Candidate construction

Build task candidates from incomplete Reminders and unresolved prior plan items.

For each candidate derive:

- Deadline urgency.
- Reminder priority.
- Carryover age.
- Deferral count.
- Explicit user selection history.
- Recent Screenwatch project activity.
- Estimated duration and uncertainty.
- Required energy and plausible time window.
- Calendar feasibility.
- Blocked or missing-input status.

### 9.3 Deterministic ranking

Use a versioned scoring policy whose features and weights are stored with each plan run.

Hard deadlines and explicit user locks outrank inferred activity.

The planner must reject any set whose estimated duration exceeds usable capacity.

AI may adjust bounded semantic features and explain the result, but it may not bypass capacity, fixed events, blocked state, or explicit exclusions.

### 9.4 Selection

Select three to five commitments when capacity supports them.

Choose one main objective based on consequence, urgency, and the user's prior explicit choices.

Allow fewer than three tasks when one large outcome credibly consumes the day.

Every plan item must show a short reason such as deadline, carried over twice, active project evidence, or waiting client commitment.

### 9.5 Dry-run comparison

Before enabling writes, run the new planner in shadow mode for at least seven observed planning cycles.

Compare proposed plans against Ziad's manual choices, completed work, actual duration, and overrides.

Shadow runs never change Reminders or Calendar.

The release gate requires explainable plans, zero capacity violations, and no unresolved timezone or duplicate-action defects.

## 10. Calendar scheduling

### 10.1 Scheduling algorithm

Convert the accepted or autonomous plan into candidate blocks using fixed commitments and free intervals.

Prefer contiguous blocks that fit the estimate plus transition time.

Do not split tasks shorter than 45 minutes.

Long tasks may split only at configured boundaries and must retain one shared plan-item identifier.

Place high-energy or high-consequence work in historically successful windows when evidence is sufficient.

Fall back to earliest feasible placement when historical evidence is sparse.

### 10.2 Replanning

Replan when:

- A fixed Calendar commitment changes.
- A Zoid block is missed by its grace period.
- A task completes early or late.
- A new high-priority Reminder appears.
- Ziad explicitly overrides the day.

Replanning may move only future Zoid-owned blocks.

It must keep completed and currently active blocks immutable.

It must produce one summarized change notification rather than a notification per moved block.

### 10.3 Transactional action outbox

Planning writes desired actions and the plan state in one SQLite transaction.

The agent executes pending commands outside that transaction.

Each command uses an idempotency key derived from action type, entity, desired state, and plan version.

On restart, the agent resumes pending and retryable commands without duplicating Calendar or Reminder mutations.

## 11. Background agent and scheduling

### 11.1 LaunchAgent packaging

Bundle `ZoidCoachAgent` and a LaunchAgent plist inside the signed app.

Register it through `SMAppService` from an explicit onboarding control.

Update `Scripts/package-app.sh` to copy, sign, and verify the helper and embedded plist with the same stable development or distribution identity.

### 11.2 Agent jobs

The agent owns these idempotent jobs:

- Continuous Screenwatch tailing.
- Periodic Reminder and Calendar snapshots.
- Selective screenshot indexing and OCR.
- Nightly plan generation.
- Morning plan prompt.
- Daytime replanning evaluation.
- Meeting-candidate extraction and prompt creation.
- Prompt expiry.
- Retention cleanup.
- Health checkpointing.

### 11.3 Schedule defaults

Use configurable defaults of 22:30 local time for the nightly draft and 08:00 local time for the morning confirmation.

Store the timezone identifier with every scheduled run.

When the machine misses a job because it was asleep or powered off, execute it once after wake and record the missed trigger.

Do not execute every missed interval.

### 11.4 Resource policy

Keep metadata ingestion lightweight and continuous.

Batch OCR and AI work when the machine is on power or idle where possible.

Pause expensive analysis under thermal pressure and resume from checkpoints.

Target less than one percent idle CPU and avoid retaining decoded screenshots in memory after extraction.

## 12. User-facing surfaces

### 12.1 Today command ledger

Evolve the current manual ledger into an evidence-backed daily command surface.

It must show:

- Drafted overnight or delayed-after-wake status.
- Three to five commitments with one main objective.
- Proposed Calendar blocks.
- One-line evidence reasons.
- Estimate and confidence language.
- Accept, adjust, exclude, and undo actions.
- A visible record of automatic changes.

### 12.2 Prompt inbox

Add one shared prompt inbox whose state feeds the dashboard and notifications.

Only one unresolved prompt episode may exist for the same decision.

Responses from any surface update the same episode using an idempotent action token.

### 12.3 Today dashboard

Use the existing Today dashboard as the persistent interactive view over the shared prompt inbox.

Required native contract:

- Stable action ID and title.
- Role and optional icon.
- Keyboard and accessibility semantics.
- Prompt-bound single-use event identifier.
- Bundle and experience validation.
- At-most-once callback delivery.

Until that dependency is available, use the existing temporary loopback web-action bridge only behind the `PromptSurface` adapter.

### 12.4 macOS notifications

Add UserNotifications authorization and categories for:

- `PLAN_READY` with Review and Accept actions.
- `MEETING_CANDIDATE` with Add, Edit, and Ignore actions.
- `PLAN_CHANGED` with Review and Undo actions.

Notification actions must use the same prompt action tokens as dashboard.

### 12.5 Settings and privacy

Add settings for work windows, quiet hours, nightly plan time, morning confirmation time, planning capacity, calendar selection, automation level, screenshot analysis, AI provider, retention, and wake-up eligibility.

Add controls to inspect source health, open the local data folder, export a redacted diagnostic bundle, delete a date range, and delete extracted conversation text.

## 13. WhatsApp meeting capture

### 13.1 Detection pipeline

1. Identify a new Screenwatch record whose application or window metadata indicates WhatsApp.
2. Resolve and fingerprint its screenshot.
3. Skip exact and near-duplicate screenshots.
4. Run local OCR and preserve positioned text blocks.
5. Reconstruct visible message order conservatively.
6. Extract a structured meeting candidate.
7. Resolve relative dates against the screenshot timestamp and locale.
8. Compare against existing Calendar events and unresolved candidates.
9. Route the result by confidence.
10. Prompt through dashboard and macOS notification when ready.

### 13.2 Confidence routing

- Confidence at or above 0.85 with complete date and time becomes `ready_for_confirmation`.
- Confidence from 0.60 through 0.84 becomes an editable draft in the prompt inbox.
- Confidence below 0.60 is retained only as short-lived extraction diagnostics and does not interrupt Ziad.
- Any conflicting date, timezone, or participant evidence forces `needs_clarification` regardless of numerical confidence.

### 13.3 Deduplication

Build a meeting fingerprint from normalized participants, resolved start, approximate duration, and title similarity.

Treat an existing event within fifteen minutes with matching participants or title as a likely duplicate.

Show the matched Calendar event when the decision is ambiguous.

### 13.4 Confirmation

The prompt must show who, when, duration, source conversation, Calendar destination, and any conflict.

`Add` creates the event exactly once.

`Edit` opens a compact editor before writing.

`Ignore` suppresses the same candidate fingerprint unless materially new evidence appears.

No action sends or replies to a WhatsApp message.

## 14. Learning loop

### 14.1 Feedback signals

Record:

- Accepted and removed plan items.
- Manual reordering.
- Estimate edits.
- Scheduled block moves.
- Reminder completion.
- Observed aligned work.
- Carryover and deferral.
- Prompt acceptance, edit, ignore, expiry, and undo.

### 14.2 Learning policy

Start with transparent aggregate features rather than opaque online weight updates.

Update estimate bias by task type using robust rolling medians.

Update preferred work windows only after enough completed aligned sessions exist.

Cap all learned adjustments and retain the previous policy version for replay and rollback.

Never interpret dismissal as laziness, failure, or a moral signal.

### 14.3 Evaluation

Track plan acceptance, completion, estimate error, schedule churn, intervention response, meeting precision, false positives, undo rate, and source coverage.

Do not collapse these into one focus score.

## 15. Reliability, security, and recovery

### 15.1 Permissions

Onboarding must separately explain and verify Reminders, Calendar, Notifications, Screen Recording, Accessibility, Automation, and launch-at-login permissions.

Each unavailable permission degrades only its dependent capability.

Planning from Reminders must remain available when screenshot analysis is disabled.

### 15.2 Crash recovery

On launch, recover incomplete plan runs, action commands, prompt episodes, and ingestion checkpoints.

Reconcile commands whose platform write may have succeeded before the local success record was committed.

Use ownership tokens and source queries before retrying a Calendar creation.

### 15.3 Database failure

If SQLite cannot be written, enter visible read-only mode and stop issuing external actions.

Retry with bounded backoff and never pretend a Calendar or Reminder write succeeded.

### 15.4 Privacy

Full local access does not imply permission to transmit private content.

Raw screenshots and OCR remain local unless a remote provider is explicitly enabled.

Remote requests must show the active redaction policy and record which evidence identifiers were sent.

Logs must never print raw conversation text, access tokens, or screenshot contents.

## 16. Testing strategy

### 16.1 Testability foundations

Inject `Clock`, `Calendar`, timezone, identifiers, source adapters, model providers, and action executors.

Create a deterministic day simulator that replays Reminder snapshots, Calendar events, Screenwatch records, screenshots, sleeps, wake events, and prompt responses.

Replay mode must never access live EventKit or send live prompts.

### 16.2 Unit tests

Cover:

- Every schema migration.
- Source diffing and checkpoint recovery.
- Capacity and ranking invariants.
- Calendar interval calculation.
- Timezone changes and daylight-saving transitions.
- Idempotency keys and outbox retries.
- Meeting state transitions.
- Date-expression resolution in English and Arabic fixtures.
- Deduplication thresholds.
- Model schema rejection.
- Retention and encryption behavior.

### 16.3 Integration tests

Use protocol fakes for EventKit reads and writes.

Use temporary SQLite databases for full agent transactions.

Use a fake dashboard client and fake notification center.

Use sanitized Screenwatch JSONL and screenshot fixtures, including WhatsApp light mode, dark mode, Arabic, English, group chat, quoted messages, and ambiguous dates.

### 16.4 End-to-end tests

Prove these flows in the packaged signed app:

1. A nightly run drafts a plan from real Reminders and fixed Calendar events.
2. Morning notification and dashboard display the same prompt episode.
3. Accepting the plan produces only Zoid-owned Calendar blocks.
4. A changed fixed meeting safely moves future Zoid blocks once.
5. A visible WhatsApp meeting proposal creates one candidate.
6. Adding the candidate creates one Calendar event and no duplicate on restart.
7. Disabling Calendar permission stops writes and shows a repair path.
8. Killing the agent during an action recovers without duplication.
9. Sleeping through a scheduled run produces one delayed plan after wake.

### 16.5 Quality gates

- `swift test` passes with no skipped critical suites.
- The packaged app and helper have valid stable signatures.
- Permissions survive rebuilds with the expected identity.
- VoiceOver can accept or edit every prompt through the main app.
- Reduced motion removes nonessential transitions.
- No horizontal clipping appears at the minimum supported window size.
- Idle agent CPU and memory stay within the resource policy.

## 17. Delivery sequence

### Milestone 0: Architecture and contracts

Deliver:

- Package target split.
- Domain protocols and immutable models.
- Versioned migration runner and current-schema upgrade test.
- Injectable clock and deterministic replay skeleton.
- XPC command and snapshot contracts.
- dashboard prompt-action validation.

Exit criteria:

- Current UI behavior remains functional.
- Existing nine tests still pass after target extraction.
- Database version-two fixtures migrate without data loss.
- The app can ping a signed local agent over XPC.

### Milestone 1: Persistent evidence foundation

Deliver:

- LaunchAgent packaging and lifecycle.
- Persistent Screenwatch tailing and screenshot indexing.
- Reminder snapshots and diffs.
- Calendar permission, fixed-event reads, and dedicated Zoid calendar.
- Processing checkpoints, source health, retention, and crash recovery.

Exit criteria:

- The agent continues ingesting when the main window is closed.
- Restarting does not duplicate source records.
- A full observed day can replay deterministically.

### Milestone 2: Overnight planner in shadow mode

Deliver:

- Capacity calculation.
- Candidate feature derivation.
- Deterministic ranking and three-to-five-task selection.
- AI provider boundary and evidence-backed explanations.
- Nightly scheduling and delayed-after-wake behavior.
- Planner comparison report in the dashboard.

Exit criteria:

- Seven shadow planning cycles complete without external writes.
- No plan exceeds usable capacity.
- Every suggested task has a truthful evidence explanation.
- AI unavailability still produces a valid deterministic plan.

### Milestone 3: Morning commitment experience

Deliver:

- Today command-ledger redesign.
- Shared prompt inbox.
- macOS notification categories.
- dashboard plan prompt and action handling.
- Accept, adjust, exclude, and undo flows.

Exit criteria:

- dashboard and notifications resolve the same prompt exactly once.
- Keyboard and VoiceOver can complete the full flow.
- The plan remains useful when dashboard is unavailable.

### Milestone 4: Automatic Apple actions

Deliver:

- Transactional action outbox.
- Reminder priority and due-date commands.
- Zoid Calendar block creation, update, deletion, and reconciliation.
- Daytime replanning and summarized change notification.
- Automatic-action audit and undo.

Exit criteria:

- Only Zoid-owned events are automatically changed.
- Restart and retry scenarios create no duplicate events.
- Calendar conflicts never disappear silently.
- Every automatic change is visible and reversible where EventKit permits.

### Milestone 5: WhatsApp meeting capture

Deliver:

- Selective local OCR.
- Arabic and English text normalization.
- Structured meeting extraction and temporal resolver.
- Confidence routing, deduplication, conflict detection, and expiry.
- dashboard and notification confirmation with compact editing.

Exit criteria:

- Sanitized fixture precision and recall meet the agreed evaluation threshold.
- No low-confidence candidate creates an interruption.
- No candidate writes a Calendar event without confirmation.
- Restart and repeated screenshots do not duplicate candidates or events.

### Milestone 6: Learning and autonomous maintenance

Deliver:

- Estimate-bias learning.
- Preferred work-window learning.
- Plan outcome review.
- Policy versioning and rollback.
- Automatic daytime maintenance under configured policy.

Exit criteria:

- Learned changes are bounded, explainable, replayable, and reversible.
- Plan churn stays below the configured limit.
- Overrides immediately change future behavior without punitive copy.

### Milestone 7: High-trust wake-up escalation

Deliver only after the prior milestones demonstrate trustworthiness:

- Explicit wake windows and quiet-day exceptions.
- Maximum intervention budget.
- Critical-commitment eligibility rules.
- Scheduled alarm-style notification.
- Optional system wake feasibility investigation.
- Post-intervention feedback and automatic aggressiveness reduction.

Exit criteria:

- Wake-up eligibility is fully explainable before activation.
- The feature cannot activate without explicit configuration.
- Every intervention has a visible reason, dismiss path, and disable control.

## 18. Recommended implementation tickets

| Order | Ticket | Depends on |
| --- | --- | --- |
| 1 | Extract `ZoidCoachCore` and integration protocols | None |
| 2 | Build ordered SQLite migrations and version-two upgrade fixture | 1 |
| 3 | Add `ZoidCoachAgent`, signing, LaunchAgent registration, and XPC ping | 1 |
| 4 | Persist Screenwatch records and image checkpoints | 2, 3 |
| 5 | Add Reminder snapshot diffing | 1, 2 |
| 6 | Add Calendar access, fixed events, and dedicated Zoid calendar | 1, 2 |
| 7 | Build replay clock and simulated-day harness | 1, 2, 4, 5, 6 |
| 8 | Implement capacity, ranking, and shadow plan runs | 7 |
| 9 | Add AI provider protocol and structured validation | 8 |
| 10 | Build prompt inbox, notifications, and dashboard action adapter | 3, 8 |
| 11 | Build action outbox and Calendar block executor | 6, 8, 10 |
| 12 | Add Reminder automatic commands and audit | 5, 11 |
| 13 | Implement selective Vision OCR and encrypted text storage | 4 |
| 14 | Implement meeting extraction, temporal resolution, and deduplication | 9, 13 |
| 15 | Build meeting confirmation and EventKit creation flow | 10, 11, 14 |
| 16 | Add learning aggregates and policy versioning | 7, 11, 12, 15 |
| 17 | Replace legacy capture with native agent after parity proof | 4, 7 |
| 18 | Implement wake-up escalation only after trust gate | 16 |

Each ticket should leave the app buildable and keep unrelated user work untouched.

## 19. Rollout policy

Use four operating modes backed by the same policies and event log:

1. `observe` ingests evidence and records what it would do.
2. `suggest` presents plans and meeting candidates but performs no automatic Apple writes.
3. `assist` writes only after plan-level confirmation.
4. `autonomous` maintains Zoid-owned Reminders and Calendar blocks automatically.

Progression is a release and trust gate, not a permanent limitation on the approved autonomous goal.

The app must always expose a one-step pause that stops new external actions without destroying the current plan or evidence.

## 20. Definition of complete

The autonomous-coach initiative is complete when:

- Zoid Coach prepares tomorrow's evidence-backed plan without the main app being open.
- The plan contains a realistic three-to-five-item commitment set or a justified smaller set.
- Fixed Calendar commitments and planning capacity constrain every schedule.
- The agent can create and safely maintain Zoid-owned Calendar blocks and supported Reminder fields.
- Morning notification and dashboard provide the same decision with an accessible dashboard fallback.
- Visible WhatsApp meeting proposals become deduplicated, confidence-aware confirmation prompts.
- Confirmed meetings are created exactly once.
- Every automatic action is evidence-backed, audited, recoverable, and reversible where the platform allows.
- Missing AI, missing telemetry, denied permissions, system sleep, and process crashes all degrade honestly.
- The planner improves from outcomes without hidden or unbounded behavior changes.
- Wake-up escalation remains disabled until its separate high-trust gate is deliberately enabled.
