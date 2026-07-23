# Maximum Intervention Level Candidate Report

`ZC-045-002` is ready for independent installed verification.
The candidate makes the existing persisted coaching level an explicit maximum intervention ceiling instead of presenting it as an ambiguous target.

## End-user behavior

Settings now labels the control `MAXIMUM INTERVENTION LEVEL` and exposes `settings.coaching.maximum-intervention-level` for accessibility automation.
The explanation states that the setting is a hard ceiling, not a target.
It explains that Gentle uses the lighter recovery prompt without the accountability-only break option.
It explains that Accountability may use the stronger recovery prompt and break option while remaining dismissible and bounded by the configured prompt cap and cooldown.
The first seven complete observation days remain explicitly quiet.

## Persistence and runtime boundary

`SettingsPolicyDraft.maximumInterventionLevel` is a single explicit alias over the existing durable `GamingPolicy.coachingLevel` field.
This avoids a second source of truth and keeps existing conflict-safe policy mutation behavior intact.
The gaming-drift producer reads that same persisted ceiling, chooses the gentle or accountability prompt presentation from it, and records `maximumInterventionLevel` in the durable prompt payload for review and diagnosis.
Gentle continues to omit the accountability-only break action and offers the lighter 10-minute recovery sprint.
Accountability may offer the break action when a task is actively tracking and uses the stronger 20-minute work sprint.

## Verification

`swift test --filter 'SettingsPolicyDraft|GamingDriftPromptService'` passed.
The focused proof covers policy round-trip, conflict-safe preservation, the explicit maximum-level alias, gentle prompt content, accountability prompt content, and the persisted prompt payload ceiling.
`swift build -c release` passed.

## Independent acceptance

In one signed Settings journey, select Gentle, save, relaunch, and confirm the same selected value and explanatory copy.
Generate an eligible gaming-drift prompt and confirm it uses the gentle title, 10-minute recovery sprint, and no break action.
Then select Accountability, save, relaunch, and generate a fresh eligible prompt while a task is active.
Confirm the stronger title, 20-minute sprint, and break option appear without exceeding the configured prompt cap or cooldown.
