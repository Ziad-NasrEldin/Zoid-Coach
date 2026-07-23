# Settings Working-Day Selection Candidate Report

## Scope

This candidate implements the missing working-day portion of `ZC-044-002` without modifying Today, Learning, onboarding, runtime consumers, or authoritative audit files.

## End-user behavior

- Settings shows seven locale-aware working-day buttons directly beneath work start and end.
- Every button exposes a stable identifier from `settings.schedule.weekday.1` through `settings.schedule.weekday.7`.
- Accessibility labels use the full localized weekday name and expose Selected or Not selected state.
- The final selected day cannot be removed, and its accessibility hint explains why.
- Supporting copy states that planning, scheduled reviews, and work-window coaching use the selected days.
- A changed day set is persisted through the existing versioned Settings mutation boundary.
- Independent concurrent edits merge safely, while two different working-day edits require the existing explicit conflict choice.

## Compatibility

Existing policies load the sorted union of every configured work-window weekday.

Changing only work start or end preserves every original weekday grouping.

Deliberately changing the weekday selection produces one schedule window that exactly matches the visible controls.

No UserPolicy schema or runtime consumer changed.

## Verification

`swift test --filter SettingsPolicyDraftTests` passed 33 tests.

The focused proof covers last-day protection, stable ordering, changed-day round-trip, advanced multi-window preservation, independent and overlapping conflict resolution, durable PolicyStore persistence, and a freshly persisted Tuesday-only schedule driving Tuesday's next daily review without restarting the app.

The full app and agent targets compiled as part of the focused Swift test build.

## Independent verifier plan

1. Integrate the candidate onto the authoritative root and build the signed QA app.
2. Open Settings and confirm the saved working days are visibly selected with complete accessibility values.
3. Select an initially unselected day and remove a selected day.
4. Attempt to remove every remaining day and confirm the final day stays selected.
5. Save, close Settings, reopen it, and confirm the exact day set plus start and end times persist.
6. Relaunch the app and helper and confirm the same policy version and day set remain.
7. Set only the next calendar day as a working day and confirm the next scheduled daily-review identity uses that date.
8. Confirm a non-working day does not produce work-window gaming coaching at the same local time.
9. Open two Settings windows, save distinct working-day edits, and confirm the existing conflict panel preserves the winner while Reapply My Changes deliberately saves the retry selection.
