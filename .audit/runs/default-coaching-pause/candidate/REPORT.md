# Default coaching pause duration candidate report

## Scope

This candidate implements scenario `ZC-045-007`, which lets the user choose the duration used by the menu-bar Quick Pause action.

Settings now offers One Hour, Until Tomorrow, and Indefinitely in a visible segmented control with stable accessibility identifiers and explanatory copy.

The selection persists through the existing conflict-safe policy mutation boundary.

Independent concurrent Settings edits are preserved rather than overwritten.

Legacy policy payloads continue to use Indefinitely, which preserves the prior menu-bar behavior.

The menu-bar controller reads the latest saved policy immediately before every mutation, so changing the default does not require an app or helper restart.

One Hour resumes exactly sixty minutes after the confirmed action.

Until Tomorrow resumes at the next local midnight in the policy time zone.

Indefinitely remains paused until the user explicitly resumes coaching.

The menu-bar description, accessibility label, and confirmation message all state the effective duration before and after the action.

Settings retains its existing explicit one-hour, until-tomorrow, and indefinite buttons regardless of the Quick Pause default.

## Automated evidence

`swift test --filter DefaultCoachingPauseDurationTests` passed all 3 focused tests.

The focused tests cover legacy decoding, Settings persistence, validation, independent conflict merging, all three runtime durations, the policy time-zone boundary, current-policy reload, and user-facing menu copy.

`swift test --filter 'MenuBarCoachTests|SettingsPolicyDraftTests|UserPolicyTests'` passed all 58 affected regression tests.

`swift build -c release` completed successfully.

`git diff --check` completed successfully.

## Verifier plan

The verifier should rebase this candidate onto the latest authoritative tip.

The verifier should rerun the focused and affected automated tests after the rebase.

The verifier should acquire the runtime lease and install a signed QA build.

The verifier should open Settings, choose One Hour, save, and confirm the selection after closing and reopening Settings.

The verifier should use the menu-bar Pause action and confirm its visible description, accessibility label, persisted resume timestamp, and confirmation message all describe a one-hour pause.

The verifier should resume coaching, choose Until Tomorrow in Settings, save, and confirm that menu-bar Pause stores the next midnight in the configured policy time zone.

The verifier should restart both the app and helper, confirm that Until Tomorrow remains selected, and confirm that coaching automatically becomes active at the saved boundary.

The verifier should choose Indefinitely, save, and confirm that menu-bar Pause remains active across restart until Resume is selected.

The verifier should create an independent concurrent Settings edit and confirm that the default pause selection is preserved without duplicate policy versions.

The tracker should change only after the signed runtime proof is captured.
