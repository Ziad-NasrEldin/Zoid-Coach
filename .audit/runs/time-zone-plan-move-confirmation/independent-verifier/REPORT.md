# ZC-053-010 Independent Acceptance

## Verdict

Accept the candidate as fully implemented.

The signed installed app independently proved the cross-day warning, Cancel, repeated warning, Confirm, unchanged historical plan, foreground and helper relaunch persistence, and same-day no-warning path through the existing production settings controller.

## Candidate boundary

The verifier started from authoritative commit `261ec637605febf79d6e93f936cb2dedbf74c6d9` in a fresh isolated worktree.

Candidate commits `afd7980d2ed1c63d99a18ca694f2ecda50f1646c` and `a744b77b40e5cbcc0d69de331a1bdf2b31e4b189` transplanted without conflict.

The source change is limited to `SettingsView.swift`, `SignedQATimeZonePickerControl.swift`, and its focused test file.

The driver changes only the settings draft selection and delegates inspection, confirmation, cancellation, authenticated persistence, history preservation, and status reporting to the existing `SettingsPolicyController` path.

## Static and deterministic verification

`swift test --filter SignedQATimeZonePickerControl` passed.

That suite proves the control is available only when both runtime mode and packaged mode are signed QA, fails closed in production and unpackaged QA, chooses stable cross-day and same-day destinations, and covers spring-forward and fall-back dates.

`swift test --skip-build --filter "TimeZonePlanMoveInspector|timeZonePlanDayMove|timeZoneChange|confirmedTimeZonePlanDayMove"` passed.

The existing focused suite proves real SQLite plan inspection, Cancel and Confirm behavior, unchanged historical rows, relaunch persistence, same-day and empty-plan behavior, inspection failure, and DST no-overprompt behavior.

`swift build -c release` passed.

The only observed compiler warnings were pre-existing warnings outside the candidate files.

## Independent signed journey

The installed signed QA app exposed stable native accessibility identifiers for the cross-day driver, same-day driver, warning confirmation, and warning cancellation.

The source policy was version 1 in `Africa/Cairo` with one durable `2026-07-14` plan entry for `qa-ready-task`, rank 1, main objective true, and estimate 30 minutes.

The cross-day driver changed only the draft to `Pacific/Pago_Pago`.

Saving displayed a native warning that one planned task belonged to `2026-07-14` in `Africa/Cairo` and would map to `2026-07-13` in `Pacific/Pago_Pago`.

The warning did not reveal the task title or reminder identifier.

Cancel closed the warning, retained the unsaved draft, left active policy version 1 in `Africa/Cairo`, and left the exact plan row unchanged.

Saving again displayed the same truthful warning.

Confirm created active policy version 2 in `Pacific/Pago_Pago`, visibly reported `All changes saved`, and left the exact historical plan row unchanged.

The foreground app and installed helper were both stopped and relaunched.

Relaunched Settings restored `Pacific/Pago_Pago` from active policy version 2 without an unsaved state.

The same-day driver selected `America/Vancouver` for the current instant.

Saving completed directly with `All changes saved`, created active policy version 3, and exposed no plan-move alert or confirmation actions.

The historical `2026-07-14` plan row remained byte-for-byte equivalent in its user-visible fields after both saves and relaunch.

## Pixel evidence

- `evidence/01-settings-baseline.png` shows the signed Settings baseline.
- `evidence/02-cross-day-draft.png` shows the cross-day draft before saving.
- `evidence/03-cross-day-warning.png` shows the privacy-safe native warning.
- `evidence/04-after-cancel.png` shows the retained draft after Cancel.
- `evidence/05-repeat-warning.png` shows the repeated truthful warning.
- `evidence/06-confirmed.png` shows the confirmed saved state.
- `evidence/07-relaunch-persisted.png` shows the destination after app and helper relaunch.
- `evidence/08-same-day-saved-no-alert.png` shows the direct same-day save with no alert.

The evidence images are cropped to the Zoid 666 window so unrelated desktop content is not retained.

## Cleanup

The isolated foreground process and helper were stopped.

The signed QA app, LaunchAgent, isolated data root, and isolated install root were removed.

No production application, data, policy, permission, or launch service was changed.

## Remaining gaps

No functional or end-user usability gap remains for ZC-053-010.

The tracker and registry were intentionally not edited in this verifier worktree.
