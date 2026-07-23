# ZC-047-012 Disclosure Candidate Report

## Outcome

The Settings inventory, destructive confirmation, action label, positive result, and repeat-zero result now accurately disclose the complete review and learning deletion scope.
Every state also says that raw behavior records and task facts remain.

## User-visible Contract

- The inventory is titled `Reviews and learned rules` and counts all seven deleted tables.
- The inventory detail names daily and weekly reviews, personal notes, corrections, weekly experiments, learned app-classification rules, learning samples and aggregates, and planner trust cycles.
- The confirmation repeats the complete list, states that Cancel leaves everything unchanged, states that raw behavior and task facts remain, explains that learning restarts from defaults, and says the action cannot be undone.
- The destructive button is labeled `DELETE REVIEWS AND LEARNED RULES` in both Settings and the confirmation.
- A positive result reports the exact deleted-record count, uses correct singular or plural grammar, repeats the cleared categories, and states what remains.
- A repeated deletion reports `Nothing remained to delete`, says every category is already clear, and states what remains.

## Accessibility

- The Settings entry point exposes `settings.data.delete-reviews-learning` with a descriptive hint.
- The visible result exposes `settings.data.deletion-status` and expands vertically instead of clipping the complete disclosure.
- The destructive confirmation retains the shared keyboard-accessible Cancel and confirm controls.

## Verification

- `swift test --filter reviewLearningDeletion` passed.
- The focused seven-table inventory, deletion, preservation, restart, and repeat-zero test passed.
- `swift test --filter PrivacyDataServiceTests` passed.
- `swift build -c release` passed.
- `git diff --check` passed.

## Remaining Acceptance

An independent verifier must open the installed signed Settings surface with populated review and learning data, inspect the inventory, cancel once, confirm once, verify the refreshed zero inventory and preserved raw facts, repeat the action to see the zero state, relaunch the app and helper, and confirm the deletion remains complete.
Only the root integrator may update the authoritative tracker and registry after that verification.
