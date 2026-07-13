# Configurable Daily Review Time Candidate Report

## Scope

This candidate implements scenario `ZC-040-001` from the Settings control through persisted policy and daily review notification reconciliation.

It does not modify the authoritative scenario tracker, runtime state, claims registry, Lavish artifacts, Daily Review views, motion files, or `AgentMain.swift`.

## End-user behavior

- Settings now exposes a Daily review time alongside the planning times.
- The control has the stable accessibility identifier `settings.schedule.daily-review-time`.
- Supporting copy explains that reminders run on working days and defer until quiet hours end when necessary.
- Saving persists the local review time through the existing versioned policy path.
- Concurrent Settings edits merge the review time as its own conflict group.
- The agent's existing reconciliation loop consumes the current policy each pass.
- A changed time supersedes the pending reminder for the same local review day.
- If today's configured time has passed, the next working day is scheduled.
- Weekly reminders remain anchored to the final configured workday boundary.

## Compatibility

The new stored policy value is optional.

Existing policies without the field continue to schedule daily review at the workday end, including overnight work windows.

New default policies explicitly use 18:00 local time.

Opening and saving a legacy policy materializes its existing first work-window end as the visible review time.

## Verification

`swift test --filter ReviewReminderServiceTests` passed 8 tests.

`swift test --filter "UserPolicyTests|SettingsPolicyDraftTests"` passed 49 tests.

The focused proof covers configured-time delivery, quiet-hours deferral, next-working-day rollover, pending reminder replacement, duplicate-safe identity, legacy decoding, Settings round-trip, and legacy overnight scheduling.

## Independent verifier plan

1. Integrate the candidate onto the authoritative root.
2. Build and install the signed QA app without sharing runtime ownership with another lane.
3. Open Settings and set Daily review to a near-future local time outside quiet hours.
4. Save, close Settings, reopen it, and confirm the exact time persisted.
5. Confirm exactly one pending `DAILY_REVIEW` notification exists for the expected local day and delivery time.
6. Change the time and confirm the obsolete pending notification is replaced rather than duplicated.
7. Move the selected time into quiet hours and confirm delivery moves to the quiet-hours boundary.
8. Restart the helper and app, then confirm the saved setting and single pending reminder remain stable.
