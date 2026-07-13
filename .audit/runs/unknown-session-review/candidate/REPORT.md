# Unknown session review candidate

## Scope

This candidate implements the end-user review surface for `ZC-045-011`, `ZC-046-010`, `ZC-061-004`, `ZC-061-006`, `ZC-061-007`, and `ZC-061-008`.
It does not change tracker status because installed UI and running-agent acceptance belong to a fresh verifier.

## User-visible behavior

- Reviews now separates Unknown sessions from classified activity instead of burying uncertainty in one undifferentiated list.
- The queue shows the exact pending-session count and rounded duration while preserving chronological order.
- Neutral copy states that insufficient evidence caused the Unknown state and that Unknown is not distraction or a plan violation.
- The user may leave a session Unknown without creating a correction or learned fact.
- Each pending row shows only application, time range, duration, and observation count, with explicit confirmation that captured titles, URLs, screenshots, and guessed explanations are absent.
- A recognized session can be classified and optionally attached to a task through the existing durable correction boundary.
- The correction button is named `APPLY CLASSIFICATION` for Unknown evidence instead of implying that the user made an error.
- The existing future-rule option remains scoped to the application, previews its consequence, and cannot save Idle or Unknown as a lasting rule.
- After correction, the session leaves the Unknown queue, appears with classified activity, and updates corrected totals.
- The empty queue explicitly confirms that no classification decision is waiting.

## State and persistence

- `UnknownSessionReviewState` derives pending and classified sessions without mutating their stored classification.
- Pending and classified sessions receive stable chronological ordering with deterministic tie-breaking.
- Pending duration is derived only from Unknown sessions.
- Focused store proof corrects an Unknown Safari session to Work, attaches `Research`, saves the scoped future rule, reopens the database, and confirms that the queue remains clear while both correction and rule persist.
- Existing focused proof continues to reject Idle and Unknown future rules, preserve historical corrections when rules change, split only the selected session half, and reopen confirmed reviews after correction.

## Focused proof

- `swift test --filter DailyReviewTests` passed the complete Daily Review test file after the change.
- The targeted Unknown queue, correction, future-rule persistence, unsafe-rule refusal, and split-correction seams passed.
- A clean QA release package at candidate `59b0b7eba052322a24f0c19c2cdd8fcba8bd65d8` passed application and agent release builds, package identity checks, Mach-service checks, and strict code-signing validation.

## Fresh verifier plan

1. Rebase the candidate once onto the current authoritative root and rerun only Daily Review and classification-rule seams affected by the rebase.
2. Install one signed isolated QA application under an exclusive runtime lease.
3. Seed one Unknown Safari session, one Unknown Preview session, and one classified Cursor Work session using privacy-safe fixture labels.
4. Open Reviews and prove the two Unknown sessions appear only in the dedicated queue with the exact count, minutes, neutral uncertainty copy, and no captured content.
5. Prove the Cursor session appears only in Classified Activity Sessions and leaving Preview untouched creates no correction or rule.
6. Change Safari from Unknown to Work, attach it to the fixture `Research` task, enable the future app rule, and apply the classification.
7. Prove Safari immediately leaves the Unknown queue, classified totals update, Preview remains Unknown, and the active Safari-to-Work rule is visible.
8. Relaunch the application and prove the corrected session, task attachment, remaining Unknown queue, and active future rule restore without duplication.
9. Feed a later privacy-safe Safari observation through the running agent and prove it is classified Work by the scoped rule while an unrelated unknown application remains Unknown.
10. Remove the future rule, prove historical Safari correction remains Work, and prove a later Safari observation returns to normal policy classification.
11. Capture queue, correction, restored, future-match, and rule-removal evidence, then clean the isolated runtime.

The verifier must keep tracker, registry, and Lavish status conservative until the complete installed journey passes.
