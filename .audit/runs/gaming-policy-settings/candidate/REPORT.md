# Gaming policy Settings candidate

## Outcome

Settings now exposes the runtime gaming policy values that previously existed only in the stored model.
The user can set base daily gaming minutes and the one-time priority-objective completion reward without choosing a preset again.

## End-to-end behavior

- The Settings draft loads both values from the active `GamingPolicy`.
- The controls allow values from 0 through 1,440 minutes in five-minute steps, matching policy validation bounds.
- Saving writes both values through the existing authenticated, conflict-safe policy mutation boundary.
- Reopening Settings reconstructs the exact saved values.
- `GamingStatusCalculator` immediately uses the saved base and reward values for remaining allowance and the next-unlock explanation.
- Concurrent unrelated edits merge safely.
- Concurrent edits to the same gaming value retain the winning value and preserve the user's value for an explicit reapply.
- Explanatory copy distinguishes no allowance, fixed allowance, and priority-completion reward behavior without punitive language.

## Verification

- `swift test --filter SettingsPolicyDraftTests` passed the complete focused Settings draft suite.
- The focused round-trip test verifies 95 base minutes, a 25-minute completion reward, pre-completion remaining allowance, and post-completion unlocked allowance.
- The focused conflict test verifies independent merge and overlapping-value reapply behavior.
- `git diff --check` passed.

## Acceptance boundary

The candidate does not claim signed installed-app click-through.
A fresh verifier should exercise both steppers in the installed Settings window, save through the QA agent, reopen the app, and confirm the Today gaming allowance reflects the persisted values before tracker integration.
