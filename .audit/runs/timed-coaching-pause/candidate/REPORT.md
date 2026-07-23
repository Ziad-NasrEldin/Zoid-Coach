# Timed coaching pause candidate

## Claim

- Primary scenario `ZC-039-001`: pause coaching for one hour.
- Primary scenario `ZC-039-002`: pause coaching until tomorrow.
- Primary scenario `ZC-039-003`: resume coaching before a timed pause expires.
- Primary scenario `ZC-039-004`: see clearly that coaching is paused and when it resumes.
- Related scenario `ZC-039-006`: provide focused rule evidence that existing prompt producers honor an active timed pause and automatically become eligible after expiry.

## Owned files

- `Sources/ZoidCoachCore/UserPolicy.swift`
- `Sources/ZoidCoachApp/Views/SettingsPolicyDraft.swift`
- `Sources/ZoidCoachApp/Views/SettingsPolicyController.swift`
- `Sources/ZoidCoachApp/Views/SettingsView.swift`
- `Tests/ZoidCoachAppTests/UserPolicyTests.swift`
- `Tests/ZoidCoachAppTests/SettingsPolicyDraftTests.swift`
- `Tests/ZoidCoachAppTests/GamingDriftPromptServiceTests.swift` is explicitly excluded because it belongs to the five-minute follow-up lane.
- `.audit/runs/timed-coaching-pause/candidate/REPORT.md`

## Exclusions

- The root worktree, installed runtime, tracker, scenario registry, Lavish artifact, backlog, and active-work ledger remain untouched.
- The five-minute gaming follow-up implementation files remain untouched.

## Planned acceptance

- Settings presents explicit one-hour, until-tomorrow, and indefinite pause choices.
- A one-hour pause persists an exact UTC resume boundary.
- An until-tomorrow pause resumes at the next local midnight in the configured policy time zone.
- Settings shows the active pause and a direct resume action.
- Resuming early persists the running state immediately.
- Expired timed pauses evaluate as running without requiring an app restart or cleanup write.
- Legacy indefinite and running policy JSON remains compatible.

## Evidence

- `AutomationPause` preserves the existing `isPaused` and `resumesAtUTC` JSON keys while retaining the requested pause separately from its wall-clock active state.
- `pausedForOneHour` persists an exact boundary sixty minutes after the user's choice.
- `pausedUntilTomorrow` persists the next local midnight using the configured policy time zone, including calendar-based day transitions.
- Existing consumers of `automationPause.isPaused` automatically evaluate an expired timed pause as running without a cleanup write or restart.
- Settings retains the exact pause boundary in its draft and policy mutation instead of collapsing every pause to indefinite.
- The one-hour, until-tomorrow, indefinite, and resume-now actions persist immediately without saving unrelated draft edits.
- The pause card refreshes its state every thirty seconds, shows the resume time in the configured policy time zone, and exposes stable accessibility identifiers for each action and status.
- The pause card explicitly states that task and behavior tracking continue while prompts and autonomous actions are paused.
- `swift test --filter UserPolicyTests` passed with exit code 0.
- `swift test --filter SettingsPolicyDraftTests` passed with exit code 0.
- `swift test --filter timedAutomationPauseHonorsExactBoundaryAndLegacyCodingShape` passed with exit code 0.
- `swift test --filter timedPauseChoicesPersistImmediatelyAndResumeWithoutSavingOtherEdits` passed with exit code 0 after the final schedule-time-zone formatting compile check.
- `git diff --check` passed.

## Conservative status recommendation

- Keep `ZC-039-001` below fully implemented until a verifier chooses the one-hour action in the signed app, confirms the durable boundary, and observes automatic expiry.
- Keep `ZC-039-002` below fully implemented until a verifier chooses until tomorrow in a non-UTC schedule and confirms the visible local boundary after restart.
- Keep `ZC-039-003` below fully implemented until a verifier resumes early from the signed app and proves prompt eligibility returns without saving unrelated settings.
- Keep `ZC-039-004` below fully implemented until the signed Settings card and its thirty-second boundary refresh are inspected visually and through accessibility.
- Treat `ZC-039-006` as partial only because this batch makes timed expiry available to existing suppression gates but does not cancel an intervention that was already delivered before the user paused.

## Independent verifier plan

- Rebase this candidate onto authoritative commit `bc16f7e` or its successor before verification.
- Run the focused UserPolicy and SettingsPolicyDraft suites from the rebased candidate.
- Package and install a clean signed QA identity without touching production data.
- Open Settings and confirm the coaching pause card is readable at the supported window sizes with no clipping or overflow.
- Choose pause for one hour and verify the visible configured-time-zone boundary and exact persisted UTC boundary.
- Restart both the app and helper before expiry and confirm the same active pause and resume boundary return.
- Keep task tracking and fixture behavior ingestion active during the pause and confirm their records continue to advance.
- Confirm no newly eligible coaching prompt or autonomous write executes while the pause is active.
- Resume early and confirm the policy becomes running immediately while unrelated unsaved draft edits remain unsaved.
- Choose until tomorrow under a non-UTC schedule and verify the next local midnight boundary across restart.
- Exercise a shortened deterministic timed pause and confirm Settings changes to running within its thirty-second refresh window and new prompt production becomes eligible.
- Update the tracker, registry, backlog, and Lavish artifact only from the authoritative root after signed proof passes.

## Known boundaries

- The shared automation pause also suspends autonomous writes, while the agent's ingestion and task-state pipelines continue.
- A coaching notification delivered before the pause is not recalled by this batch.
- Signed-app visual, accessibility, notification-suppression, and automatic-expiry proof remains assigned to the independent verifier.
