# Zoid 666 End-User Scenario Tracker

This tracker covers the complete Zoid 666 product specification from the end user's point of view.

Every checkbox describes something the user can see, do, understand, configure, confirm, or recover from.

Technical implementation details are included only when they create an observable user outcome.

## Audit result

Updated on 2026-07-12 against branch `codex/full-system` through weekly-review tip `2e20227` plus the independently verified background-agent lifecycle batch, 42 passing registry and evidence tests, focused Swift coverage, a passing signed-QA package gate, deterministic operating-system fixtures, the exact 666-scenario registry, and visible macOS accessibility click-through testing.

This update includes the implemented twelve-step onboarding flow, crash-safe onboarding persistence, permission deferral and repair paths, canonical Screenwatch folder selection, application discovery and classification, schedule and gaming-policy choices, rules-only coaching, Reminder-list inclusion policy, and durable first-daily-plan preparation.

Only scenarios proven completely usable end to end are checked.

- **Fully implemented:** 68
- **Touches remaining:** 165
- **Frontend only left:** 22
- **Partially implemented:** 132
- **Barely started:** 45
- **Not implemented:** 202
- **Blocked from verification:** 32
- **Total:** 666

### Status meanings

- **Fully implemented** means the complete user journey is available and credibly proven in the running product.
- **Touches remaining** means the core journey is usable but smaller usability or verification gaps remain.
- **Frontend only left** means supporting behavior exists but the user cannot complete the scenario through the interface.
- **Partially implemented** means meaningful pieces exist but the user cannot complete the whole scenario.
- **Barely started** means only a primitive, model, store, or generic shell exists.
- **Not implemented** means no meaningful implementation of the user scenario was found.
- **Blocked from verification** means the flow may exist but current conditions prevent credible end-to-end proof.

### Current verification note

The signed-QA application now opens a clean first launch without requiring a pre-existing policy database.

Visible accessibility click-through verified all 12 onboarding steps from welcome through the first daily plan and Today.

The test also verified leaving setup for Today, relaunching the app, resuming at the exact saved onboarding step, completing setup, and relaunching directly into Today.

The isolated QA and unit suites cover persistence conflicts, exact Reminder-list identities, all-lists-excluded local fallback, canonical Screenwatch bookmarks, gaming-policy storage, and first-plan restart durability.

The persistent signed-QA runtime registered its dedicated helper through SMAppService, ran the exact QA Mach service from the installed application, and passed real XPC mutation receipt, replay, and stale-write rejection checks.

The visible run saved exact Reminder-list choices, application classifications, schedule boundaries, gaming posture, rules-only coaching, bounded notification delivery, and onboarding completion through that installed runtime.

The first daily-plan handoff exposed and fixed two direct blockers: Today now refreshes on the onboarding route transition, and external Reminder reconciliation preserves incomplete local fallback tasks; the installed signed-QA background-agent journey additionally verified live health refresh, Login Items navigation, packaged repair, disabled and re-enabled launchd states, local-data preservation, and simultaneous production/QA identity isolation.

## 1. First launch

- [x] Open Zoid 666 for the first time and immediately understand that it helps connect planned work with actual computer activity. **Status: Fully implemented.** A clean signed-QA launch opens the Welcome step with explicit planned-versus-actual copy, and the visible accessibility run confirmed the complete first screen (`Sources/ZoidCoachApp/Views/Onboarding/OnboardingRootView.swift:102`; `Tests/ZoidCoachAppTests/OnboardingCoordinatorTests.swift`).
- [x] Understand that Apple Reminders represents intended work. **Status: Fully implemented.** The Welcome and Local Truth steps explicitly describe Reminders as intended work before the dedicated permission step, and both screens were verified in the signed-QA app (`Sources/ZoidCoachApp/Views/Onboarding/OnboardingRootView.swift:102`).
- [x] Understand that Screenwatch represents observed computer activity. **Status: Fully implemented.** The first-launch copy explains what actually happens on the Mac and the dedicated Screenwatch step explains behavior coaching before access or folder selection; the visible run reached and inspected this step (`Sources/ZoidCoachApp/Views/Onboarding/OnboardingRootView.swift:102`).
- [x] Understand that the Today dashboard provides persistent status and prompts. **Status: Fully implemented.** Welcome states that Today keeps the plan, source status, and unanswered coaching choices in one place, and Exit For Now visibly opened Today (`Sources/ZoidCoachApp/Views/Onboarding/OnboardingRootView.swift:104`; `Sources/ZoidCoachApp/Views/DashboardView.swift`).
- [ ] Understand that Zoid 666 is a coach rather than a replacement task manager. **Status: Touches remaining.** First launch consistently presents Zoid 666 as a coach grounded in Reminders, but it still does not state as directly as it should that Reminders remains the task system of record.
- [x] Understand that the app does not punish, shame, or block the user by default. **Status: Fully implemented.** The Welcome step says recovery is without shame and nothing is blocked or punished by default; the gaming-policy step reinforces that no option locks apps or removes the user's final decision (`Sources/ZoidCoachApp/Views/Onboarding/OnboardingRootView.swift:104`).
- [x] Understand that important data stays on the Mac by default. **Status: Fully implemented.** The Local Truth step explicitly explains local Reminders, Screenwatch summaries, plans, and coaching history, and the signed-QA run visibly confirmed the screen (`Sources/ZoidCoachApp/Views/Onboarding/OnboardingRootView.swift:108`).
- [x] Continue onboarding without being forced to configure optional AI features. **Status: Fully implemented.** The installed signed-QA run selected Rules-only, saved it through the XPC policy boundary, continued without configuring a model provider, and completed setup (`OnboardingRootView.swift`; `OnboardingCoordinatorTests.swift`; `.audit/runs/onboarding-visible/cfe7fbd3480191177d0a59b568061a0236101147/evidence.json`).
- [x] Leave onboarding and resume from the same point later. **Status: Fully implemented.** Exit For Now opened Today from step 3, and relaunching the signed-QA app returned to the exact same Reminders step (`Sources/ZoidCoachInfrastructure/OnboardingProgressStore.swift`; `Tests/ZoidCoachAppTests/OnboardingCoordinatorTests.swift`).
- [x] Restart the app during onboarding without losing completed setup steps. **Status: Fully implemented.** Killing and relaunching the signed-QA app at step 3 restored step 3 exactly, while crash-safe revision and migration tests cover durable progress recovery (`Tests/ZoidCoachAppTests/OnboardingProgressStoreHardeningTests.swift`; `Tests/ZoidCoachAppTests/OnboardingProgressTests.swift`).

## 2. Reminders permission during onboarding

- [x] See why Reminders access is useful before macOS requests permission. **Status: Fully implemented.** The dedicated Reminders onboarding step explains intended work and unavailable capabilities before the Request Access control, and the signed-QA run visibly inspected this state without invoking macOS permission (`Sources/ZoidCoachApp/Views/Onboarding/OnboardingRootView.swift`; `Tests/ZoidCoachAppTests/OnboardingCoordinatorTests.swift`).
- [ ] Grant Reminders access and continue setup. **Status: Touches remaining.** The installed signed-QA run exercised the granted path, refreshed healthy fixture state, discovered exact stable list identifiers, saved list choices, and continued. A real EventKit authorization prompt still requires a user-controlled macOS permission reset before this can qualify as fully implemented (`OnboardingCoordinator.swift`; `QAFixtureOSCompositionTests.swift`; `.audit/runs/onboarding-visible/cfe7fbd3480191177d0a59b568061a0236101147/evidence.json`).
- [ ] Deny Reminders access and understand which features will be unavailable. **Status: Touches remaining.** Denied-state consequence copy, repair, and local-only continuation are implemented and deterministically tested, but the visible run exercised deliberate deferral rather than a real macOS denial (`OnboardingRootView.swift`; `OnboardingCoordinatorTests.swift`).
- [ ] Continue setup after denying Reminders access. **Status: Touches remaining.** The explicit Not Now path was clicked in the signed-QA app and the denied path passes deterministic QA, but an actual macOS denial followed by continuation has not yet been visibly exercised (`OnboardingCoordinator.swift`; `OnboardingCoordinatorTests.swift`).
- [ ] Open System Settings directly when ready to grant previously denied access. **Status: Touches remaining.** Onboarding now exposes the Reminders privacy repair destination and tests cover the command, but the native System Settings handoff was not clicked in the visible run (`OnboardingDependencies.swift:176-189`; `OnboardingCoordinatorTests.swift`).
- [ ] Return from System Settings and see the updated permission state. **Status: Touches remaining.** Recheck and foreground-safe inspection update onboarding health and list discovery, with deterministic tests covering transitions; the real System Settings round trip remains unperformed (`OnboardingCoordinator.swift`; `OnboardingCoordinatorTests.swift`).
- [ ] Avoid seeing the same permission dialog repeatedly after declining it. **Status: Blocked from verification.** EventKit and macOS authorization handling support the behavior, but the independent `a068d27` verifier could not run the packaged deny-and-retry UI flow without mutating real permission state (`.audit/runs/baseline/a068d27/REPORT.md`).
- [ ] Use manual local planning while Reminders access is unavailable. **Status: Touches remaining.** The visible signed-QA run created and opened a local starter plan when no eligible external task existed, and relaunch retained the same local task after the route-refresh and reconciliation fixes. The exact real-macOS-denied variant remains unperformed (`OnboardingFirstDailyPlanService.swift`; `AppModel.swift`; `OnboardingFirstDailyPlanServiceTests.swift`; `.audit/runs/onboarding-visible/cfe7fbd3480191177d0a59b568061a0236101147/evidence.json`).

## 3. Screenwatch setup during onboarding

- [x] Let Zoid 666 find Screenwatch automatically at the expected location. **Status: Fully implemented.** The onboarding step automatically inspects the canonical default source before asking for a choice, and the visible signed-QA run displayed its current health plus Check Expected Folder and Choose Folder controls (`Sources/ZoidCoachInfrastructure/ScreenwatchSourceRepository.swift`; `Tests/ZoidCoachAppTests/ScreenwatchSetupServiceTests.swift`).
- [ ] See whether the detected Screenwatch source is healthy. **Status: Blocked from verification.** Source health code and the live backend verifier support the behavior, but the independent `a068d27` verifier had no current packaged UI or accessibility proof (`.audit/runs/baseline/a068d27/REPORT.md`).
- [ ] Select another Screenwatch folder when the default location is unavailable. **Status: Touches remaining.** A native folder picker, private atomic security-scoped bookmark store, no-follow validation, canonical app-agent-OCR consumption, and restart tests are implemented; the visible run confirmed the Choose Folder control but did not complete the picker (`ScreenwatchSourceRepository.swift`; `ScreenwatchSourceRepositoryTests.swift`).
- [ ] Understand why a selected folder is invalid without seeing sensitive captured content. **Status: Touches remaining.** Privacy-safe malformed, schema, bookmark, and unsafe-path diagnostics are implemented and tested without exposing captured records, but an invalid native folder selection was not visibly exercised (`Tests/ZoidCoachAppTests/ScreenwatchSetupServiceTests.swift`; `Tests/ZoidCoachAppTests/ScreenwatchSourceRepositoryTests.swift`).
- [x] Continue setup without Screenwatch and understand that behavior coaching will be unavailable. **Status: Fully implemented.** The signed-QA run clicked Not Now on the Screenwatch step, saw the consequence copy, and continued to Notifications (`Sources/ZoidCoachApp/Onboarding/OnboardingCoordinator.swift`; `Tests/ZoidCoachAppTests/OnboardingCoordinatorTests.swift`).
- [ ] Open the repair path when folder access is denied. **Status: Touches remaining.** Choose Folder and Recheck are now present and the repository rejects stale, invalid, unsafe, and cross-run bookmarks deterministically; the actual denied-access picker recovery was not visibly exercised (`ScreenwatchSourceRepositoryTests.swift`).
- [ ] Return after repairing access and see Screenwatch become connected. **Status: Touches remaining.** Recheck resolves the canonical bookmark afresh and updates onboarding health, with consumer and restart tests covering the transition; a visible repair round trip remains (`ScreenwatchSourceRepositoryTests.swift`; `OnboardingCoordinatorTests.swift`).
- [ ] Understand that screenshots are not routinely inspected. **Status: Touches remaining.** Onboarding explains the local, privacy-bounded source and Settings exposes explicit screenshot-analysis opt-in, but the exact routine-versus-ambiguous promise still needs clearer copy (`Sources/ZoidCoachApp/Views/Onboarding/OnboardingRootView.swift`; `Sources/ZoidCoachApp/Views/SettingsView.swift`).
- [ ] Choose whether screenshot analysis may be used for genuinely ambiguous situations. **Status: Touches remaining.** The persisted choice is implemented in onboarding and Settings with policy tests, but the visible run has not reached and saved that preference (`OnboardingRootView.swift`; `SettingsPolicyDraftTests.swift`).

## 4. Notification setup

- [x] Understand that the Today dashboard remains available without notification permission. **Status: Fully implemented.** The Notifications onboarding step explicitly explains the Today fallback, and the visible signed-QA run clicked Not Now and continued successfully (`Sources/ZoidCoachApp/Views/Onboarding/OnboardingRootView.swift:132`; `Tests/ZoidCoachAppTests/OnboardingCoordinatorTests.swift`).
- [ ] Grant notification permission for timely prompts. **Status: Touches remaining.** The fresh installed signed-QA run visibly reported healthy notification access, accepted Request Notification Access, scheduled the canonical prompt, and processed its action through the running agent, while a real macOS authorization reset and Notification Center click remain before full qualification (`NotificationService.swift`; `PromptNotificationCoordinator.swift`; `.audit/runs/onboarding-test-prompt/signed-acceptance/REPORT.md`).
- [x] Resolve a test notification action. **Status: Fully implemented.** The installed signed-QA app created one canonical `ONBOARDING_TEST` prompt, the running agent accepted only its whitelisted `continue_intentionally` action from the delivered fixture notification, the response persisted with surface `notification`, onboarding changed to Prompt Resolved, and relaunch retained the result (`OnboardingTestPromptService.swift`; `PromptNotificationCoordinator.swift`; `.audit/runs/onboarding-test-prompt/signed-acceptance/REPORT.md`).
- [ ] Deny notification permission and continue with in-app prompts. **Status: Touches remaining.** A fresh installed signed-QA denial journey visibly reported Attention without touching production Notification Center, continued through every remaining preference step, and completed the canonical Today fallback, while an actual macOS authorization-panel denial remains before full qualification (`OnboardingCoordinator.swift`; `OnboardingTestPromptService.swift`; `.audit/runs/onboarding-test-prompt/signed-acceptance/REPORT.md`).
- [x] Test the Today dashboard prompt inbox. **Status: Fully implemented.** With notification permission denied, step 11 visibly reported Today Fallback, Exit For Now exposed the same unresolved canonical prompt and actions under Today Decisions, Continue Setup resolved it with persisted surface `dashboard`, and Resume Setup returned to step 11 with Prompt Resolved and Continue enabled (`DashboardView.swift`; `TodayDashboardXPC.swift`; `.audit/runs/onboarding-test-prompt/signed-acceptance/REPORT.md`).

## 5. Initial preferences

- [x] Choose which Reminder lists Zoid 666 should use. **Status: Fully implemented.** The installed signed-QA run discovered Work and Personal with their exact stable identifiers, selected Include Work and Exclude Personal in the native UI, persisted both choices through XPC, and advanced successfully (`RemindersService.swift`; `OnboardingRootView.swift`; `SettingsView.swift`; `UserPolicy.swift`; `.audit/runs/onboarding-visible/cfe7fbd3480191177d0a59b568061a0236101147/evidence.json`).
- [x] Exclude personal or irrelevant Reminder lists. **Status: Fully implemented.** Exclude Personal was selected in the visible run and saved through the same conflict-safe policy boundary. AppModel, agent synchronization, planning, rename, restart, unknown-list fail-closed, and all-excluded local fallback tests cover downstream enforcement (`AppModel.swift`; `AgentReminderPlanner.swift`; `OnboardingFirstDailyPlanService.swift`; `.audit/runs/onboarding-visible/cfe7fbd3480191177d0a59b568061a0236101147/evidence.json`).
- [x] Preview detected applications before assigning categories. **Status: Fully implemented.** The installed signed-QA app scanned the actual Mac, displayed 116 detected applications, exposed Scan Again, and advanced only after the user reviewed the inventory (`Sources/ZoidCoachApp/Views/Onboarding/OnboardingRootView.swift`; `Tests/ZoidCoachAppTests/OnboardingCoordinatorTests.swift`).
- [x] Mark known work applications. **Status: Fully implemented.** The visible installed run selected Work for Activity Monitor, saved the classification through the live QA XPC helper, advanced to schedule setup, and retained the winning policy version (`OnboardingCoordinator.swift`; `PolicyStoreTests.swift`; `.audit/runs/onboarding-visible/cfe7fbd3480191177d0a59b568061a0236101147/evidence.json`).
- [x] Mark known gaming applications. **Status: Fully implemented.** The visible installed run selected Gaming for Atoll, saved it through the live QA XPC helper, and advanced successfully; policy persistence and behavior-consumer tests cover the downstream classification (`OnboardingCoordinator.swift`; `PolicyStoreTests.swift`; `.audit/runs/onboarding-visible/cfe7fbd3480191177d0a59b568061a0236101147/evidence.json`).
- [x] Leave ambiguous applications unclassified for later review. **Status: Fully implemented.** Every detected app defaulted to Automatic, most remained unchanged, and the complete classification policy was durably saved when the run advanced to schedule setup (`Sources/ZoidCoachApp/Views/Onboarding/OnboardingRootView.swift`; `.audit/runs/onboarding-visible/cfe7fbd3480191177d0a59b568061a0236101147/evidence.json`).
- [ ] Configure a flexible work window. **Status: Touches remaining.** The installed run visibly reviewed and saved the default 09:00-18:00 work window through the conflict-safe policy boundary. A visible non-default time selection remains before the configuration interaction is fully proven (`OnboardingRootView.swift`; `OnboardingCoordinatorTests.swift`; `.audit/runs/onboarding-visible/cfe7fbd3480191177d0a59b568061a0236101147/evidence.json`).
- [ ] Configure quiet hours. **Status: Touches remaining.** The installed run visibly reviewed and saved the overnight 23:00-07:00 quiet window. A visible non-default picker selection remains before full qualification (`OnboardingRootView.swift`; `OnboardingCoordinatorTests.swift`; `.audit/runs/onboarding-visible/cfe7fbd3480191177d0a59b568061a0236101147/evidence.json`).
- [x] Choose an initial gaming policy. **Status: Fully implemented.** The installed run selected Balanced, saved it through the app-agent XPC policy boundary, and advanced to coaching mode; restart and mutation tests cover durability (`OnboardingRootView.swift`; `PolicyStoreTests.swift`; `.audit/runs/onboarding-visible/cfe7fbd3480191177d0a59b568061a0236101147/evidence.json`).
- [x] Choose rules-only coaching for Release 1. **Status: Fully implemented.** The installed run selected Rules-only, saved it without configuring AI, advanced through delivery proof, and completed onboarding (`OnboardingRootView.swift`; `OnboardingCoordinatorTests.swift`; `.audit/runs/onboarding-visible/cfe7fbd3480191177d0a59b568061a0236101147/evidence.json`).
- [x] Finish onboarding by opening the first daily plan. **Status: Fully implemented.** The installed Zoid 666 QA run prepared a real 15-minute local starter objective, opened Today with one active commitment and one planned block immediately, then retained the same task, estimate, and action controls across package replacement and repeated quit/relaunch (`OnboardingFirstDailyPlanService.swift`; `AppModel.swift`; `OnboardingFirstDailyPlanServiceTests.swift`; `.audit/runs/onboarding-visible/cfe7fbd3480191177d0a59b568061a0236101147/evidence.json`).

## 6. Starting the day

- [ ] Receive a low-pressure planning invitation at the configured planning time. **Status: Partially implemented.** The agent schedules a PLAN_READY notification at morning confirmation time, but the wording was not assessed as low-pressure and no live delivery was verified (`AgentMain.swift:776-813`; `PromptNotificationCoordinator.swift:93-102`).
- [ ] Receive the invitation when first using the Mac if the configured time passed while inactive. **Status: Partially implemented.** Missed nightly planning after wake is unit-tested and immediate notification delivery is possible when the target time is past, but the complete wake-to-invitation flow was not exercised live.
- [ ] Open planning manually before the configured time. **Status: Touches remaining.** The installed signed app exposed enabled `PLAN NOW` and `DRAFT TODAY` controls with two real deterministic Reminder candidates, while activation of the manual draft itself remains unclaimed (`DashboardView.swift`; `.audit/runs/morning-planning/27ad4f34c23d4a77e36ae3f065e9c70cda7f6f4d/REPORT.md`).
- [x] Snooze planning without causing coaching escalation. **Status: Fully implemented.** The installed signed app snoozed the canonical PLAN_READY decision, removed it without escalation, rendered `PLANNING SNOOZED` with the exact return time, and preserved that state through package replacement and relaunch (`PlanningInvitationService.swift`; `DashboardView.swift`; `PlanningInvitationServiceTests.swift`; `.audit/runs/morning-planning/27ad4f34c23d4a77e36ae3f065e9c70cda7f6f4d/REPORT.md`).
- [x] Receive the planning invitation again when the snooze ends. **Status: Fully implemented.** A focused time-shift advanced the persisted snooze to its due time, the running signed helper presented it once, and relaunch visibly restored the full invitation with Plan Now, Snooze, Dismiss, and Work Unplanned actions (`AgentMain.swift`; `PlanningInvitationServiceTests.swift`; `.audit/runs/morning-planning/27ad4f34c23d4a77e36ae3f065e9c70cda7f6f4d/REPORT.md`).
- [ ] Dismiss planning temporarily without being trapped in repeated prompts. **Status: Touches remaining.** The installed signed app exposed the enabled Dismiss For Now action and focused persistence tests prove two-hour suppression and due recovery, but the verifier conservatively stopped before a second destructive prompt mutation (`PlanningInvitationService.swift`; `PlanningInvitationServiceTests.swift`; `.audit/runs/morning-planning/27ad4f34c23d4a77e36ae3f065e9c70cda7f6f4d/REPORT.md`).
- [x] See clearly that the day is currently unplanned. **Status: Fully implemented.** The installed signed Today surface explicitly rendered `DAY STATE / UNPLANNED`, explained that drift coaching stays off until the user chooses, and kept two available Reminder tasks visible (`DashboardView.swift`; `.audit/runs/morning-planning/27ad4f34c23d4a77e36ae3f065e9c70cda7f6f4d/REPORT.md`).
- [ ] Start work manually even when the day has not been planned. **Status: Touches remaining.** Each installed Reminder row exposed a stable Start Without Planning control and the XPC journey test proves durable unplanned task start and restart recovery, but this verifier did not click the signed mutation (`TodayDashboardAgent.swift`; `TodayDashboardXPC.swift`; `TodayDashboardAgentTests.swift`; `.audit/runs/morning-planning/27ad4f34c23d4a77e36ae3f065e9c70cda7f6f4d/REPORT.md`).
- [ ] Avoid drift warnings before approving a plan or explicitly starting unplanned work. **Status: Touches remaining.** The signed surface truthfully stated that drift coaching stays off until a choice, and focused state tests gate interventions until unplanned work starts, while a live generated-drift episode remains unexercised (`PlanningInvitationService.swift`; `PlanningInvitationServiceTests.swift`; `.audit/runs/morning-planning/27ad4f34c23d4a77e36ae3f065e9c70cda7f6f4d/REPORT.md`).

## 7. Seeing today's available tasks

- [ ] See incomplete Reminders due today. **Status: Touches remaining.** All incomplete reminders are fetched and due dates render, so due-today items appear, but the installed list was not populated during runtime verification (`RemindersService.swift:90-126`; `DashboardView.swift:774-776`).
- [ ] See overdue incomplete Reminders. **Status: Touches remaining.** Overdue reminders are included and active-plan rows label them Overdue, but there is no dedicated overdue grouping and live data was not exercised (`TodayTaskRowView`, `DashboardView.swift:682-688`).
- [ ] See tasks manually selected for today. **Status: Touches remaining.** Added reminders persist as daily-plan entries and render in the proposed plan, with store tests passing, but a complete live add-and-reopen flow was not performed (`AppModel.swift:200-218`; `EventStore.swift:88-155`).
- [ ] See tasks from included Today lists. **Status: Touches remaining.** Identifier-based list inclusion now controls the Reminder inventory used by the app, agent, and first-plan service, and signed-QA exact-ID tests prove included tasks survive filtering. A dedicated named Today-list policy is intentionally not inferred from display names, and the visible native inventory still needs unlocked-Mac proof.
- [ ] Carry a task without a due date into today. **Status: Touches remaining.** Undated incomplete reminders are fetched and can be added to the plan, but the installed flow was not exercised (`RemindersService.swift:90-126`; `InboxReminderTaskRow`).
- [ ] Avoid seeing future tasks that were not selected for today. **Status: Not implemented.** The full inventory intentionally contains all incomplete reminders, including future-dated tasks, because fetch predicates have no date boundary (`RemindersService.swift:93-97`).
- [ ] Avoid seeing tasks from excluded Reminder lists. **Status: Touches remaining.** Excluded identifiers are removed from the current AppModel session immediately after a durable Settings save and are also excluded before agent synchronization and first-plan planning. Policy-read failures suspend synchronization rather than failing open or deleting durable imports; signed-QA exact-ID and all-excluded tests pass, but native visual proof remains.
- [ ] Avoid seeing duplicate copies of the same Reminder. **Status: Touches remaining.** EventKit identifiers and plan reconciliation prevent one ID from being added twice, but no UI/E2E duplicate-source fixture was verified (`AppModel.swift:202-205`).
- [ ] Hide completed tasks from the active task list. **Status: Blocked from verification.** EventKit filtering and plan reconciliation support the behavior, but the independent `a068d27` verifier could not seed a completed Reminder fixture and assert the packaged UI without touching real data (`.audit/runs/baseline/a068d27/REPORT.md`).
- [ ] Still find completed tasks in today's history. **Status: Frontend only left.** Task completion history is persisted and tested, but the Reviews navigation currently renders the generic foundation/source-health page rather than a day history (`TodayDashboardAgent.swift:120-127`; `DashboardView.swift:21-29`).
- [ ] See recurring Reminder occurrences as separate tasks when appropriate. **Status: Blocked from verification.** EventKit supplies current Reminder entities, but there is no recurrence-specific UI logic or E2E recurring-reminder test demonstrating separate occurrences.
- [x] Understand when Reminders could not be refreshed. **Status: Fully implemented.** The installed signed-QA Settings card visibly changed from Connected to Refresh Failed when task retrieval failed, explained that the last successful sync remained available, retained its exact timestamp, and returned to Connected with a newer timestamp after one explicit retry (`RemindersConnectionController.swift`; `RemindersConnectionView.swift`; `.audit/runs/reminders-recovery/verifier/REPORT.md`).

## 8. Building the daily plan

- [ ] See a suggested main objective. **Status: Touches remaining.** The autonomous planner chooses a capacity-safe main objective and Today renders it prominently, with planner tests passing, but no live populated plan was verified (`AutonomousPlanner.swift`; `DashboardView.swift:918-932`).
- [ ] See three suggested priority tasks. **Status: Touches remaining.** The planner supports a bounded commitment set and the UI targets `3 PROPOSED`, but capacity may yield fewer and no live three-task draft was exercised (`DashboardView.swift:872-952`).
- [ ] Understand why each suggested task matters today. **Status: Touches remaining.** Suggested entries persist and display a selection reason; manually selected items truthfully say no ranking claim, but live reason quality was not verified (`DashboardView.swift:1022-1041`).
- [ ] See the proposed task order. **Status: Touches remaining.** Entries persist rank and render in rank order with numeric labels in the proposal ledger (`DashboardView.swift:868-870,981-1058`).
- [ ] See the estimated focused-work total. **Status: Frontend only left.** Individual estimates and planner totals exist, but no total focused-work value is shown in the plan UI.
- [ ] See the planned buffer time. **Status: Frontend only left.** Capacity planning reserves headroom in core logic, but the proposed-plan surface never displays buffer minutes or percentage.
- [ ] See the first recommended task. **Status: Touches remaining.** The populated Today overview has one `DO THIS NEXT` card and recommendation sentence, but no populated live plan was exercised (`TodayDashboardCommandOverview.swift:250-283`).
- [ ] See the proposed gaming unlock condition. **Status: Partially implemented.** The Today behavior panel shows current gaming budget and next unlock reason, but this is not a proposed-plan unlock condition users can review (`TodayDashboardCommandOverview.swift:172-191`).
- [ ] Add an available task to the plan. **Status: Touches remaining.** Inbox rows call `addToDailyPlan`, enforce uniqueness and maximum five, and persist through the agent, but the installed add flow was not exercised (`AppModel.swift:200-218`).
- [ ] Remove a task from the plan. **Status: Touches remaining.** `EXCLUDE` and `REMOVE` update and persist the plan, with fallback restoration on failure, but the live flow was not exercised (`DashboardView.swift:1044-1051`; `AppModel.swift:220-245`).
- [ ] Reorder priority tasks. **Status: Not implemented.** Users can reorder Reminder-list groups, not the priority entries within the daily plan; plan rank is not directly editable.
- [ ] Choose a different main objective. **Status: Touches remaining.** `ADJUST: MAKE MAIN` updates exactly one main objective and persists it, but the installed interaction was not exercised (`DashboardView.swift:1044-1049`; `AppModel.swift:247-263`).
- [ ] Mark a task optional. **Status: Not implemented.** Daily-plan entries have no optional flag or user control.
- [ ] Mark a task blocked and explain why. **Status: Partially implemented.** Active plan task rows can be marked blocked, but there is no reason-entry field or explanation persistence (`DashboardView.swift:660-670`; `TaskExecutionStore.swift:53-55`).
- [ ] Reduce the day's scope. **Status: Touches remaining.** Users can exclude plan entries before acceptance and changes persist, but no capacity or consequence feedback is shown.
- [ ] Change the gaming unlock condition. **Status: Not implemented.** No user-facing gaming policy controls exist.
- [ ] Approve the proposed plan. **Status: Touches remaining.** `ACCEPT BLOCKS` sends a schedule-plan mutation and the PLAN_READY notification has Accept, with tests proving durable queueing, but an actual Calendar end-to-end acceptance was not exercised (`AppModel.swift:305-330`; `PromptResponseEffectRouter.swift:43-50`).
- [ ] Restart the app and see the approved plan restored correctly. **Status: Touches remaining.** Daily plan persistence and migration tests pass and AppModel reloads it at launch, but the installed approve-restart-compare sequence was not performed (`AppModel.swift:55-71,515-522`; `EventStore.swift:133-155`).

## 9. Planning an unrealistic workload

- [ ] See a clear warning when planned work exceeds available focus capacity. **Status: Touches remaining.** The live Today surface now renders a dedicated capacity panel in both snapshot and fallback states, and focused tests prove exact overage classification, but the signed seeded overload could not be completed after the helper snapshot failed to refresh seeded Reminders (`PlanningCapacityState.swift`; `DashboardView.swift`; `.audit/runs/planning-capacity/capacity-warning/REPORT.md`).
- [ ] See the selected workload and available capacity in the same warning. **Status: Touches remaining.** The signed app visibly showed `0 MIN PLANNED / 126 MIN AVAILABLE` after merging overlapping external commitments and ignoring a Zoid-owned block, while the populated-workload installed state remains unproven (`AppModel.swift`; `PlanningCapacityState.swift`; `.audit/runs/planning-capacity/capacity-warning/REPORT.md`).
- [ ] Receive a concrete suggestion about what to remove, defer, or make optional. **Status: Touches remaining.** The overload state names the lowest-ranked task and explains removal, estimate reduction, or exclusion, with focused rule coverage, but the signed helper refresh blocker prevented visible populated-plan proof (`PlanningCapacityState.swift`; `DashboardView.swift`; `.audit/runs/planning-capacity/capacity-warning/REPORT.md`).
- [ ] Reduce the plan directly from the warning. **Status: Touches remaining.** A stable accessible Remove Suggested Task action removes the exact suggested entry and immediately persists the revised plan, but the installed click-through remains outstanding (`AppModel.swift`; `DashboardView.swift`; `.audit/runs/planning-capacity/capacity-warning/REPORT.md`).
- [ ] Change an estimate and see capacity update immediately. **Status: Touches remaining.** Capacity derives directly from published plan state, the Calendar adjustment is now published, and focused tests prove overloaded-to-realistic recalculation after estimate changes; visible signed interaction remains outstanding (`AppModel.swift`; `PlanningCapacityStateTests.swift`).
- [ ] Add or remove a task and see capacity update immediately. **Status: Touches remaining.** Add, remove, and direct reduction mutate published plan state and therefore recalculate the live panel immediately, but stale helper snapshot inventory prevented the final installed add-remove sequence (`AppModel.swift`; `DashboardView.swift`; `.audit/runs/planning-capacity/capacity-warning/REPORT.md`).
- [ ] Approve a realistic revised plan. **Status: Touches remaining.** Acceptance is disabled for empty, missing-estimate, and overloaded plans and enabled only for a realistic revision, with exact recovery copy and focused tests; the signed accept-and-relaunch mutation remains outstanding (`AppModel.swift`; `DashboardView.swift`; `PlanningCapacityStateTests.swift`).
- [ ] Avoid receiving a vague warning with no useful next action. **Status: Touches remaining.** Missing estimates name their count, overload names the exact minutes and a specific reduction, and Calendar failure explicitly identifies configured-work-window fallback, while the complete populated signed journey remains unproven (`DashboardView.swift`; `.audit/runs/planning-capacity/capacity-warning/REPORT.md`).

## 10. Skipping planning

- [ ] Skip planning explicitly. **Status: Touches remaining.** The signed invitation exposed Work Unplanned, the XPC command persists the explicit choice, and focused tests prove restart-safe state, but the verifier did not click this second signed mutation (`AppModel.swift`; `TodayDashboardXPC.swift`; `TodayDashboardAgentTests.swift`).
- [ ] Understand that Zoid 666 is now in limited unplanned mode. **Status: Touches remaining.** The implemented limited-mode banner explains the reduced contract and focused persistence tests prove its state, while the exact post-click signed screen remains unclaimed (`DashboardView.swift`; `PlanningInvitationServiceTests.swift`).
- [x] See overdue and available tasks during an unplanned day. **Status: Fully implemented.** Before any plan existed, the installed signed Today screen labelled the day unplanned and rendered two available Work reminders with independent actions (`DashboardView.swift`; `.audit/runs/morning-planning/27ad4f34c23d4a77e36ae3f065e9c70cda7f6f4d/REPORT.md`).
- [ ] Start any available task during an unplanned day. **Status: Touches remaining.** The installed signed app exposed Start Without Planning for both available reminders and the agent journey proves durable XPC mutation and restart recovery, while the final signed click remains unclaimed (`TodayDashboardAgent.swift`; `TodayDashboardXPC.swift`; `TodayDashboardAgentTests.swift`).
- [ ] See behavior totals without being told that behavior violated a nonexistent plan. **Status: Touches remaining.** The unplanned signed screen retained behavior totals and explicitly suppressed pre-choice drift coaching, while the limited-mode post-click wording remains covered by focused state tests rather than a completed signed mutation (`DashboardView.swift`; `PlanningInvitationServiceTests.swift`).
- [ ] Return to planning later in the same day. **Status: Touches remaining.** Plan Now remained enabled on both the initial unplanned and restart-safe snoozed screens, and backend planning remains available, while a signed skip-then-plan mutation sequence was not completed (`DashboardView.swift`; `.audit/runs/morning-planning/27ad4f34c23d4a77e36ae3f065e9c70cda7f6f4d/REPORT.md`).
- [ ] End and review an unplanned day without invented planned outcomes. **Status: Frontend only left.** Behavior and history stores can represent activity without a plan, but there is no end-day control or unplanned-day review UI.

## 11. Adding task estimates

- [ ] Choose a 15-minute estimate. **Status: Touches remaining.** Both proposal and Today estimate selectors offer 15 and persist it, but the live click-and-reload flow was not exercised (`DashboardView.swift:1230-1305`; `TodayDashboardCommandOverview.swift:750-779`).
- [ ] Choose a 30-minute estimate. **Status: Touches remaining.** Both selectors offer 30 and use the same persisted update path, without live E2E interaction.
- [ ] Choose a 45-minute estimate. **Status: Touches remaining.** Both selectors offer 45 and use the same persisted update path, without live E2E interaction.
- [ ] Choose a 60-minute estimate. **Status: Touches remaining.** Both selectors offer 60 and use the same persisted update path, without live E2E interaction.
- [ ] Choose a 90-minute estimate. **Status: Touches remaining.** Both selectors offer 90 and use the same persisted update path, without live E2E interaction.
- [ ] Enter a custom estimate. **Status: Not implemented.** Estimate selectors expose only `[15, 30, 45, 60, 90]` and no text or stepper input (`DashboardView.swift:1236`; `TodayDashboardCommandOverview.swift:755`).
- [ ] Receive a clear error for an empty, zero, negative, or malformed estimate. **Status: Not implemented.** There is no custom estimate input and no estimate validation/error surface.
- [ ] Select `Unknown` when an estimate cannot be made confidently. **Status: Not implemented.** No Unknown option exists in either selector.
- [ ] See the conservative placeholder assigned to an unknown estimate. **Status: Frontend only left.** Core planner candidates require positive integer estimates, but the UI and data model have no explicit unknown estimate state.
- [ ] Understand that the placeholder is uncertain. **Status: Not implemented.** No unknown placeholder or uncertainty copy is rendered.
- [ ] Change an estimate before starting the task. **Status: Touches remaining.** A selected estimate can be reopened with the pencil control or clicked in Today and persisted before task start (`DashboardView.swift:1246-1296`).
- [ ] See that every priority task needs an estimate or explicit `Unknown` choice before approval. **Status: Partially implemented.** Empty plans say estimates are required, but `ACCEPT BLOCKS` is disabled only for an empty plan and AppModel does not validate every estimate (`DashboardView.swift:944-952`; `AppModel.swift:305-330`).

## 12. Learning from previous estimates

- [ ] See a suggested estimate based on similar completed tasks when enough history exists. **Status: Frontend only left.** Estimate learning records robust aggregates and tests pass, but no UI reads or displays a learned suggestion (`TodayDashboardAgent.swift:140-165`; `LearningAggregateStore.swift`).
- [ ] See how many similar tasks support the suggestion. **Status: Frontend only left.** Aggregate evidence/sample counts exist in storage, but are never surfaced in the app.
- [ ] See the historical duration range behind the suggestion. **Status: Frontend only left.** Learning aggregates retain evidence and rollback values, but no duration-range UI exists.
- [ ] Understand when the evidence is uncertain. **Status: Frontend only left.** Core learning suppresses sparse aggregates, but Today provides no uncertainty explanation for estimates.
- [ ] Accept the suggested estimate. **Status: Frontend only left.** Users can choose a preset estimate, but there is no learned-suggestion value or Accept action.
- [ ] Keep the original estimate instead. **Status: Frontend only left.** Existing estimates remain unchanged unless clicked, but there is no suggestion comparison or explicit Keep action.
- [ ] Enter a different estimate. **Status: Partially implemented.** Users can select a different preset, but cannot enter arbitrary minutes.
- [ ] Avoid receiving a confident suggestion when tracking coverage or sample size is insufficient. **Status: Touches remaining.** Sparse evidence is prevented from creating aggregates by passing tests, but the end-user absence and later appearance of advice were not verified (`LearningAggregateStoreTests`).
- [ ] Avoid having an advisory estimate silently replace the user's estimate. **Status: Touches remaining.** Learned aggregates are separate from daily-plan values and no UI auto-writes them, but no end-to-end history scenario was exercised.

## 13. Understanding the Today dashboard

- [ ] See the current date and day state at a glance. **Status: Partially implemented.** A populated snapshot shows the full date, while the empty installed state omits it and neither surface names a formal day state (`TodayDashboardCommandOverview.swift:23-43`; runtime screenshot).
- [ ] See whether coaching is active or paused. **Status: Partially implemented.** Settings header clearly shows automation Running or Paused, but Today does not show coaching state and `AppModel.coachingState` is not rendered there (`SettingsView.swift:223-236`).
- [ ] See whether connected data sources are healthy. **Status: Blocked from verification.** Today and Source health contain the ledger and repair controls, but the independent `a068d27` verifier had no current main-window accessibility proof (`.audit/runs/baseline/a068d27/REPORT.md`).
- [ ] See the main objective as the strongest task-level element. **Status: Blocked from verification.** Source styling makes the main objective visually prominent, but the independent `a068d27` verifier could not capture and assess the current packaged UI (`.audit/runs/baseline/a068d27/REPORT.md`).
- [ ] See the active task or recommended next task prominently. **Status: Blocked from verification.** The focus and `DO THIS NEXT` cards exist in source, but the independent `a068d27` verifier had no isolated current UI state or visual proof (`.audit/runs/baseline/a068d27/REPORT.md`).
- [ ] See the top three before remaining tasks. **Status: Touches remaining.** Planned rows precede the full unplanned inventory, but the product does not enforce exactly three and can hold up to five (`DashboardView.swift:864-979,215-274`; `AppModel.swift:202-204`).
- [ ] See work, gaming, distraction, idle, and unknown totals. **Status: Touches remaining.** Core snapshot tracks all five and the usage popover separates categories, but the primary card emphasizes work and older installed UI combines gaming/distraction (`TodayDashboard.swift:128-192`; `TodayDashboardCommandOverview.swift:106-191`).
- [ ] See gaming budget status. **Status: Blocked from verification.** Budget calculation tests pass and the Today surface exists, but the independent `a068d27` verifier could not capture the current packaged UI or seed controlled budget states (`.audit/runs/baseline/a068d27/REPORT.md`).
- [ ] See recent coach decisions. **Status: Touches remaining.** Prompt inbox and automatic-action ledger show recent decisions/actions, but there is no concise chronological coach-decision history and the installed screen was dominated by stale meeting detections.
- [ ] End the workday from the dashboard. **Status: Not implemented.** `endWorkday` exists only as an unused prompt action kind; no fixed dashboard control or effect is implemented (`PromptInbox.swift:47-64`; `PromptResponseEffectRouter.swift:43-108`).
- [ ] Understand the dashboard even when some data is missing. **Status: Touches remaining.** Empty plan, missing source, limited coverage, and loading states have written explanations, though the installed dashboard stayed on `LOADING PLAN` and did not expose why it had not resolved.
- [ ] Distinguish missing information from a real zero value. **Status: Touches remaining.** Coverage explanations distinguish limited telemetry from observed values, but empty-plan/loading states still mix absence with zero-like counts (`TodayDashboard.swift:196-205`; `TodayDashboardCommandOverview.swift:160-163`).

## 14. Main objective and task list

- [ ] See the main objective's title, deadline, estimate, and status. **Status: Partially implemented.** The focus card shows title, estimate, deadline, and urgency, while status is implied by the command/heading rather than explicitly labelled (`TodayDashboardCommandOverview.swift:57-105`).
- [ ] Understand why it is the main objective. **Status: Touches remaining.** Suggested plan entries can show selection evidence and the next-reason text identifies the main objective, but manual plans only say no ranking claim (`DashboardView.swift:1022-1041`; `TodayDashboardCommandOverview.swift:344-347`).
- [ ] Start or resume it directly from its card. **Status: Touches remaining.** The primary focus card maps ready to Start and paused to Resume through XPC-backed task commands, but this installed-app action and persisted effect were not exercised end to end (`TodayDashboardCommandOverview.swift:95-98,368-374`).
- [ ] See each task's rank, title, list or project, estimate, deadline, urgency, and status. **Status: Partially implemented.** Proposal rows show numeric rank, title, estimate, and evidence, while active Today rows show deadline, urgency, and status; neither unified row includes all fields and planned rows omit list/project (`DashboardView.swift:981-1058`; `TodayDashboardCommandOverview.swift:662-748`).
- [ ] Complete a task from its row. **Status: Touches remaining.** Active rows expose Complete and the agent queues Reminder completion, with passing store tests, but a live Reminder completion was not exercised (`DashboardView.swift:650-659`; `TodayDashboardAgent.swift:120-127`).
- [ ] Start a task from its row. **Status: Touches remaining.** Ready rows expose Start and task execution tests pass, but the installed app had no runnable planned row during verification (`DashboardView.swift:656-659`).
- [ ] Identify blocked, deferred, paused, active, and completed tasks visually. **Status: Partially implemented.** Rows render state text for blocked, paused, active, completed, and rescheduled, but there is no distinct deferred state and limited visual encoding beyond text/buttons.
- [ ] Read long task titles without losing access to controls. **Status: Touches remaining.** Task titles wrap to two lines with layout priority and controls remain separate, but longer-than-two-line truncation was not visually tested (`TodayDashboardCommandOverview.swift:681-701`).
- [ ] See task information clearly with larger text enabled. **Status: Blocked from verification.** SwiftUI semantic fonts and adaptive layouts are present, but no larger-text accessibility runtime pass or screenshot was completed.
- [ ] Find remaining non-priority tasks without letting them dominate the plan. **Status: Blocked from verification.** The inventory is positioned below priority surfaces in source, but the independent `a068d27` verifier had no current packaged UI hierarchy proof (`.audit/runs/baseline/a068d27/REPORT.md`).

## 15. Receiving a next-task recommendation

- [ ] See one recommended next task rather than a list of competing recommendations. **Status: Blocked from verification.** `TodaySnapshot` and the Today source model one card, but the independent `a068d27` verifier did not run the current packaged recommendation journey (`.audit/runs/baseline/a068d27/REPORT.md`).
- [ ] See one concise reason for the recommendation. **Status: Blocked from verification.** The recommendation explanation exists in source, but the independent `a068d27` verifier had no current packaged visual or accessibility proof of its clarity (`.audit/runs/baseline/a068d27/REPORT.md`).
- [ ] Receive recommendations that prefer today's selected tasks. **Status: Blocked from verification.** Recommender tests cover selected daily rows, but the independent `a068d27` verifier could not prove the complete packaged UI and persisted recommendation effect (`.audit/runs/baseline/a068d27/REPORT.md`).
- [ ] Receive a bounded sprint recommendation when an important task is too large for the available time. **Status: Partially implemented.** The recommender has a short-fit reason and receives available minutes, but the rendered recommendation does not create or start a bounded sprint (`TodayDashboard.swift:208-229`; `TodayDashboardAgent.swift:61`).
- [ ] Start the recommendation immediately. **Status: Touches remaining.** A ready recommended row has a direct Begin/Start control routed to `.start`, but the installed-app action and persisted result were not exercised end to end (`TodayDashboardCommandOverview.swift:279-282,368-374`).
- [ ] Choose `Not now`. **Status: Not implemented.** The recommendation card has no Not now feedback action.
- [ ] Say the recommendation has the wrong priority. **Status: Not implemented.** No wrong-priority feedback control or persisted signal exists.
- [ ] Say the task is too large. **Status: Not implemented.** No too-large feedback action exists.
- [ ] Mark the task blocked. **Status: Partially implemented.** The task can be blocked from its row's More menu, but not directly from the recommendation card and no reason can be entered (`DashboardView.swift:660-670`).
- [ ] Mark the task already done. **Status: Partially implemented.** An active task can be completed, but a ready recommendation cannot be marked already done directly and completion implies a tracked session.
- [ ] Hide the task for today. **Status: Partially implemented.** Removing a plan entry excludes it from Today, but there is no recommendation-specific Hide for today action or durable hidden state.
- [ ] See a new recommendation after giving feedback. **Status: Partially implemented.** Starting, completing, or blocking through task commands refreshes the snapshot and recommendation, but the requested feedback controls are absent (`AppModel.swift:136-145`; `TodayDashboardAgent.swift:112-168`).
- [ ] Avoid receiving completed, cancelled, deleted, or unusably blocked tasks as recommendations. **Status: Touches remaining.** Completed and blocked states are excluded by passing recommender tests and missing Reminder IDs disappear from rows, but cancelled/deleted live-source cases were not exercised (`NextTaskRecommender`; `TodayDashboardAgentTests`).

## 16. Starting a task

- [ ] Start a task from the Today dashboard. **Status: Touches remaining.** Ready task rows and the focus recommendation issue serialized `.start` commands through the agent, return an updated snapshot, and expose clear pending, success, and failure states. The signed-QA package and deterministic agent journey pass, but the Mac was locked during independent verification, so the installed click-through remains (`AppModel.swift`; `DashboardView.swift`; `TodayDashboardCommandOverview.swift`; `TodayDashboardAgentTests`).
- [ ] Start a task from the menu bar. **Status: Not implemented.** The only menu-bar extra is Zoid Voice and it contains no active-task or task-start menu (`ZoidCoachApp.swift:51-55`).
- [ ] Start a task from a dashboard prompt. **Status: Barely started.** Prompt actions can render generically and the enum includes `startRecommendedTask`, but the prompt response effect router ignores task actions, so clicking cannot start work end to end (`PromptInbox.swift:47-64`; `PromptResponseEffectRouter.swift:43-108`).
- [ ] Start a task from the recommendation card. **Status: Touches remaining.** The recommendation card routes a ready row through `.start`, but the installed-app action and persisted result were not exercised end to end during this audit (`TodayDashboardCommandOverview.swift:279-282,368-374`).
- [ ] Start a task with a keyboard shortcut. **Status: Not implemented.** No task-start keyboard shortcut or Commands entry exists; only modal cancel shortcuts are defined.
- [ ] See the task become the single active task everywhere. **Status: Partially implemented.** Backend execution enforces one open interval and Today updates to the active row, but the menu bar does not show task state and no cross-surface live test exists (`TaskExecutionStore.swift:35-46`; `TodayDashboardAgent.swift:60-61`).
- [ ] See the previous task pause automatically when starting another task. **Status: Touches remaining.** Both Today task surfaces now show an explicit switch confirmation explaining that the current task will pause and preserve its time. The transactional command records `switchingTasks` atomically, but the signed-QA switch click-through remains because the Mac was locked (`TodayDashboardCommandOverview.swift`; `DashboardView.swift`; `TaskExecutionStoreTests`).
- [ ] Avoid seeing two active tasks after clicking twice or using two surfaces. **Status: Touches remaining.** App-wide task-command serialization disables every task action while one command is pending, while SQLite permits only one open activity interval and atomically switches tasks. Deterministic coverage passes, but multi-surface rapid-click behavior still needs installed UI automation (`AppModel.swift`; `DashboardView.swift`; `TodayDashboardCommandOverview.swift`; `TaskExecutionStore.swift`).
- [ ] See active-task status appear in the dashboard and menu bar. **Status: Partially implemented.** Dashboard rows show Active and switch commands, while the menu bar remains voice-only (`DashboardView.swift:644-659`; `ZoidCoachApp.swift:51-55`).
- [ ] Restart Zoid 666 and continue the same active session without duplicated time. **Status: Touches remaining.** Open intervals, elapsed minutes, and pause episodes persist in migration 29. Store and agent reconstruction tests prove that elapsed time survives pause, resume, switch, and restart without double counting, but the installed start-restart-clock click-through remains (`TaskExecutionStore.swift`; `TaskExecutionStoreTests`; `TodayDashboardAgentTests`).

## 17. Choosing a work commitment

- [ ] Start an open-ended work session. **Status: Touches remaining.** Starting a task opens an unbounded activity interval and persists it, but the UI never labels the commitment as open-ended (`TaskExecutionStore.swift:39-45,123-129`).
- [ ] Start a 10-minute recovery sprint. **Status: Barely started.** `startShortSprint` exists as a prompt action kind, but there is no duration model, effect routing, timer, or direct UI (`PromptInbox.swift:47-64`).
- [ ] Start a 20-minute work sprint. **Status: Not implemented.** No sprint-duration state or 20-minute action exists.
- [ ] Start a 25-minute focus sprint. **Status: Not implemented.** No sprint-duration state or 25-minute action exists.
- [ ] Enter a custom sprint duration. **Status: Not implemented.** There is no sprint input or bounded-session model.
- [ ] Start a block matching the full task estimate. **Status: Partially implemented.** Starting work and selecting an estimate both exist, but start always opens an unbounded interval and does not attach the estimate as a timer boundary.
- [ ] See elapsed time for an open-ended session. **Status: Frontend only left.** The snapshot carries `elapsedMinutes`, but current Today task rows and focus card do not render it (`TodayDashboard.swift:37-58`; `TodayDashboardCommandOverview.swift:57-105,662-748`).
- [ ] See remaining time for a bounded sprint. **Status: Not implemented.** No bounded sprint deadline or remaining-time field exists.
- [ ] Reach the end of a sprint without having the task completed automatically. **Status: Not implemented.** There is no sprint end event or bounded timer behavior.
- [ ] Continue working after a sprint ends. **Status: Not implemented.** There is no sprint lifecycle or continue action.
- [ ] Pause and later resume a bounded sprint with understandable timing. **Status: Frontend only left.** Generic task pause/resume correctly preserves elapsed interval time, but bounded duration and remaining-time semantics do not exist (`TaskExecutionStore.swift:46-49`; `TaskExecutionStoreTests`).

## 18. Active-task controls

- [ ] See the active task title and elapsed time. **Status: Touches remaining.** The focus card now presents the active task title with `MIN TRACKED`, while detailed task rows include tracked minutes and the latest pause reason. Persistence and agent reconstruction tests pass, but the installed clock progression remains unverified because the Mac was locked (`TodayDashboardCommandOverview.swift`; `DashboardView.swift`; `TaskExecutionStoreTests`).
- [ ] See sprint time remaining when applicable. **Status: Not implemented.** There is no sprint session model, countdown field, or active sprint UI. The only short-sprint artifact is a prompt action enum.
- [ ] See progress against the estimate when meaningful. **Status: Not implemented.** The UI renders the estimate and the execution store tracks elapsed minutes, but no view calculates or presents elapsed-versus-estimate progress.
- [ ] See whether the current computer context appears aligned, uncertain, or mismatched. **Status: Not implemented.** Behavior classification and telemetry coverage exist, but there is no task-context alignment state or active-task alignment UI.
- [ ] Read neutral alignment language rather than judgmental productivity labels. **Status: Barely started.** Existing copy is generally neutral, but no alignment result is generated or displayed, so the intended scenario cannot be exercised.
- [ ] Pause the task. **Status: Touches remaining.** The focus card and active task row both expose a labelled pause menu with four understandable reasons, serialize the command, persist the pause episode, and refresh the snapshot. The installed menu click-through remains because the Mac was locked (`TodayDashboardCommandOverview.swift`; `DashboardView.swift`; `TaskExecutionStoreTests`).
- [ ] Resume the task. **Status: Touches remaining.** Paused focus and task-row surfaces expose Resume, close the open pause episode, preserve prior elapsed time, and show explicit confirmation. Store-restart and agent-restart journeys pass, but installed UI acceptance remains (`AppModel.swift`; `TaskExecutionStoreTests`; `TodayDashboardAgentTests`).
- [ ] Complete the task. **Status: Touches remaining.** The live active card exposes `COMPLETE FOCUS`, and the agent records completion and enqueues an Apple Reminders completion action. The UI does not wait for or display source confirmation, and this destructive action was not performed on the user's real Reminder.
- [ ] Mark the task blocked. **Status: Touches remaining.** The focus-card pause menu and task-row overflow expose `Task is blocked`, persist an exact blocked pause reason and blocked task state, and return an updated snapshot. Contextual replanning and installed click-through proof remain (`TodayDashboardCommandOverview.swift`; `DashboardView.swift`; `TaskExecutionStore.swift`).
- [ ] Switch to another task. **Status: Touches remaining.** Both Today task surfaces present an explicit confirmation naming the selected task and explaining that tracked time will be preserved. One transaction pauses the current task with `switchingTasks` and starts the next, with store and agent restart proof; installed UI acceptance remains (`TodayDashboardCommandOverview.swift`; `DashboardView.swift`; `TaskExecutionStoreTests`; `TodayDashboardAgentTests`).
- [ ] See every active-task surface update promptly after an action. **Status: Partially implemented.** Every Today task command returns and installs a fresh snapshot, while global command serialization keeps the focus card and task rows from racing and errors preserve the last confirmed state. The voice-only menu bar still lacks task parity, and installed cross-surface proof remains (`AppModel.swift`; `DashboardView.swift`; `TodayDashboardCommandOverview.swift`).

## 19. Pausing and switching

- [ ] Pause for a break. **Status: Touches remaining.** Both active-task surfaces expose `Take a break`, persist the exact break reason in an append-only pause episode, and render the reason afterward. This is a task pause rather than a timed accepted-break session, and installed click-through remains (`TaskPauseReason`; `TaskExecutionStore.swift`; `TodayDashboardCommandOverview.swift`; `DashboardView.swift`).
- [ ] Pause because the task is blocked. **Status: Touches remaining.** The user-facing `Task is blocked` action persists a blocked reason and blocked state while retaining tracked time. Contextual replanning and installed click-through proof remain (`TaskExecutionStore.swift`; `TodayDashboardCommandOverview.swift`; `DashboardView.swift`).
- [ ] Pause while switching tasks. **Status: Touches remaining.** Starting another task now requires explicit confirmation and atomically records `switchingTasks` on the previous task while preserving time. Store and agent journeys pass; installed UI acceptance remains (`TaskExecutionStoreTests`; `TodayDashboardAgentTests`; `TodayDashboardCommandOverview.swift`).
- [ ] Pause for an external interruption. **Status: Touches remaining.** Both active-task surfaces expose `External interruption`, persist the exact reason, and render it after refresh or restart. The installed menu click-through remains because the Mac was locked (`TaskPauseReason`; `TaskExecutionStoreTests`; `DashboardView.swift`).
- [ ] Pause because the user is done for now. **Status: Touches remaining.** Both active-task surfaces expose `Done for now`, persist the exact reason, retain elapsed time, and allow later Resume or explicit Complete. Deterministic persistence passes; installed UI acceptance remains (`TaskExecutionStoreTests`; `TodayDashboardCommandOverview.swift`; `DashboardView.swift`).
- [ ] Pause when ending the workday. **Status: Touches remaining.** Both active-task surfaces expose `End the workday` and persist that exact pause reason across restart. A broader close-workday workflow and installed click-through proof remain (`TaskPauseReason`; `TaskExecutionStore.swift`; `TodayDashboardCommandOverview.swift`).
- [ ] See the selected pause reason in task history or review where relevant. **Status: Touches remaining.** Migration 29 adds append-only constrained pause episodes, and the focus card plus task rows render the current or latest reason after refresh and restart. A dedicated completed-history or review ledger remains (`AutonomousDatabaseMigrator.swift`; `TaskExecutionStore.swift`; `TodayDashboardCommandOverview.swift`; `DashboardView.swift`).
- [ ] Resume the paused task later. **Status: Touches remaining.** Paused tasks expose Resume, close the open pause episode, preserve accumulated time, and survive both store and agent reconstruction. The installed UI click-through remains (`TaskExecutionStoreTests`; `TodayDashboardAgentTests`; `DashboardView.swift`).
- [ ] Switch tasks without losing the earlier task's tracked time. **Status: Touches remaining.** Switch confirmation explains the effect before acting, and deterministic store plus agent restart tests prove the prior interval closes, its minutes remain, and only the selected task becomes active. Installed UI acceptance remains (`TaskExecutionStoreTests`; `TodayDashboardAgentTests`; `TodayDashboardCommandOverview.swift`).
- [ ] Replan after an important task becomes blocked. **Status: Not implemented.** The app can redraft a whole plan, but there is no blocked-task flow that leads into contextual replanning.

## 20. Completing and rescheduling tasks

- [ ] Complete an active task even when observed aligned time is low. **Status: Partially implemented.** Completion is not gated by behavior totals, and the live active card has a completion button. Alignment is not calculated, so the exact low-alignment condition cannot be seen or verified.
- [ ] Complete a paused task explicitly. **Status: Touches remaining.** A paused focus card exposes a separate Complete button and a paused task row exposes `Complete paused task`, preserving elapsed minutes and closing the pause episode. The deterministic agent restart journey passes, but installed click-through and Reminder source confirmation remain (`TodayDashboardCommandOverview.swift`; `DashboardView.swift`; `TaskExecutionStoreTests`; `TodayDashboardAgentTests`).
- [ ] See the task disappear from active work and appear in today's completed history. **Status: Partially implemented.** Completion removes active execution state, but the Today snapshot builds rows only from incomplete Reminder snapshots and no completed-history section is rendered.
- [ ] See the corresponding Apple Reminder become completed. **Status: Blocked from verification.** Completion enqueues `.completeReminder` and an action executor exists, but this destructive source mutation was not performed on the user's real Reminder.
- [ ] See a clear pending-sync warning if Apple Reminders rejects completion. **Status: Partially implemented.** An automatic-action ledger can show outbox state and the direct reminder path sets a generic error, but task completion returns before Apple Reminders confirmation and the active task UI does not show task-specific pending sync.
- [ ] Retry a failed completion sync. **Status: Not implemented.** No task-level retry control exists; only background outbox retry behavior is available.
- [ ] Avoid seeing a false success before Apple Reminders confirms completion. **Status: Not implemented.** `TodayDashboardAgent.apply(.complete)` immediately marks local execution completed and returns a refreshed snapshot before the queued external action is confirmed.
- [ ] Reschedule a task only after confirming the new date. **Status: Not implemented.** `.reschedule` has no date payload, confirmation sheet, date picker, or source action.
- [ ] See a clear pending-sync warning if rescheduling fails. **Status: Not implemented.** Rescheduling is only a local task execution state and task-history record.
- [ ] Keep the task and its local history when a source write fails. **Status: Partially implemented.** Local execution and task history are written before the outbox completes, but there is no end-user recovery UI and a live source-write failure was not induced.

## 21. Changes made in Apple Reminders

- [ ] See an externally completed Reminder update in Zoid 666. **Status: Partially implemented.** The agent periodically refreshes Reminder snapshots and Today rows are derived from incomplete snapshots, so the task should disappear after refresh. No live external-change E2E test or completed-history presentation was found.
- [ ] See an active externally completed task end with an understandable reason. **Status: Not implemented.** A missing Reminder drops out of the snapshot; there is no explicit external-completion reason or session closure explanation.
- [ ] See title, notes, list, due date, or priority changes made in Reminders appear after sync. **Status: Partially implemented.** Reminder snapshots carry these source fields and refresh periodically, but Today rows expose only title, due date, and priority-derived urgency. Notes are not displayed, and no live sync test was performed.
- [ ] Keep local estimates and coaching history when source-owned fields change. **Status: Partially implemented.** Estimates live in the local plan by Reminder ID and task history is local, which should survive source field changes, but a live external-field change and restart sequence was not verified.
- [ ] See an active task pause when its Reminder is deleted externally. **Status: Not implemented.** Deleted snapshots cause the row to be omitted; no deletion reconciliation pauses the open execution interval.
- [ ] Choose whether to keep a deleted Reminder as a local historical task. **Status: Not implemented.** No deleted-task decision UI or historical preservation choice exists.
- [ ] Avoid having Zoid 666 automatically rewrite Reminder titles, notes, lists, or priorities. **Status: Touches remaining.** The action system only creates/completes/reschedules supported entities and no automatic metadata rewrite path was found. This was verified statically, not through a complete external-change E2E test.
- [ ] Complete one recurring occurrence without modifying future occurrences. **Status: Blocked from verification.** Completion targets an EventKit Reminder identifier, but no recurring-occurrence test or safe live proof establishes future-instance behavior.

## 22. Work away from the Mac

- [ ] Mark a task session as work completed away from the Mac. **Status: Not implemented.** No offline-work domain type, command, or UI exists.
- [ ] Add offline work during the task session. **Status: Not implemented.** No duration entry is available from the active task.
- [x] Add offline work during end-of-day review. **Status: Fully implemented.** The signed-QA Reviews screen accepted a labeled 30-minute away-from-Mac entry and immediately displayed it in the selected day's review (`.audit/runs/offline-work/9cb54454/REPORT.md`).
- [x] See offline work included in actual task time. **Status: Fully implemented.** The signed-QA review changed Actual Time from 0 to 30 minutes and then to 45 minutes after correction, with restart preserving the corrected total (`.audit/runs/offline-work/9cb54454/REPORT.md`).
- [x] See offline work kept separate from Screenwatch-aligned time. **Status: Fully implemented.** The signed-QA coverage summary kept Screenwatch-observed at 0 minutes while Away from Mac and Actual Time changed independently, and the persisted entry retained that separation after relaunch (`.audit/runs/offline-work/9cb54454/REPORT.md`).
- [x] Correct the duration of an offline work session. **Status: Fully implemented.** The signed-QA Edit flow changed one entry from 30 to 45 minutes without duplication, and the corrected duration, task, note, and totals survived process termination and relaunch (`.audit/runs/offline-work/9cb54454/REPORT.md`).
- [x] Distinguish intentional offline work from missing telemetry. **Status: Fully implemented.** Reviews explicitly explain that missing telemetry is never invented as work, require a bounded task or note before enabling Add, preserve Screenwatch observations during scoped removal, and expose the same distinction to accessibility (`.audit/runs/offline-work/9cb54454/REPORT.md`).

## 23. Menu bar use

- [ ] See a neutral menu bar state when healthy with no active task. **Status: Not implemented.** The installed app's menu bar extra is `Zoid Voice` and reflects voice state only, not coach or task state.
- [ ] See an active state while a task or sprint is running. **Status: Not implemented.** The menu icon does not inspect active task execution, and sprint sessions do not exist.
- [ ] See a warning state when attention or source repair is needed. **Status: Not implemented.** Source health is available in the main window only.
- [ ] See a paused state while coaching is paused. **Status: Not implemented.** The voice menu symbol reflects voice transport state, not coaching pause state.
- [ ] Open Today. **Status: Not implemented.** `VoiceMenuView` has no command to show or navigate the main Today window.
- [ ] Start the recommended task. **Status: Not implemented.** The menu bar extra does not expose Today recommendations.
- [ ] Pause or resume the active task. **Status: Not implemented.** No task controls exist in `VoiceMenuView`.
- [ ] Start a break. **Status: Not implemented.** Break sessions are absent from both the model and menu.
- [ ] Pause coaching. **Status: Not implemented.** Coaching pause is available in Settings policy, not the menu bar extra.
- [ ] End the workday. **Status: Not implemented.** No end-workday command is wired.
- [ ] Open source health. **Status: Touches remaining.** The signed-QA menu-bar popover now exposes Agent Health and opens a live, repairable Background Agent window; Command-Shift-L and the application menu provide the same route, but the menu bar still does not open the complete multi-source health surface (`.audit/runs/agent-lifecycle/candidate/REPORT.md`).
- [ ] Open settings. **Status: Not implemented.** No menu-bar settings command exists.

## 24. Understanding behavior totals

- [ ] See deep work, creative work, research, communication, and administration represented as work categories. **Status: Not implemented.** The behavior model has only `work`, `gaming`, `distracting`, `idle`, and `unknown`.
- [ ] See gaming, entertainment, passive consumption, distraction, system-neutral, idle, and unknown time represented distinctly. **Status: Partially implemented.** Gaming, distraction, idle, and unknown are distinct. Entertainment, passive consumption, and system-neutral are not modeled.
- [ ] See a useful summary without needing to inspect raw five-second records. **Status: Touches remaining.** The live dashboard exposes an observed-use popover with application percentages and category totals. It does not present a complete, task-aligned behavioral summary.
- [ ] See totals update as new activity is observed. **Status: Partially implemented.** The background agent regenerates snapshots while ingesting, but `AppModel` does not poll Today snapshots while the window stays open; refresh is tied mainly to launch, foreground activation, or commands.
- [ ] Avoid seeing false minute-level precision when coverage is incomplete. **Status: Partially implemented.** Stale/no telemetry produces limited coverage and avoids filling gaps, with tests in `TodayDashboardTests`. The UI still renders integer minute totals without expressing a range or coverage proportion.
- [ ] See unknown time separately from distraction. **Status: Touches remaining.** The model and usage-category selector separate unknown and distracting time. Live app usage inspection confirms an `Unclassified` category, but no long-duration E2E correction was run.
- [ ] See idle time only when it can be observed reliably. **Status: Partially implemented.** Idle is classified only for known apps such as `screensaver` and `loginwindow`, but reliability and lock/wake transitions are not validated end to end.
- [ ] See active-task elapsed time separately from aligned time. **Status: Not implemented.** Elapsed is stored but not rendered, and aligned time is not calculated.
- [ ] See a low-coverage warning when too much of a task session is unknown. **Status: Partially implemented.** A general Screenwatch stale/no-observation warning exists, but coverage is day-level rather than task-session unknown share.
- [ ] Understand which source problem caused missing totals. **Status: Touches remaining.** The dashboard displays Screenwatch freshness details and source health repair information. The wording does not always connect a specific missing total to its cause.

## 25. Ambiguous applications and activity

- [x] See known work applications classified according to configured rules. **Status: Fully implemented.** The signed-QA Settings ledger discovered 131 installed, observed, and saved applications, exposed distinct Auto, Work, Communication, and Gaming choices, persisted an explicit rule through the agent, and restored that exact normalized rule after relaunch. Runtime tests prove that Work and Communication rules count as work while Communication remains visibly distinct (`AppClassificationLedger.swift`; `UserPolicyTests.swift`; `.audit/runs/app-classification-management/candidate/REPORT.md`).
- [x] See known games classified as gaming. **Status: Fully implemented.** The signed-QA ledger exposes Gaming for every discovered application, the visible verifier applied Gaming individually and through a confirmed filtered bulk action, and runtime tests prove configured Gaming overrides classification and budget accounting (`AppClassificationLedger.swift`; `TodayDashboardTests.swift`; `.audit/runs/app-classification-management/candidate/REPORT.md`).
- [ ] See browsers, Discord, Slack, Notion, YouTube, and Preview treated according to context rather than permanently judged. **Status: Not implemented.** Discord is always gaming, Slack always work, YouTube always distracting, and browsers/Notion/Preview generally unknown unless globally overridden. No task or window context classifier exists.
- [ ] See uncertain activity remain unknown. **Status: Touches remaining.** Unmatched applications are classified `unknown` and shown as `Unclassified`; this behavior is implemented and tested at the classifier/sessionizer level.
- [ ] Avoid a strong drift warning based only on uncertain activity. **Status: Barely started.** Unknown classification exists, but drift warning generation does not.
- [ ] Be asked for confirmation when ambiguity materially affects coaching. **Status: Not implemented.** No ambiguity-confirmation prompt generator exists.
- [ ] See a technical tutorial related to the active task treated as research or left uncertain. **Status: Not implemented.** Content/task semantic context is not used in behavior classification.
- [ ] Understand when Zoid 666 may be wrong. **Status: Partially implemented.** Limited coverage and `Unclassified` communicate some uncertainty, but there is no explanation or correction affordance adjacent to a specific questionable classification.

## 26. Correcting observed activity

- [ ] Reclassify an incorrectly categorized session. **Status: Barely started.** The user can globally classify an application, but cannot correct an individual observed session.
- [ ] Split a session that contains two different activities. **Status: Not implemented.** No session editor exists.
- [ ] Merge adjacent sessions that are really one activity. **Status: Not implemented.** No session editor exists.
- [ ] Attach a session to the correct task. **Status: Not implemented.** Behavior observations have no task attachment workflow.
- [ ] See affected totals update after correction. **Status: Barely started.** Future ingested observations can use a changed app rule, but existing observations keep their stored classification and there is no correction recalculation flow.
- [ ] See affected alignment and review statements update after correction. **Status: Not implemented.** Alignment and correction-aware review statements are absent.
- [ ] Apply a correction only once. **Status: Not implemented.** No correction record or idempotency key exists for activity corrections.
- [ ] Create a reusable rule from a correction. **Status: Barely started.** Reusable global application rules exist in Settings, but they are not created from a session correction flow.
- [ ] Apply a one-time correction without creating a rule. **Status: Not implemented.** Only persistent application-level choices exist.
- [ ] Preview exactly how broadly a proposed rule will apply. **Status: Not implemented.** Settings lists apps but provides no affected-session preview.
- [ ] Edit or remove a learned rule later. **Status: Partially implemented.** A user can change a global app classification back to `Auto`, but there is no learned-rule ledger or historical impact view.
- [ ] Ensure a user correction continues to outrank future automatic classification. **Status: Partially implemented.** Explicit work/gaming app overrides outrank built-in automatic classification, with a passing unit test. Session-level user corrections do not exist.

## 27. Grace periods and neutral activity

- [ ] Switch applications during the first three minutes after starting a task without receiving a normal drift warning. **Status: Not implemented.** No task-start grace-period or drift detector exists.
- [ ] Receive protection during the first minute after waking, unlocking, or returning from idle. **Status: Not implemented.** No wake/unlock grace policy exists for behavior coaching.
- [ ] Allow high-confidence gaming to bypass the task-start grace period when other trigger conditions are met. **Status: Not implemented.** There is no grace policy or gaming drift trigger engine.
- [ ] Use System Settings briefly without having the task marked misaligned. **Status: Not implemented.** Neutral-supporting activity and task alignment are not modeled.
- [ ] Use a password manager briefly without having the task marked misaligned. **Status: Not implemented.** Neutral-supporting activity and task alignment are not modeled.
- [ ] Use file dialogs, downloads, or short communication checks as neutral supporting activity. **Status: Not implemented.** The classifier works from application name only and has no neutral-supporting state.
- [ ] Avoid having neutral activity automatically pause the task. **Status: Barely started.** No behavior currently auto-pauses tasks at all, so the harmful behavior does not occur, but the intended neutral-activity policy is absent.

## 28. Taking breaks

- [ ] Start an accepted break from the dashboard. **Status: Not implemented.** No dashboard break control or break state exists.
- [ ] Start an accepted break from the menu bar. **Status: Not implemented.** The menu bar extra is voice-only.
- [ ] Start an accepted break from a coach prompt. **Status: Barely started.** `PromptActionKind.startBreak` exists, but no coaching prompt generator or response effect implements it.
- [ ] Choose or understand the expected break duration. **Status: Not implemented.** Break duration is not modeled.
- [ ] Avoid receiving drift prompts during an accepted break. **Status: Not implemented.** Neither accepted breaks nor drift prompts are implemented.
- [ ] Receive a break-end reminder. **Status: Not implemented.** No break timer or notification exists.
- [ ] End the break early. **Status: Not implemented.** No break state exists to end.
- [ ] Resume work after the break. **Status: Not implemented.** No break-to-task transition exists.
- [ ] See break activity without having it described as failure or drift. **Status: Not implemented.** Break activity and drift interpretation are absent.

## 29. Gaming policy setup

- [ ] Observe gaming without applying a budget. **Status: Not implemented.** Gaming is always evaluated against a `GamingPolicy` with a default 60-minute budget; there is no disabled-budget mode.
- [ ] Set a daily gaming budget. **Status: Frontend only left.** `GamingPolicy.dailyBudgetMinutes` exists, but it is not part of `UserPolicy`, Settings, or persistence and the agent uses its initializer default.
- [ ] Unlock gaming after selected priority tasks are completed. **Status: Partially implemented.** Completing the main objective can apply a one-time reward, but the user cannot select unlock tasks or configure the condition.
- [ ] Earn gaming time from aligned focus time. **Status: Not implemented.** Rewards are completion-based only; aligned focus time is not calculated.
- [ ] Combine a base budget, task unlock, and focus-time rewards. **Status: Not implemented.** Only base budget plus a fixed one-time priority reward exists.
- [ ] Choose which applications count as gaming. **Status: Touches remaining.** Settings provides per-app Gaming classification and persists it in `BehaviorPolicy`. There is no context-sensitive rule or current-session preview.
- [ ] Decide whether Discord or Twitch count only in a gaming context. **Status: Not implemented.** Rules are global by application name; Discord is built-in gaming and Twitch is not context aware.
- [ ] Set the base available minutes. **Status: Frontend only left.** The core policy supports a numeric base budget, but no Settings control or policy-store field exposes it.
- [ ] Set the unlock tasks or focus-time rule. **Status: Not implemented.** Unlock selection and focus ratios are not modeled.
- [ ] Set the daily maximum during work hours. **Status: Not implemented.** No separate work-hours maximum exists.
- [ ] Choose whether early gaming creates same-day debt. **Status: Not implemented.** Debt is not modeled.
- [ ] Choose whether debt carries into another day. **Status: Not implemented.** Debt is not modeled.
- [ ] Set the intentional-override cooldown. **Status: Not implemented.** There is no intentional gaming override policy engine.
- [ ] Configure different weekend or after-work behavior. **Status: Not implemented.** Work windows exist, but gaming policy has no weekday or after-work variants.

## 30. Gaming budget use

- [ ] See available, earned, used, locked, and debt minutes. **Status: Partially implemented.** The live dashboard shows only unlocked remaining minutes and a next-unlock reason. The model has budget and used minutes, but no earned, locked, or debt breakdown and the UI does not render used.
- [ ] See the next unlock condition. **Status: Touches remaining.** The live dashboard shows `Finish one priority task to unlock a one-time reward.` The condition is fixed rather than user configured.
- [ ] See gaming time accumulate from confidently detected gaming sessions. **Status: Touches remaining.** Screenwatch observations classified as gaming feed `GamingStatus.usedMinutes`, and unit tests verify it. The live UI only indirectly shows remaining allowance, and no confidence threshold beyond app classification exists.
- [ ] Avoid counting a brief game-launcher transition as meaningful gaming. **Status: Not implemented.** Every contiguous classified observation up to the sessionizer cap contributes time; there is no minimum-session threshold.
- [ ] See gaming unlock after the configured task condition is satisfied. **Status: Partially implemented.** Completing the main objective records a fixed priority reward, but selected conditions are not configurable and live source completion was not tested.
- [ ] See gaming time earned after the required aligned work. **Status: Not implemented.** There is no aligned-work reward calculation.
- [ ] Stop earning automatic time at the configured daily maximum. **Status: Not implemented.** No focus-time earning or configurable maximum exists.
- [ ] See same-day debt after gaming before unlock when debt is enabled. **Status: Not implemented.** Debt is absent.
- [ ] Start the next day without carried debt by default. **Status: Not implemented.** Debt is absent, so the intended policy cannot be configured or reviewed.
- [ ] Carry debt only when explicitly configured. **Status: Not implemented.** Debt is absent.
- [ ] Add or remove gaming time manually. **Status: Not implemented.** No manual adjustment action or ledger exists.
- [ ] See manual adjustments separately from automatically earned rewards. **Status: Not implemented.** No adjustment ledger exists.

## 31. Gaming drift detection

- [ ] Game for less than ten minutes without receiving the default drift prompt. **Status: Not implemented.** No gaming drift detector or ten-minute threshold exists.
- [ ] Game for at least ten minutes with incomplete priority work and become eligible for a prompt. **Status: Not implemented.** Gaming totals and incomplete tasks coexist in the snapshot, but no trigger combines them into a prompt.
- [ ] Avoid receiving a prompt when all applicable unlock conditions are satisfied. **Status: Not implemented.** No gaming coaching prompt generator exists.
- [ ] Avoid receiving a prompt while on an accepted break. **Status: Not implemented.** Breaks and gaming coaching prompts are absent.
- [ ] Avoid receiving a prompt while coaching is paused. **Status: Not implemented.** User policy has an automation pause, but there is no gaming prompt engine for it to gate.
- [ ] Avoid receiving a prompt outside the configured work window. **Status: Not implemented.** Work windows exist, but no gaming drift trigger evaluates them.
- [ ] Avoid receiving a prompt after the workday is closed. **Status: Not implemented.** Workday closure is not modeled.
- [ ] Avoid receiving a prompt when the gaming classification is uncertain. **Status: Not implemented.** Unknown classification exists, but there is no prompt eligibility policy.
- [ ] Avoid receiving repeated prompts for the same continuing gaming session. **Status: Barely started.** `PromptInboxStore` deduplicates unresolved episodes by decision key, but no gaming-session prompt producer supplies such episodes or cooldowns.
- [ ] Correct an application rule and stop future false gaming alerts for that context. **Status: Barely started.** App rules can be changed, but alerts are not implemented and rules are global rather than contextual.

## 32. First-week observation mode

- [ ] Use the app for the first seven complete days without behavior-triggered interruptions. **Status: Not implemented.** No installation-day baseline counter or seven-day gate exists. The absence of behavior prompts is due to missing coaching implementation, not observation mode.
- [ ] See that eligible drift is being observed during the baseline. **Status: Not implemented.** Drift eligibility is not calculated or shown.
- [ ] Understand why accountability prompts are not active yet. **Status: Not implemented.** There is no baseline explanation UI.
- [ ] Complete the baseline week and see coaching progress to the configured level. **Status: Not implemented.** No baseline state transition exists.
- [ ] Keep stronger coaching disabled if the baseline is incomplete. **Status: Not implemented.** Coaching levels and baseline completeness are not connected.
- [ ] Use baseline results to review work capacity, gaming patterns, and alert sensitivity. **Status: Not implemented.** There is no baseline report or alert-sensitivity review.

## 33. Receiving a coaching prompt

- [ ] Receive a gentle nudge offering an easy return to work. **Status: Barely started.** A generic prompt inbox and notification framework exists, but the agent generates only plan, meeting, and wake prompts, not drift nudges.
- [ ] Receive an accountability prompt asking whether gaming is intentional. **Status: Barely started.** The `continueIntentionally` action enum exists, but no gaming accountability prompt is generated.
- [ ] See the observed fact before the coach's interpretation. **Status: Not implemented.** No coaching prompt content builder or fact/interpretation structure exists.
- [ ] See the relevant unfinished task named. **Status: Not implemented.** Coaching prompt generation is absent.
- [ ] See one clear primary action. **Status: Partially implemented.** Generic `PromptActionRole.primary` is rendered with primary styling in the dashboard. No coaching prompt currently uses this flow.
- [ ] See no more than three secondary actions. **Status: Not implemented.** The generic prompt UI renders every supplied action with no secondary-action cap.
- [ ] See reliable elapsed time when included. **Status: Not implemented.** Coaching prompts are absent and active elapsed time is not displayed elsewhere.
- [ ] See uncertainty acknowledged when context is ambiguous. **Status: Not implemented.** No ambiguity-aware coaching prompt builder exists.
- [ ] Avoid guilt, insults, moral labels, disappointment, or exaggerated claims. **Status: Barely started.** Existing plan/meeting copy is neutral, but there is no coaching copy pipeline to verify against this requirement.
- [ ] Avoid being told what the user's intent must be. **Status: Barely started.** Existing copy does not assert intent, but the intended coaching prompts do not exist.
- [ ] Find the same unresolved prompt in the dashboard if the initial surface disappears. **Status: Partially implemented.** `PromptInboxStore.unresolved()` and the live `DECISIONS` dashboard prove shared persistence for plan and meeting prompts across notification and dashboard surfaces, but coaching prompts are not generated and a live notification-disappearance sequence was not exercised.

## 34. Responding to coaching

- [ ] Start the recommended task. **Status: Barely started.** The action enum and generic prompt button exist, but `PromptResponseEffectRouter` has no effect for `startRecommendedTask`; clicking would only resolve the prompt.
- [ ] Start a 10-minute recovery sprint. **Status: Barely started.** `startShortSprint` exists as one undifferentiated enum value, but no 10-minute session or routed task effect exists.
- [ ] Start a 20-minute work sprint. **Status: Not implemented.** There is no distinct 20-minute action, duration payload, timer, or execution effect.
- [ ] Return to the current active task. **Status: Barely started.** `returnToActiveTask` exists as an enum, but no response effect resumes or foregrounds the task.
- [ ] Choose `Five more minutes`. **Status: Barely started.** `fiveMoreMinutes` exists as an enum, but no coaching prompt currently offers it and no snooze is scheduled.
- [ ] Receive one follow-up when the five-minute snooze ends. **Status: Not implemented.** There is no snooze store, timer, cooldown, or follow-up producer.
- [ ] Start an accepted break. **Status: Barely started.** `startBreak` exists as an enum, but no break state or effect is wired.
- [ ] Choose `Continue intentionally`. **Status: Barely started.** `continueIntentionally` exists as an enum, but no gaming prompt or override effect exists.
- [ ] Pause the task. **Status: Barely started.** `pauseTask` exists as a prompt action and task pause exists separately, but the response router does not connect them.
- [ ] Reschedule the task. **Status: Barely started.** `rescheduleTask` exists as a prompt action and local execution state, but no date confirmation, Reminder mutation, or response effect exists.
- [ ] Mark the task blocked. **Status: Barely started.** `markBlocked` exists as a prompt action and `.block` exists in task execution, but no router connects them and no block reason is captured.
- [ ] End the workday. **Status: Barely started.** `endWorkday` exists as an enum only; no day-closure effect exists.
- [ ] Ignore or dismiss the prompt. **Status: Partially implemented.** `ignore` is fully routed for meeting prompts and the prompt store supports dismissal state, but generic coaching prompt dismissal is not exposed consistently in the dashboard.
- [ ] Avoid having the same action happen twice after clicking more than once. **Status: Touches remaining.** `PromptInboxTests` and `PromptResponseEffectRouterTests` prove idempotent response tokens and exactly-once meeting effects across repeated delivery. Coaching actions have no effects to protect yet, and no live double-click UI test was performed.
- [ ] See a refreshed state instead of applying an action from an outdated prompt. **Status: Partially implemented.** A resolved prompt is removed after the XPC response and prompt state transitions reject invalid repeats. There is no coaching-specific stale-state validation against a changed active task or gaming session.

## 35. Prompt frequency and escalation

- [ ] Receive no more than six behavior interventions during a default workday. **Status: Not implemented.** No behavior-intervention producer or daily behavior-cap policy exists; `AgentMain` only creates plan-ready, plan-changed, and meeting prompts.
- [ ] Avoid having estimate requests and source warnings counted against the behavior cap. **Status: Not implemented.** There is no behavior-cap ledger or prompt-type accounting to distinguish these cases.
- [ ] Receive no duplicate prompt during its cooldown. **Status: Barely started.** `PromptInboxStore` deduplicates one unresolved `decisionKey`, but there is no behavior cooldown model, expiry policy, or end-user behavior-prompt flow.
- [ ] Receive a 15-minute pause after a gentle nudge. **Status: Not implemented.** No gentle-nudge prompt or 15-minute suppression state exists.
- [ ] Receive a 20-minute pause after answering an accountability prompt. **Status: Not implemented.** No accountability-prompt producer or response-specific suppression timer exists.
- [ ] Receive the selected snooze duration after choosing a snooze. **Status: Not implemented.** `PromptActionKind` has no snooze action or duration payload.
- [ ] Receive a 45-minute same-behavior pause after an intentional override. **Status: Not implemented.** `continueIntentionally` is only an unused action enum; no override window is stored or enforced.
- [ ] Receive no more prompts that day after choosing `I am done today`. **Status: Barely started.** `endWorkday` exists as an action enum, but it is not surfaced, routed, or persisted as a day-level prompt stop.
- [ ] See later drift recorded quietly after reaching the prompt cap. **Status: Not implemented.** There is no prompt-cap state and no quiet post-cap drift ledger.
- [ ] See quietly recorded drift summarized only during review. **Status: Not implemented.** The Reviews navigation item renders the generic source-health foundation view, not a drift review.
- [ ] See coaching return to observation after aligned work resumes. **Status: Not implemented.** `CoachingState` is display-only and no behavior episode state machine returns it to observation.
- [ ] See coaching de-escalate after starting a break, pausing work, rescheduling, or ending the day. **Status: Not implemented.** Task commands exist, but they are not connected to behavior-coaching escalation state.

## 36. Intentional gaming

- [ ] Choose to continue gaming intentionally. **Status: Barely started.** `PromptActionKind.continueIntentionally` exists, but no generated prompt or visible button uses it.
- [ ] See the current prompt close immediately. **Status: Barely started.** Generic prompt responses close a prompt atomically, but the intentional-gaming prompt is never created and the action has no effect router.
- [ ] Avoid another equivalent prompt during the override window. **Status: Not implemented.** No intentional-override window is persisted or checked.
- [ ] Continue seeing gaming time tracked. **Status: Partially implemented.** Screenwatch observations are classified and the Today dashboard shows gaming usage, but this was not exercised through an intentional-override journey.
- [ ] See incomplete priority work remain visible without moral judgment. **Status: Partially implemented.** Planned and incomplete tasks remain visible in Today with neutral state labels, but there is no intentional-gaming context tying the behavior to that presentation.
- [ ] See the intentional choice recorded factually in the review. **Status: Not implemented.** There is no daily review UI or intentional-choice review record.
- [ ] Return to work before the override ends. **Status: Not implemented.** Work observations can be tracked, but there is no override lifecycle to end early.
- [ ] Receive normal coaching again after the override expires if conditions still apply. **Status: Not implemented.** Neither override expiry nor normal behavior coaching is implemented.

## 37. Dashboard active-task status

- [ ] See the active task in the Today dashboard. **Status: Touches remaining.** `TodayDashboardCommandOverview` selects `snapshot.activeTask` and the installed app visibly renders the current active commitment, but this audit did not start a controlled task and prove the full persisted transition.
- [ ] See elapsed time for an open-ended task. **Status: Frontend only left.** `TodayTaskRow.elapsedMinutes` and `TaskExecutionStore.elapsedMinutes` are implemented and tested, but the current Today UI never renders elapsed minutes.
- [ ] See remaining time for a sprint. **Status: Not implemented.** There is no sprint execution mode, countdown, or remaining-time field in the active-task model or UI.
- [ ] See estimate or meaningful progress where appropriate. **Status: Partially implemented.** Estimates are editable and visible, and elapsed minutes are stored, but progress/elapsed information is not presented to the user.
- [ ] See the dashboard update when pausing, resuming, switching, or completing a task. **Status: Touches remaining.** All commands are wired through `AppModel.applyTaskCommand`, snapshot refreshes, and passing tests cover transitions and switching, but a complete installed-app lifecycle journey was not performed.
- [ ] Use the compact active-task view without losing essential task state. **Status: Not implemented.** The menu-bar surface is only `Zoid Voice`; there is no compact active-task view.
- [ ] Open the full dashboard for totals, gaming budget, coaching state, and primary actions. **Status: Partially implemented.** The full Today dashboard shows behavior totals, gaming budget, and task actions, but behavior-coaching state and intervention controls are absent.
- [ ] See the task activity disappear when no useful active state remains. **Status: Touches remaining.** Snapshot state removes `activeTask` after completion and tests verify completion refresh; installed UI cleanup was not verified end to end.
- [ ] Avoid distracting updates more often than necessary. **Status: Partially implemented.** The UI refreshes after explicit commands rather than on a rapid visual timer, but there is no usability test or explicit update-throttling contract.

## 38. Prompt fallback surfaces

- [ ] Receive a macOS notification when notification permission is available. **Status: Partially implemented.** `PromptNotificationCoordinator` schedules authorized plan, meeting, and plan-change notifications, but behavior prompts are not produced and live delivery was not exercised.
- [ ] See a menu bar badge if notifications are unavailable. **Status: Not implemented.** No prompt badge exists in `MenuBarExtra` or another menu-bar surface.
- [ ] Find every unresolved prompt in the dashboard. **Status: Touches remaining.** `PromptInboxLedger` displays the shared unresolved prompt store and explains the shared surface; persistence tests pass, but the installed app had no healthy live prompt journey to verify.
- [ ] Respond from any available surface. **Status: Touches remaining.** The signed canonical prompt was independently resolved from both the notification action and Today dashboard through the same durable XPC store, but unrelated behavior action kinds and the absent menu-bar prompt surface still need completion (`PromptNotificationCoordinator.swift`; `TodayDashboardXPC.swift`; `.audit/runs/onboarding-test-prompt/signed-acceptance/REPORT.md`).
- [ ] See all other surfaces update after responding once. **Status: Partially implemented.** The shared store is atomic, but there is no demonstrated notification withdrawal or menu-bar synchronization after a dashboard response.
- [ ] Avoid having two surfaces start duplicate sprints or apply the same choice twice. **Status: Touches remaining.** Response tokens and `PromptInboxStore.respond` are idempotent and concurrency tests pass; sprint effects themselves are not implemented and no multi-surface UI test exists.
- [ ] See only the latest relevant notification when delivery is throttled. **Status: Not implemented.** Notifications use prompt-specific identifiers, but there is no relevance/throttling policy that cancels older decisions.
- [ ] Continue using all task controls without notifications. **Status: Touches remaining.** Today task controls do not depend on notification authorization and are covered by task-store/dashboard tests; the live denied-permission journey was not run.

## 39. Pausing coaching

- [ ] Pause coaching for one hour. **Status: Not implemented.** Settings only supports an indefinite automation pause.
- [ ] Pause coaching until tomorrow. **Status: Not implemented.** `AutomationPause` has no until-tomorrow state or expiry.
- [ ] Resume coaching before the pause expires. **Status: Partially implemented.** The user can resume an indefinite automation pause and that immediate save is tested, but timed coaching pauses do not exist.
- [ ] See clearly that coaching is paused. **Status: Touches remaining.** Settings shows `PAUSED`, and source-health headers expose `CoachingState.paused`; this was visible in code/accessibility structure but not exercised as a live state change.
- [ ] Continue tracking tasks and behavior while coaching prompts are paused. **Status: Partially implemented.** Task and Screenwatch pipelines are separate from the saved automation-pause flag, but there is no end-to-end test proving ingestion continues throughout a pause.
- [ ] Avoid receiving behavior interventions during the pause. **Status: Not implemented.** Behavior interventions are not implemented, and no pause-specific suppression policy exists.
- [ ] End the workday from the pause controls. **Status: Not implemented.** The Settings pause card only pauses/resumes all automation; it has no end-workday control.
- [ ] Disable notification prompts while retaining dashboard access. **Status: Not implemented.** There is no notification-prompt preference independent of dashboard access.
- [ ] Stop Screenwatch ingestion without deleting existing data. **Status: Not implemented.** Capture mode can switch pipelines, but there is no user-facing stop-ingestion switch.

## 40. End-of-day review trigger

- [ ] Open the review at the configured review time. **Status: Not implemented.** Settings has nightly planning and morning confirmation times, but no review time or review UI.
- [ ] Open the review immediately after ending the workday manually. **Status: Not implemented.** There is no manual end-workday flow or daily review screen.
- [ ] Find an unfinished previous-day review on the next launch. **Status: Not implemented.** No review draft/persistence lifecycle exists.
- [ ] Delay the review without losing the day's evidence. **Status: Not implemented.** Evidence persists independently, but there is no delay-review action or review state.
- [ ] Resume an unfinished review after restarting the app. **Status: Not implemented.** No unfinished-review record exists.
- [ ] Skip the review explicitly and close the day. **Status: Not implemented.** No skip-review or close-day action exists.

## 41. Understanding the daily review

- [ ] See whether the main objective was completed. **Status: Barely started.** Main-objective and task-completion data exist in daily-plan/task stores, but there is no daily review aggregator or UI.
- [ ] See how many priority tasks were completed. **Status: Barely started.** Task states and priorities exist, but no review count is computed or displayed.
- [ ] See total active-task time. **Status: Barely started.** Task intervals and elapsed minutes are stored, but no day-level review total is produced.
- [ ] See aligned work time separately. **Status: Barely started.** Work-classified Screenwatch time appears in Today, but it is not reconciled with tasks in a review.
- [ ] See work broken down by category. **Status: Barely started.** Today can group application observations by classification, but no review categories or historical review presentation exist.
- [ ] See gaming and distraction time. **Status: Barely started.** Today stores and displays these totals, but the Reviews surface is a placeholder.
- [ ] See reliable idle time. **Status: Barely started.** Idle observations are summarized in the core, but not presented as a review with reliability context.
- [ ] See unknown or missing coverage. **Status: Barely started.** Today exposes limited coverage and unknown time, but no daily-review view exists.
- [ ] See the best work block. **Status: Not implemented.** No best-block calculation or review presentation was found.
- [ ] See the largest drift episode. **Status: Not implemented.** No drift-episode review calculation exists.
- [ ] See coaching prompts and responses. **Status: Not implemented.** Prompt records exist for plans/meetings, but no review presentation and no behavior coaching records exist.
- [ ] See intentional gaming overrides. **Status: Not implemented.** Overrides are not stored.
- [ ] See estimate-versus-actual comparisons. **Status: Barely started.** Estimate-learning aggregates store estimate/actual samples, but no user review display exists.
- [ ] Understand when incomplete data makes a total less precise. **Status: Partially implemented.** Today labels limited Screenwatch coverage, but the absent review cannot qualify each review total.
- [ ] Receive a complete factual review without AI. **Status: Not implemented.** Rules-only planning exists, but no factual daily-review generator exists.

## 42. Facts, hypotheses, and review corrections

- [ ] See observed facts labeled separately from context and hypotheses. **Status: Not implemented.** No review model or facts/hypotheses UI exists.
- [ ] See evidence supporting a causal hypothesis. **Status: Not implemented.** No causal-hypothesis generator or evidence view exists.
- [ ] Reject a causal hypothesis. **Status: Not implemented.** No hypothesis correction action exists.
- [ ] Reclassify a behavior session from the review. **Status: Not implemented.** App classification affects future observations only; session-level review correction is absent.
- [ ] Split or merge a session from the review when needed. **Status: Not implemented.** There is no session editor.
- [ ] Add away-from-Mac work. **Status: Not implemented.** No manual activity-entry flow exists.
- [ ] Correct a task's completion state. **Status: Not implemented.** Today can complete a task, but there is no review correction or reopen operation.
- [ ] Add a personal note. **Status: Not implemented.** No review-note field or storage exists.
- [ ] Change tomorrow's main task. **Status: Partially implemented.** A user can choose the main objective for the current daily plan, but there is no tomorrow/review-specific flow.
- [ ] See totals and conclusions update after corrections. **Status: Not implemented.** Review corrections and conclusions do not exist.
- [ ] Confirm the corrected review. **Status: Not implemented.** There is no review confirmation state.
- [ ] Prevent unconfirmed hypotheses from becoming learned facts. **Status: Not implemented.** Learning aggregates have evidence/confidence safeguards, but no hypothesis-confirmation boundary exists.

## 43. Weekly review

- [x] Receive a weekly review after at least three days with acceptable coverage. **Status: Fully implemented.** The signed QA Reviews surface visibly changed from a 0/7 limited state to a factual 7/7 prior-week review after seven confirmed days with at least 30 observed minutes, while focused tests enforce the three-day gate (`WeeklyReviewStore.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).
- [x] Receive a data-quality summary instead of strong conclusions when evidence is insufficient. **Status: Fully implemented.** The clean signed QA app visibly showed `DATA QUALITY SUMMARY 0/7 DAYS`, the exact missing-day guidance, no patterns, and no experiment before sufficient evidence was seeded (`WeeklyReviewView.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).
- [x] See completed outcomes and planned-versus-completed work. **Status: Fully implemented.** The signed review visibly reported 14 planned items, 525 estimated minutes, 5 completed items, and a 36 percent outcome rate explicitly labelled as not being a productivity score (`WeeklyReviewStore.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).
- [x] See estimate accuracy patterns. **Status: Fully implemented.** The signed review derived estimate accuracy only from eligible prior-week learning samples and visibly expanded three dated estimated-versus-corrected examples (`WeeklyReviewStore.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).
- [x] See the best work windows. **Status: Fully implemented.** The signed review visibly reported the median corrected aligned start time and duration from five eligible prior-week work-window samples, with dated evidence available on demand (`WeeklyReviewStore.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).
- [x] See frequent drift triggers. **Status: Fully implemented.** The signed review visibly identified the strongest corrected distracting or gaming application pattern with sample count, confidence, date range, and expandable evidence (`WeeklyReviewStore.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).
- [x] See gaming timing and budget adherence. **Status: Fully implemented.** The signed review visibly reported six corrected gaming-day samples against the configured 60-minute budget, and each expandable example includes corrected minutes and first observed local time (`WeeklyReviewStore.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).
- [x] See recovery success after coaching prompts. **Status: Fully implemented.** The signed review visibly reported that 1 of 1 answered prompts was followed by correction-aware observed work within 30 minutes and preserved a non-causal alternative explanation (`WeeklyReviewStore.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).
- [x] See which prompts were useful or ineffective. **Status: Fully implemented.** The canonical response-effect relation now drives the signed prompt follow-through pattern, which visibly reported 1 of 1 applied actions without mistaking correlation for behavioral proof (`WeeklyReviewStore.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).
- [x] See repeated blocked or vague tasks. **Status: Fully implemented.** The signed review visibly reported a repeatedly blocked task from two prior-week events and expandable evidence uses the local task title rather than an opaque identifier (`WeeklyReviewStore.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).
- [x] See sample size, date range, examples, confidence, and alternative explanations for every pattern. **Status: Fully implemented.** Every signed pattern visibly exposed sample count, stable prior-week date range, confidence, an evidence control, privacy-safe dated examples, and an alternative explanation; the estimate pattern was expanded in the installed app (`WeeklyReview.swift`; `WeeklyReviewView.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).
- [x] Receive no more than one primary behavioral experiment for the next week. **Status: Fully implemented.** Migration 31 enforces one experiment per review week and repeated loads preserve the same proposal; the signed review visibly showed exactly one primary experiment (`AutonomousDatabaseMigrator.swift`; `WeeklyReviewStore.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).
- [x] Accept the experiment. **Status: Fully implemented.** The installed signed app accepted the edited proposal, visibly changed it to `ACCEPTED`, displayed 2/7 next-week tracking, and preserved that state after relaunch (`WeeklyReviewView.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).
- [x] Edit the experiment. **Status: Fully implemented.** The installed signed app changed the proposal title to `Make the first blocked step concrete`, saved it, showed success feedback, and preserved the edited text through acceptance and relaunch (`WeeklyReviewView.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).
- [x] Reject the experiment. **Status: Fully implemented.** The installed signed app changed the accepted experiment to `REJECTED`, removed active tracking, disabled the repeated reject action, and preserved rejection after another relaunch (`WeeklyReviewView.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).
- [x] Track an accepted experiment during the following week. **Status: Fully implemented.** The installed signed app visibly showed `TRACKING 2/7 DAYS · START 2026-07-11` after acceptance and again after relaunch, proving durable next-week progress from the stable prior-week review (`WeeklyReviewStore.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).

## 44. General settings

- [ ] Enable or disable launch at login. **Status: Not implemented.** The app auto-registers the bundled agent on launch; `disableAndInspect` exists in the service but no settings control calls it.
- [ ] Set workday start and end times. **Status: Touches remaining.** Both controls persist through versioned policy and settings tests pass, including two-controller conflict recovery that preserves the current winner, rebases independent edits, and avoids duplicate policy versions. A visible signed-app save and relaunch check remains.
- [ ] Set planning and review times. **Status: Partially implemented.** Nightly planning and morning confirmation are configurable and now participate in field-level conflict recovery, but review time is absent.
- [ ] Use manual workday start and end without fixed hours. **Status: Not implemented.** No manual-workday mode or start/end controls exist.
- [ ] Configure time-zone behavior. **Status: Not implemented.** Policy preserves the existing time zone and the UI only states the current zone; it cannot be configured.
- [ ] Configure keyboard shortcuts. **Status: Partially implemented.** Voice hotkey presets are configurable in the Voice section, but there is no general shortcut configuration for task and coaching actions.
- [ ] See current permission and connection states. **Status: Touches remaining.** The installed signed-QA Settings journey now proves passive Ready to Connect, Connected, Access Needed, Refresh Failed, retry recovery, and durable last-success states for Reminders without opening a permission prompt. Source health and macOS permission ledgers also expose Calendar, notifications, agent, Screenwatch, Accessibility, Automation, and screen recording, but several non-Reminders statuses remain coarse (`.audit/runs/reminders-recovery/verifier/REPORT.md`).
- [ ] Change included Reminder lists. **Status: Touches remaining.** Settings now exposes permission state, System Settings repair, in-place recheck, discovery retry, explicit local-only configuration, deleted-list notices, and stable-ID Include or Exclude controls. Saves use CAS rebasing, preserve concurrent unrelated settings, expose explicit Keep Current Values and Reapply My Changes decisions for overlapping edits, and refresh visible tasks exactly once. Deterministic signed-QA restart, rename, stale-writer rejection, and duplicate-free retry proof passes, while the Settings conflict click-through remains unperformed.
- [ ] Change the Screenwatch folder. **Status: Touches remaining.** Onboarding and Settings now expose native folder selection backed by one canonical private security-scoped bookmark, and app, agent, and OCR consumers resolve the same source. Unsafe, stale, symlinked, and cross-QA paths fail closed in tests; native picker completion remains unverified (`ScreenwatchSourceRepositoryTests.swift`).
- [ ] Test Screenwatch health. **Status: Touches remaining.** Source Check and Screenwatch Refresh inspect schema-valid, stale, and missing streams with passing reader tests. One post-recovery verifier run confirmed fresh ingestion, while the later recheck correctly failed when Screenwatch became stale; the UI test action itself was not exercised.
- [ ] See notification authorization and delivery state. **Status: Partially implemented.** Authorization is shown; last delivery result is not stored or displayed.
- [ ] Send a test notification. **Status: Touches remaining.** Onboarding now exposes a bounded local delivery test and records whether macOS or the isolated QA fixture accepted and delivered it; the visible run has not reached this step (`OnboardingDeliveryTestService.swift`; `QAFixtureOSCompositionTests.swift`).
- [ ] See notification authorization status. **Status: Touches remaining.** `NotificationService.inspect` maps macOS authorization into Source Health; runtime accessibility confirmed the Source health surface, though denial repair is incomplete.

## 45. Coaching and classification settings

- [ ] Choose the coaching mode. **Status: Partially implemented.** Observe, Suggest, Approve actions, and Autonomous operating modes exist and now participate in conflict-safe Settings saves, but these control automation authority rather than behavior-coaching style.
- [ ] Choose the maximum intervention level. **Status: Not implemented.** Only a wake-intervention daily maximum exists; no coaching escalation ceiling exists.
- [ ] Change the daily prompt cap. **Status: Not implemented.** No behavior prompt-cap setting exists.
- [ ] Change quiet hours. **Status: Touches remaining.** Quiet start/end controls persist in the versioned schedule policy and now survive disjoint concurrent Settings edits without overwriting a newer value. Enforcement is present for scheduled wake behavior, but a complete behavior-prompt journey cannot be tested because behavior prompts are absent.
- [ ] Change cooldowns. **Status: Not implemented.** No cooldown controls or policy fields exist.
- [ ] Change the task-start grace period. **Status: Not implemented.** No grace-period setting exists.
- [ ] Change the default coaching-pause duration. **Status: Not implemented.** Only an indefinite pause exists.
- [x] Review application rules. **Status: Fully implemented.** The signed-QA Settings ledger loaded 131 installed, observed, and saved applications with search plus All, Auto, Work, Communication, and Gaming filters. The visible verifier searched Discord, changed its distinct category, saved through the agent, killed and relaunched the app, and saw policy V3 with Communication still selected (`AppClassificationLedger.swift`; `.audit/runs/app-classification-management/candidate/REPORT.md`).
- [ ] Review domain rules. **Status: Not implemented.** URL/domain classification rules are not exposed or modeled.
- [ ] Review project mappings. **Status: Not implemented.** No project-mapping model or UI exists.
- [ ] Review unknown sessions. **Status: Not implemented.** Unknown time can appear in totals, but there is no session review queue.
- [ ] Enable or disable screenshot analysis. **Status: Touches remaining.** A persisted Screenwatch screenshot-analysis toggle exists, participates in field-level conflict recovery, and has persistence coverage. Live agent behavior after toggling was not verified.
- [x] Import classification rules. **Status: Fully implemented.** The signed-QA native chooser accepted a reviewed JSON replacement only after previewing one Work, one Communication, and one Gaming rule and requiring destructive confirmation. Focused tests reject wrong types, folders, symlinks, oversized data, malformed documents, unsupported schemas, blanks, duplicates, and cross-category conflicts before draft mutation (`AppClassificationRulesDocumentService.swift`; `AppClassificationRulesDocumentServiceTests.swift`; `.audit/runs/app-classification-management/candidate/REPORT.md`).
- [x] Export classification rules. **Status: Fully implemented.** The signed-QA native destination chooser exported the visible draft, and inspection confirmed a normalized schema-only JSON document containing no unrelated settings or secrets. Atomic writing and symlink-destination rejection are covered by focused tests (`AppClassificationRulesDocumentService.swift`; `AppClassificationRulesDocumentServiceTests.swift`; `.audit/runs/app-classification-management/candidate/REPORT.md`).
- [ ] Reset learned rules. **Status: Not implemented.** Policy rollback exists, but there is no targeted learned-rule reset.

## 46. AI settings and behavior

- [ ] Use rules-only mode with all Release 1 functionality available. **Status: Partially implemented.** Disabled-AI/local-only mode preserves deterministic planning and task controls, but daily/weekly reviews, coaching, and many Release 1 scenarios are missing.
- [ ] See that remote AI is off until explicitly configured. **Status: Touches remaining.** Defaults select Disabled and Local only, remote evidence is disabled for local providers, and policy plus conflict tests preserve a newer remote-evidence winner. The installed settings state and an offline relaunch were not verified end to end.
- [ ] Choose a future approved provider and model. **Status: Touches remaining.** Settings exposes Disabled, local Ollama, and Codex CLI according to capability gates, plus model/reasoning selection. Provider, model, and reasoning choices now participate in field-level conflict recovery, but actual provider execution was not exercised end to end.
- [ ] Choose local or remote processing when supported. **Status: Partially implemented.** Provider and Remote Evidence controls distinguish local-only, redacted, and private modes and preserve current winners during concurrent Settings saves. The wording is evidence policy rather than a simple processing-location choice, and no request preview is supplied.
- [ ] Preview a representative redacted payload before enabling remote AI. **Status: Not implemented.** Explanatory copy exists, but no payload preview exists.
- [ ] Set a daily or monthly request budget. **Status: Frontend only left.** `ModelRunStore` enforces a supplied daily request budget and voice has a separate Gemini cap, but general AI policy/settings do not expose a daily or monthly budget.
- [ ] Clear the AI cache. **Status: Not implemented.** Model runs can be queried as cache entries, but there is no clear-cache command or UI.
- [ ] Disable AI instantly without disabling planning, tracking, coaching rules, or reviews. **Status: Partially implemented.** Selecting Disabled preserves deterministic planning and tracking and now saves through the same conflict-safe version boundary as other Settings fields. Behavior coaching and reviews are not available to preserve, and the complete settings-to-runtime transition was not exercised.
- [ ] Continue using Zoid 666 while offline. **Status: Touches remaining.** Core planning, tracking, settings, and task commands are local and rules-first; no installed-app network-off acceptance test was run.
- [ ] See ambiguous activity remain unknown when AI fails. **Status: Partially implemented.** Unknown classification and structured-provider failure states exist, but no end-user AI-failure journey proves ambiguous sessions remain visibly unknown.
- [ ] Receive a deterministic factual review when AI is unavailable. **Status: Not implemented.** No daily review generator exists.
- [ ] Avoid having AI directly complete, delete, reschedule, block, or override a corrected task. **Status: Partially implemented.** Structured generation is separated from explicit mutation/outbox commands and trust gates, but corrected-task locks and a complete adversarial E2E test are absent.

## 47. Privacy and data controls

- [ ] Understand which data stays local. **Status: Touches remaining.** Settings now shows a content-safe inventory covering plans, behavior evidence, prompts, meetings, learning, voice, AI request metadata, settings, database path, size, and schema version; the packaged Settings surface still needs a visible installed-app pass.
- [ ] Understand when a remote AI request could leave the Mac. **Status: Touches remaining.** Remote Evidence help text distinguishes local-only, redacted metadata, and explicitly private content; it still lacks a representative payload preview.
- [ ] See what data an export will contain before creating it. **Status: Touches remaining.** Settings shows the exact counts-only redacted manifest and exclusions before export, backed by payload tests; the preview still needs installed-app visual verification.
- [ ] Choose an explicit export destination. **Status: Touches remaining.** Settings uses a native JSON save panel and the service writes atomically only to the chosen JSON destination, with focused tests; the save-panel journey still needs installed-app verification.
- [ ] Open the local data folder. **Status: Touches remaining.** The button calls `NSWorkspace.open` on the canonical storage directory, but the audit did not click it in the installed app or verify the resulting Finder selection.
- [ ] Configure retention separately for raw records, sessions, prompts, reviews, and diagnostics. **Status: Touches remaining.** Independent local retention now covers screenshots, extracted text, raw behavior, task sessions, prompts, reviews and learning, and diagnostics with migration-safe defaults and maintenance tests; the packaged Settings controls still need a visible save-and-reload pass.
- [ ] Delete one behavior session. **Status: Touches remaining.** Settings derives bounded application sessions, confirms the exact application and inclusive time range, and routes exact deletion through the agent with focused tests; the destructive installed-app journey remains unexercised.
- [ ] Delete one day. **Status: Touches remaining.** Settings provides a dedicated today-only confirmation and converts the local calendar day to a half-open service range that includes the full day across DST; installed-app deletion and refreshed totals remain to be witnessed.
- [ ] Delete a date range. **Status: Touches remaining.** Inclusive local-day selection now deletes behavior evidence plus every canonical and projected day-keyed plan record, preserves adjacent days, never deletes source screenshots, and refreshes Today and inventory; the destructive installed-app journey remains unexercised.
- [ ] Delete all raw behavior metadata. **Status: Touches remaining.** A confirmation-backed agent command deletes only local behavior, analysis, artifact-index, fact, and meeting-evidence rows while leaving source-owned files untouched; installed-app confirmation and result refresh remain to be witnessed.
- [ ] Delete AI request metadata. **Status: Touches remaining.** A confirmation-backed agent command independently deletes model runs, Codex jobs, and transmission receipts without touching Keychain credentials; installed-app confirmation and result refresh remain to be witnessed.
- [ ] Delete reviews and learned rules. **Status: Partially implemented.** A confirmation-backed agent command independently deletes learning samples, aggregates, and planner trust cycles, but the review product itself is not yet implemented and the installed deletion journey is unverified.
- [ ] Delete all Zoid 666 data. **Status: Touches remaining.** A confirmation-backed agent command deletes all user tables while preserving schema migrations, source-owned files, and Keychain credentials, and an empty-store restart test passes; the destructive installed-app journey remains unexercised.
- [ ] See related totals and conclusions disappear when their evidence is deleted. **Status: Touches remaining.** Successful data mutations now refresh the Today snapshot and stored-data inventory, and range deletion removes both canonical and projected plan conclusions; visible installed-app before-and-after proof is still required.
- [ ] Export redacted diagnostics without exposing raw titles, URLs, notes, screenshots, prompts, or credentials. **Status: Touches remaining.** Export is counts-only, excludes content and paths, rejects non-JSON and symbolic-link targets, and has payload inspection tests plus a pre-export manifest; a live saved-file inspection from the packaged app remains.

## 48. Source health and diagnostics

- [x] See Reminders permission and last successful sync. **Status: Fully implemented.** Settings visibly shows Ready to Connect, Connected, Access Needed, and Refresh Failed beside the last confirmed sync timestamp. The installed signed-QA journey proved that a successful refresh persisted the timestamp across restart, a failed refresh retained it, and a recovered retry advanced it (`RemindersConnectionController.swift`; `RemindersConnectionView.swift`; `.audit/runs/reminders-recovery/verifier/REPORT.md`).
- [ ] See Screenwatch path and time of the last valid record. **Status: Partially implemented.** Missing-state evidence shows the path and healthy/stale state shows relative age, but the UI does not show the absolute last-record time together with the path.
- [ ] See whether Screenwatch is waiting, healthy, stale, missing, denied, incompatible, or failing to parse. **Status: Partially implemented.** Healthy, stale, missing, empty/no-valid-record, and read-failure details exist, but denied/incompatible/schema states are not distinct and some collapse to generic Attention.
- [ ] See notification authorization and the last delivery result. **Status: Partially implemented.** Authorization is mapped to Source Health; delivery attempts/results are not persisted or displayed.
- [x] See local database health, size, and last migration. **Status: Fully implemented.** Source Health performs a read-only integrity check and displays the canonical database filename, aggregate database/WAL/SHM size, exact current and expected schema versions, latest migration time, and a clear healthy, attention, or not-ready state. The signed-QA app visibly changed from Not Ready to Healthy after the runtime created storage, Refresh exposed a 660 KB schema 29-of-29 store, and restart preserved the healthy state with the same migration time (`.audit/runs/local-system-diagnostics/candidate/REPORT.md`).
- [x] See the current AI mode and recent provider failures. **Status: Fully implemented.** Source Health displays the effective rules-only, local Ollama, Codex CLI, Apple on-device, or remote OpenAI mode, explains the processing boundary, and lists only the five newest provider/state/time/redacted-diagnostic failures. The signed-QA app visibly reported Local Ollama with local processing, Refresh succeeded, and restart preserved the same truthful mode (`.audit/runs/local-system-diagnostics/candidate/REPORT.md`).
- [ ] See whether the background helper is running. **Status: Partially implemented.** Source Health reports `SMAppService` registration status rather than verified process liveness; the signed repeat-install acceptance run independently proved first install, same-path and changed-path replacement, uninstall/reinstall, exact running-helper ownership, and production isolation (`.audit/runs/signed-qa-repeat-install/10cc1da/REPORT.md`), but the user-facing row still cannot distinguish an enabled registration from a live helper process.
- [ ] Understand the impact of each unhealthy source. **Status: Touches remaining.** Source rows include detail/evidence and Today shows limited Screenwatch coverage, but several states do not explain all downstream feature impacts.
- [ ] Open a direct repair action when one is available. **Status: Partially implemented.** Source rows offer Connect/Retry/Refresh and capture permissions open System Settings; a denied notification Retry only requests authorization again instead of opening the correct settings pane.
- [ ] Export a safe diagnostic package after reviewing its contents. **Status: Partially implemented.** Settings now previews the exact redacted JSON manifest and exclusions before a user chooses its destination, but it remains a single JSON artifact rather than a multi-file diagnostic package and lacks installed-app proof.

## 49. Screenwatch outage and recovery

- [ ] See a warning when Screenwatch stops reporting during active use. **Status: Partially implemented.** Today Source Freshness and coverage text show `limited`/stale state, but there is no prominent active-use warning or proven automatic foreground refresh.
- [ ] Understand that behavior totals and drift detection are temporarily unreliable. **Status: Partially implemented.** The dashboard states that Screenwatch coverage is limited/stale, but does not explicitly mention drift-detection suspension.
- [ ] Avoid receiving behavior prompts while Screenwatch is stale. **Status: Not implemented.** Behavior prompts do not exist, so no stale-source suppression behavior can be verified.
- [ ] Continue planning and manually tracking tasks during the outage. **Status: Touches remaining.** Planning and task execution are independent of Screenwatch and tests pass with limited coverage, but a live controlled Screenwatch outage was not induced after runtime recovery.
- [ ] See missing time represented as missing rather than productive or distracting. **Status: Partially implemented.** The sessionizer leaves totals unchanged and marks coverage limited, but does not display the amount of missing time explicitly.
- [ ] See Screenwatch return to healthy automatically when valid activity resumes. **Status: Partially implemented.** Reader state becomes healthy when refreshed with a valid recent record, with tests for healthy/missing states; the foreground app lacks a proven periodic refresh and no live recovery was exercised.
- [ ] Continue totals from the correct point without obvious duplicates after recovery. **Status: Touches remaining.** Archive/checkpoint tests cover incremental reads, partial lines, and deterministic replay without duplicate ingestion; live outage/recovery totals were not verified.
- [ ] See a clear schema-mismatch message when the source format changes. **Status: Not implemented.** Invalid records produce the generic `no valid records` or read-failure message, not a schema mismatch with repair guidance.
- [ ] Preserve prior activity and task history during the outage. **Status: Touches remaining.** Existing history is not deleted by missing or stale reads, the canonical database is healthy, and stores are independently tested, but a live outage and recovery comparison was not performed.

## 50. Notification failure

- [x] Continue using Zoid 666 when notification permission is unavailable. **Status: Fully implemented.** The fresh installed signed-QA denial journey continued through onboarding, opened the complete Today dashboard, exposed the paused-setup recovery strip, and resolved the canonical choice without touching the production notification center (`OnboardingRootView.swift`; `DashboardView.swift`; `.audit/runs/onboarding-test-prompt/signed-acceptance/REPORT.md`).
- [ ] See a permission repair path when notification access is revoked. **Status: Partially implemented.** Source Health explains enabling notifications and offers Retry, but does not directly open Notification settings after denial.
- [x] Receive prompts through the Today dashboard when notification delivery fails. **Status: Fully implemented.** A fresh signed-QA run with notification permission denied created the canonical prompt, visibly reported Today Fallback, and displayed the same title, summary, and harmless actions in Today Decisions (`OnboardingTestPromptService.swift`; `DashboardView.swift`; `.audit/runs/onboarding-test-prompt/signed-acceptance/REPORT.md`).
- [ ] Continue seeing active-task state in the dashboard and menu bar. **Status: Partially implemented.** The dashboard state is independent of notifications, but the menu bar has only Zoid Voice and no active-task state.
- [ ] Avoid losing a prompt response when notification handling is interrupted. **Status: Touches remaining.** Prompt response plus pending effect is transactional, token-bound, idempotent, and concurrency tested; notification-process interruption itself lacks a live E2E test.
- [x] Continue using in-app prompts when notification permission is denied. **Status: Fully implemented.** The installed denial journey resolved Continue Setup directly from Today, removed the decision from the dashboard, persisted response surface `dashboard`, and returned to onboarding with the same resolved state and enabled continuation (`PromptInboxStore.swift`; `TodayDashboardXPC.swift`; `.audit/runs/onboarding-test-prompt/signed-acceptance/REPORT.md`).
- [ ] Avoid receiving stacked duplicate notifications for one coaching decision. **Status: Touches remaining.** Unresolved `decisionKey` deduplication and deterministic notification identifiers prevent duplicate scheduling for supported prompt types, but behavior-coaching decisions are not implemented and live Notification Center stacking was not inspected.

## 51. Reminders failure and recovery

- [ ] Continue manual planning after Reminders access is denied or revoked. **Status: Not implemented.** The Today surface depends on imported Reminders and offers no user-created local task flow; the empty state only directs the user to connect Reminders.
- [x] See when task data may be out of date. **Status: Fully implemented.** The installed signed-QA card visibly reported Refresh Failed, explained that task data was not returned, retained the prior successful-sync timestamp, and offered an explicit retry without discarding prior success (`.audit/runs/reminders-recovery/verifier/REPORT.md`).
- [x] Retry Reminders synchronization. **Status: Fully implemented.** The installed signed-QA card visibly recovered from an injected task-fetch failure through one Refresh Reminders action, changed back to Connected, and advanced the last-success timestamp only after tasks were returned (`RemindersConnectionController.swift`; `.audit/runs/reminders-recovery/verifier/REPORT.md`).
- [ ] Keep local estimates, active sessions, and plan state while sync is unavailable. **Status: Partially implemented.** These values are stored separately from EventKit in the recovered canonical database, but the full permission-loss, continued work, restart, and recovery journey was not verified.
- [ ] See completion remain pending when Apple Reminders rejects it. **Status: Partially implemented.** The action outbox models retryable failures, but the installed Today UI has no specific, clearly labeled pending Reminder-completion state.
- [ ] Retry the pending completion after access returns. **Status: Partially implemented.** Retryable outbox execution is tested, but no complete user-visible permission-loss, retry, and confirmed-success journey was proven.
- [ ] Avoid losing the local task when a Reminder write fails. **Status: Partially implemented.** Local task and action records are designed to survive source failure, but a real rejected write followed by restart and retry was not performed.
- [ ] Avoid seeing a task reported as synchronized before confirmation. **Status: Partially implemented.** The executor waits for EventKit results, but the installed UI does not clearly distinguish local completion, pending source completion, and confirmed synchronization.

## 52. Database or local-state failure

- [ ] See a read-only state when local changes cannot be saved safely. **Status: Touches remaining.** A prominent `READ-ONLY SAFETY MODE` banner exists with a reason and recheck action, but a current write failure was not safely induced to prove the complete transition and recovery.
- [ ] Understand which actions are temporarily unavailable. **Status: Partially implemented.** The read-only banner says external actions are blocked, but it does not enumerate affected controls or disable every unavailable action with a local explanation.
- [ ] Continue viewing already saved information when safe. **Status: Partially implemented.** The UI is designed to remain visible in safety mode and the canonical database is healthy now, but an actual read-only transition was not exercised.
- [ ] Avoid receiving coaching actions that cannot be recorded reliably. **Status: Partially implemented.** A database write circuit breaker and read-only agent mode exist and are tested, but a live write failure and prompt-suppression sequence was not verified.
- [ ] Retry after a temporary local database lock. **Status: Partially implemented.** Retry and recheck mechanisms exist, but no complete UI-visible lock, recovery, and successful mutation journey was proven.
- [ ] Restart after an unsuccessful upgrade and retain readable previous data. **Status: Blocked from verification.** Migration and rollback code exists and the canonical database is healthy, but safely forcing a failed installed-app upgrade requires an isolated copy rather than the user's live store.
- [ ] Avoid losing estimates, plans, prompt responses, or task sessions after a crash. **Status: Blocked from verification.** Durable stores and a healthy canonical database exist, but an intentional process crash and complete recovery check were not performed against the user's live state.

## 53. Sleep, wake, and restart

- [ ] Put the Mac to sleep during an active task. **Status: Blocked from verification.** Sleep recovery policies exist, but a real sleep cycle with a controlled test task was not performed during this audit.
- [ ] Wake after a short lock and see timing follow the configured policy. **Status: Partially implemented.** Sleep and wake events are modeled in replay and scheduling, but the active-task UI does not expose a clear short-lock timing policy or reconciliation result.
- [ ] Wake after a long sleep and be asked whether the task is still active. **Status: Not implemented.** No installed UI prompt or task-session confirmation flow for `still active?` was found.
- [ ] Avoid accumulating aligned time while no telemetry exists. **Status: Partially implemented.** Coverage and freshness logic suppress unsafe conclusions, but no live sleep-to-wake active-task accounting journey was proven.
- [ ] Sleep during a sprint and see an understandable reconciled result on wake. **Status: Not implemented.** The installed product has active commitments but no visible sprint pause/reconciliation explanation after wake.
- [ ] Restart Zoid 666 with an active task and recover it without duplicated time. **Status: Blocked from verification.** Task sessions are durable and the canonical database recovered, but no controlled test task was started, restarted, timed, and reconciled end to end.
- [ ] Restart with an unresolved prompt and see its current valid state. **Status: Blocked from verification.** Prompt persistence is implemented in the healthy canonical store, but no controlled unresolved prompt was carried through a restart.
- [ ] Restart with an unfinished review and resume it. **Status: Not implemented.** The Reviews sidebar does not route to a functional review workflow and no unfinished-review UI exists.
- [ ] Change time zones and retain accurate historical event times. **Status: Partially implemented.** UTC events and policy time zones are stored and tested, but no complete installed-app time-zone-change journey was verified.
- [ ] Confirm before a time-zone change moves a plan to another local day. **Status: Not implemented.** No user confirmation flow for moving an existing plan across local-day boundaries was found.
- [ ] Avoid negative or impossible durations when the system clock changes. **Status: Partially implemented.** Replay and date handling cover anomalies in code, but live task timing under a backward clock change was not verified.

## 54. Quiet hours and scheduling

- [ ] Receive morning planning at the configured time. **Status: Partially implemented.** The agent runs scheduled and missed-run planning, but current settings center on nightly planning and no complete morning invitation flow was proven.
- [ ] Receive planned task-start reminders. **Status: Barely started.** Scheduled calendar blocks exist, but a dedicated user-facing task-start reminder journey is not present.
- [ ] Receive break-end reminders. **Status: Not implemented.** No break model, break scheduler, or break-end notification UI was found.
- [ ] Receive the end-of-day review reminder. **Status: Not implemented.** No functional daily review system or review scheduling surface is present.
- [ ] Receive the weekly review reminder. **Status: Not implemented.** No functional weekly review generation or reminder exists.
- [ ] Avoid behavioral prompts outside configured work hours. **Status: Partially implemented.** Quiet windows and wake eligibility are policy-controlled, but the required gaming-drift intervention path is not complete end to end.
- [ ] Keep source-health problems visible in the dashboard without waking the user. **Status: Touches remaining.** Source freshness is visible and health notifications are bounded, but a live quiet-hours source failure was not exercised.
- [ ] See only one unresolved notification for the same prompt. **Status: Touches remaining.** Stable notification identifiers and prompt-store coordination prevent stacking in tests, but live duplicate delivery was not induced.
- [ ] See updated notification content replace obsolete content. **Status: Touches remaining.** The notification coordinator replaces requests by prompt identity, but a live update sequence was not verified.

## 55. Accessibility

- [ ] Complete onboarding using only the keyboard. **Status: Touches remaining.** The complete onboarding flow now has explicit accessibility identifiers, native controls, focusable choices, and keyboard shortcuts for continuation and retries, but a full keyboard-only signed-QA pass has not yet been completed (`OnboardingRootView.swift`).
- [ ] Plan the day using only the keyboard. **Status: Partially implemented.** SwiftUI buttons are keyboard-addressable and expose labels, but full focus traversal and plan completion were not proven.
- [ ] Start, pause, switch, and complete tasks using only the keyboard. **Status: Partially implemented.** Start and complete buttons are accessible, but pause, explicit switch, and full lifecycle controls are incomplete.
- [ ] Respond to coaching using only the keyboard. **Status: Partially implemented.** Notification actions and dashboard prompt buttons exist, but the full gaming coaching flow is not complete.
- [ ] Correct and confirm reviews using only the keyboard. **Status: Not implemented.** Review correction and confirmation UI is absent.
- [ ] Configure settings using only the keyboard. **Status: Partially implemented.** Settings controls use native SwiftUI semantics, but a complete keyboard-only pass has not been validated.
- [ ] Hear useful VoiceOver labels for every control and state. **Status: Partially implemented.** Many critical buttons have explicit accessibility labels and custom controls expose values, but no complete VoiceOver audit covers all 497 Today elements and settings states.
- [ ] Understand every status without relying on color alone. **Status: Touches remaining.** Major states use text labels such as `ACTIVE`, `READY`, and `READ-ONLY`, but no full state inventory and contrast-independent verification exists.
- [ ] Use larger text without clipped task titles or hidden actions. **Status: Partially implemented.** Flexible text appears throughout, but the installed UI contains very long Reminder titles and no large-text visual proof was completed.
- [ ] Follow a clear and logical focus order. **Status: Partially implemented.** Accessibility order broadly follows visual order, but the dense Today page has hundreds of elements and was not end-to-end keyboard audited.
- [ ] Use reduced motion without losing state-change feedback. **Status: Barely started.** Motion is restrained, but no explicit reduced-motion handling or user-visible verification was found.
- [ ] Use an accessible dashboard alternative to every compact notification action. **Status: Partially implemented.** Prompts are stored in a dashboard inbox, but the full set of notification actions and resulting states is not proven equivalent.

## 56. Localization and visual clarity

- [ ] See dates, durations, numbers, calendars, and week starts formatted for the current locale. **Status: Partially implemented.** Native formatters are used in many surfaces, but user-facing strings are hard-coded in English and no locale matrix was tested.
- [ ] Change locale without breaking saved task and review meaning. **Status: Partially implemented.** Stored times retain time-zone context, but reviews are absent and a real locale change was not verified.
- [ ] Read localized text without clipped controls. **Status: Not implemented.** There are no localization resources or translated strings to test.
- [ ] Use light appearance with sufficient contrast. **Status: Touches remaining.** The installed Sumi-Ink light interface is coherent and readable, but a formal contrast audit has not been completed.
- [ ] Use dark appearance with sufficient contrast. **Status: Not implemented.** `DashboardView` forces `.preferredColorScheme(.light)`.
- [ ] Recognize active, paused, warning, missing, and completed states without ambiguity. **Status: Partially implemented.** Active, ready, warning, and completed labels are present, but paused workday and review states are incomplete.
- [ ] See the Sumi-Ink visual system consistently across dashboard, planning, review, settings, menu bar, and prompts. **Status: Partially implemented.** Today, source health, and settings use Sumi-Ink; functional review and general task menu-bar surfaces do not exist.
- [ ] See restrained emphasis for risk and drift rather than alarming visual treatment. **Status: Touches remaining.** Existing warnings use restrained red seal treatment, but gaming-drift escalation is not complete enough for full validation.
- [ ] Keep gaming information visible without letting it dominate the product. **Status: Touches remaining.** The live Today hero shows a compact 60-minute gaming budget and unlock rule without dominating the page.
- [ ] Avoid distracting motion or celebratory feedback around interruptions. **Status: Touches remaining.** Current UI motion is limited and functional, but reduced-motion behavior is not explicit.

## 57. Responsiveness and perceived reliability

- [ ] Open the Today view without a noticeable cold-launch delay. **Status: Touches remaining.** The installed app becomes usable quickly in live inspection, but no controlled cold-launch timing was captured.
- [ ] Reopen the app quickly after it has already launched once. **Status: Touches remaining.** The running app returns promptly, but no repeatable timing measurement was recorded.
- [ ] See new Screenwatch activity reflected within a believable short delay. **Status: Partially implemented.** The dashboard reported current activity and one post-recovery verifier run confirmed fresh ingestion, but end-to-end UI latency was not measured and the later recheck found the source stale.
- [ ] See local task actions respond immediately. **Status: Touches remaining.** Estimate controls and visible task actions update locally, but destructive actions were not used against the user's real Reminders.
- [ ] See the dashboard and menu bar stay synchronized. **Status: Partially implemented.** The menu bar is a voice host rather than a full task-status surface, so task lifecycle parity is incomplete.
- [ ] Receive a gaming prompt shortly after the configured threshold rather than much later. **Status: Barely started.** Gaming accounting exists, but the specified ten-minute gaming-drift prompt journey is not proven.
- [ ] Generate a rules-only daily review without a noticeable wait. **Status: Not implemented.** No functional daily review generator or review screen is present.
- [ ] Leave the background helper running without obvious battery, CPU, or memory impact. **Status: Partially implemented.** launchd reports the helper running from the canonical store, but no sustained CPU, memory, energy, or handle-growth measurement was performed.
- [ ] Use the app for weeks without unexplained database growth or duplicated screenshot storage. **Status: Blocked from verification.** Retention services exist and the canonical database is healthy, but a controlled multi-week growth and screenshot-deduplication observation has not been completed.

## 58. Complete planning-to-completion journey

- [ ] Open Zoid 666 at the start of the day. **Status: Blocked from verification.** Build 8, signing, agent, database, and service checks pass, but the independent `a068d27` verifier did not launch the main app because it would refresh real EventKit and XPC state (`.audit/runs/baseline/a068d27/REPORT.md`).
- [ ] Review eligible Reminders. **Status: Blocked from verification.** Source and live database evidence show Reminder ingestion, but the independent `a068d27` verifier could not run the current packaged UI against isolated Reminder fixtures (`.audit/runs/baseline/a068d27/REPORT.md`).
- [ ] Choose a realistic top three and main objective. **Status: Partially implemented.** Users can add, remove, rank, and mark a main objective, but the live plan had five blocks and no strict top-three approval flow.
- [ ] Estimate every priority task. **Status: Touches remaining.** Visible 15, 30, 45, 60, and 90 minute controls work for planned tasks, but custom and unknown estimates are absent.
- [ ] Approve the plan. **Status: Partially implemented.** `ACCEPT BLOCKS` approves Calendar reservations, but there is no dedicated approved-day-state confirmation matching the scenario.
- [ ] Start the recommended main task. **Status: Partially implemented.** A `DO THIS NEXT` task can be started, but the live recommendation said to continue an already active commitment and main-objective semantics are not consistently enforced.
- [ ] Work in an aligned application without receiving a drift prompt. **Status: Partially implemented.** Screenwatch currentness and active commitment exist, but alignment classification and prompt suppression are not user-visible enough to prove this.
- [ ] Complete the task. **Status: Touches remaining.** The installed dashboard exposes `COMPLETE` actions, but the user's real Reminder was not mutated during audit.
- [ ] See the Apple Reminder completed. **Status: Blocked from verification.** Completing a real user task would be an external state change and was not necessary to identify the larger incomplete flow.
- [ ] See the dashboard recommend the next useful task. **Status: Touches remaining.** The dashboard displays `DO THIS NEXT` with a reason and updates from agent state, but post-completion recomputation was not safely exercised.
- [ ] End the workday and confirm an accurate review. **Status: Not implemented.** No end-workday control or functional daily review confirmation flow exists.

## 59. Complete gaming-recovery journey

- [ ] Approve a plan with at least one incomplete priority task. **Status: Partially implemented.** Planned blocks and incomplete tasks exist, but the exact approved priority-plan state is not exposed.
- [ ] Start gaming during the work window before unlock conditions are satisfied. **Status: Blocked from verification.** This requires a live behavioral session and cannot establish completion while downstream intervention behavior is missing.
- [ ] Receive one accountability prompt after the threshold. **Status: Barely started.** Prompt infrastructure exists, but no verified ten-minute gaming trigger delivered the specified prompt.
- [ ] Understand the observed gaming time and unfinished task. **Status: Barely started.** Gaming budget and task state are visible separately, but the combined accountability message is not proven.
- [ ] Start a 20-minute sprint from the prompt. **Status: Not implemented.** No 20-minute sprint action appears in the installed prompt or task controls.
- [ ] See gaming stop accumulating when the context changes. **Status: Partially implemented.** Behavior sessions can close on context changes, but the installed UI did not show a full gaming-to-work transition.
- [ ] See the selected task become active everywhere. **Status: Partially implemented.** The Today surface updates active commitment, but the menu bar lacks equivalent task state.
- [ ] Work in an aligned context for at least ten minutes. **Status: Partially implemented.** Aligned work can be inferred in domain logic, but the user cannot verify the recovery window end to end.
- [ ] See the intervention counted as a recovery. **Status: Not implemented.** No user-visible recovery metric or review exists.
- [ ] See the journey described factually in the daily review. **Status: Not implemented.** Daily reviews are absent.

## 60. Complete intentional-gaming journey

- [ ] Start gaming while priority work remains incomplete. **Status: Blocked from verification.** A real gaming session was not required because the response and review path is incomplete.
- [ ] Receive one appropriate prompt. **Status: Barely started.** General prompt delivery exists, but the gaming-specific end-to-end trigger is not proven.
- [ ] Choose `Continue intentionally`. **Status: Not implemented.** This action is not present in current prompt actions.
- [ ] See the prompt close and the override cooldown begin. **Status: Not implemented.** No intentional-gaming override control or visible cooldown exists.
- [ ] Continue gaming without repeated equivalent prompts during the cooldown. **Status: Not implemented.** The required override state does not exist in the user flow.
- [ ] See gaming budget or debt update according to policy. **Status: Partially implemented.** A durable gaming ledger and live budget exist, but override/debt response integration is not complete.
- [ ] Return to work voluntarily. **Status: Partially implemented.** A user can start a task, but the transition is not connected to an intentional-gaming episode.
- [ ] See the choice recorded without shame in the review. **Status: Not implemented.** Neither the choice nor daily review exists.

## 61. Complete ambiguous-work journey

- [ ] Start a technical task. **Status: Touches remaining.** Real tasks can be started, but no task-type declaration or dedicated technical-task context is visible.
- [ ] Open a browser or YouTube tutorial related to that task. **Status: Partially implemented.** Screenwatch observes application and context, but this exact relationship was not safely staged.
- [ ] See the session classified as research when evidence is sufficient. **Status: Not implemented.** Current Today behavior exposes app percentages rather than a user-visible research-session classification.
- [ ] See the session remain unknown or request confirmation when evidence is insufficient. **Status: Not implemented.** No unknown-session confirmation UI is present.
- [ ] Avoid receiving a strong drift prompt without sufficient evidence. **Status: Partially implemented.** Confidence policies exist, but the user-facing drift system is incomplete and cannot be validated end to end.
- [ ] Correct the session if Zoid 666 is wrong. **Status: Not implemented.** No behavior-session correction interface exists.
- [ ] Save an appropriately scoped rule if the same context will recur. **Status: Not implemented.** Settings expose application categories, not a correction-to-rule scope preview and save flow.
- [ ] See future matching activity handled according to the correction. **Status: Not implemented.** The prerequisite correction and learned-rule flow is absent.

## 62. Complete degraded-mode journey

- [ ] Begin a planned workday with all sources healthy. **Status: Partially implemented.** One post-recovery run confirmed Reminders, Screenwatch, the background agent, canonical database, and ingestion verifier healthy, but the later Screenwatch freshness recheck failed and the exact approved-day start flow remains incomplete.
- [ ] Lose Screenwatch activity during an active task. **Status: Blocked from verification.** Disrupting the user's real capture service was not performed; this needs an isolated fixture or explicit controlled outage.
- [ ] See a source warning and prompt suppression. **Status: Partially implemented.** Freshness warnings and suppression policies exist, but a live outage was not induced.
- [ ] Continue manually tracking the active task. **Status: Partially implemented.** Active commitments continue independently of Screenwatch, but pause and full manual timing controls are incomplete.
- [ ] Lose notification availability before a prompt. **Status: Blocked from verification.** Notification authorization was not changed during the audit.
- [ ] Receive the prompt through notification or dashboard instead. **Status: Partially implemented.** Prompt inbox fallback exists, but notification-loss routing was not exercised end to end.
- [ ] Resolve the prompt once from the available surface. **Status: Partially implemented.** Idempotent prompt response infrastructure is tested, but no live degraded-mode episode was resolved.
- [ ] Recover Screenwatch and notification delivery. **Status: Blocked from verification.** Safe live service disruption and recovery were not attempted.
- [ ] See source health return to normal without losing the plan or duplicating actions. **Status: Partially implemented.** The installed signed-QA agent moved visibly through healthy, repaired, not connected, and re-enabled states while a preservation marker survived and the production helper remained isolated; Screenwatch and notification outages, plan preservation with real populated data, and cross-surface duplicate-action checks remain unproven (`.audit/runs/agent-lifecycle/candidate/REPORT.md`).
- [ ] Confirm a review that clearly identifies the missing coverage period. **Status: Not implemented.** No functional review confirmation path exists.

## 63. Complete correction-and-learning journey

- [ ] Finish a day containing an incorrectly classified session. **Status: Touches remaining.** The Reviews surface now groups local behavior observations into privacy-safe application sessions and displays the stored classification, but a signed-QA day containing a known incorrect session could not be visibly exercised while the Mac was locked (`Sources/ZoidCoachCore/DailyReview.swift`; `Sources/ZoidCoachInfrastructure/DailyReviewStore.swift`; `.audit/runs/daily-review/7b96623/REPORT.md`).
- [ ] Open the daily review. **Status: Touches remaining.** Reviews navigation now renders the complete daily review surface with day selection, loading, empty, failure, retry, and populated states in the clean signed-QA package; visible navigation proof remains outstanding because Computer Use reported a locked Mac (`Sources/ZoidCoachApp/Views/DashboardView.swift`; `Sources/ZoidCoachApp/Views/DailyReviewView.swift`; `.audit/runs/daily-review/7b96623/REPORT.md`).
- [ ] Find the incorrect session and reclassify it. **Status: Touches remaining.** Every session exposes an accessible classification picker and durable Apply Correction action, and store tests prove reclassification survives reopening and recalculates totals; the packaged interaction still needs visible click-through proof (`DailyReviewView.swift`; `DailyReviewTests.swift`; `.audit/runs/daily-review/7b96623/REPORT.md`).
- [ ] Split or attach the session to a task if needed. **Status: Touches remaining.** The user can correct the second half of a session and attach a trimmed task identifier or title, with deterministic tests proving the first half remains unchanged and the task attachment persists; selecting a canonical Reminder task and visible signed-QA interaction remain as finishing touches (`DailyReviewStore.swift`; `DailyReviewTests.swift`).
- [ ] See totals and review language update. **Status: Touches remaining.** Applying a correction reloads the snapshot, recalculates category totals, and regenerates explicitly tentative review language without exposing titles, URLs, or screenshots; visible signed-QA before-and-after proof remains outstanding (`DailyReviewStore.swift`; `DailyReviewView.swift`; `DailyReviewTests.swift`).
- [ ] Reject an unsupported causal hypothesis. **Status: Touches remaining.** The review presents Accept Explanation and Reject Explanation actions, persists rejection locally, labels the explanation as a hypothesis rather than fact, and invalidates a prior confirmation when the decision changes; the signed-QA control was not visibly clicked while the Mac was locked (`DailyReviewView.swift`; `DailyReviewStore.swift`; `DailyReviewTests.swift`).
- [ ] Confirm the corrected review. **Status: Touches remaining.** Confirmation is durable and remains editable, while any later correction atomically returns the hypothesis to pending and clears confirmation so learning cannot use stale approval; visible relaunch confirmation proof remains outstanding (`DailyReviewStore.swift`; `DailyReviewTests.swift`; `.audit/runs/daily-review/7b96623/REPORT.md`).
- [x] Complete enough well-covered days for a weekly review. **Status: Fully implemented.** The signed QA journey visibly progressed from 0/7 limited evidence to a 7/7 review for 2026-07-04 through 2026-07-10, and the store tests enforce at least three confirmed days with 30 observed minutes (`WeeklyReviewStore.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).
- [x] Inspect the evidence behind a weekly pattern. **Status: Fully implemented.** The installed signed app expanded estimate evidence into three dated estimated-versus-corrected examples and an alternative explanation, then collapsed it through the same accessible control (`WeeklyReviewView.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).
- [x] Accept, edit, or reject one proposed experiment. **Status: Fully implemented.** The installed signed app edited, accepted, relaunched with tracking, rejected, and relaunched with the rejected state preserved for the same single weekly experiment (`WeeklyReviewStore.swift`; `WeeklyReviewView.swift`; `.audit/runs/weekly-review/verifier/REPORT.md`).

## 64. Release 1 end-user acceptance

- [ ] Use real Apple Reminders for daily planning. **Status: Touches remaining.** The installed app displays real Reminders, builds plans, and now persists through the canonical store, but permission-denied and manual fallback remain incomplete.
- [ ] Use real Screenwatch activity for understandable behavior totals. **Status: Touches remaining.** Live behavior minutes and app-percentage disclosure are visible, and the new daily review derives privacy-safe category totals plus durable corrections from the same canonical behavior records. The later recheck found Screenwatch stale, and the complete signed-QA correction journey remains unverified (`DailyReviewStore.swift`; `.audit/runs/daily-review/7b96623/REPORT.md`).
- [ ] Use notifications or the Today dashboard for timely status and prompts. **Status: Partially implemented.** Both delivery surfaces exist, but the core gaming-drift coaching episode is not complete.
- [ ] Complete morning planning, task tracking, one gaming intervention, response, recovery, and review as one continuous flow. **Status: Not implemented.** Planning, task tracking, and daily review now exist as separate durable journeys, but the gaming intervention, response, recovery, and continuous cross-surface acceptance run remain missing.
- [ ] Use the app for seven consecutive days without losing plans, estimates, task sessions, corrections, or prompt responses. **Status: Blocked from verification.** Corrections, hypothesis decisions, and confirmations now persist through restart in deterministic tests, but no controlled seven-day acceptance run has been completed.
- [ ] Complete the baseline week without unwanted behavior interruptions. **Status: Partially implemented.** Trust gates exist, but the original seven-day behavior-observation flow is not visible or verified.
- [ ] Understand every intervention and the evidence that caused it. **Status: Partially implemented.** Prompt context is stored and some UI explanations exist, but the core gaming intervention evidence surface is incomplete.
- [ ] Correct wrong classifications and see the product adapt. **Status: Partially implemented.** Daily review now supports durable whole-session and midpoint reclassification, task attachment, recalculated totals, and confirmation invalidation after later edits. Turning an accepted correction into a scoped future classification rule and visibly proving adaptation are still missing (`DailyReviewStore.swift`; `DailyReviewTests.swift`).
- [ ] Pause or override coaching without punishment. **Status: Partially implemented.** Automation can be paused, but intentional gaming override and coaching-specific pause durations are incomplete.
- [ ] Continue using planning and task tracking when behavior sources fail. **Status: Partially implemented.** The architecture and canonical persistence separate planning from behavior sources, but a live source outage and complete manual-control flow were not verified.
- [ ] Export or delete personal data without hidden dependencies. **Status: Touches remaining.** Export, inventory, retention, and every deletion route run locally through the database and agent without network services, source-file ownership, or Keychain deletion; the complete packaged UI journey still needs isolated destructive verification.
- [ ] Understand the product under missing data, denied permissions, restarts, and integration failures. **Status: Partially implemented.** Health and safety UI exists, canonical persistence is healthy, and the latest verifier correctly exposed Screenwatch staleness, but several failure states still lack a complete explanation and repair journey.
- [ ] Finish the week feeling that the next responsible action is easier to see and begin. **Status: Blocked from verification.** This outcome requires a stable week-long product trial after the missing review and coaching flows are implemented.

## 65. Explicitly deferred end-user scenarios

- [x] Keep team workspaces, managers, shared permissions, and monitoring of other people out of Release 1. **Status: Fully implemented.** The installed app is single-user and local-first with no team or remote-admin surface (`.audit/runs/baseline/a068d27/REPORT.md`).
- [x] Keep a public web dashboard out of Release 1. **Status: Fully implemented.** The product is a native local macOS app and has no public web dashboard (`.audit/runs/baseline/a068d27/REPORT.md`).
- [x] Keep cloud screenshot synchronization off by default and outside the MVP. **Status: Fully implemented.** Screenwatch evidence remains local and no cloud screenshot-sync feature is exposed (`.audit/runs/baseline/a068d27/REPORT.md`).
- [x] Keep mobile and cross-device behavior correlation outside the MVP. **Status: Fully implemented.** No mobile companion or cross-device behavior surface exists (`.audit/runs/baseline/a068d27/REPORT.md`).
- [ ] Keep calendar auto-scheduling outside the MVP. **Status: Not implemented.** The current product explicitly supports autonomous Calendar planning and exposes `ACCEPT BLOCKS`, so this deferred constraint has been superseded rather than satisfied.
- [x] Keep automatic multi-task Reminder decomposition outside the MVP. **Status: Fully implemented.** The app plans existing tasks and does not expose automatic decomposition into multiple new Reminders (`.audit/runs/baseline/a068d27/REPORT.md`).
- [x] Keep hard application or website blocking outside Release 1. **Status: Fully implemented.** No blocking controls or enforcement service are present (`.audit/runs/baseline/a068d27/REPORT.md`).
- [ ] Require any future blocking to be explicitly enabled, reversible, time-bounded, and protected by an escape hatch. **Status: Barely started.** General policy, approval, undo, and pause patterns exist, but no blocking-specific contract or UI can yet prove these safeguards.
