# ZC-046-006 Independent Verification

## Result

Candidate `b8c2421` independently passes the non-destructive AI request-budget flow in a signed installed application.

The scenario remains `Touches remaining` because the destructive `DELETE AI METADATA` confirmation was deliberately not activated without fresh action-time user approval.

## Standards

- The focused `AIBudgetStatusServiceTests|SettingsPolicyDraftTests` suite passed 43 of 43 tests.
- One clean release build exited successfully and produced both `ZoidCoach` and `ZoidCoachAgent` release executables.
- The signed QA package passed deep strict code-signature verification and launched its isolated application and helper from the installed bundle.
- The Settings controls exposed stable accessibility identifiers and truthful aggregate values.
- The accessibility surface did not expose seeded row identifiers, input hashes, provider-specific secrets, model-specific secrets, prompt content, diagnostics, or credentials.
- The destructive warning is readable, visually centered, unclipped, and provides distinct Cancel and destructive actions.
- The candidate's constrained-width evidence shows a pre-existing adjacent retention-stepper wrapping defect where day labels break across multiple lines.
- That adjacent visual defect does not block the AI budget controls, but it should remain in the UI polish backlog.

## Spec

- The signed Settings screen exposed separate daily and monthly controls with saved values of 100 and 3,000 requests.
- Incrementing both controls exposed `DISCARD CHANGES` and `SAVE CHANGES` together.
- `DISCARD CHANGES` restored the complete canonical values to 100 and 3,000, removed the dirty actions, and announced that all unsaved Settings changes were discarded.
- Saving 110 daily and 3,100 monthly requests advanced the canonical policy to version 2.
- Killing and relaunching both the application and helper restored 110 daily and 3,100 monthly requests from the isolated canonical database.
- The status explained that one shared budget covers all providers and models and that switching cannot reset or bypass it.
- Three canonical rows spanning Ollama `llama3`, Codex `gpt-5`, and Codex `gpt-5.6` appeared as one shared `3 / 110` daily and `3 / 3,100` monthly count.
- The visible reset copy reported local reset times and explicitly stated that enforcement uses UTC boundaries.
- Saving the daily request limit as zero advanced the policy to version 3 and displayed `AI REQUESTS OFF`.
- The disabled state preserved local planning, tracking, coaching rules, and reviews and explicitly stated that no paid request is sent.
- Opening Clear AI Cache and Request History disclosed that model-run metadata, cached responses, Codex jobs, and transmission receipts would be deleted.
- The warning truthfully disclosed that deletion immediately resets daily and monthly counted usage and may allow requests again while leaving Keychain credentials unchanged.
- `CANCEL` closed the warning and preserved all three canonical `model_runs` rows and both visible aggregate counts.

## Enforcement parity

`AIBudgetStatusService` and `ModelRunStore` both count the provider-agnostic `model_runs` table from UTC day and month lower bounds.

The status service additionally limits each query to the current period's upper reset boundary, which prevents future-dated rows from being shown in the current period.

The implementation therefore matches the shared provider and model enforcement bucket for ordinary canonical rows.

## Remaining acceptance boundary

The destructive confirmation still requires a separately authorized verifier to prove that one click clears canonical AI metadata through the running helper, refreshes usage to zero, preserves saved limits and Keychain credentials, and survives relaunch.

No production application, production database, or production credential state was touched.

The isolated signed runtime, isolated data root, installed QA bundle, package build output, and temporary verifier build products were removed after the lease.

## Evidence

- `disabled-shared-usage.png` records the signed version-3 Settings state after the disabled budget was saved.
- `clear-history-warning.png` records the signed destructive warning before Cancel.
- The focused test run passed 43 tests.
- The independent signed AX transcript observed `TODAY  3 / 110 REQUESTS`, `THIS MONTH  3 / 3,100 REQUESTS`, `TODAY  3 / 0 REQUESTS`, and the no-paid local fallback.
- The isolated database contained exactly three seeded `model_runs` rows after Cancel.
