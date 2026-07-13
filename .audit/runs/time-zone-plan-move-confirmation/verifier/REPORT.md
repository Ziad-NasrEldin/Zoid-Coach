# ZC-053-010 Time-Zone Local Plan-Day Confirmation Verification

## Verdict

The scenario advances from **Not implemented** to **Touches remaining**.

The confirmation boundary is implemented and deterministic integration coverage proves its safety behavior.

The scenario is not fully implemented because the signed installed-app run could not drive the native time-zone Picker to a cross-day target and therefore could not visibly complete the warning, Cancel, Confirm, database, and relaunch sequence.

## Revisions

- Authoritative baseline: `8665ab3b7c6b4d631ed9decda9fde4d8af9243d7`.
- Candidate source revision: `55544ce97b631c0c9249a0920dea2c52d706b0b6`.
- Independent verifier source revision: `31992e9780b52ed05668512c0ae2ac00c171321d`.
- Integration candidate revisions: `26d40f0` and `99dde56`.

The candidate backlog edit was excluded from integration.

## Implemented behavior

- `TimeZonePlanMoveInspector` compares the source and destination local calendar days at one captured instant and counts plan entries on the source policy day.
- Settings pauses save only when the local day changes and the source day contains planned entries.
- The native alert names the entry count, source date and time zone, and destination date and time zone without exposing task titles.
- Cancel leaves the edited draft in place and does not create a durable policy version.
- Confirm repeats the inspection at the same reference instant and saves through the normal authenticated policy mutation boundary.
- Same-day changes and changes from an empty source plan save without an unnecessary warning.
- Inspection failure fails closed and reports the safety-check error.
- Stable accessibility identifiers exist for the confirmation and cancellation controls.

## Deterministic verification

- Real SQLite inspection proves a two-entry UTC plan at `2026-07-14T00:30:00Z` maps to the prior local day in `America/Los_Angeles` and reports exactly two affected entries.
- Controller tests prove Cancel preserves the durable policy and unsaved draft.
- Controller tests prove Confirm creates the new durable policy version while the plan remains on its historical source-policy day.
- A recreated Settings controller restores the confirmed destination time zone without silently moving the source-day plan.
- A DST transition test proves the inspector warns when the same instant crosses a local calendar day and does not warn after the spring-forward transition when both policies resolve to the same local day.
- Empty-plan, same-day, and inspection-failure paths are covered.
- The focused selection `swift test --filter "TimeZonePlanMoveInspector|timeZonePlanDayMove|timeZoneChange|confirmedTimeZonePlanDayMove"` passed.
- The broader `swift test --filter SettingsPolicy` selection passed.
- `swift build -c release` completed successfully.
- `git diff --check` passed before the verifier commit.

## Signed installed-app checkpoint

- A release QA package was created, signed, installed into an isolated location, and passed package identity checks.
- The isolated signed app created a real Today plan with one `daily_plan_entries` row for `2026-07-14`.
- Settings visibly exposed the saved and draft `Africa/Cairo` time zone for the running Mac.
- Accessibility inspection exposed the native Picker and its menu items.
- Same-process menu search, keyboard selection, and AX value-setting attempts did not change the Picker to `UTC` or `America/Los_Angeles`.
- No screenshot from this run is claimed as warning, Cancel, Confirm, or relaunch evidence.
- The QA LaunchAgent was unregistered and the isolated app, database, and temporary automation artifacts were removed after the capped run.

## Remaining acceptance gap

1. Install a signed isolated build with a plan on the current source-policy day near a controlled cross-zone date boundary.
2. Select a destination time zone that resolves the captured instant to another local calendar day.
3. Capture the warning with the correct entry count and privacy-safe source and destination dates.
4. Choose Cancel and prove that the durable policy remains unchanged while the edited draft remains available.
5. Save again, choose Confirm, and prove that the new policy persists without rewriting the historical source-day plan.
6. Restart both app and helper and prove the confirmed policy and truthful plan-day state remain visible.

Until that signed Picker sequence is complete, the scenario must remain unchecked and no higher than **Touches remaining**.
