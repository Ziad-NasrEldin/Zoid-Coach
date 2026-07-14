# Gaming Manual Adjustment Integration

This repair branch is based on candidate `8cfeda1622c4202a8141a579d0452ec9e02d74ee` and intentionally does not include the independent review-hypothesis candidate.

The canonical branch currently ends at database schema version 46.

The review-hypothesis candidate owns migration 47 and must land before this repair.

This repair reserves migration 48 for `gaming_manual_adjustments`.

Do not ship or install this branch directly because its isolated migration list intentionally omits the independently owned migration 47.

After the review candidate lands, rebase this repair onto that integrated commit and resolve these four overlapping files:

- `Sources/ZoidCoachInfrastructure/AutonomousDatabaseMigrator.swift` must retain the review-hypothesis table as migration 47, retain the gaming manual adjustment table as migration 48, and keep `currentVersion` at 48.
- `Sources/ZoidCoachInfrastructure/PrivacyDataService.swift` must retain the review promotion inventory and learned-data deletion entries while also retaining the gaming adjustment inventory and date-range deletion entries.
- `Sources/ZoidCoachCore/TodayDashboard.swift` must retain the review work-category additions and the gaming manual allowance fields and recomputation behavior.
- `Tests/ZoidCoachAppTests/AutonomousDatabaseMigratorTests.swift` must use the final contiguous migration sequence through version 48, retain the dedicated review migration 47 test, and retain the dedicated gaming migration 48 test.

After conflict resolution, every migration expectation that temporarily skips version 47 on this isolated branch must return to the final contiguous sequence.

The integration gate is the focused gaming adjustment, gaming drift, privacy, and migration suites followed by the affected full suite, release build, and installed signed end-to-end journey.
