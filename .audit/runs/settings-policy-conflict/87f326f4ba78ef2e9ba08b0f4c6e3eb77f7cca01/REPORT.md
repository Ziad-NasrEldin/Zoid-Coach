# Settings Policy Conflict UX Evidence

## Verified revision

- Commit: `87f326f4ba78ef2e9ba08b0f4c6e3eb77f7cca01`.
- Build identity: `zoid-coach-87f326f4ba78ef2e9ba08b0f4c6e3eb77f7cca01-clean`.
- Signed application: `.build/app-qa/Zoid 666 QA.app`.
- Isolated QA root: `/tmp/zoid-settings-conflict-87f326f`.

## End-user contract implemented

- A stale Settings window cannot overwrite a newer saved policy on its first save attempt.
- The visible conflict panel names the current winning policy version.
- The panel lists policy groups that changed elsewhere and separately identifies overlapping groups that require a decision.
- The safe draft retains the current winning value for every overlap.
- Independent local edits are rebased onto the winning policy and remain available to save.
- `KEEP CURRENT VALUES` dismisses the conflict without restoring stale overlapping values.
- `REAPPLY MY CHANGES` is the only path that deliberately reapplies stale overlapping edits.
- A second concurrent winner during reapply produces another decision instead of silently overwriting it.
- Failed and stale requests do not create duplicate policy versions.
- All conflict and status controls have stable accessibility identifiers for the parallel visible verifier.

## Affected scenarios

This batch provides the shared safe mutation boundary for Settings scenarios without claiming their feature-specific runtime journeys complete.

- `ZC-044-002` Set workday start and end times.
- `ZC-044-003` Set planning and review times.
- `ZC-044-008` Change included Reminder lists.
- `ZC-045-001` Choose the coaching mode.
- `ZC-045-004` Change quiet hours.
- `ZC-045-008` Review application rules.
- `ZC-045-012` Enable or disable screenshot analysis.
- `ZC-046-002` See that remote AI is off until explicitly configured.
- `ZC-046-003` Choose a future approved provider and model.
- `ZC-046-004` Choose local or remote processing when supported.
- `ZC-046-008` Disable AI without disabling local functionality.

## Automated proof

- `swift test --filter SettingsPolicyDraftTests` passed 20 focused tests.
- `swift test` passed 462 tests across five suites.
- `swift build -c release` passed.
- `python3 -m unittest discover -s Tests/ScenarioRegistryTests` passed 41 tests.
- `git diff --check` passed before the implementation commit.

The focused suite proves field-level disjoint merge, overlapping winner preservation, explicit reapply, repeated concurrent races, reminder-list rebasing, one-step pause isolation, durable exact receipts, and duplicate-free version history.

## Signed-QA package proof

The following command completed successfully from a clean implementation commit:

```sh
ZOID_COACH_PACKAGE_MODE=qa \
ZOID_COACH_QA_RUN_ROOT=/tmp/zoid-settings-conflict-87f326f \
CONFIGURATION=release \
Scripts/package-app.sh
```

Package verification proved coherent application, LaunchAgent, Mach service, signing identities, full clean build identity, and the `Zoid 666 QA` display name.

## Remaining independent verification

A parallel verifier should open two signed-QA Settings instances against the isolated QA root, create one overlapping and one independent edit, save the first instance, save the stale instance, inspect the conflict panel, exercise both decisions, relaunch, and compare the persisted winning policy and version history.
The authoritative tracker and registry remain unchanged until that visible proof passes.
