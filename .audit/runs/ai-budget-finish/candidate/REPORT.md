# ZC-046-006 AI Budget Controls Candidate Report

## Candidate

- Scenario: ZC-046-006, set a daily or monthly request budget.
- Base revision: `2596f6e9c60bb6a7fad8f85003ccf17dea765236`.
- Worktree: `/private/tmp/zoid-666-zc046006`.
- Branch: `codex/zc046006-ai-budget-finish`.
- Candidate status: ready for independent signed installed-app verification.
- Tracker status remains unchanged until that verification is complete.

## End-user behavior added

- Settings shows saved daily and monthly usage beside the saved limits.
- The status explicitly says one shared budget covers all providers and models, so switching either cannot reset or bypass enforcement.
- Daily and monthly reset instants use the same UTC calendar boundaries as the existing enforcement and are displayed in the user's local time.
- Disabled and exhausted states state that local planning, tracking, coaching rules, and reviews continue and that no paid request is sent.
- Clearing AI cache and request history now warns that deleting model-run metadata immediately resets counted budget usage and may allow requests again.
- A visible `DISCARD CHANGES` action restores the complete canonical saved Settings draft and clears pending confirmation and conflict state.
- Existing `SAVE CHANGES` remains the only action that persists edited budget values.

## Privacy and accessibility

- The status service opens the canonical database read-only.
- It reads only the active policy and aggregate `model_runs` counts inside the existing enforcement windows.
- It does not read or display prompt content, input hashes, diagnostics, credentials, provider secrets, or transmitted context.
- Budget status, fallback, failure, discard, daily usage, and monthly usage controls have stable accessibility labels or identifiers.

## Test-first evidence

- Red AI budget compile reproduced the missing public behavior with `cannot find 'AIBudgetStatusService' in scope` in both new acceptance tests.
- Red discard compile reproduced the missing cancel behavior with `value of type 'SettingsPolicyController' has no member 'discardUnsavedChanges'`.
- The first combined green run found a real dirty-state defect after canonical draft restoration.
- `hasUnsavedChanges` now compares the editable draft against the canonical persisted editable draft, which makes discard truthful without rewriting preserved policy fields.

## Green verification

- `swift test --filter "AIBudgetStatusServiceTests|SettingsPolicyDraftTests"` passed 43 of 43 tests.
- `swift build -c release` passed in 74.12 seconds.
- `git diff --check` passed.
- Existing unrelated compiler warnings remain in `CodexJobCoordinator.swift` and `VoiceAudioEngine.swift`.

## Independent verification still required

- Install and launch a signed QA build under the serialized runtime lease.
- Verify the full Settings layout and accessibility tree at normal and constrained window sizes.
- Edit both limits, discard all changes, and prove the saved values remain unchanged.
- Edit both limits, save, relaunch the app and helper, and prove the saved values and status return.
- Seed or invoke different provider and model rows and prove they count toward the same daily and monthly bucket.
- Exhaust or disable the saved budget and prove the end-user sees the local fallback with no paid provider invocation.
- Confirm the AI history deletion warning, Cancel behavior, destructive confirmation, post-delete zero usage, and history reset disclosure.
