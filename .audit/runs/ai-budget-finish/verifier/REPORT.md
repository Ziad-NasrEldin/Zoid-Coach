# ZC-046-006 Signed Runtime Verification

## Result

Candidate `ffb95c3c1f792cd441448b28ce41f6052da84ada` passed the bounded signed installed-app verification completed in this run.

The scenario remains `Touches remaining` until a separate verifier performs the destructive confirmation that this run was not permitted to activate without a fresh human confirmation.

## Signed package identity

- Installed application: `/private/tmp/zc046006-install/Zoid 666 QA E2E.app`.
- Isolated data root: `/private/tmp/zc046006-runtime`.
- Visible build identity: `ZOID-COACH-FFB95C3C1F792CD441448B28CE41F6052DA84ADA-CLEAN`.
- Visible policy advanced from version 1 to version 2 after saving 110 daily and 3,100 monthly requests.
- App and helper were killed, relaunched, and restored policy version 2 with both values unchanged.

## End-user proof

- The signed Intelligence screen visibly exposed distinct daily and monthly controls.
- The screen visibly stated that one shared budget covers all providers and models and that switching cannot reset or bypass it.
- The screen displayed canonical saved usage separately from unsaved edited values.
- Editing both limits exposed `DISCARD CHANGES` and `SAVE CHANGES` together.
- Discard restored 100 daily and 3,000 monthly requests, removed the dirty state, and announced that all unsaved Settings changes were discarded.
- Saving 110 daily and 3,100 monthly requests produced policy version 2 and restored both values after app and helper relaunch.
- Three isolated canonical `model_runs` rows covering Ollama `llama3`, Codex `gpt-5`, and Codex `gpt-5.6` appeared as one shared `3 / 110` daily and `3 / 3,100` monthly count.
- Saving daily limit zero produced policy version 3 and visibly changed the status to disabled.
- The disabled status explicitly preserved local planning, tracking, coaching rules, and reviews and stated that no paid request is sent.
- The clear-history confirmation explicitly warned that deleting AI request history immediately resets counted daily and monthly usage and may allow requests again.
- Cancel closed the warning and preserved all three canonical request rows in both the UI and database.

## Accessibility and privacy

- Stable accessibility identifiers remained present for daily limit, monthly limit, saved status, local fallback, clear history, and discard.
- The accessibility tree exposed aggregate counts and policy-safe copy only.
- No prompt content, hashes, diagnostics, credentials, provider secrets, or transmitted context appeared in the budget status.

## Pixel review

- The budget status card, reset copy, disabled fallback, and clear-history action were readable without clipping or overlap.
- `budget-panel-layout.png` records the visible signed disabled state.
- `shared-provider-usage.png` records the signed screen after cross-provider aggregation.
- `clear-history-warning.png` records the truthful destructive warning.
- `disabled-local-fallback.png` records the no-paid local fallback.
- `saved-budget-status.png` records the initial signed status.
- A pre-existing adjacent retention-control wrapping defect remains visible at the constrained viewport and is outside this no-further-scope candidate.

## Remaining boundary

The destructive `DELETE AI METADATA` confirmation was not activated because graphical local-data deletion requires a fresh action-time human confirmation.

A separate verifier must confirm that one destructive click routes through the running helper, clears the canonical model-run rows, refreshes saved usage to zero, preserves policy limits and Keychain credentials, and survives relaunch.
