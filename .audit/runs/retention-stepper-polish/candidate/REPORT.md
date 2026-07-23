# Retention Stepper Polish Candidate

## Candidate

- Candidate commit: `6d30d2639b15d3878b2addf40afdb6771628c638`.
- Canonical base: `5441cd1358add34be93899f03628b11bb2ba3a55`.
- Affected scenario: `ZC-047-006`, configure retention separately for raw records, sessions, prompts, reviews, and diagnostics.
- Scenario status remains `Touches remaining` until signed installed-app save, discard, and relaunch persistence are visibly verified.

## User-facing correction

The seven retention controls now use an adaptive Settings-local grid instead of forcing four controls into one narrow row.

Each retention value keeps at least 72 points of value space at the 160-point minimum column width and remains on one line.

Each increment and decrement action retains a 44 by 44 point hit target.

The value, increment, and decrement elements expose stable accessibility identifiers derived from the retention category.

The direct Settings bindings and existing zero through 3,650 day bounds remain unchanged, so Save and Discard continue to use the existing policy controller.

The shared Sumi stepper, AI budget panel, signed-QA time-zone controls, prompt infrastructure, and menu-bar surfaces were not changed.

## Automated verification

Four focused tests passed, covering constrained adaptive column counts, single-line retention copy, stable accessibility identifiers, bounded mutation, and the nearest Settings policy retention round trip.

One release build passed and produced both `ZoidCoach` and `ZoidCoachAgent` release executables.

`git diff --check` passed.

Only existing unrelated compiler warnings were present.

## Signed verification remaining

A serialized isolated signed-runtime verifier must inspect the retention controls at the 1,180 by 760 default window and at a narrower supported width.

The verifier must confirm that 90-day and 365-day values remain readable without vertical wrapping or horizontal overflow, that accessibility identifiers and labels remain reachable, and that editing, Discard, Save, and app plus helper relaunch preserve canonical behavior.
