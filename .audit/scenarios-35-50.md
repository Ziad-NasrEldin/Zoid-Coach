# Zoid 666 end-user scenario audit: sections 35-50

Audited on 2026-07-12 against the current `main` checkout, the installed build 8 app at `/Users/ziadnasreldin/Applications/Zoid 666.app`, the running background agent, and the complete Swift test suite.
`swift test` passed 188 tests, but those tests are predominantly model, store, and service tests rather than complete UI journeys.
The installed app was opened and its accessibility tree was inspected.
The installed app's current database path contains a zero-byte database while the already-running agent still has the former database open from `.Trash/Zoid 666`; therefore no scenario is labeled fully implemented solely from code or unit-test evidence.

## Status summary

- Fully implemented: 0
- Touches remaining: 29
- Frontend only left: 2
- Partially implemented: 38
- Barely started: 15
- Not implemented: 92
- Blocked from verification: 0
- Total scenarios audited: 176

## 35. Prompt frequency and escalation

- [ ] Receive no more than six behavior interventions during a default workday. - **Not implemented.** No behavior-intervention producer or daily behavior-cap policy exists; `AgentMain` only creates plan-ready, plan-changed, and meeting prompts.
- [ ] Avoid having estimate requests and source warnings counted against the behavior cap. - **Not implemented.** There is no behavior-cap ledger or prompt-type accounting to distinguish these cases.
- [ ] Receive no duplicate prompt during its cooldown. - **Barely started.** `PromptInboxStore` deduplicates one unresolved `decisionKey`, but there is no behavior cooldown model, expiry policy, or end-user behavior-prompt flow.
- [ ] Receive a 15-minute pause after a gentle nudge. - **Not implemented.** No gentle-nudge prompt or 15-minute suppression state exists.
- [ ] Receive a 20-minute pause after answering an accountability prompt. - **Not implemented.** No accountability-prompt producer or response-specific suppression timer exists.
- [ ] Receive the selected snooze duration after choosing a snooze. - **Not implemented.** `PromptActionKind` has no snooze action or duration payload.
- [ ] Receive a 45-minute same-behavior pause after an intentional override. - **Not implemented.** `continueIntentionally` is only an unused action enum; no override window is stored or enforced.
- [ ] Receive no more prompts that day after choosing `I am done today`. - **Barely started.** `endWorkday` exists as an action enum, but it is not surfaced, routed, or persisted as a day-level prompt stop.
- [ ] See later drift recorded quietly after reaching the prompt cap. - **Not implemented.** There is no prompt-cap state and no quiet post-cap drift ledger.
- [ ] See quietly recorded drift summarized only during review. - **Not implemented.** The Reviews navigation item renders the generic source-health foundation view, not a drift review.
- [ ] See coaching return to observation after aligned work resumes. - **Not implemented.** `CoachingState` is display-only and no behavior episode state machine returns it to observation.
- [ ] See coaching de-escalate after starting a break, pausing work, rescheduling, or ending the day. - **Not implemented.** Task commands exist, but they are not connected to behavior-coaching escalation state.

## 36. Intentional gaming

- [ ] Choose to continue gaming intentionally. - **Barely started.** `PromptActionKind.continueIntentionally` exists, but no generated prompt or visible button uses it.
- [ ] See the current prompt close immediately. - **Barely started.** Generic prompt responses close a prompt atomically, but the intentional-gaming prompt is never created and the action has no effect router.
- [ ] Avoid another equivalent prompt during the override window. - **Not implemented.** No intentional-override window is persisted or checked.
- [ ] Continue seeing gaming time tracked. - **Partially implemented.** Screenwatch observations are classified and the Today dashboard shows gaming usage, but this was not exercised through an intentional-override journey.
- [ ] See incomplete priority work remain visible without moral judgment. - **Partially implemented.** Planned and incomplete tasks remain visible in Today with neutral state labels, but there is no intentional-gaming context tying the behavior to that presentation.
- [ ] See the intentional choice recorded factually in the review. - **Not implemented.** There is no daily review UI or intentional-choice review record.
- [ ] Return to work before the override ends. - **Not implemented.** Work observations can be tracked, but there is no override lifecycle to end early.
- [ ] Receive normal coaching again after the override expires if conditions still apply. - **Not implemented.** Neither override expiry nor normal behavior coaching is implemented.

## 37. Dashboard active-task status

- [ ] See the active task in the Today dashboard. - **Touches remaining.** `TodayDashboardCommandOverview` selects `snapshot.activeTask` and renders the active commitment; `TaskExecutionStore` and dashboard tests cover state, but the installed app's detached live database prevented a complete start-to-visible-active verification.
- [ ] See elapsed time for an open-ended task. - **Frontend only left.** `TodayTaskRow.elapsedMinutes` and `TaskExecutionStore.elapsedMinutes` are implemented and tested, but the current Today UI never renders elapsed minutes.
- [ ] See remaining time for a sprint. - **Not implemented.** There is no sprint execution mode, countdown, or remaining-time field in the active-task model or UI.
- [ ] See estimate or meaningful progress where appropriate. - **Partially implemented.** Estimates are editable and visible, and elapsed minutes are stored, but progress/elapsed information is not presented to the user.
- [ ] See the dashboard update when pausing, resuming, switching, or completing a task. - **Touches remaining.** All commands are wired through `AppModel.applyTaskCommand`, snapshot refreshes, and passing tests cover transitions and switching; a complete installed-app journey was blocked by the current database state.
- [ ] Use the compact active-task view without losing essential task state. - **Not implemented.** The menu-bar surface is only `Zoid Voice`; there is no compact active-task view.
- [ ] Open the full dashboard for totals, gaming budget, coaching state, and primary actions. - **Partially implemented.** The full Today dashboard shows behavior totals, gaming budget, and task actions, but behavior-coaching state and intervention controls are absent.
- [ ] See the task activity disappear when no useful active state remains. - **Touches remaining.** Snapshot state removes `activeTask` after completion and tests verify completion refresh; installed UI cleanup was not verified end to end.
- [ ] Avoid distracting updates more often than necessary. - **Partially implemented.** The UI refreshes after explicit commands rather than on a rapid visual timer, but there is no usability test or explicit update-throttling contract.

## 38. Prompt fallback surfaces

- [ ] Receive a macOS notification when notification permission is available. - **Partially implemented.** `PromptNotificationCoordinator` schedules authorized plan, meeting, and plan-change notifications, but behavior prompts are not produced and live delivery was not exercised.
- [ ] See a menu bar badge if notifications are unavailable. - **Not implemented.** No prompt badge exists in `MenuBarExtra` or another menu-bar surface.
- [ ] Find every unresolved prompt in the dashboard. - **Touches remaining.** `PromptInboxLedger` displays the shared unresolved prompt store and explains the shared surface; persistence tests pass, but the installed app had no healthy live prompt journey to verify.
- [ ] Respond from any available surface. - **Partially implemented.** Dashboard and notification response paths exist for supported prompt categories, but behavior actions are not registered as notification categories and several action kinds have no effects.
- [ ] See all other surfaces update after responding once. - **Partially implemented.** The shared store is atomic, but there is no demonstrated notification withdrawal or menu-bar synchronization after a dashboard response.
- [ ] Avoid having two surfaces start duplicate sprints or apply the same choice twice. - **Touches remaining.** Response tokens and `PromptInboxStore.respond` are idempotent and concurrency tests pass; sprint effects themselves are not implemented and no multi-surface UI test exists.
- [ ] See only the latest relevant notification when delivery is throttled. - **Not implemented.** Notifications use prompt-specific identifiers, but there is no relevance/throttling policy that cancels older decisions.
- [ ] Continue using all task controls without notifications. - **Touches remaining.** Today task controls do not depend on notification authorization and are covered by task-store/dashboard tests; the live denied-permission journey was not run.

## 39. Pausing coaching

- [ ] Pause coaching for one hour. - **Not implemented.** Settings only supports an indefinite automation pause.
- [ ] Pause coaching until tomorrow. - **Not implemented.** `AutomationPause` has no until-tomorrow state or expiry.
- [ ] Resume coaching before the pause expires. - **Partially implemented.** The user can resume an indefinite automation pause and that immediate save is tested, but timed coaching pauses do not exist.
- [ ] See clearly that coaching is paused. - **Touches remaining.** Settings shows `PAUSED`, and source-health headers expose `CoachingState.paused`; this was visible in code/accessibility structure but not exercised as a live state change.
- [ ] Continue tracking tasks and behavior while coaching prompts are paused. - **Partially implemented.** Task and Screenwatch pipelines are separate from the saved automation-pause flag, but there is no end-to-end test proving ingestion continues throughout a pause.
- [ ] Avoid receiving behavior interventions during the pause. - **Not implemented.** Behavior interventions are not implemented, and no pause-specific suppression policy exists.
- [ ] End the workday from the pause controls. - **Not implemented.** The Settings pause card only pauses/resumes all automation; it has no end-workday control.
- [ ] Disable notification prompts while retaining dashboard access. - **Not implemented.** There is no notification-prompt preference independent of dashboard access.
- [ ] Stop Screenwatch ingestion without deleting existing data. - **Not implemented.** Capture mode can switch pipelines, but there is no user-facing stop-ingestion switch.

## 40. End-of-day review trigger

- [ ] Open the review at the configured review time. - **Not implemented.** Settings has nightly planning and morning confirmation times, but no review time or review UI.
- [ ] Open the review immediately after ending the workday manually. - **Not implemented.** There is no manual end-workday flow or daily review screen.
- [ ] Find an unfinished previous-day review on the next launch. - **Not implemented.** No review draft/persistence lifecycle exists.
- [ ] Delay the review without losing the day's evidence. - **Not implemented.** Evidence persists independently, but there is no delay-review action or review state.
- [ ] Resume an unfinished review after restarting the app. - **Not implemented.** No unfinished-review record exists.
- [ ] Skip the review explicitly and close the day. - **Not implemented.** No skip-review or close-day action exists.

## 41. Understanding the daily review

- [ ] See whether the main objective was completed. - **Barely started.** Main-objective and task-completion data exist in daily-plan/task stores, but there is no daily review aggregator or UI.
- [ ] See how many priority tasks were completed. - **Barely started.** Task states and priorities exist, but no review count is computed or displayed.
- [ ] See total active-task time. - **Barely started.** Task intervals and elapsed minutes are stored, but no day-level review total is produced.
- [ ] See aligned work time separately. - **Barely started.** Work-classified Screenwatch time appears in Today, but it is not reconciled with tasks in a review.
- [ ] See work broken down by category. - **Barely started.** Today can group application observations by classification, but no review categories or historical review presentation exist.
- [ ] See gaming and distraction time. - **Barely started.** Today stores and displays these totals, but the Reviews surface is a placeholder.
- [ ] See reliable idle time. - **Barely started.** Idle observations are summarized in the core, but not presented as a review with reliability context.
- [ ] See unknown or missing coverage. - **Barely started.** Today exposes limited coverage and unknown time, but no daily-review view exists.
- [ ] See the best work block. - **Not implemented.** No best-block calculation or review presentation was found.
- [ ] See the largest drift episode. - **Not implemented.** No drift-episode review calculation exists.
- [ ] See coaching prompts and responses. - **Not implemented.** Prompt records exist for plans/meetings, but no review presentation and no behavior coaching records exist.
- [ ] See intentional gaming overrides. - **Not implemented.** Overrides are not stored.
- [ ] See estimate-versus-actual comparisons. - **Barely started.** Estimate-learning aggregates store estimate/actual samples, but no user review display exists.
- [ ] Understand when incomplete data makes a total less precise. - **Partially implemented.** Today labels limited Screenwatch coverage, but the absent review cannot qualify each review total.
- [ ] Receive a complete factual review without AI. - **Not implemented.** Rules-only planning exists, but no factual daily-review generator exists.

## 42. Facts, hypotheses, and review corrections

- [ ] See observed facts labeled separately from context and hypotheses. - **Not implemented.** No review model or facts/hypotheses UI exists.
- [ ] See evidence supporting a causal hypothesis. - **Not implemented.** No causal-hypothesis generator or evidence view exists.
- [ ] Reject a causal hypothesis. - **Not implemented.** No hypothesis correction action exists.
- [ ] Reclassify a behavior session from the review. - **Not implemented.** App classification affects future observations only; session-level review correction is absent.
- [ ] Split or merge a session from the review when needed. - **Not implemented.** There is no session editor.
- [ ] Add away-from-Mac work. - **Not implemented.** No manual activity-entry flow exists.
- [ ] Correct a task's completion state. - **Not implemented.** Today can complete a task, but there is no review correction or reopen operation.
- [ ] Add a personal note. - **Not implemented.** No review-note field or storage exists.
- [ ] Change tomorrow's main task. - **Partially implemented.** A user can choose the main objective for the current daily plan, but there is no tomorrow/review-specific flow.
- [ ] See totals and conclusions update after corrections. - **Not implemented.** Review corrections and conclusions do not exist.
- [ ] Confirm the corrected review. - **Not implemented.** There is no review confirmation state.
- [ ] Prevent unconfirmed hypotheses from becoming learned facts. - **Not implemented.** Learning aggregates have evidence/confidence safeguards, but no hypothesis-confirmation boundary exists.

## 43. Weekly review

- [ ] Receive a weekly review after at least three days with acceptable coverage. - **Not implemented.** No weekly-review scheduler, model, or UI exists.
- [ ] Receive a data-quality summary instead of strong conclusions when evidence is insufficient. - **Not implemented.** Limited coverage is shown for Today only; no weekly summary exists.
- [ ] See completed outcomes and planned-versus-completed work. - **Not implemented.** Historical data exists, but there is no weekly outcome aggregation.
- [ ] See estimate accuracy patterns. - **Barely started.** `LearningAggregateStore` persists estimate accuracy samples with confidence, but exposes no weekly user view.
- [ ] See the best work windows. - **Barely started.** Work-window learning aggregates exist, but no weekly review presentation exists.
- [ ] See frequent drift triggers. - **Not implemented.** No weekly drift-trigger aggregation exists.
- [ ] See gaming timing and budget adherence. - **Not implemented.** Daily gaming totals exist, but no weekly timing/adherence view exists.
- [ ] See recovery success after coaching prompts. - **Not implemented.** Behavior coaching and recovery outcomes are absent.
- [ ] See which prompts were useful or ineffective. - **Not implemented.** No prompt-effectiveness analysis exists.
- [ ] See repeated blocked or vague tasks. - **Not implemented.** Blocked task state exists, but no weekly repetition/vagueness analysis exists.
- [ ] See sample size, date range, examples, confidence, and alternative explanations for every pattern. - **Not implemented.** Learning stores track samples/confidence internally, but no complete explanatory weekly pattern object or UI exists.
- [ ] Receive no more than one primary behavioral experiment for the next week. - **Not implemented.** No behavioral-experiment model exists.
- [ ] Accept the experiment. - **Not implemented.** No experiment action exists.
- [ ] Edit the experiment. - **Not implemented.** No experiment editor exists.
- [ ] Reject the experiment. - **Not implemented.** No experiment action exists.
- [ ] Track an accepted experiment during the following week. - **Not implemented.** No experiment persistence/tracking exists.

## 44. General settings

- [ ] Enable or disable launch at login. - **Not implemented.** The app auto-registers the bundled agent on launch; `disableAndInspect` exists in the service but no settings control calls it.
- [ ] Set workday start and end times. - **Touches remaining.** Both controls persist through versioned policy and settings tests pass; the installed database condition blocked a live save/relaunch check.
- [ ] Set planning and review times. - **Partially implemented.** Nightly planning and morning confirmation are configurable, but review time is absent.
- [ ] Use manual workday start and end without fixed hours. - **Not implemented.** No manual-workday mode or start/end controls exist.
- [ ] Configure time-zone behavior. - **Not implemented.** Policy preserves the existing time zone and the UI only states the current zone; it cannot be configured.
- [ ] Configure keyboard shortcuts. - **Partially implemented.** Voice hotkey presets are configurable in the Voice section, but there is no general shortcut configuration for task and coaching actions.
- [ ] See current permission and connection states. - **Touches remaining.** Source health and macOS permission ledgers expose Reminders, Calendar, notifications, agent, Screenwatch, Accessibility, Automation, and screen recording; current runtime inspection confirmed the surfaces, but several statuses are coarse.
- [ ] Change included Reminder lists. - **Not implemented.** All incomplete reminders are fetched; list order can change, but inclusion/exclusion cannot.
- [ ] Change the Screenwatch folder. - **Not implemented.** The app fixes the path to `~/screenwatch/days`; only the agent CLI accepts an override.
- [ ] Test Screenwatch health. - **Touches remaining.** Source Check and Screenwatch Refresh inspect schema-valid/stale/missing streams, with passing reader/source tests; live health was not trusted because the app database is detached.
- [ ] See notification authorization and delivery state. - **Partially implemented.** Authorization is shown; last delivery result is not stored or displayed.
- [ ] Send a test notification. - **Not implemented.** No test-notification control exists.
- [ ] See notification authorization status. - **Touches remaining.** `NotificationService.inspect` maps macOS authorization into Source Health; runtime accessibility confirmed the Source health surface, though denial repair is incomplete.

## 45. Coaching and classification settings

- [ ] Choose the coaching mode. - **Partially implemented.** Observe, Suggest, Approve actions, and Autonomous operating modes exist, but these control automation authority rather than behavior-coaching style.
- [ ] Choose the maximum intervention level. - **Not implemented.** Only a wake-intervention daily maximum exists; no coaching escalation ceiling exists.
- [ ] Change the daily prompt cap. - **Not implemented.** No behavior prompt-cap setting exists.
- [ ] Change quiet hours. - **Touches remaining.** Quiet start/end controls persist in the versioned schedule policy; enforcement is present for scheduled wake behavior, but a complete behavior-prompt journey cannot be tested because behavior prompts are absent.
- [ ] Change cooldowns. - **Not implemented.** No cooldown controls or policy fields exist.
- [ ] Change the task-start grace period. - **Not implemented.** No grace-period setting exists.
- [ ] Change the default coaching-pause duration. - **Not implemented.** Only an indefinite pause exists.
- [ ] Review application rules. - **Touches remaining.** `AppClassificationLedger` lists known/saved applications and work, gaming, or automatic choices; persistence tests pass, but a live classify-observe-result journey was not run.
- [ ] Review domain rules. - **Not implemented.** URL/domain classification rules are not exposed or modeled.
- [ ] Review project mappings. - **Not implemented.** No project-mapping model or UI exists.
- [ ] Review unknown sessions. - **Not implemented.** Unknown time can appear in totals, but there is no session review queue.
- [ ] Enable or disable screenshot analysis. - **Touches remaining.** A persisted Screenwatch screenshot-analysis toggle exists and policy tests cover persistence; live agent behavior after toggling was not verified.
- [ ] Import classification rules. - **Not implemented.** No import command or UI exists.
- [ ] Export classification rules. - **Not implemented.** No export command or UI exists.
- [ ] Reset learned rules. - **Not implemented.** Policy rollback exists, but there is no targeted learned-rule reset.

## 46. AI settings and behavior

- [ ] Use rules-only mode with all Release 1 functionality available. - **Partially implemented.** Disabled-AI/local-only mode preserves deterministic planning and task controls, but daily/weekly reviews, coaching, and many Release 1 scenarios are missing.
- [ ] See that remote AI is off until explicitly configured. - **Touches remaining.** Defaults select Disabled and Local only, remote evidence is disabled for local providers, and policy tests enforce it; the live installed policy could not be verified safely against the detached database.
- [ ] Choose a future approved provider and model. - **Touches remaining.** Settings exposes Disabled, local Ollama, and Codex CLI according to capability gates, plus model/reasoning selection; actual provider execution was not exercised end to end.
- [ ] Choose local or remote processing when supported. - **Partially implemented.** Provider and Remote Evidence controls distinguish local-only/redacted/private modes, but the wording is evidence policy rather than a simple processing-location choice and no request preview is supplied.
- [ ] Preview a representative redacted payload before enabling remote AI. - **Not implemented.** Explanatory copy exists, but no payload preview exists.
- [ ] Set a daily or monthly request budget. - **Frontend only left.** `ModelRunStore` enforces a supplied daily request budget and voice has a separate Gemini cap, but general AI policy/settings do not expose a daily or monthly budget.
- [ ] Clear the AI cache. - **Not implemented.** Model runs can be queried as cache entries, but there is no clear-cache command or UI.
- [ ] Disable AI instantly without disabling planning, tracking, coaching rules, or reviews. - **Partially implemented.** Selecting Disabled preserves deterministic planning/tracking, but behavior coaching and reviews are not available to preserve, and saving depends on the agent/database path.
- [ ] Continue using Zoid 666 while offline. - **Touches remaining.** Core planning, tracking, settings, and task commands are local and rules-first; no installed-app network-off acceptance test was run.
- [ ] See ambiguous activity remain unknown when AI fails. - **Partially implemented.** Unknown classification and structured-provider failure states exist, but no end-user AI-failure journey proves ambiguous sessions remain visibly unknown.
- [ ] Receive a deterministic factual review when AI is unavailable. - **Not implemented.** No daily review generator exists.
- [ ] Avoid having AI directly complete, delete, reschedule, block, or override a corrected task. - **Partially implemented.** Structured generation is separated from explicit mutation/outbox commands and trust gates, but corrected-task locks and a complete adversarial E2E test are absent.

## 47. Privacy and data controls

- [ ] Understand which data stays local. - **Partially implemented.** Settings repeatedly labels local-first behavior and explains remote-evidence modes, but there is no complete inventory of every stored data class.
- [ ] Understand when a remote AI request could leave the Mac. - **Touches remaining.** Remote Evidence help text distinguishes local-only, redacted metadata, and explicitly private content; it still lacks a representative payload preview.
- [ ] See what data an export will contain before creating it. - **Not implemented.** Export runs immediately; no preview or manifest confirmation is shown first.
- [ ] Choose an explicit export destination. - **Not implemented.** Diagnostics are written automatically under the app's `Diagnostics` directory.
- [ ] Open the local data folder. - **Touches remaining.** The button calls `NSWorkspace.open` on the storage directory, but the current runtime reveals a serious edge case: the agent retained an open database after that directory was moved to Trash while the app created a zero-byte replacement.
- [ ] Configure retention separately for raw records, sessions, prompts, reviews, and diagnostics. - **Partially implemented.** Screenshots, extracted text, and diagnostics have separate retention fields; raw behavior records, sessions, prompts, and reviews do not.
- [ ] Delete one behavior session. - **Not implemented.** No session-level delete command exists.
- [ ] Delete one day. - **Not implemented.** The date-range service is half-open and rejects equal start/end dates, while the UI labels the end as `THROUGH`; there is no safe one-day shortcut.
- [ ] Delete a date range. - **Partially implemented.** A confirmation-backed range deletion exists and is unit tested, but its exclusive end conflicts with the UI's inclusive wording and the UI does not refresh totals afterward.
- [ ] Delete all raw behavior metadata. - **Not implemented.** No targeted all-behavior delete command exists.
- [ ] Delete AI request metadata. - **Not implemented.** No model-run deletion command exists.
- [ ] Delete reviews and learned rules. - **Not implemented.** No targeted command exists, and reviews themselves are absent.
- [ ] Delete all Zoid 666 data. - **Not implemented.** No delete-all command exists.
- [ ] See related totals and conclusions disappear when their evidence is deleted. - **Partially implemented.** Range deletion removes behavior rows and plan entries, but `performDataCommand` does not refresh Today, and review conclusions do not exist.
- [ ] Export redacted diagnostics without exposing raw titles, URLs, notes, screenshots, prompts, or credentials. - **Touches remaining.** `PrivacyDataService` exports only grouped state counts and explicitly omits those fields, with passing tests; there is no pre-export review and no live package inspection in this audit.

## 48. Source health and diagnostics

- [ ] See Reminders permission and last successful sync. - **Partially implemented.** Source health shows permission and current counts/list discovery, but not the timestamp of the last successful sync.
- [ ] See Screenwatch path and time of the last valid record. - **Partially implemented.** Missing-state evidence shows the path and healthy/stale state shows relative age, but the UI does not show the absolute last-record time together with the path.
- [ ] See whether Screenwatch is waiting, healthy, stale, missing, denied, incompatible, or failing to parse. - **Partially implemented.** Healthy, stale, missing, empty/no-valid-record, and read-failure details exist, but denied/incompatible/schema states are not distinct and some collapse to generic Attention.
- [ ] See notification authorization and the last delivery result. - **Partially implemented.** Authorization is mapped to Source Health; delivery attempts/results are not persisted or displayed.
- [ ] See local database health, size, and last migration. - **Not implemented.** The UI has a read-only safety banner but no database size/migration diagnostic. This audit found a zero-byte current database and an agent still holding the former Trash path, which the UI does not explain.
- [ ] See the current AI mode and recent provider failures. - **Not implemented.** Settings shows the selected provider, but Source Health has no AI row or recent failure history.
- [ ] See whether the background helper is running. - **Partially implemented.** Source Health reports `SMAppService` registration status, not verified process liveness; this audit independently confirmed a running `ZoidCoachAgent` process.
- [ ] Understand the impact of each unhealthy source. - **Touches remaining.** Source rows include detail/evidence and Today shows limited Screenwatch coverage, but several states do not explain all downstream feature impacts.
- [ ] Open a direct repair action when one is available. - **Partially implemented.** Source rows offer Connect/Retry/Refresh and capture permissions open System Settings; a denied notification Retry only requests authorization again instead of opening the correct settings pane.
- [ ] Export a safe diagnostic package after reviewing its contents. - **Partially implemented.** Safe redacted JSON export exists, but there is no content review before creation and it is a single file rather than a reviewed package.

## 49. Screenwatch outage and recovery

- [ ] See a warning when Screenwatch stops reporting during active use. - **Partially implemented.** Today Source Freshness and coverage text show `limited`/stale state, but there is no prominent active-use warning or proven automatic foreground refresh.
- [ ] Understand that behavior totals and drift detection are temporarily unreliable. - **Partially implemented.** The dashboard states that Screenwatch coverage is limited/stale, but does not explicitly mention drift-detection suspension.
- [ ] Avoid receiving behavior prompts while Screenwatch is stale. - **Not implemented.** Behavior prompts do not exist, so no stale-source suppression behavior can be verified.
- [ ] Continue planning and manually tracking tasks during the outage. - **Touches remaining.** Planning/task execution is architecturally independent of Screenwatch and tests pass with limited coverage; the installed database condition blocked a live outage journey.
- [ ] See missing time represented as missing rather than productive or distracting. - **Partially implemented.** The sessionizer leaves totals unchanged and marks coverage limited, but does not display the amount of missing time explicitly.
- [ ] See Screenwatch return to healthy automatically when valid activity resumes. - **Partially implemented.** Reader state becomes healthy when refreshed with a valid recent record, with tests for healthy/missing states; the foreground app lacks a proven periodic refresh and no live recovery was exercised.
- [ ] Continue totals from the correct point without obvious duplicates after recovery. - **Touches remaining.** Archive/checkpoint tests cover incremental reads, partial lines, and deterministic replay without duplicate ingestion; live outage/recovery totals were not verified.
- [ ] See a clear schema-mismatch message when the source format changes. - **Not implemented.** Invalid records produce the generic `no valid records` or read-failure message, not a schema mismatch with repair guidance.
- [ ] Preserve prior activity and task history during the outage. - **Touches remaining.** Existing history is not deleted by missing/stale reads and stores are independently tested; the current detached-database runtime is an unresolved durability concern.

## 50. Notification failure

- [ ] Continue using Zoid 666 when notification permission is unavailable. - **Touches remaining.** Notification scheduling returns false without blocking Today, planning, or task controls; installed-app denied-permission E2E was not run.
- [ ] See a permission repair path when notification access is revoked. - **Partially implemented.** Source Health explains enabling notifications and offers Retry, but does not directly open Notification settings after denial.
- [ ] Receive prompts through the Today dashboard when notification delivery fails. - **Touches remaining.** Prompt episodes persist in the shared inbox independently of notification scheduling, with store tests; no live failed-delivery prompt was created.
- [ ] Continue seeing active-task state in the dashboard and menu bar. - **Partially implemented.** The dashboard state is independent of notifications, but the menu bar has only Zoid Voice and no active-task state.
- [ ] Avoid losing a prompt response when notification handling is interrupted. - **Touches remaining.** Prompt response plus pending effect is transactional, token-bound, idempotent, and concurrency tested; notification-process interruption itself lacks a live E2E test.
- [ ] Continue using in-app prompts when notification permission is denied. - **Touches remaining.** Dashboard prompt controls read/write the same local store without checking notification authorization; a live denied-permission acceptance test remains.
- [ ] Avoid receiving stacked duplicate notifications for one coaching decision. - **Touches remaining.** Unresolved `decisionKey` deduplication and deterministic notification identifiers prevent duplicate scheduling for supported prompt types, but behavior-coaching decisions are not implemented and live Notification Center stacking was not inspected.

## Verification evidence

- `swift test`: 188 tests passed in 4 suites.
- Installed app: version `0.1.0`, build `8`, bundle ID `com.ziadnasreldin.ZoidCoach`.
- Runtime: main app and `ZoidCoachAgent` were both running.
- UI inspection: Today, Source health, Reviews, and Settings navigation entries exist; Reviews currently shares the generic source-health/foundation content because `DashboardView` only special-cases Today and Settings.
- Runtime storage blocker: the current Application Support database is zero bytes, while `lsof` shows the running agent holding `/Users/ziadnasreldin/.Trash/Zoid 666/zoid-coach.sqlite` and its WAL/SHM files open.
