# Onboarding work-window verification

Candidate `1c30a680a844ba2f7974e4f210d4446ca35f9fb1` was independently applied on authoritative root `870c290`.

## Result

ZC-005-007 is fully usable on the signed onboarding Schedule step.

The user can choose any non-empty weekday subset, configure exact hour and minute boundaries, save through the agent, and recover the same values after relaunch.

The interface blocks Continue and explains the recovery action when no weekday remains selected.

## Focused proof

- `classificationAndScheduleAreAppliedBeforeAdvancing` passed and persisted Monday plus Saturday, 08:30 to 17:15, and 21:45 to 06:30 together.
- `onboardingScheduleRejectsEmptyWindowsAndAcceptsOvernightWorkAndQuietHours` passed and proved equal-window rejection, overnight acceptance, empty-weekday blocking, and one-day recovery.
- Code inspection confirmed that an existing non-quarter minute remains an available picker option and that legacy policies reload their stored first work-window weekdays.
- The release build passed.
- One clean release-configured signed QA package and install passed.

## Installed end-to-end proof

- Fresh onboarding visibly exposed all seven weekday controls with selected-state accessibility values.
- The signed journey selected only Monday and Saturday.
- It configured work from 08:30 to 18:15 and overnight quiet hours from 23:45 to 07:30.
- The summary visibly reported two selected days, same-day work, overnight quiet hours, and the Africa/Cairo timezone.
- Continue saved policy version 3 and advanced to the next onboarding step.
- The active policy stored weekdays `[2, 7]` and the exact configured work and quiet boundaries.
- Relaunching onto the saved Schedule step restored Monday and Saturday plus every exact boundary unchanged.
- Deselecting Saturday and then the final Monday changed the validation message to `Choose at least one work day.` and disabled Continue.

## Independent boundary noted

The first attempt to leave Activity Classification hit an existing cold-start policy-version race and showed `PolicyStoreError error 5`.

Relaunching after the helper had completed bootstrap restored the same onboarding step, and the retry saved normally.

This run does not claim that separate cold-start race as fixed.

ZC-005-008 remains below Full because this run proved quiet-hour configuration and persistence but did not traverse a real notification delivery boundary during the quiet window.
