# Weekly Review Independent Verification

## Candidate

- Candidate implementation commit: `7486772`.
- Verifier correction commits: `9b43971` and `3732d8b`.
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

## Pending Integration Gates

- Rebase the verified slice onto the final morning-planning root tip.
- Run the full Swift suite with the root-approved worker count or proven fallback.
- Run all 42 Python tests.
- Produce a release build and a signed QA package under the exclusive package/runtime lease.
- Seed limited and sufficient prior-week fixtures and visibly inspect the Weekly Review surface.
- Expand one pattern's evidence, edit and accept the single experiment, relaunch to confirm tracking, reject it, and relaunch again to confirm the rejected state.
- Update the authoritative tracker, registry, evidence paths, and Lavish report only after those gates pass.
