# Zoid Coach End-User Scenario Audit: Sections 18-34

Audit date: 2026-07-12.

This audit uses a strict end-user bar.
An item is checked only when the complete flow is available through the UI, its action has a real effect, failure and recovery behavior are usable, and the current installed app provides credible runtime proof.

Evidence used:

- Installed app `/Users/ziadnasreldin/Applications/Zoid Coach.app`, version `0.1.0`, build `8`.
- Live Computer Use accessibility inspection of the Today dashboard.
- Current source and tests under `Sources/` and `Tests/`.
- `swift test` in the current checkout.
- Process and persistence inspection for the running app and background agent.

Critical runtime caveat:
The running `ZoidCoachAgent` process still has its live SQLite files open under `$HOME/.Trash/Zoid Coach/`, while the canonical `$HOME/Library/Application Support/Zoid Coach/zoid-coach.sqlite` is currently a zero-byte file.
The installed app can display state through that already-running agent, but persistence and restart behavior are not trustworthy until the agent and canonical database are repaired and reverified.

Status meanings:

- **Fully implemented**: Complete and end-to-end usable now.
- **Touches remaining**: Usable core flow exists, with smaller but material usability or verification gaps.
- **Frontend only left**: Backend behavior exists, but the end user cannot access the complete flow in the UI.
- **Partially implemented**: A meaningful subset exists, but important behavior is missing.
- **Barely started**: Types, storage, or a generic shell exists without the intended usable flow.
- **Not implemented**: No meaningful implementation of this user scenario was found.
- **Blocked from verification**: The flow may exist, but current runtime conditions prevent a credible end-to-end conclusion.

## 18. Active-task controls

- [ ] See the active task title and elapsed time. - **Status: Partially implemented.** The live Today dashboard shows the active task title, but it shows `ACTIVE COMMITMENT · 45 MIN`, which is the estimate, not elapsed time. `ActiveTaskSnapshot.elapsedMinutes` and `TodayTaskRow.elapsedMinutes` exist, but the active UI does not render them.
- [ ] See sprint time remaining when applicable. - **Status: Not implemented.** There is no sprint session model, countdown field, or active sprint UI. The only short-sprint artifact is a prompt action enum.
- [ ] See progress against the estimate when meaningful. - **Status: Not implemented.** The UI renders the estimate and the execution store tracks elapsed minutes, but no view calculates or presents elapsed-versus-estimate progress.
- [ ] See whether the current computer context appears aligned, uncertain, or mismatched. - **Status: Not implemented.** Behavior classification and telemetry coverage exist, but there is no task-context alignment state or active-task alignment UI.
- [ ] Read neutral alignment language rather than judgmental productivity labels. - **Status: Barely started.** Existing copy is generally neutral, but no alignment result is generated or displayed, so the intended scenario cannot be exercised.
- [ ] Pause the task. - **Status: Frontend only left.** `TaskActivityCommand.pause` and `TaskExecutionStore.apply(.pause)` persist the transition, but the live active-task card only exposes `COMPLETE FOCUS`; there is no pause control.
- [ ] Resume the task. - **Status: Partially implemented.** The backend supports resume and the overview renders `RESUME FOCUS` for a paused row, but the user has no active pause control to reach that state through the same UI, and live end-to-end use was not safely demonstrated.
- [ ] Complete the task. - **Status: Touches remaining.** The live active card exposes `COMPLETE FOCUS`, and the agent records completion and enqueues an Apple Reminders completion action. The UI does not wait for or display source confirmation, and the orphaned live database prevents trustworthy restart and persistence proof.
- [ ] Mark the task blocked. - **Status: Frontend only left.** The execution store supports `.block`, but no active-task or task-row control exposes it, and no reason capture or replanning UI exists.
- [ ] Switch to another task. - **Status: Partially implemented.** Other task rows expose `START`, and `TaskExecutionStoreTests.startingAnotherTaskAtomicallyPausesTheExistingTask` verifies atomic backend switching. The live action was not executed against the user's real tasks, and the UI gives no explicit switch confirmation.
- [ ] See every active-task surface update promptly after an action. - **Status: Partially implemented.** XPC commands return a refreshed Today snapshot, so the dashboard can update immediately. There is no task-focused menu bar surface, no polling proof across surfaces, and no live action test.

## 19. Pausing and switching

- [ ] Pause for a break. - **Status: Not implemented.** There is no pause-reason picker or break session model.
- [ ] Pause because the task is blocked. - **Status: Not implemented.** Pause and block are separate backend states, but there is no user-facing reason flow.
- [ ] Pause while switching tasks. - **Status: Partially implemented.** Starting another task atomically pauses the previous task in `TaskExecutionStore`, with a passing unit test. The UI does not explain that transition or let the user choose this reason.
- [ ] Pause for an external interruption. - **Status: Not implemented.** No interruption reason is modeled or displayed.
- [ ] Pause because the user is done for now. - **Status: Not implemented.** No pause reason or done-for-now action exists.
- [ ] Pause when ending the workday. - **Status: Not implemented.** There is no end-workday flow wired to task execution.
- [ ] See the selected pause reason in task history or review where relevant. - **Status: Not implemented.** Task execution persists state and intervals only; pause reasons are neither stored nor rendered.
- [ ] Resume the paused task later. - **Status: Partially implemented.** Resume persistence exists and paused rows can render a resume action, but the current UI lacks the pause entry point and the canonical live database is broken.
- [ ] Switch tasks without losing the earlier task's tracked time. - **Status: Touches remaining.** `TaskExecutionStoreTests.startingAnotherTaskAtomicallyPausesTheExistingTask` proves the earlier interval is closed and elapsed time retained. End-to-end UI and restart proof remain blocked by the current datastore state.
- [ ] Replan after an important task becomes blocked. - **Status: Not implemented.** The app can redraft a whole plan, but there is no blocked-task flow that leads into contextual replanning.

## 20. Completing and rescheduling tasks

- [ ] Complete an active task even when observed aligned time is low. - **Status: Partially implemented.** Completion is not gated by behavior totals, and the live active card has a completion button. Alignment is not calculated, so the exact low-alignment condition cannot be seen or verified.
- [ ] Complete a paused task explicitly. - **Status: Frontend only left.** The execution store accepts completion from any state, but a paused row renders resume rather than complete and exposes no alternate completion control.
- [ ] See the task disappear from active work and appear in today's completed history. - **Status: Partially implemented.** Completion removes active execution state, but the Today snapshot builds rows only from incomplete Reminder snapshots and no completed-history section is rendered.
- [ ] See the corresponding Apple Reminder become completed. - **Status: Blocked from verification.** Completion enqueues `.completeReminder` and an action executor exists, but this destructive source mutation was not performed on the user's real Reminder, and the current live database path is orphaned.
- [ ] See a clear pending-sync warning if Apple Reminders rejects completion. - **Status: Partially implemented.** An automatic-action ledger can show outbox state and the direct reminder path sets a generic error, but task completion returns before Apple Reminders confirmation and the active task UI does not show task-specific pending sync.
- [ ] Retry a failed completion sync. - **Status: Not implemented.** No task-level retry control exists; only background outbox retry behavior is available.
- [ ] Avoid seeing a false success before Apple Reminders confirms completion. - **Status: Not implemented.** `TodayDashboardAgent.apply(.complete)` immediately marks local execution completed and returns a refreshed snapshot before the queued external action is confirmed.
- [ ] Reschedule a task only after confirming the new date. - **Status: Not implemented.** `.reschedule` has no date payload, confirmation sheet, date picker, or source action.
- [ ] See a clear pending-sync warning if rescheduling fails. - **Status: Not implemented.** Rescheduling is only a local task execution state and task-history record.
- [ ] Keep the task and its local history when a source write fails. - **Status: Partially implemented.** Local execution and task history are written before the outbox completes, but there is no end-user recovery UI and the current canonical database cannot prove durable survival.

## 21. Changes made in Apple Reminders

- [ ] See an externally completed Reminder update in Zoid Coach. - **Status: Partially implemented.** The agent periodically refreshes Reminder snapshots and Today rows are derived from incomplete snapshots, so the task should disappear after refresh. No live external-change E2E test or completed-history presentation was found.
- [ ] See an active externally completed task end with an understandable reason. - **Status: Not implemented.** A missing Reminder drops out of the snapshot; there is no explicit external-completion reason or session closure explanation.
- [ ] See title, notes, list, due date, or priority changes made in Reminders appear after sync. - **Status: Partially implemented.** Reminder snapshots carry these source fields and refresh periodically, but Today rows expose only title, due date, and priority-derived urgency. Notes are not displayed, and no live sync test was performed.
- [ ] Keep local estimates and coaching history when source-owned fields change. - **Status: Partially implemented.** Estimates live in the local plan by Reminder ID and task history is local, which should survive source field changes. The orphaned runtime database blocks credible restart proof.
- [ ] See an active task pause when its Reminder is deleted externally. - **Status: Not implemented.** Deleted snapshots cause the row to be omitted; no deletion reconciliation pauses the open execution interval.
- [ ] Choose whether to keep a deleted Reminder as a local historical task. - **Status: Not implemented.** No deleted-task decision UI or historical preservation choice exists.
- [ ] Avoid having Zoid Coach automatically rewrite Reminder titles, notes, lists, or priorities. - **Status: Touches remaining.** The action system only creates/completes/reschedules supported entities and no automatic metadata rewrite path was found. This was verified statically, not through a complete external-change E2E test.
- [ ] Complete one recurring occurrence without modifying future occurrences. - **Status: Blocked from verification.** Completion targets an EventKit Reminder identifier, but no recurring-occurrence test or safe live proof establishes future-instance behavior.

## 22. Work away from the Mac

- [ ] Mark a task session as work completed away from the Mac. - **Status: Not implemented.** No offline-work domain type, command, or UI exists.
- [ ] Add offline work during the task session. - **Status: Not implemented.** No duration entry is available from the active task.
- [ ] Add offline work during end-of-day review. - **Status: Not implemented.** Reviews are not connected to editable offline work.
- [ ] See offline work included in actual task time. - **Status: Not implemented.** Actual time is derived only from local task activity intervals.
- [ ] See offline work kept separate from Screenwatch-aligned time. - **Status: Not implemented.** Neither offline time nor aligned task time is modeled in the user surface.
- [ ] Correct the duration of an offline work session. - **Status: Not implemented.** There is no offline session record to edit.
- [ ] Distinguish intentional offline work from missing telemetry. - **Status: Not implemented.** The app only shows a general limited-coverage explanation.

## 23. Menu bar use

- [ ] See a neutral menu bar state when healthy with no active task. - **Status: Not implemented.** The installed app's menu bar extra is `Zoid Voice` and reflects voice state only, not coach or task state.
- [ ] See an active state while a task or sprint is running. - **Status: Not implemented.** The menu icon does not inspect active task execution, and sprint sessions do not exist.
- [ ] See a warning state when attention or source repair is needed. - **Status: Not implemented.** Source health is available in the main window only.
- [ ] See a paused state while coaching is paused. - **Status: Not implemented.** The voice menu symbol reflects voice transport state, not coaching pause state.
- [ ] Open Today. - **Status: Not implemented.** `VoiceMenuView` has no command to show or navigate the main Today window.
- [ ] Start the recommended task. - **Status: Not implemented.** The menu bar extra does not expose Today recommendations.
- [ ] Pause or resume the active task. - **Status: Not implemented.** No task controls exist in `VoiceMenuView`.
- [ ] Start a break. - **Status: Not implemented.** Break sessions are absent from both the model and menu.
- [ ] Pause coaching. - **Status: Not implemented.** Coaching pause is available in Settings policy, not the menu bar extra.
- [ ] End the workday. - **Status: Not implemented.** No end-workday command is wired.
- [ ] Open source health. - **Status: Not implemented.** No menu-bar navigation command exists.
- [ ] Open settings. - **Status: Not implemented.** No menu-bar settings command exists.

## 24. Understanding behavior totals

- [ ] See deep work, creative work, research, communication, and administration represented as work categories. - **Status: Not implemented.** The behavior model has only `work`, `gaming`, `distracting`, `idle`, and `unknown`.
- [ ] See gaming, entertainment, passive consumption, distraction, system-neutral, idle, and unknown time represented distinctly. - **Status: Partially implemented.** Gaming, distraction, idle, and unknown are distinct. Entertainment, passive consumption, and system-neutral are not modeled.
- [ ] See a useful summary without needing to inspect raw five-second records. - **Status: Touches remaining.** The live dashboard exposes an observed-use popover with application percentages and category totals. It does not present a complete, task-aligned behavioral summary.
- [ ] See totals update as new activity is observed. - **Status: Partially implemented.** The background agent regenerates snapshots while ingesting, but `AppModel` does not poll Today snapshots while the window stays open; refresh is tied mainly to launch, foreground activation, or commands.
- [ ] Avoid seeing false minute-level precision when coverage is incomplete. - **Status: Partially implemented.** Stale/no telemetry produces limited coverage and avoids filling gaps, with tests in `TodayDashboardTests`. The UI still renders integer minute totals without expressing a range or coverage proportion.
- [ ] See unknown time separately from distraction. - **Status: Touches remaining.** The model and usage-category selector separate unknown and distracting time. Live app usage inspection confirms an `Unclassified` category, but no long-duration E2E correction was run.
- [ ] See idle time only when it can be observed reliably. - **Status: Partially implemented.** Idle is classified only for known apps such as `screensaver` and `loginwindow`, but reliability and lock/wake transitions are not validated end to end.
- [ ] See active-task elapsed time separately from aligned time. - **Status: Not implemented.** Elapsed is stored but not rendered, and aligned time is not calculated.
- [ ] See a low-coverage warning when too much of a task session is unknown. - **Status: Partially implemented.** A general Screenwatch stale/no-observation warning exists, but coverage is day-level rather than task-session unknown share.
- [ ] Understand which source problem caused missing totals. - **Status: Touches remaining.** The dashboard displays Screenwatch freshness details and source health repair information. The wording does not always connect a specific missing total to its cause.

## 25. Ambiguous applications and activity

- [ ] See known work applications classified according to configured rules. - **Status: Touches remaining.** Settings exposes per-app `Auto`, `Work`, and `Gaming` choices, policy is persisted, and classification overrides are tested. The Today popover reflects the resulting category, but no live reclassification cycle was performed.
- [ ] See known games classified as gaming. - **Status: Touches remaining.** Built-in matching covers common game names and user overrides, with unit coverage. The heuristic is application-name based and not context aware.
- [ ] See browsers, Discord, Slack, Notion, YouTube, and Preview treated according to context rather than permanently judged. - **Status: Not implemented.** Discord is always gaming, Slack always work, YouTube always distracting, and browsers/Notion/Preview generally unknown unless globally overridden. No task or window context classifier exists.
- [ ] See uncertain activity remain unknown. - **Status: Touches remaining.** Unmatched applications are classified `unknown` and shown as `Unclassified`; this behavior is implemented and tested at the classifier/sessionizer level.
- [ ] Avoid a strong drift warning based only on uncertain activity. - **Status: Barely started.** Unknown classification exists, but drift warning generation does not.
- [ ] Be asked for confirmation when ambiguity materially affects coaching. - **Status: Not implemented.** No ambiguity-confirmation prompt generator exists.
- [ ] See a technical tutorial related to the active task treated as research or left uncertain. - **Status: Not implemented.** Content/task semantic context is not used in behavior classification.
- [ ] Understand when Zoid Coach may be wrong. - **Status: Partially implemented.** Limited coverage and `Unclassified` communicate some uncertainty, but there is no explanation or correction affordance adjacent to a specific questionable classification.

## 26. Correcting observed activity

- [ ] Reclassify an incorrectly categorized session. - **Status: Barely started.** The user can globally classify an application, but cannot correct an individual observed session.
- [ ] Split a session that contains two different activities. - **Status: Not implemented.** No session editor exists.
- [ ] Merge adjacent sessions that are really one activity. - **Status: Not implemented.** No session editor exists.
- [ ] Attach a session to the correct task. - **Status: Not implemented.** Behavior observations have no task attachment workflow.
- [ ] See affected totals update after correction. - **Status: Barely started.** Future ingested observations can use a changed app rule, but existing observations keep their stored classification and there is no correction recalculation flow.
- [ ] See affected alignment and review statements update after correction. - **Status: Not implemented.** Alignment and correction-aware review statements are absent.
- [ ] Apply a correction only once. - **Status: Not implemented.** No correction record or idempotency key exists for activity corrections.
- [ ] Create a reusable rule from a correction. - **Status: Barely started.** Reusable global application rules exist in Settings, but they are not created from a session correction flow.
- [ ] Apply a one-time correction without creating a rule. - **Status: Not implemented.** Only persistent application-level choices exist.
- [ ] Preview exactly how broadly a proposed rule will apply. - **Status: Not implemented.** Settings lists apps but provides no affected-session preview.
- [ ] Edit or remove a learned rule later. - **Status: Partially implemented.** A user can change a global app classification back to `Auto`, but there is no learned-rule ledger or historical impact view.
- [ ] Ensure a user correction continues to outrank future automatic classification. - **Status: Partially implemented.** Explicit work/gaming app overrides outrank built-in automatic classification, with a passing unit test. Session-level user corrections do not exist.

## 27. Grace periods and neutral activity

- [ ] Switch applications during the first three minutes after starting a task without receiving a normal drift warning. - **Status: Not implemented.** No task-start grace-period or drift detector exists.
- [ ] Receive protection during the first minute after waking, unlocking, or returning from idle. - **Status: Not implemented.** No wake/unlock grace policy exists for behavior coaching.
- [ ] Allow high-confidence gaming to bypass the task-start grace period when other trigger conditions are met. - **Status: Not implemented.** There is no grace policy or gaming drift trigger engine.
- [ ] Use System Settings briefly without having the task marked misaligned. - **Status: Not implemented.** Neutral-supporting activity and task alignment are not modeled.
- [ ] Use a password manager briefly without having the task marked misaligned. - **Status: Not implemented.** Neutral-supporting activity and task alignment are not modeled.
- [ ] Use file dialogs, downloads, or short communication checks as neutral supporting activity. - **Status: Not implemented.** The classifier works from application name only and has no neutral-supporting state.
- [ ] Avoid having neutral activity automatically pause the task. - **Status: Barely started.** No behavior currently auto-pauses tasks at all, so the harmful behavior does not occur, but the intended neutral-activity policy is absent.

## 28. Taking breaks

- [ ] Start an accepted break from the dashboard. - **Status: Not implemented.** No dashboard break control or break state exists.
- [ ] Start an accepted break from the menu bar. - **Status: Not implemented.** The menu bar extra is voice-only.
- [ ] Start an accepted break from a coach prompt. - **Status: Barely started.** `PromptActionKind.startBreak` exists, but no coaching prompt generator or response effect implements it.
- [ ] Choose or understand the expected break duration. - **Status: Not implemented.** Break duration is not modeled.
- [ ] Avoid receiving drift prompts during an accepted break. - **Status: Not implemented.** Neither accepted breaks nor drift prompts are implemented.
- [ ] Receive a break-end reminder. - **Status: Not implemented.** No break timer or notification exists.
- [ ] End the break early. - **Status: Not implemented.** No break state exists to end.
- [ ] Resume work after the break. - **Status: Not implemented.** No break-to-task transition exists.
- [ ] See break activity without having it described as failure or drift. - **Status: Not implemented.** Break activity and drift interpretation are absent.

## 29. Gaming policy setup

- [ ] Observe gaming without applying a budget. - **Status: Not implemented.** Gaming is always evaluated against a `GamingPolicy` with a default 60-minute budget; there is no disabled-budget mode.
- [ ] Set a daily gaming budget. - **Status: Frontend only left.** `GamingPolicy.dailyBudgetMinutes` exists, but it is not part of `UserPolicy`, Settings, or persistence and the agent uses its initializer default.
- [ ] Unlock gaming after selected priority tasks are completed. - **Status: Partially implemented.** Completing the main objective can apply a one-time reward, but the user cannot select unlock tasks or configure the condition.
- [ ] Earn gaming time from aligned focus time. - **Status: Not implemented.** Rewards are completion-based only; aligned focus time is not calculated.
- [ ] Combine a base budget, task unlock, and focus-time rewards. - **Status: Not implemented.** Only base budget plus a fixed one-time priority reward exists.
- [ ] Choose which applications count as gaming. - **Status: Touches remaining.** Settings provides per-app Gaming classification and persists it in `BehaviorPolicy`. There is no context-sensitive rule or current-session preview.
- [ ] Decide whether Discord or Twitch count only in a gaming context. - **Status: Not implemented.** Rules are global by application name; Discord is built-in gaming and Twitch is not context aware.
- [ ] Set the base available minutes. - **Status: Frontend only left.** The core policy supports a numeric base budget, but no Settings control or policy-store field exposes it.
- [ ] Set the unlock tasks or focus-time rule. - **Status: Not implemented.** Unlock selection and focus ratios are not modeled.
- [ ] Set the daily maximum during work hours. - **Status: Not implemented.** No separate work-hours maximum exists.
- [ ] Choose whether early gaming creates same-day debt. - **Status: Not implemented.** Debt is not modeled.
- [ ] Choose whether debt carries into another day. - **Status: Not implemented.** Debt is not modeled.
- [ ] Set the intentional-override cooldown. - **Status: Not implemented.** There is no intentional gaming override policy engine.
- [ ] Configure different weekend or after-work behavior. - **Status: Not implemented.** Work windows exist, but gaming policy has no weekday or after-work variants.

## 30. Gaming budget use

- [ ] See available, earned, used, locked, and debt minutes. - **Status: Partially implemented.** The live dashboard shows only unlocked remaining minutes and a next-unlock reason. The model has budget and used minutes, but no earned, locked, or debt breakdown and the UI does not render used.
- [ ] See the next unlock condition. - **Status: Touches remaining.** The live dashboard shows `Finish one priority task to unlock a one-time reward.` The condition is fixed rather than user configured.
- [ ] See gaming time accumulate from confidently detected gaming sessions. - **Status: Touches remaining.** Screenwatch observations classified as gaming feed `GamingStatus.usedMinutes`, and unit tests verify it. The live UI only indirectly shows remaining allowance, and no confidence threshold beyond app classification exists.
- [ ] Avoid counting a brief game-launcher transition as meaningful gaming. - **Status: Not implemented.** Every contiguous classified observation up to the sessionizer cap contributes time; there is no minimum-session threshold.
- [ ] See gaming unlock after the configured task condition is satisfied. - **Status: Partially implemented.** Completing the main objective records a fixed priority reward, but selected conditions are not configurable and live source completion was not tested.
- [ ] See gaming time earned after the required aligned work. - **Status: Not implemented.** There is no aligned-work reward calculation.
- [ ] Stop earning automatic time at the configured daily maximum. - **Status: Not implemented.** No focus-time earning or configurable maximum exists.
- [ ] See same-day debt after gaming before unlock when debt is enabled. - **Status: Not implemented.** Debt is absent.
- [ ] Start the next day without carried debt by default. - **Status: Not implemented.** Debt is absent, so the intended policy cannot be configured or reviewed.
- [ ] Carry debt only when explicitly configured. - **Status: Not implemented.** Debt is absent.
- [ ] Add or remove gaming time manually. - **Status: Not implemented.** No manual adjustment action or ledger exists.
- [ ] See manual adjustments separately from automatically earned rewards. - **Status: Not implemented.** No adjustment ledger exists.

## 31. Gaming drift detection

- [ ] Game for less than ten minutes without receiving the default drift prompt. - **Status: Not implemented.** No gaming drift detector or ten-minute threshold exists.
- [ ] Game for at least ten minutes with incomplete priority work and become eligible for a prompt. - **Status: Not implemented.** Gaming totals and incomplete tasks coexist in the snapshot, but no trigger combines them into a prompt.
- [ ] Avoid receiving a prompt when all applicable unlock conditions are satisfied. - **Status: Not implemented.** No gaming coaching prompt generator exists.
- [ ] Avoid receiving a prompt while on an accepted break. - **Status: Not implemented.** Breaks and gaming coaching prompts are absent.
- [ ] Avoid receiving a prompt while coaching is paused. - **Status: Not implemented.** User policy has an automation pause, but there is no gaming prompt engine for it to gate.
- [ ] Avoid receiving a prompt outside the configured work window. - **Status: Not implemented.** Work windows exist, but no gaming drift trigger evaluates them.
- [ ] Avoid receiving a prompt after the workday is closed. - **Status: Not implemented.** Workday closure is not modeled.
- [ ] Avoid receiving a prompt when the gaming classification is uncertain. - **Status: Not implemented.** Unknown classification exists, but there is no prompt eligibility policy.
- [ ] Avoid receiving repeated prompts for the same continuing gaming session. - **Status: Barely started.** `PromptInboxStore` deduplicates unresolved episodes by decision key, but no gaming-session prompt producer supplies such episodes or cooldowns.
- [ ] Correct an application rule and stop future false gaming alerts for that context. - **Status: Barely started.** App rules can be changed, but alerts are not implemented and rules are global rather than contextual.

## 32. First-week observation mode

- [ ] Use the app for the first seven complete days without behavior-triggered interruptions. - **Status: Not implemented.** No installation-day baseline counter or seven-day gate exists. The absence of behavior prompts is due to missing coaching implementation, not observation mode.
- [ ] See that eligible drift is being observed during the baseline. - **Status: Not implemented.** Drift eligibility is not calculated or shown.
- [ ] Understand why accountability prompts are not active yet. - **Status: Not implemented.** There is no baseline explanation UI.
- [ ] Complete the baseline week and see coaching progress to the configured level. - **Status: Not implemented.** No baseline state transition exists.
- [ ] Keep stronger coaching disabled if the baseline is incomplete. - **Status: Not implemented.** Coaching levels and baseline completeness are not connected.
- [ ] Use baseline results to review work capacity, gaming patterns, and alert sensitivity. - **Status: Not implemented.** There is no baseline report or alert-sensitivity review.

## 33. Receiving a coaching prompt

- [ ] Receive a gentle nudge offering an easy return to work. - **Status: Barely started.** A generic prompt inbox and notification framework exists, but the agent generates only plan, meeting, and wake prompts, not drift nudges.
- [ ] Receive an accountability prompt asking whether gaming is intentional. - **Status: Barely started.** The `continueIntentionally` action enum exists, but no gaming accountability prompt is generated.
- [ ] See the observed fact before the coach's interpretation. - **Status: Not implemented.** No coaching prompt content builder or fact/interpretation structure exists.
- [ ] See the relevant unfinished task named. - **Status: Not implemented.** Coaching prompt generation is absent.
- [ ] See one clear primary action. - **Status: Partially implemented.** Generic `PromptActionRole.primary` is rendered with primary styling in the dashboard. No coaching prompt currently uses this flow.
- [ ] See no more than three secondary actions. - **Status: Not implemented.** The generic prompt UI renders every supplied action with no secondary-action cap.
- [ ] See reliable elapsed time when included. - **Status: Not implemented.** Coaching prompts are absent and active elapsed time is not displayed elsewhere.
- [ ] See uncertainty acknowledged when context is ambiguous. - **Status: Not implemented.** No ambiguity-aware coaching prompt builder exists.
- [ ] Avoid guilt, insults, moral labels, disappointment, or exaggerated claims. - **Status: Barely started.** Existing plan/meeting copy is neutral, but there is no coaching copy pipeline to verify against this requirement.
- [ ] Avoid being told what the user's intent must be. - **Status: Barely started.** Existing copy does not assert intent, but the intended coaching prompts do not exist.
- [ ] Find the same unresolved prompt in the dashboard if the initial surface disappears. - **Status: Partially implemented.** `PromptInboxStore.unresolved()` and the live `DECISIONS` dashboard prove shared persistence for plan/meeting prompts across notification and dashboard surfaces. Coaching prompts are not generated, and the canonical database is currently broken.

## 34. Responding to coaching

- [ ] Start the recommended task. - **Status: Barely started.** The action enum and generic prompt button exist, but `PromptResponseEffectRouter` has no effect for `startRecommendedTask`; clicking would only resolve the prompt.
- [ ] Start a 10-minute recovery sprint. - **Status: Barely started.** `startShortSprint` exists as one undifferentiated enum value, but no 10-minute session or routed task effect exists.
- [ ] Start a 20-minute work sprint. - **Status: Not implemented.** There is no distinct 20-minute action, duration payload, timer, or execution effect.
- [ ] Return to the current active task. - **Status: Barely started.** `returnToActiveTask` exists as an enum, but no response effect resumes or foregrounds the task.
- [ ] Choose `Five more minutes`. - **Status: Barely started.** `fiveMoreMinutes` exists as an enum, but no coaching prompt currently offers it and no snooze is scheduled.
- [ ] Receive one follow-up when the five-minute snooze ends. - **Status: Not implemented.** There is no snooze store, timer, cooldown, or follow-up producer.
- [ ] Start an accepted break. - **Status: Barely started.** `startBreak` exists as an enum, but no break state or effect is wired.
- [ ] Choose `Continue intentionally`. - **Status: Barely started.** `continueIntentionally` exists as an enum, but no gaming prompt or override effect exists.
- [ ] Pause the task. - **Status: Barely started.** `pauseTask` exists as a prompt action and task pause exists separately, but the response router does not connect them.
- [ ] Reschedule the task. - **Status: Barely started.** `rescheduleTask` exists as a prompt action and local execution state, but no date confirmation, Reminder mutation, or response effect exists.
- [ ] Mark the task blocked. - **Status: Barely started.** `markBlocked` exists as a prompt action and `.block` exists in task execution, but no router connects them and no block reason is captured.
- [ ] End the workday. - **Status: Barely started.** `endWorkday` exists as an enum only; no day-closure effect exists.
- [ ] Ignore or dismiss the prompt. - **Status: Partially implemented.** `ignore` is fully routed for meeting prompts and the prompt store supports dismissal state, but generic coaching prompt dismissal is not exposed consistently in the dashboard.
- [ ] Avoid having the same action happen twice after clicking more than once. - **Status: Touches remaining.** `PromptInboxTests` and `PromptResponseEffectRouterTests` prove idempotent response tokens and exactly-once meeting effects across repeated delivery. Coaching actions have no effects to protect yet, and no live double-click UI test was performed.
- [ ] See a refreshed state instead of applying an action from an outdated prompt. - **Status: Partially implemented.** A resolved prompt is removed after the XPC response and prompt state transitions reject invalid repeats. There is no coaching-specific stale-state validation against a changed active task or gaming session.

## Section summary

This slice contains **172 scenarios**.
Under the strict end-to-end usability bar, **0 scenarios are fully implemented and checked**.

Status counts:

- Fully implemented: 0
- Touches remaining: 13
- Frontend only left: 5
- Partially implemented: 28
- Barely started: 23
- Not implemented: 101
- Blocked from verification: 2

The current test suite passes **188 tests**, but these are predominantly unit and infrastructure tests and do not change the strict usability classifications above.

The dominant gaps are:

- Active task execution has real storage and a live Today surface, but elapsed time, pause controls, reasons, alignment, and reliable cross-surface state are incomplete.
- Completion is optimistically local and does not wait for Apple Reminders confirmation or offer task-level retry.
- Offline work, activity-session correction, grace periods, breaks, and first-week baseline mode are absent.
- Gaming has basic classification, totals, a fixed budget, and a fixed completion reward, but almost all configurable policy, debt, focus earning, and drift prompting are absent.
- The prompt framework is real and idempotent for plan and meeting prompts, but coaching prompt generation and coaching action effects are mostly enum-only scaffolding.
- The installed runtime is currently unsafe evidence for persistence because the long-running agent has its database open in Trash while the canonical database is empty.
