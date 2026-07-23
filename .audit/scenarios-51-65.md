# Scenario Audit: Sections 51-65

Audit date: 2026-07-12.

Runtime evidence used: installed Build 8, live accessibility inspection, `swift test`, release build, launchd inspection, background-service verification, current source, and current local storage.

Critical runtime caveat: the running agent has its former database open through deleted file descriptors under `~/.Trash/Zoid Coach`, while the documented database path contains a zero-byte file.
The current UI can display the agent's in-memory/open-file state, but restart-safe persistence is not proven and the background verification fails on the missing schema.

## 51. Reminders failure and recovery

- [ ] Continue manual planning after Reminders access is denied or revoked. **Status: Not implemented.** The Today surface depends on imported Reminders and offers no user-created local task flow; the empty state only directs the user to connect Reminders.
- [ ] See when task data may be out of date. **Status: Touches remaining.** Source freshness and a refresh control are visible, but the current split database state prevents complete recovery proof.
- [ ] Retry Reminders synchronization. **Status: Touches remaining.** `REFRESH REMINDERS` is reachable in the installed app and backed by `AppModel.refreshReminderTasks()`, but permission-loss recovery was not safely induced in the user's live store.
- [ ] Keep local estimates, active sessions, and plan state while sync is unavailable. **Status: Partially implemented.** These values are stored separately from EventKit, but the agent currently depends on an unlinked database and cannot guarantee survival after restart.
- [ ] See completion remain pending when Apple Reminders rejects it. **Status: Partially implemented.** The action outbox models retryable failures, but the installed Today UI has no specific, clearly labeled pending Reminder-completion state.
- [ ] Retry the pending completion after access returns. **Status: Partially implemented.** Retryable outbox execution is tested, but no complete user-visible permission-loss, retry, and confirmed-success journey was proven.
- [ ] Avoid losing the local task when a Reminder write fails. **Status: Partially implemented.** Local task and action records are designed to survive source failure, but current storage continuity is broken for the next agent restart.
- [ ] Avoid seeing a task reported as synchronized before confirmation. **Status: Partially implemented.** The executor waits for EventKit results, but the installed UI does not clearly distinguish local completion, pending source completion, and confirmed synchronization.

## 52. Database or local-state failure

- [ ] See a read-only state when local changes cannot be saved safely. **Status: Touches remaining.** A prominent `READ-ONLY SAFETY MODE` banner exists with a reason and recheck action, but the real split-storage failure did not surface that banner in the installed UI.
- [ ] Understand which actions are temporarily unavailable. **Status: Partially implemented.** The read-only banner says external actions are blocked, but it does not enumerate affected controls or explain why the current zero-byte canonical database is not detected.
- [ ] Continue viewing already saved information when safe. **Status: Partially implemented.** The UI can remain visible in safety mode, but the only current saved state is held by open descriptors to deleted files and is not durable.
- [ ] Avoid receiving coaching actions that cannot be recorded reliably. **Status: Partially implemented.** A database write circuit breaker and read-only agent mode exist and are tested, but the live agent continued operating from deleted storage without flagging the canonical-path failure.
- [ ] Retry after a temporary local database lock. **Status: Partially implemented.** Retry and recheck mechanisms exist, but no complete UI-visible lock, recovery, and successful mutation journey was proven.
- [ ] Restart after an unsuccessful upgrade and retain readable previous data. **Status: Blocked from verification.** Migration and rollback code exists, but restarting the current agent would risk losing the only open copy of the live database, so this cannot be tested safely.
- [ ] Avoid losing estimates, plans, prompt responses, or task sessions after a crash. **Status: Blocked from verification.** Tests cover durable stores, but the installed agent's database is already unlinked and its state is at risk on crash or restart.

## 53. Sleep, wake, and restart

- [ ] Put the Mac to sleep during an active task. **Status: Blocked from verification.** Sleep recovery policies exist, but a real sleep cycle would risk terminating the agent that holds the only live unlinked database.
- [ ] Wake after a short lock and see timing follow the configured policy. **Status: Partially implemented.** Sleep and wake events are modeled in replay and scheduling, but the active-task UI does not expose a clear short-lock timing policy or reconciliation result.
- [ ] Wake after a long sleep and be asked whether the task is still active. **Status: Not implemented.** No installed UI prompt or task-session confirmation flow for `still active?` was found.
- [ ] Avoid accumulating aligned time while no telemetry exists. **Status: Partially implemented.** Coverage and freshness logic suppress unsafe conclusions, but no live sleep-to-wake active-task accounting journey was proven.
- [ ] Sleep during a sprint and see an understandable reconciled result on wake. **Status: Not implemented.** The installed product has active commitments but no visible sprint pause/reconciliation explanation after wake.
- [ ] Restart Zoid Coach with an active task and recover it without duplicated time. **Status: Blocked from verification.** Task sessions are durable in design, but restarting now could discard the unlinked live database.
- [ ] Restart with an unresolved prompt and see its current valid state. **Status: Blocked from verification.** Prompt persistence is implemented in stores, but current storage makes safe restart proof impossible.
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
- [ ] Keep source-health problems visible in the dashboard without waking the user. **Status: Touches remaining.** Source freshness is visible and health notifications are bounded, but the canonical database failure is not being surfaced.
- [ ] See only one unresolved notification for the same prompt. **Status: Touches remaining.** Stable notification identifiers and prompt-store coordination prevent stacking in tests, but live duplicate delivery was not induced.
- [ ] See updated notification content replace obsolete content. **Status: Touches remaining.** The notification coordinator replaces requests by prompt identity, but a live update sequence was not verified.

## 55. Accessibility

- [ ] Complete onboarding using only the keyboard. **Status: Not implemented.** There is no complete onboarding flow in the installed app.
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
- [ ] See new Screenwatch activity reflected within a believable short delay. **Status: Partially implemented.** The dashboard reports current activity and the source is live, but end-to-end latency was not measured and the verification script targets the missing canonical database.
- [ ] See local task actions respond immediately. **Status: Touches remaining.** Estimate controls and visible task actions update locally, but destructive actions were not used against the user's real Reminders.
- [ ] See the dashboard and menu bar stay synchronized. **Status: Partially implemented.** The menu bar is a voice host rather than a full task-status surface, so task lifecycle parity is incomplete.
- [ ] Receive a gaming prompt shortly after the configured threshold rather than much later. **Status: Barely started.** Gaming accounting exists, but the specified ten-minute gaming-drift prompt journey is not proven.
- [ ] Generate a rules-only daily review without a noticeable wait. **Status: Not implemented.** No functional daily review generator or review screen is present.
- [ ] Leave the background helper running without obvious battery, CPU, or memory impact. **Status: Partially implemented.** launchd reports the helper running, but no sustained resource measurement was performed and it has many open handles to deleted storage.
- [ ] Use the app for weeks without unexplained database growth or duplicated screenshot storage. **Status: Blocked from verification.** Retention services exist, but current live storage was moved to Trash and the canonical path is empty.

## 58. Complete planning-to-completion journey

- [ ] Open Zoid Coach at the start of the day. **Status: Fully implemented.** Installed Build 8 opens to a usable Today dashboard with live agent state.
- [ ] Review eligible Reminders. **Status: Fully implemented.** The installed Today dashboard shows real incomplete Reminders and a full unplanned inventory.
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
- [ ] Correct the session if Zoid Coach is wrong. **Status: Not implemented.** No behavior-session correction interface exists.
- [ ] Save an appropriately scoped rule if the same context will recur. **Status: Not implemented.** Settings expose application categories, not a correction-to-rule scope preview and save flow.
- [ ] See future matching activity handled according to the correction. **Status: Not implemented.** The prerequisite correction and learned-rule flow is absent.

## 62. Complete degraded-mode journey

- [ ] Begin a planned workday with all sources healthy. **Status: Partially implemented.** Reminders and Screenwatch appear current, but the canonical database is empty and background verification fails.
- [ ] Lose Screenwatch activity during an active task. **Status: Blocked from verification.** Disrupting the user's real capture service was unnecessary and the current storage state already prevents clean recovery proof.
- [ ] See a source warning and prompt suppression. **Status: Partially implemented.** Freshness warnings and suppression policies exist, but a live outage was not induced.
- [ ] Continue manually tracking the active task. **Status: Partially implemented.** Active commitments continue independently of Screenwatch, but pause and full manual timing controls are incomplete.
- [ ] Lose notification availability before a prompt. **Status: Blocked from verification.** Notification authorization was not changed during the audit.
- [ ] Receive the prompt through notification or dashboard instead. **Status: Partially implemented.** Prompt inbox fallback exists, but notification-loss routing was not exercised end to end.
- [ ] Resolve the prompt once from the available surface. **Status: Partially implemented.** Idempotent prompt response infrastructure is tested, but no live degraded-mode episode was resolved.
- [ ] Recover Screenwatch and notification delivery. **Status: Blocked from verification.** Safe live service disruption and recovery were not attempted.
- [ ] See source health return to normal without losing the plan or duplicating actions. **Status: Partially implemented.** Recovery logic exists, but current storage continuity makes this unreliable across restart.
- [ ] Confirm a review that clearly identifies the missing coverage period. **Status: Not implemented.** No functional review confirmation path exists.

## 63. Complete correction-and-learning journey

- [ ] Finish a day containing an incorrectly classified session. **Status: Barely started.** Behavior evidence is collected, but a user-visible classified daily session history is absent.
- [ ] Open the daily review. **Status: Not implemented.** The Reviews navigation item does not render a review workflow.
- [ ] Find the incorrect session and reclassify it. **Status: Not implemented.** No session correction UI exists.
- [ ] Split or attach the session to a task if needed. **Status: Not implemented.** No split, merge, or task-attachment controls exist.
- [ ] See totals and review language update. **Status: Not implemented.** Review corrections and narratives do not exist.
- [ ] Reject an unsupported causal hypothesis. **Status: Not implemented.** No hypothesis review UI exists.
- [ ] Confirm the corrected review. **Status: Not implemented.** No review confirmation state exists.
- [ ] Complete enough well-covered days for a weekly review. **Status: Barely started.** Daily evidence and learning aggregates exist, but weekly review generation is absent.
- [ ] Inspect the evidence behind a weekly pattern. **Status: Not implemented.** No weekly pattern surface exists.
- [ ] Accept, edit, or reject one proposed experiment. **Status: Not implemented.** No weekly experiment workflow exists.

## 64. Release 1 end-user acceptance

- [ ] Use real Apple Reminders for daily planning. **Status: Touches remaining.** The installed app displays real Reminders and builds plans, but permission-denied/manual fallback and canonical storage health remain incomplete.
- [ ] Use real Screenwatch activity for understandable behavior totals. **Status: Touches remaining.** Live behavior minutes and app-percentage disclosure are visible, but category totals, corrections, and reliable post-restart continuity remain incomplete.
- [ ] Use notifications or the Today dashboard for timely status and prompts. **Status: Partially implemented.** Both delivery surfaces exist, but the core gaming-drift coaching episode is not complete.
- [ ] Complete morning planning, task tracking, one gaming intervention, response, recovery, and review as one continuous flow. **Status: Not implemented.** Planning and task tracking are partial; gaming response, recovery, and review are missing.
- [ ] Use the app for seven consecutive days without losing plans, estimates, task sessions, corrections, or prompt responses. **Status: Blocked from verification.** The live database is unlinked and would be lost on agent termination; session corrections are not implemented.
- [ ] Complete the baseline week without unwanted behavior interruptions. **Status: Partially implemented.** Trust gates exist, but the original seven-day behavior-observation flow is not visible or verified.
- [ ] Understand every intervention and the evidence that caused it. **Status: Partially implemented.** Prompt context is stored and some UI explanations exist, but the core gaming intervention evidence surface is incomplete.
- [ ] Correct wrong classifications and see the product adapt. **Status: Not implemented.** No correction and learned-rule end-user flow exists.
- [ ] Pause or override coaching without punishment. **Status: Partially implemented.** Automation can be paused, but intentional gaming override and coaching-specific pause durations are incomplete.
- [ ] Continue using planning and task tracking when behavior sources fail. **Status: Partially implemented.** The architecture separates sources, but current live storage and incomplete manual controls prevent full proof.
- [ ] Export or delete personal data without hidden dependencies. **Status: Partially implemented.** Privacy data services and settings controls exist, but complete export/delete UI validation was not performed and current storage is split.
- [ ] Understand the product under missing data, denied permissions, restarts, and integration failures. **Status: Partially implemented.** Health and safety UI exists, but several failures have no complete repair journey and the real database failure is currently silent.
- [ ] Finish the week feeling that the next responsible action is easier to see and begin. **Status: Blocked from verification.** This outcome requires a stable week-long product trial after the critical storage and missing review/coaching flows are fixed.

## 65. Explicitly deferred end-user scenarios

- [x] Keep team workspaces, managers, shared permissions, and monitoring of other people out of Release 1. **Status: Fully implemented.** The installed app is single-user and local-first with no team or remote-admin surface.
- [x] Keep a public web dashboard out of Release 1. **Status: Fully implemented.** The product is a native local macOS app and has no public web dashboard.
- [x] Keep cloud screenshot synchronization off by default and outside the MVP. **Status: Fully implemented.** Screenwatch evidence remains local and no cloud screenshot-sync feature is exposed.
- [x] Keep mobile and cross-device behavior correlation outside the MVP. **Status: Fully implemented.** No mobile companion or cross-device behavior surface exists.
- [ ] Keep calendar auto-scheduling outside the MVP. **Status: Not implemented.** The current product explicitly supports autonomous Calendar planning and exposes `ACCEPT BLOCKS`, so this deferred constraint has been superseded rather than satisfied.
- [x] Keep automatic multi-task Reminder decomposition outside the MVP. **Status: Fully implemented.** The app plans existing tasks and does not expose automatic decomposition into multiple new Reminders.
- [x] Keep hard application or website blocking outside Release 1. **Status: Fully implemented.** No blocking controls or enforcement service are present.
- [ ] Require any future blocking to be explicitly enabled, reversible, time-bounded, and protected by an escape hatch. **Status: Barely started.** General policy, approval, undo, and pause patterns exist, but no blocking-specific contract or UI can yet prove these safeguards.

## Section summary

- Fully implemented: 8
- Touches remaining: 20
- Frontend only left: 0
- Partially implemented: 55
- Barely started: 9
- Not implemented: 38
- Blocked from verification: 14
