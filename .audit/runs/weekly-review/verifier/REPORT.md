# Weekly Review Independent Verification

## Candidate

- Rebased candidate implementation commit: `36e1668`.
- Rebased verifier correction commits: `ff7b207` and `702ba5a`.
- Verification branch: `codex/verify-weekly-review`.

## Focused Findings And Corrections

- The original prompt-effectiveness query used the nonexistent `prompt_res_effects` table and `res_id` column, so prompt usefulness and recovery patterns could never appear from the canonical schema.
- The query now uses `prompt_response_effects.response_id`, fails visibly on a real database error, and has focused applied-prompt coverage.
- The original estimate pattern interpreted the aggregate's recommended estimate in minutes as an actual-to-estimate ratio.
- The original best-work-window pattern displayed the aggregate key, which is a timezone identifier, as though it were the learned time window.
- Estimate and work-window patterns now derive from eligible learning samples inside the stable previous-week window.
- Their evidence examples now name a local date, factual estimate or time interval, corrected aligned minutes or coverage, and avoid internal evidence identifiers.
- Stale and future learning samples are excluded by focused regression coverage.
- Recovery now reports the count of answered prompts followed by a correction-aware work session within 30 minutes while explicitly preserving the non-causal alternative explanation.
- Gaming evidence now includes corrected minutes and the first observed local gaming time for each sampled day.
- Repeated blocked-work evidence uses the local task title when available and never exposes an opaque task identifier.

## Focused Proof

- `swift test --filter WeeklyReview` passes six focused Swift Testing cases.
- `swift test --filter weeklyReviewMigration` passes the migration 31 preservation and uniqueness case.
- `git diff --check` passes.
- Migration ownership is preserved as version 28 for daily review, version 29 for task pauses, version 30 for offline work, and version 31 for weekly experiments.

## Integration And Release Proof

- The verified slice was rebased onto final morning-planning tip `c09bd1f` without changing migration ownership.
- The complete 4-worker Swift run, the serial fallback, and one fresh-scratch 4-worker run compiled successfully but each SwiftPM Testing helper remained idle with no worker process or CPU use.
- The runners were terminated under the no-third-cycle policy and this report does not claim a fresh full-suite pass.
- The focused weekly-review and migration tests remained green after the verifier corrections.
- `python3 -m unittest discover -s Tests/ScenarioRegistryTests -p "test_*.py"` passed all 42 tests.
- The release build completed successfully with only pre-existing concurrency and deprecation warnings outside this slice.
- The signed QA package passed coherent app, LaunchAgent, Mach-service, signing-identity, designated-requirement, and clean-build-identity verification.

## Visible Signed Acceptance

- The installed signed QA app first showed `DATA QUALITY SUMMARY 0/7 DAYS`, exact missing-day guidance, no patterns, and no experiment.
- After deterministic prior-week evidence was seeded, the same installed app showed `ENOUGH COVERAGE 7/7 DAYS` for 2026-07-04 through 2026-07-10.
- The signed review visibly showed 14 planned items, 525 estimated minutes, 5 completed items, a 36 percent outcome rate, and seven evidence-backed patterns.
- Estimate evidence expanded to three dated estimated-versus-corrected examples plus its alternative explanation.
- The single proposal was edited to `Make the first blocked step concrete`, saved, and accepted.
- Acceptance visibly showed `TRACKING 2/7 DAYS · START 2026-07-11`, and the accepted edited state survived app relaunch.
- The same experiment was rejected, active tracking disappeared, and the rejected edited state survived another app relaunch.
- The QA app, helper, isolated database, and runtime root were removed after acceptance so the shared package/runtime lease was released cleanly.
