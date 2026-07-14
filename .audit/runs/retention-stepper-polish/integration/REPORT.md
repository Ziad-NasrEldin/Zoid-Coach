# ZC-047-006 Retention Polish Integration

## Integration boundary

- Canonical base: `ac2fabda7d8231d7e7001c59af0bd9ab3536d20b`.
- Accepted source and evidence tip: `029251998de889c3fca88902c52ee5e4c4830ea1`.
- Rebased integration source and evidence tip before tracker integration: `20ce83c9780e72d70a8da3b70f5e1550637c4e9c`.
- The accepted and integrated `SettingsView.swift` and `SettingsRetentionControlsTests.swift` blobs are identical.
- The transplant applied without conflicts, and canonical had no intervening changes to either product path.

## Focused test

`swift test --filter SettingsRetentionControlsTests` passed.

The focused suite ran three tests covering constrained adaptive columns and single-line values, stable category-specific accessibility identifiers, and bounded retention adjustments.

The durable focused output is `focused-test.log`.

## Preserved signed evidence

The independent signed run already proved the three-column default and two-column narrow layouts, readable values, 44-point actions, stable accessibility identifiers for all seven categories, a discarded Behavior records change, a saved Task sessions change, exact database persistence, and app plus helper relaunch restoration.

The signed runtime was not repeated during integration.

## Scenario decision

ZC-047-006 remains `Touches remaining` with no count change.

A distinct saved-and-reloaded end-to-end journey for every remaining retention category is still required before the broad separate-retention scenario can be checked as fully implemented.

The registry validates exactly 666 scenarios, and all 48 scenario registry tests pass.

The generated Lavish audit contains exactly 666 rows with counts unchanged at 179 fully implemented, 298 touches remaining, 100 partially implemented, 27 blocked from verification, 3 frontend only left, 51 not implemented, and 8 barely started.
