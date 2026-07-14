# ZC-047-006 Retention Control Signed Verification

## Result

Candidate `6d30d2639b15d3878b2addf40afdb6771628c638` passed the bounded signed installed-app retention-control verification.

ZC-047-006 remains `Touches remaining` because this polish proves readable controls and one canonical save, discard, and relaunch path but does not complete every separately configured category journey required by the broader scenario.

## Signed package

The clean release candidate was packaged, deeply signature-verified, installed, and launched with an isolated application, helper, data root, and LaunchAgent identity.

No production application, database, helper, or credential state was touched.

## Pixel proof

At the signed 1,180 by 760 default window, the adaptive grid rendered three equal columns and displayed 30 DAYS, 14 DAYS, 90 DAYS, and 365 DAYS on one line without clipping, overlap, or horizontal overflow.

At a signed 980 by 760 narrower window, the grid adapted to two columns and kept all seven category labels, values, 44-point adjustment targets, and the retention disclosure readable without vertical value wrapping or horizontal overflow.

`default-retention-grid.png` and `default-retention-bottom.png` record the default-width grid.

`narrow-retention-grid.png` records the complete narrower grid.

## Accessibility proof

The signed accessibility tree exposed stable value, decrement, and increment identifiers for Screenshots, Extracted text, Diagnostics, Behavior records, Task sessions, Prompts, and Reviews plus learning.

The accessibility values remained complete single-line phrases including `BEHAVIOR RECORDS, 90 DAYS`, `TASK SESSIONS, 365 DAYS`, and `REVIEWS + LEARNING, 365 DAYS`.

The decrement and increment controls exposed category-specific action labels instead of ambiguous plus or minus labels.

## Discard, save, database, and relaunch proof

Incrementing Behavior records changed the visible value from 90 to 91 days and exposed Discard Changes and Save Changes.

Discard Changes restored Behavior records to 90 days and announced that all unsaved Settings changes were discarded.

Incrementing Task sessions to 366 days and selecting Save Changes advanced the policy to version 2 through the running helper.

The isolated canonical `policy_versions` row stored `taskSessionRetentionDays` as 366 while preserving Behavior records at 90 and every other retention value.

After killing and relaunching both the signed application and helper, the narrower Settings grid restored Task sessions at 366 days, Behavior records at 90 days, and Reviews plus learning at 365 days through the same stable accessibility identifiers.

## Automated proof

Four focused tests passed for constrained layout, single-line copy, accessibility identifiers, bounded mutations, and the nearest Settings policy retention round trip.

One release build passed and produced both application and helper executables.

`git diff --check` passed.

## Cleanup

The isolated installed application, helper registration, runtime root, package output, and temporary build products were removed before the runtime lease ended.
