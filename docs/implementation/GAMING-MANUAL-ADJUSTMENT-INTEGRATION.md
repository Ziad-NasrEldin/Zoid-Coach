# Gaming Manual Adjustment And Session Merge Integration

This integration candidate is based on canonical commit `35e61ab55f3eb487934d9a2800f20ab93b2a2893`.

The database migration sequence is contiguous through version 49.

- Migration 47 owns `review_hypothesis_promotions`.
- Migration 48 owns `gaming_manual_adjustments`.
- Migration 49 owns `daily_review_session_merges`.

The gaming product delta comes from candidate `27601ab8c7879b0b837bb40519b83dd268dce525` relative to its review-integrated base `60fa73c`.

The session merge product delta comes from candidate `c8a72ce35ffa8fad624bc0ad235ec82cf19b709b` plus repair `e2b9c8f9158952115720657384c70743ecc052d6`.

The migration, privacy, and migration-test files intentionally contain the union of both candidates.

The privacy inventory includes gaming adjustments with planning data and session merges with review-learning data.

Full review-learning deletion removes review promotions and session merges.

Date-range deletion removes gaming adjustments and session merges for the selected local-day range.

The integration gates are the focused migration suite, affected gaming and session-merge suites, a release build, and installed signed end-to-end verification.

Do not ship this candidate until those gates pass and the canonical tracker is updated with the signed evidence.
