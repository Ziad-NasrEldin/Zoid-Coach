# Onboarding schedule boundaries candidate

## Outcome

The onboarding schedule step now supports practical quarter-hour boundaries instead of forcing every work and quiet boundary to a whole hour.
It prevents invalid work windows before any policy mutation or onboarding advancement.

## End-to-end behavior

- Work start, work end, quiet start, and quiet end each expose separate hour and 15-minute controls.
- The coordinator loads existing minute values rather than silently rounding them to the hour.
- A work window with equal start and end is rejected with a specific message.
- A work window that crosses midnight is rejected because work windows must end later on the same day.
- Quiet hours may cross midnight.
- Equal quiet start and end is rejected as an empty quiet window.
- Continue remains disabled while the selected boundaries are invalid.
- A defensive coordinator guard also prevents invalid policy persistence if continuation is invoked outside the UI.
- Valid minute-precision values persist through the canonical policy mutation boundary.
- Stable accessibility identifiers cover every hour field, minute field, and validation result.

## Verification

- `swift test --filter classificationAndScheduleAreAppliedBeforeAdvancing` passed with 08:30-17:15 work and 21:45-06:30 quiet boundaries.
- `swift test --filter onboardingScheduleRejectsEmptyOrOvernightWorkAndAcceptsOvernightQuietHours` passed.
- `git diff --check` passed.

## Acceptance boundary

The candidate does not claim installed-app picker interaction or restart proof.
A fresh verifier should select non-default quarter-hour values in the signed onboarding UI, confirm invalid-state copy and disabled Continue, persist valid daytime and overnight boundaries, restart, and verify the exact four values plus runtime work-window and quiet-delivery behavior.
