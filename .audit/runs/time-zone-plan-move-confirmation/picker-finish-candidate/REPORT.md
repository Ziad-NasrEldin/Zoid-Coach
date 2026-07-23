# ZC-053-010 Signed Time-Zone Picker Finish Candidate

## Verdict

Recommend advancing ZC-053-010 from **Touches remaining** to **Fully implemented** after independent integration verification.

The native signed-QA journey now proves the complete visible warning, Cancel, Confirm, durable policy, unchanged historical plan, app/helper relaunch, and same-day no-warning paths.

## Revisions

- Authoritative baseline: `98777ae30df517178a104b02a998ed83d4f7f346`.
- Signed candidate source revision: `afd7980d2ed1c63d99a18ca694f2ecda50f1646c`.
- Signed build identity: `zoid-coach-afd7980d2ed1c63d99a18ca694f2ecda50f1646c-clean`.

## Implementation

The signed-QA Settings surface now includes a thin deterministic driver that changes only the existing time-zone draft binding.

The cross-day driver selects one of the fixed `Pacific/Kiritimati` or `Pacific/Pago_Pago` destinations only when its local date differs from the persisted source zone for the full five-minute stability window.

The same-day driver selects from fixed known zones only when its local date matches the persisted source zone for the full five-minute stability window.

Every save still uses the existing `SettingsPolicyController` inspection, native alert, authenticated policy mutation, Cancel, Confirm, and persistence implementation.

Production and unpackaged QA runtimes render no driver controls, and direct driver calls fail closed with no destination.

The signed controls expose stable accessibility identifiers without task titles:

- `settings.schedule.time-zone.qa-controls`.
- `settings.schedule.time-zone.qa-cross-day`.
- `settings.schedule.time-zone.qa-same-day`.

## Automated verification

`swift test --filter SignedQATimeZonePickerControl` passed.

The selection tests prove signed-package gating, fail-closed production and unpackaged-QA behavior, stable cross-day choices, stable same-day choices, and spring-forward plus fall-back boundary dates.

`swift test --skip-build --filter "TimeZonePlanMoveInspector|timeZonePlanDayMove|timeZoneChange|confirmedTimeZonePlanDayMove"` passed.

The existing focused coverage proves real SQLite plan counting, Cancel and Confirm semantics, unchanged historical plan rows, relaunch persistence, empty-plan behavior, same-day behavior, inspection failure, and DST boundary no-overprompt behavior.

`swift build -c release` completed successfully.

`git diff --check` passed.

Only the pre-existing `CodexJobCoordinator` immutable-variable warning and `VoiceAudioEngine` sendable-capture warnings appeared.

## Signed native journey

The isolated signed release opened directly at Today with 140 native Accessibility nodes and one visible 30-minute planned task.

The Settings screen exposed the saved `Africa/Cairo` zone, the signed-QA-only driver, and the exact clean build identity.

The cross-day control selected `Pacific/Pago_Pago` while the durable policy remained `Africa/Cairo`.

Save opened the native warning with one planned task, source day `2026-07-14` in `Africa/Cairo`, and destination day `2026-07-13` in `Pacific/Pago_Pago`.

The warning exposed the existing `settings.schedule.time-zone.confirm-plan-move` and `settings.schedule.time-zone.cancel-plan-move` actions and did not expose the task title.

Cancel returned to Settings with `The time-zone change was not saved. Your edits remain available to review.` and retained `Pacific/Pago_Pago` in the draft.

The database after Cancel remained policy version 1 with `Africa/Cairo` and retained the exact `2026-07-14`, `qa-ready-task`, rank 1, main-objective, 30-minute plan row.

Repeating Save opened the same truthful native warning.

Confirm saved policy version 2 through the installed helper and visibly reported `All changes saved`.

The database then contained active policy version 2 with `Pacific/Pago_Pago`, while the exact historical `2026-07-14` plan row remained unchanged.

The helper and foreground app were both stopped and relaunched.

Relaunched Settings visibly restored policy version 2 and `Pacific/Pago_Pago` with no unsaved state.

The live same-day driver then selected `America/Vancouver` from persisted `Pacific/Pago_Pago` at an instant when both zones resolved to `2026-07-13`.

Save completed directly as policy version 3 with no local-plan-day warning, proving the installed same-day no-overprompt path.

The DST no-overprompt boundary is proven deterministically in the focused selection tests rather than by changing the Mac clock during the signed run.

## Pixel evidence

- `evidence/01-today-seeded.png` shows the isolated ready-state task and plan.
- `evidence/02-settings-qa-controls.png` shows the signed-QA-only controls and saved source zone.
- `evidence/03-cross-day-draft.png` shows the cross-day destination in the unsaved draft.
- `evidence/04-cross-day-warning.png` shows the first privacy-safe native warning.
- `evidence/05-cancel-keeps-draft.png` shows Cancel status and the retained draft.
- `evidence/06-repeat-warning.png` shows the repeated warning before Confirm.
- `evidence/07-confirm-saved-v2.png` shows the confirmed policy version 2 state.
- `evidence/08-relaunch-retains-zone.png` shows the relaunched policy version 2 destination.
- `evidence/09-same-day-draft.png` shows the live same-day destination draft.
- `evidence/10-same-day-saved-without-alert.png` shows direct policy version 3 save without an alert.

## Cleanup

The QA LaunchAgent was unregistered.

The isolated foreground app and helper were stopped.

The isolated installed app and QA data root were removed.

No production data, application, policy, permissions, or launch service was changed.

The final free disk checkpoint was 4.0 GiB.

## Remaining review boundary

No functional or usability gap remains in the candidate evidence.

An independent verifier should integrate the source and evidence commit, confirm the signed build revision, and then update the tracker and registry atomically.
