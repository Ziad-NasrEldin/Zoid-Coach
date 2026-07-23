# Dashboard Prompt Task Start Verification

## Result

`ZC-016-003` advances from Barely started to Touches remaining.

Focused persistence and presentation proof establishes the complete prompt-response behavior, but the signed fixture could not render a dashboard prompt action for native activation.

## Automated proof

- `dashboardPromptStartsRecommendedTaskOnceAndProvidesVisibleOutcome` passed.
- `dashboardPromptStartOutcomeUsesHonestFallbackAndIgnoresOtherActions` passed.
- `gamingPromptReturnActionStartsTheNamedTaskExactlyOnce` passed.
- `coachingTaskActionsApplyExactDurationsAndNeverReplay` passed.
- One QA release package passed app and helper builds, package coherence, signing, LaunchAgent, and Mach-service validation.

## Proven behavior

- The dashboard prompt response routes `startRecommendedTask` through the canonical serialized task-start boundary.
- Dashboard and notification replay apply one task-start effect and one active interval rather than duplicating work.
- Today refreshes before the outcome is computed.
- The neutral `<task> is active in Today.` message appears only when the refreshed active task identifier matches the task requested by the prompt.
- VoiceOver receives the same confirmed state change.
- A missing title uses a safe generic confirmation.
- A stale mismatched task, unrelated action, or replay cannot present a misleading start confirmation.

## Signed runtime boundary

- The installed signed ready-state app loaded Today and exposed the known `qa-ready-task` Reminder.
- The ready-state fixture contract contains OS notifications but no prompt-episode seed seam.
- A direct isolated prompt-row seed was rejected by the prompt decoder, so the installed UI truthfully displayed `Decisions could not be refreshed` and no prompt Start action.
- `prompt-fixture-unavailable.png` records that exact signed state.
- The runtime leg stopped without substituting the unrelated unplanned Start action or claiming native activation, replay, or relaunch persistence.

## Remaining acceptance

A supported deterministic prompt fixture must render the task-named Start action in the installed app, after which native accessibility must prove the single active Today state, neutral confirmation, replay idempotency, and relaunch persistence.
