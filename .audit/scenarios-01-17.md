# Zoid 666 end-user scenario audit - sections 1-17

Audit date: 2026-07-12.

This is a strict usability audit, so backend code or a passing unit test does not by itself qualify as fully implemented.
The installed build at `/Users/ziadnasreldin/Applications/Zoid 666.app` launched successfully and showed the Today dashboard, plan ledger, prompt inbox, meeting detections, and navigation, but no first-run onboarding appeared.
The current repository also passed all 188 Swift tests, which is used below as supporting evidence rather than end-to-end proof.
A read-only check of the live database found zero current `daily_plan_entries`, `task_execution_states`, `task_activity_intervals`, `today_snapshots`, `prompt_episodes`, and `source_checkpoints`, so populated planning and task-session claims could not be promoted to fully implemented from the current user environment.

## 1. First launch

- [ ] Open Zoid 666 for the first time and immediately understand that it helps connect planned work with actual computer activity. - **Partially implemented**: The installed app opens directly to a Today screen labelled around reminders and local sources, but there is no first-launch explanation or guided context (`ZoidCoachApp.swift:18-46`).
- [ ] Understand that Apple Reminders represents intended work. - **Touches remaining**: Source health labels Reminders as `Intent` and Today says it is grounded in reminders, but the relationship is not explained during first launch (`AppModel.swift:594-604`; runtime screenshot).
- [ ] Understand that Screenwatch represents observed computer activity. - **Partially implemented**: Source health labels Screenwatch as `Behavior`, but there is no first-launch explanation connecting captured activity to coaching (`AppModel.swift:634-644`).
- [ ] Understand that the Today dashboard provides persistent status and prompts. - **Touches remaining**: The dashboard visibly contains source status and a shared prompt inbox, but first launch never explains persistence or how prompts return (`DashboardView.swift:312-353`).
- [ ] Understand that Zoid 666 is a coach rather than a replacement task manager. - **Partially implemented**: The app calls itself a coach and shows Reminders inventory, but it never explicitly explains that Reminders remains the task system of record.
- [ ] Understand that the app does not punish, shame, or block the user by default. - **Not implemented**: No onboarding or settings copy states this user promise, and the installed first-launch surface does not communicate it.
- [ ] Understand that important data stays on the Mac by default. - **Touches remaining**: Persistent `LOCAL ONLY` and `LOCAL-FIRST` labels are visible, with remote evidence controls, but the default privacy boundary is not introduced on first launch (`SettingsView.swift:281-294,572-648`).
- [ ] Continue onboarding without being forced to configure optional AI features. - **Not implemented**: There is no onboarding flow or continuation action; the app simply opens the main dashboard, while AI remains optional only in Settings.
- [ ] Leave onboarding and resume from the same point later. - **Not implemented**: No onboarding state, steps, exit control, or resume persistence exists in the app target.
- [ ] Restart the app during onboarding without losing completed setup steps. - **Not implemented**: No onboarding state model or persisted setup-step record exists.

## 2. Reminders permission during onboarding

- [ ] See why Reminders access is useful before macOS requests permission. - **Partially implemented**: Source health says EventKit access is required for task sync, but clicking Connect requests permission immediately and there is no pre-permission explainer (`RemindersService.swift:39-48`; `AppModel.swift:106-115`).
- [ ] Grant Reminders access and continue setup. - **Partially implemented**: The Connect action requests full EventKit access and refreshes tasks on success, but there is no setup flow to continue (`RemindersService.swift:72-88`; `AppModel.swift:106-115`).
- [ ] Deny Reminders access and understand which features will be unavailable. - **Partially implemented**: Denial produces `Reminders access is unavailable` and a task-load error, but the UI does not enumerate unavailable planning, completion, and sync features (`RemindersService.swift:49-58`; `AppModel.swift:507-512`).
- [ ] Continue setup after denying Reminders access. - **Not implemented**: There is no setup flow and no explicit continue-without-Reminders action.
- [ ] Open System Settings directly when ready to grant previously denied access. - **Not implemented**: The Reminders repair button retries the permission request; no Reminders privacy deep link is wired, unlike native-capture repair links (`AppModel.swift:106-115`; `SettingsView.swift:826-842`).
- [ ] Return from System Settings and see the updated permission state. - **Partially implemented**: Foreground activation does not refresh source health, though a manual Retry or global source check updates it (`ZoidCoachApp.swift:34-42`; `AppModel.swift:85-130`).
- [ ] Avoid seeing the same permission dialog repeatedly after declining it. - **Fully implemented**: EventKit reports denied status and macOS will not re-present the system prompt; the app shows an attention state instead (`RemindersService.swift:33-69,72-88`).
- [ ] Use manual local planning while Reminders access is unavailable. - **Not implemented**: Manual plan items can only be added from fetched `ReminderTask` records, and unavailable access clears that inventory (`AppModel.swift:491-513,200-218`).

## 3. Screenwatch setup during onboarding

- [ ] Let Zoid 666 find Screenwatch automatically at the expected location. - **Touches remaining**: The reader automatically checks `~/screenwatch/days/YYYY-MM-DD/log.jsonl`, and tests cover healthy and missing streams, but no onboarding confirmation was exercised (`ScreenwatchReader.swift:13-23,83-92`).
- [ ] See whether the detected Screenwatch source is healthy. - **Fully implemented**: Source health reports missing, invalid, stale, or current telemetry with age and parsed-record evidence (`ScreenwatchReader.swift:22-80`; `DashboardView.swift:510-529`).
- [ ] Select another Screenwatch folder when the default location is unavailable. - **Not implemented**: `ScreenwatchReader` is constructed with a fixed default base directory and no folder picker or persisted bookmark is exposed (`ScreenwatchReader.swift:13-20`).
- [ ] Understand why a selected folder is invalid without seeing sensitive captured content. - **Not implemented**: There is no folder selection flow; fixed-source errors avoid content leakage but cannot validate a user-selected folder.
- [ ] Continue setup without Screenwatch and understand that behavior coaching will be unavailable. - **Partially implemented**: The app remains usable when the stream is missing and shows `Unavailable`, but no setup choice or explicit consequence summary exists (`ScreenwatchReader.swift:25-35`).
- [ ] Open the repair path when folder access is denied. - **Not implemented**: Source health only retries inspection; it does not open Finder, System Settings, or a folder reauthorization picker.
- [ ] Return after repairing access and see Screenwatch become connected. - **Partially implemented**: A manual source refresh will re-inspect and update health, but foreground return is not automatically detected (`AppModel.swift:116-118,445-455`).
- [ ] Understand that screenshots are not routinely inspected. - **Partially implemented**: Settings exposes an opt-in `Analyze Screenwatch screenshots` toggle, but the first-use source flow never explains the default behavior (`SettingsView.swift:572-575`).
- [ ] Choose whether screenshot analysis may be used for genuinely ambiguous situations. - **Touches remaining**: The persisted screenshot-analysis toggle exists and is covered by settings-policy tests, but its UI copy does not limit use specifically to ambiguous situations (`SettingsView.swift:572-575`).

## 4. Notification setup

- [ ] Understand that the Today dashboard remains available without notification permission. - **Partially implemented**: The dashboard does work without authorization, but the notification connection UI does not explain that fallback.
- [ ] Grant notification permission for timely prompts. - **Touches remaining**: Source health requests alert, sound, and badge permission and the prompt coordinator can schedule authorized notifications, but this path was not exercised live (`NotificationService.swift:75-90`; `PromptNotificationCoordinator.swift:38-56`).
- [ ] Resolve a test notification action. - **Not implemented**: There is no test-notification control or synthetic test prompt anywhere in the app.
- [ ] Deny notification permission and continue with in-app prompts. - **Touches remaining**: Denial yields an attention state while the dashboard prompt inbox remains functional, though no explicit continue action or explanatory handoff exists (`NotificationService.swift:52-61`; `DashboardView.swift:312-353`).
- [ ] Test the Today dashboard prompt inbox. - **Partially implemented**: The inbox renders actions and sends responses through XPC, but no user-facing test prompt is available and several task-related prompt action kinds have no effect router (`DashboardView.swift:312-353`; `PromptResponseEffectRouter.swift:43-108`).

## 5. Initial preferences

- [ ] Choose which Reminder lists Zoid 666 should use. - **Not implemented**: The app fetches every incomplete Reminder from all calendars and only lets users reorder list presentation (`RemindersService.swift:90-126`; `DashboardView.swift:298-308`).
- [ ] Exclude personal or irrelevant Reminder lists. - **Not implemented**: No included or excluded Reminder-list policy exists in Settings or fetch filtering.
- [ ] Preview detected applications before assigning categories. - **Touches remaining**: Settings inventory merges installed and observed apps and presents classification controls, with passing inventory tests, but the first-use flow is not guided or live-verified (`SettingsView.swift:486-492`; `AppClassificationLedger.swift`).
- [ ] Mark known work applications. - **Touches remaining**: The app-classification ledger persists exact work overrides and tests pass, but the installed interaction was not exercised end to end (`SettingsPolicyDraft.swift:66-78`).
- [ ] Mark known gaming applications. - **Touches remaining**: The same ledger supports gaming overrides and persistence tests pass, but live selection and subsequent behavior reclassification were not verified (`SettingsPolicyDraft.swift:66-78`).
- [ ] Leave ambiguous applications unclassified for later review. - **Touches remaining**: Applications can be returned to Automatic, but there is no explicit ambiguous-review queue or onboarding defer action.
- [ ] Configure a flexible work window. - **Touches remaining**: Work start and end time fields persist in the versioned policy, but no initial-preferences flow or live scheduling proof was completed (`SettingsView.swift:464-483`).
- [ ] Configure quiet hours. - **Touches remaining**: Quiet start and end controls exist and persist, but there is no onboarding preview or live prompt-suppression proof (`SettingsView.swift:464-483`).
- [ ] Choose an initial gaming policy. - **Frontend only left**: Core gaming budget and reward policy exists and dashboard status is calculated, but Settings exposes no budget, reward, or unlock-policy controls (`TodayDashboard.swift:232-257`; `TodayDashboardAgent.swift:57-60`).
- [ ] Choose rules-only coaching for Release 1. - **Touches remaining**: Settings offers the Disabled rules-only AI provider and local-only behavior, but it is not presented as an initial Release 1 choice (`SettingsView.swift:572-648`; `AIProviderCapabilities.swift`).
- [ ] Finish onboarding by opening the first daily plan. - **Not implemented**: There is no onboarding completion transition; the app always opens Today directly.

## 6. Starting the day

- [ ] Receive a low-pressure planning invitation at the configured planning time. - **Partially implemented**: The agent schedules a PLAN_READY notification at morning confirmation time, but the wording was not assessed as low-pressure and no live delivery was verified (`AgentMain.swift:776-813`; `PromptNotificationCoordinator.swift:93-102`).
- [ ] Receive the invitation when first using the Mac if the configured time passed while inactive. - **Partially implemented**: Missed nightly planning after wake is unit-tested and immediate notification delivery is possible when the target time is past, but the complete wake-to-invitation flow was not exercised live.
- [ ] Open planning manually before the configured time. - **Fully implemented**: The installed app opens directly to Today and exposes `DRAFT TODAY`, independently of scheduled notification time (`DashboardView.swift:57-81`; runtime screenshot).
- [ ] Snooze planning without causing coaching escalation. - **Not implemented**: PLAN_READY notification actions are only Accept and Review, and the prompt action model has no planning snooze (`PromptNotificationCoordinator.swift:93-102`).
- [ ] Receive the planning invitation again when the snooze ends. - **Not implemented**: No snooze duration, rescheduling action, or follow-up scheduler exists.
- [ ] Dismiss planning temporarily without being trapped in repeated prompts. - **Partially implemented**: macOS can dismiss a notification and prompt episodes expire or dismiss internally, but there is no explicit temporary-dismiss action or tested suppression contract for planning.
- [ ] See clearly that the day is currently unplanned. - **Touches remaining**: An empty state says `PLAN BEFORE MOTION` and `0 / 3 PROPOSED`, but there is no explicit day-state label such as Unplanned (`DashboardView.swift:143-162,872-952`).
- [ ] Start work manually even when the day has not been planned. - **Not implemented**: Task start controls only exist for tasks in the active plan snapshot; unplanned reminder rows only add or complete items.
- [ ] Avoid drift warnings before approving a plan or explicitly starting unplanned work. - **Frontend only left**: Current drift policy and observation logic are largely backend-oriented, but the product has no explicit unplanned-work start state to satisfy this end-to-end scenario.

## 7. Seeing today's available tasks

- [ ] See incomplete Reminders due today. - **Touches remaining**: All incomplete reminders are fetched and due dates render, so due-today items appear, but the installed list was not populated during runtime verification (`RemindersService.swift:90-126`; `DashboardView.swift:774-776`).
- [ ] See overdue incomplete Reminders. - **Touches remaining**: Overdue reminders are included and active-plan rows label them Overdue, but there is no dedicated overdue grouping and live data was not exercised (`TodayTaskRowView`, `DashboardView.swift:682-688`).
- [ ] See tasks manually selected for today. - **Touches remaining**: Added reminders persist as daily-plan entries and render in the proposed plan, with store tests passing, but a complete live add-and-reopen flow was not performed (`AppModel.swift:200-218`; `EventStore.swift:88-155`).
- [ ] See tasks from included Today lists. - **Not implemented**: There is no included-list preference or Today-list semantic; every Reminder list is fetched.
- [ ] Carry a task without a due date into today. - **Touches remaining**: Undated incomplete reminders are fetched and can be added to the plan, but the installed flow was not exercised (`RemindersService.swift:90-126`; `InboxReminderTaskRow`).
- [ ] Avoid seeing future tasks that were not selected for today. - **Not implemented**: The full inventory intentionally contains all incomplete reminders, including future-dated tasks, because fetch predicates have no date boundary (`RemindersService.swift:93-97`).
- [ ] Avoid seeing tasks from excluded Reminder lists. - **Not implemented**: No list exclusion policy or filter exists.
- [ ] Avoid seeing duplicate copies of the same Reminder. - **Touches remaining**: EventKit identifiers and plan reconciliation prevent one ID from being added twice, but no UI/E2E duplicate-source fixture was verified (`AppModel.swift:202-205`).
- [ ] Hide completed tasks from the active task list. - **Fully implemented**: EventKit fetches only incomplete reminders and plan reconciliation removes IDs absent from that set (`RemindersService.swift:93-97`; `AppModel.swift:517-541`).
- [ ] Still find completed tasks in today's history. - **Frontend only left**: Task completion history is persisted and tested, but the Reviews navigation currently renders the generic foundation/source-health page rather than a day history (`TodayDashboardAgent.swift:120-127`; `DashboardView.swift:21-29`).
- [ ] See recurring Reminder occurrences as separate tasks when appropriate. - **Blocked from verification**: EventKit supplies current Reminder entities, but there is no recurrence-specific UI logic or E2E recurring-reminder test demonstrating separate occurrences.
- [ ] Understand when Reminders could not be refreshed. - **Fully implemented**: Failed or unavailable fetches show a clear access-unavailable message in Today and source health (`AppModel.swift:507-512`; `DashboardView.swift:223-239`).

## 8. Building the daily plan

- [ ] See a suggested main objective. - **Touches remaining**: The autonomous planner chooses a capacity-safe main objective and Today renders it prominently, with planner tests passing, but no live populated plan was verified (`AutonomousPlanner.swift`; `DashboardView.swift:918-932`).
- [ ] See three suggested priority tasks. - **Touches remaining**: The planner supports a bounded commitment set and the UI targets `3 PROPOSED`, but capacity may yield fewer and no live three-task draft was exercised (`DashboardView.swift:872-952`).
- [ ] Understand why each suggested task matters today. - **Touches remaining**: Suggested entries persist and display a selection reason; manually selected items truthfully say no ranking claim, but live reason quality was not verified (`DashboardView.swift:1022-1041`).
- [ ] See the proposed task order. - **Touches remaining**: Entries persist rank and render in rank order with numeric labels in the proposal ledger (`DashboardView.swift:868-870,981-1058`).
- [ ] See the estimated focused-work total. - **Frontend only left**: Individual estimates and planner totals exist, but no total focused-work value is shown in the plan UI.
- [ ] See the planned buffer time. - **Frontend only left**: Capacity planning reserves headroom in core logic, but the proposed-plan surface never displays buffer minutes or percentage.
- [ ] See the first recommended task. - **Touches remaining**: The populated Today overview has one `DO THIS NEXT` card and recommendation sentence, but no populated live plan was exercised (`TodayDashboardCommandOverview.swift:250-283`).
- [ ] See the proposed gaming unlock condition. - **Partially implemented**: The Today behavior panel shows current gaming budget and next unlock reason, but this is not a proposed-plan unlock condition users can review (`TodayDashboardCommandOverview.swift:172-191`).
- [ ] Add an available task to the plan. - **Touches remaining**: Inbox rows call `addToDailyPlan`, enforce uniqueness and maximum five, and persist through the agent, but the installed add flow was not exercised (`AppModel.swift:200-218`).
- [ ] Remove a task from the plan. - **Touches remaining**: `EXCLUDE` and `REMOVE` update and persist the plan, with fallback restoration on failure, but the live flow was not exercised (`DashboardView.swift:1044-1051`; `AppModel.swift:220-245`).
- [ ] Reorder priority tasks. - **Not implemented**: Users can reorder Reminder-list groups, not the priority entries within the daily plan; plan rank is not directly editable.
- [ ] Choose a different main objective. - **Touches remaining**: `ADJUST: MAKE MAIN` updates exactly one main objective and persists it, but the installed interaction was not exercised (`DashboardView.swift:1044-1049`; `AppModel.swift:247-263`).
- [ ] Mark a task optional. - **Not implemented**: Daily-plan entries have no optional flag or user control.
- [ ] Mark a task blocked and explain why. - **Partially implemented**: Active plan task rows can be marked blocked, but there is no reason-entry field or explanation persistence (`DashboardView.swift:660-670`; `TaskExecutionStore.swift:53-55`).
- [ ] Reduce the day's scope. - **Touches remaining**: Users can exclude plan entries before acceptance and changes persist, but no capacity or consequence feedback is shown.
- [ ] Change the gaming unlock condition. - **Not implemented**: No user-facing gaming policy controls exist.
- [ ] Approve the proposed plan. - **Touches remaining**: `ACCEPT BLOCKS` sends a schedule-plan mutation and the PLAN_READY notification has Accept, with tests proving durable queueing, but an actual Calendar end-to-end acceptance was not exercised (`AppModel.swift:305-330`; `PromptResponseEffectRouter.swift:43-50`).
- [ ] Restart the app and see the approved plan restored correctly. - **Touches remaining**: Daily plan persistence and migration tests pass and AppModel reloads it at launch, but the installed approve-restart-compare sequence was not performed (`AppModel.swift:55-71,515-522`; `EventStore.swift:133-155`).

## 9. Planning an unrealistic workload

- [ ] See a clear warning when planned work exceeds available focus capacity. - **Frontend only left**: Core planner caps generated plans to capacity, but manual plan edits have no capacity warning surface.
- [ ] See the selected workload and available capacity in the same warning. - **Frontend only left**: Both values are computable in core policy and plan data, but no warning UI combines or displays them.
- [ ] Receive a concrete suggestion about what to remove, defer, or make optional. - **Frontend only left**: The planner chooses a bounded set, but the app does not explain an over-capacity manual plan or suggest a specific edit.
- [ ] Reduce the plan directly from the warning. - **Not implemented**: No capacity warning exists, so no embedded removal or defer action exists.
- [ ] Change an estimate and see capacity update immediately. - **Frontend only left**: Estimate selection updates persisted entries immediately, but no displayed capacity value reacts to it (`AppModel.swift:265-280`).
- [ ] Add or remove a task and see capacity update immediately. - **Frontend only left**: Plan contents update, but no capacity meter or warning recalculation is visible.
- [ ] Approve a realistic revised plan. - **Partially implemented**: Revised entries can be accepted, but the UI never establishes that the revision is realistic or blocks over-capacity approval.
- [ ] Avoid receiving a vague warning with no useful next action. - **Not implemented**: There is no workload warning of any kind to assess.

## 10. Skipping planning

- [ ] Skip planning explicitly. - **Not implemented**: No Skip planning command exists in Today, notifications, prompt actions, or policy state.
- [ ] Understand that Zoid 666 is now in limited unplanned mode. - **Not implemented**: There is no unplanned-day mode or explanatory state.
- [ ] See overdue and available tasks during an unplanned day. - **Partially implemented**: The full Reminder inventory remains visible with an empty plan, but it is not recognized or labelled as unplanned mode.
- [ ] Start any available task during an unplanned day. - **Not implemented**: Inbox reminders can be added or completed, but not directly started without becoming a plan item and snapshot row.
- [ ] See behavior totals without being told that behavior violated a nonexistent plan. - **Touches remaining**: Behavior totals can render with an empty plan and current UI does not show a violation label, but no explicit unplanned-mode E2E test covers drift suppression.
- [ ] Return to planning later in the same day. - **Partially implemented**: `DRAFT TODAY` is always available, but there is no prior skip state to return from.
- [ ] End and review an unplanned day without invented planned outcomes. - **Frontend only left**: Behavior and history stores can represent activity without a plan, but there is no end-day control or unplanned-day review UI.

## 11. Adding task estimates

- [ ] Choose a 15-minute estimate. - **Touches remaining**: Both proposal and Today estimate selectors offer 15 and persist it, but the live click-and-reload flow was not exercised (`DashboardView.swift:1230-1305`; `TodayDashboardCommandOverview.swift:750-779`).
- [ ] Choose a 30-minute estimate. - **Touches remaining**: Both selectors offer 30 and use the same persisted update path, without live E2E interaction.
- [ ] Choose a 45-minute estimate. - **Touches remaining**: Both selectors offer 45 and use the same persisted update path, without live E2E interaction.
- [ ] Choose a 60-minute estimate. - **Touches remaining**: Both selectors offer 60 and use the same persisted update path, without live E2E interaction.
- [ ] Choose a 90-minute estimate. - **Touches remaining**: Both selectors offer 90 and use the same persisted update path, without live E2E interaction.
- [ ] Enter a custom estimate. - **Not implemented**: Estimate selectors expose only `[15, 30, 45, 60, 90]` and no text or stepper input (`DashboardView.swift:1236`; `TodayDashboardCommandOverview.swift:755`).
- [ ] Receive a clear error for an empty, zero, negative, or malformed estimate. - **Not implemented**: There is no custom estimate input and no estimate validation/error surface.
- [ ] Select `Unknown` when an estimate cannot be made confidently. - **Not implemented**: No Unknown option exists in either selector.
- [ ] See the conservative placeholder assigned to an unknown estimate. - **Frontend only left**: Core planner candidates require positive integer estimates, but the UI and data model have no explicit unknown estimate state.
- [ ] Understand that the placeholder is uncertain. - **Not implemented**: No unknown placeholder or uncertainty copy is rendered.
- [ ] Change an estimate before starting the task. - **Touches remaining**: A selected estimate can be reopened with the pencil control or clicked in Today and persisted before task start (`DashboardView.swift:1246-1296`).
- [ ] See that every priority task needs an estimate or explicit `Unknown` choice before approval. - **Partially implemented**: Empty plans say estimates are required, but `ACCEPT BLOCKS` is disabled only for an empty plan and AppModel does not validate every estimate (`DashboardView.swift:944-952`; `AppModel.swift:305-330`).

## 12. Learning from previous estimates

- [ ] See a suggested estimate based on similar completed tasks when enough history exists. - **Frontend only left**: Estimate learning records robust aggregates and tests pass, but no UI reads or displays a learned suggestion (`TodayDashboardAgent.swift:140-165`; `LearningAggregateStore.swift`).
- [ ] See how many similar tasks support the suggestion. - **Frontend only left**: Aggregate evidence/sample counts exist in storage, but are never surfaced in the app.
- [ ] See the historical duration range behind the suggestion. - **Frontend only left**: Learning aggregates retain evidence and rollback values, but no duration-range UI exists.
- [ ] Understand when the evidence is uncertain. - **Frontend only left**: Core learning suppresses sparse aggregates, but Today provides no uncertainty explanation for estimates.
- [ ] Accept the suggested estimate. - **Frontend only left**: Users can choose a preset estimate, but there is no learned-suggestion value or Accept action.
- [ ] Keep the original estimate instead. - **Frontend only left**: Existing estimates remain unchanged unless clicked, but there is no suggestion comparison or explicit Keep action.
- [ ] Enter a different estimate. - **Partially implemented**: Users can select a different preset, but cannot enter arbitrary minutes.
- [ ] Avoid receiving a confident suggestion when tracking coverage or sample size is insufficient. - **Touches remaining**: Sparse evidence is prevented from creating aggregates by passing tests, but the end-user absence and later appearance of advice were not verified (`LearningAggregateStoreTests`).
- [ ] Avoid having an advisory estimate silently replace the user's estimate. - **Touches remaining**: Learned aggregates are separate from daily-plan values and no UI auto-writes them, but no end-to-end history scenario was exercised.

## 13. Understanding the Today dashboard

- [ ] See the current date and day state at a glance. - **Partially implemented**: A populated snapshot shows the full date, while the empty installed state omits it and neither surface names a formal day state (`TodayDashboardCommandOverview.swift:23-43`; runtime screenshot).
- [ ] See whether coaching is active or paused. - **Partially implemented**: Settings header clearly shows automation Running or Paused, but Today does not show coaching state and `AppModel.coachingState` is not rendered there (`SettingsView.swift:223-236`).
- [ ] See whether connected data sources are healthy. - **Fully implemented**: Today includes source freshness rows with written states and repair buttons, and Source health provides the full ledger (`DashboardView.swift:510-529,1537-1606`).
- [ ] See the main objective as the strongest task-level element. - **Fully implemented**: Both empty proposal and populated Today designs give the main objective the largest task typography and prominent background (`DashboardView.swift:918-932`; `TodayDashboardCommandOverview.swift:57-105`).
- [ ] See the active task or recommended next task prominently. - **Fully implemented**: The focus commitment and `DO THIS NEXT` cards select active, main, or recommended rows and expose the primary command (`TodayDashboardCommandOverview.swift:57-105,250-283`).
- [ ] See the top three before remaining tasks. - **Touches remaining**: Planned rows precede the full unplanned inventory, but the product does not enforce exactly three and can hold up to five (`DashboardView.swift:864-979,215-274`; `AppModel.swift:202-204`).
- [ ] See work, gaming, distraction, idle, and unknown totals. - **Touches remaining**: Core snapshot tracks all five and the usage popover separates categories, but the primary card emphasizes work and older installed UI combines gaming/distraction (`TodayDashboard.swift:128-192`; `TodayDashboardCommandOverview.swift:106-191`).
- [ ] See gaming budget status. - **Fully implemented**: Today shows unlocked remaining minutes and the next unlock reason, with calculation tests passing (`TodayDashboardCommandOverview.swift:172-191`; `TodayDashboardAgent.swift:57-60`).
- [ ] See recent coach decisions. - **Touches remaining**: Prompt inbox and automatic-action ledger show recent decisions/actions, but there is no concise chronological coach-decision history and the installed screen was dominated by stale meeting detections.
- [ ] End the workday from the dashboard. - **Not implemented**: `endWorkday` exists only as an unused prompt action kind; no fixed dashboard control or effect is implemented (`PromptInbox.swift:47-64`; `PromptResponseEffectRouter.swift:43-108`).
- [ ] Understand the dashboard even when some data is missing. - **Touches remaining**: Empty plan, missing source, limited coverage, and loading states have written explanations, though the installed dashboard stayed on `LOADING PLAN` and did not expose why it had not resolved.
- [ ] Distinguish missing information from a real zero value. - **Touches remaining**: Coverage explanations distinguish limited telemetry from observed values, but empty-plan/loading states still mix absence with zero-like counts (`TodayDashboard.swift:196-205`; `TodayDashboardCommandOverview.swift:160-163`).

## 14. Main objective and task list

- [ ] See the main objective's title, deadline, estimate, and status. - **Partially implemented**: The focus card shows title, estimate, deadline, and urgency, while status is implied by the command/heading rather than explicitly labelled (`TodayDashboardCommandOverview.swift:57-105`).
- [ ] Understand why it is the main objective. - **Touches remaining**: Suggested plan entries can show selection evidence and the next-reason text identifies the main objective, but manual plans only say no ranking claim (`DashboardView.swift:1022-1041`; `TodayDashboardCommandOverview.swift:344-347`).
- [ ] Start or resume it directly from its card. - **Fully implemented**: The primary focus card maps ready to Start and paused to Resume through XPC-backed task commands (`TodayDashboardCommandOverview.swift:95-98,368-374`).
- [ ] See each task's rank, title, list or project, estimate, deadline, urgency, and status. - **Partially implemented**: Proposal rows show numeric rank, title, estimate, and evidence, while active Today rows show deadline, urgency, and status; neither unified row includes all fields and planned rows omit list/project (`DashboardView.swift:981-1058`; `TodayDashboardCommandOverview.swift:662-748`).
- [ ] Complete a task from its row. - **Touches remaining**: Active rows expose Complete and the agent queues Reminder completion, with passing store tests, but a live Reminder completion was not exercised (`DashboardView.swift:650-659`; `TodayDashboardAgent.swift:120-127`).
- [ ] Start a task from its row. - **Touches remaining**: Ready rows expose Start and task execution tests pass, but the installed app had no runnable planned row during verification (`DashboardView.swift:656-659`).
- [ ] Identify blocked, deferred, paused, active, and completed tasks visually. - **Partially implemented**: Rows render state text for blocked, paused, active, completed, and rescheduled, but there is no distinct deferred state and limited visual encoding beyond text/buttons.
- [ ] Read long task titles without losing access to controls. - **Touches remaining**: Task titles wrap to two lines with layout priority and controls remain separate, but longer-than-two-line truncation was not visually tested (`TodayDashboardCommandOverview.swift:681-701`).
- [ ] See task information clearly with larger text enabled. - **Blocked from verification**: SwiftUI semantic fonts and adaptive layouts are present, but no larger-text accessibility runtime pass or screenshot was completed.
- [ ] Find remaining non-priority tasks without letting them dominate the plan. - **Fully implemented**: The full inventory is placed below the plan, grouped by Reminder list, after the decision and action surfaces (`DashboardView.swift:215-274`).

## 15. Receiving a next-task recommendation

- [ ] See one recommended next task rather than a list of competing recommendations. - **Fully implemented**: `TodaySnapshot` contains one recommendation and Today renders one `DO THIS NEXT` card (`TodayDashboard.swift:308-319`; `TodayDashboardCommandOverview.swift:250-283`).
- [ ] See one concise reason for the recommendation. - **Fully implemented**: The next card shows one sentence plus a short `Why this` explanation (`TodayDashboardCommandOverview.swift:260-278,344-347`).
- [ ] Receive recommendations that prefer today's selected tasks. - **Fully implemented**: The recommender is given only daily-plan rows, and tests confirm stable recommendations that skip blocked tasks (`TodayDashboardAgent.swift:38-61`; `TodayDashboardAgentTests`).
- [ ] Receive a bounded sprint recommendation when an important task is too large for the available time. - **Partially implemented**: The recommender has a short-fit reason and receives available minutes, but the rendered recommendation does not create or start a bounded sprint (`TodayDashboard.swift:208-229`; `TodayDashboardAgent.swift:61`).
- [ ] Start the recommendation immediately. - **Fully implemented**: A ready recommended row has a direct Begin/Start control routed to `.start` (`TodayDashboardCommandOverview.swift:279-282,368-374`).
- [ ] Choose `Not now`. - **Not implemented**: The recommendation card has no Not now feedback action.
- [ ] Say the recommendation has the wrong priority. - **Not implemented**: No wrong-priority feedback control or persisted signal exists.
- [ ] Say the task is too large. - **Not implemented**: No too-large feedback action exists.
- [ ] Mark the task blocked. - **Partially implemented**: The task can be blocked from its row's More menu, but not directly from the recommendation card and no reason can be entered (`DashboardView.swift:660-670`).
- [ ] Mark the task already done. - **Partially implemented**: An active task can be completed, but a ready recommendation cannot be marked already done directly and completion implies a tracked session.
- [ ] Hide the task for today. - **Partially implemented**: Removing a plan entry excludes it from Today, but there is no recommendation-specific Hide for today action or durable hidden state.
- [ ] See a new recommendation after giving feedback. - **Partially implemented**: Starting, completing, or blocking through task commands refreshes the snapshot and recommendation, but the requested feedback controls are absent (`AppModel.swift:136-145`; `TodayDashboardAgent.swift:112-168`).
- [ ] Avoid receiving completed, cancelled, deleted, or unusably blocked tasks as recommendations. - **Touches remaining**: Completed and blocked states are excluded by passing recommender tests and missing Reminder IDs disappear from rows, but cancelled/deleted live-source cases were not exercised (`NextTaskRecommender`; `TodayDashboardAgentTests`).

## 16. Starting a task

- [ ] Start a task from the Today dashboard. - **Fully implemented**: Ready task rows and primary/recommendation cards all issue `.start` through the agent, with task execution tests passing (`DashboardView.swift:656-659`; `TodayDashboardCommandOverview.swift:368-374`).
- [ ] Start a task from the menu bar. - **Not implemented**: The only menu-bar extra is Zoid Voice and it contains no active-task or task-start menu (`ZoidCoachApp.swift:51-55`).
- [ ] Start a task from a dashboard prompt. - **Barely started**: Prompt actions can render generically and the enum includes `startRecommendedTask`, but the prompt response effect router ignores task actions, so clicking cannot start work end to end (`PromptInbox.swift:47-64`; `PromptResponseEffectRouter.swift:43-108`).
- [ ] Start a task from the recommendation card. - **Fully implemented**: The recommendation card directly starts a ready row through `.start` (`TodayDashboardCommandOverview.swift:279-282,368-374`).
- [ ] Start a task with a keyboard shortcut. - **Not implemented**: No task-start keyboard shortcut or Commands entry exists; only modal cancel shortcuts are defined.
- [ ] See the task become the single active task everywhere. - **Partially implemented**: Backend execution enforces one open interval and Today updates to the active row, but the menu bar does not show task state and no cross-surface live test exists (`TaskExecutionStore.swift:35-46`; `TodayDashboardAgent.swift:60-61`).
- [ ] See the previous task pause automatically when starting another task. - **Touches remaining**: The transactional store pauses the prior task and a passing test proves the state transition, but no populated UI E2E sequence was exercised (`TaskExecutionStore.swift:39-45`; `TaskExecutionStoreTests`).
- [ ] Avoid seeing two active tasks after clicking twice or using two surfaces. - **Touches remaining**: One database open interval and idempotent state updates prevent simultaneous active tasks, but multi-surface rapid-click behavior was not runtime-tested (`TaskExecutionStore.swift:35-46,142-148`).
- [ ] See active-task status appear in the dashboard and menu bar. - **Partially implemented**: Dashboard rows show Active and switch commands, while the menu bar remains voice-only (`DashboardView.swift:644-659`; `ZoidCoachApp.swift:51-55`).
- [ ] Restart Zoid 666 and continue the same active session without duplicated time. - **Touches remaining**: Open intervals and elapsed time persist in SQLite, and pause/restart timing tests pass, but an installed app start-restart-clock sequence was not performed (`TaskExecutionStore.swift:63-75,142-160`; `TaskExecutionStoreTests`).

## 17. Choosing a work commitment

- [ ] Start an open-ended work session. - **Touches remaining**: Starting a task opens an unbounded activity interval and persists it, but the UI never labels the commitment as open-ended (`TaskExecutionStore.swift:39-45,123-129`).
- [ ] Start a 10-minute recovery sprint. - **Barely started**: `startShortSprint` exists as a prompt action kind, but there is no duration model, effect routing, timer, or direct UI (`PromptInbox.swift:47-64`).
- [ ] Start a 20-minute work sprint. - **Not implemented**: No sprint-duration state or 20-minute action exists.
- [ ] Start a 25-minute focus sprint. - **Not implemented**: No sprint-duration state or 25-minute action exists.
- [ ] Enter a custom sprint duration. - **Not implemented**: There is no sprint input or bounded-session model.
- [ ] Start a block matching the full task estimate. - **Partially implemented**: Starting work and selecting an estimate both exist, but start always opens an unbounded interval and does not attach the estimate as a timer boundary.
- [ ] See elapsed time for an open-ended session. - **Frontend only left**: The snapshot carries `elapsedMinutes`, but current Today task rows and focus card do not render it (`TodayDashboard.swift:37-58`; `TodayDashboardCommandOverview.swift:57-105,662-748`).
- [ ] See remaining time for a bounded sprint. - **Not implemented**: No bounded sprint deadline or remaining-time field exists.
- [ ] Reach the end of a sprint without having the task completed automatically. - **Not implemented**: There is no sprint end event or bounded timer behavior.
- [ ] Continue working after a sprint ends. - **Not implemented**: There is no sprint lifecycle or continue action.
- [ ] Pause and later resume a bounded sprint with understandable timing. - **Frontend only left**: Generic task pause/resume correctly preserves elapsed interval time, but bounded duration and remaining-time semantics do not exist (`TaskExecutionStore.swift:46-49`; `TaskExecutionStoreTests`).

## Section summary

Status counts are generated from the 174 exact scenarios above.

- Fully implemented: 17
- Touches remaining: 54
- Frontend only left: 20
- Partially implemented: 35
- Barely started: 2
- Not implemented: 44
- Blocked from verification: 2

The strongest usable area in sections 1-17 is the core Today task execution path: plan display, one recommendation, one active task, start/pause/resume/complete persistence, source health, and gaming status.
The largest end-user gaps are the entire onboarding journey, Reminder-list inclusion rules, explicit unplanned-day mode, capacity warnings, learned-estimate presentation, recommendation feedback, menu-bar task control, and every bounded sprint flow.
