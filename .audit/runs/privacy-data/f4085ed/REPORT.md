# Zoid 666 privacy-data integration verification

The privacy-data slice was independently integrated onto `codex/full-system` and reviewed once at commit `f4085ed`.

## Verified implementation

- Settings exposes a content-safe inventory of every grouped local data class, database path, byte size, and schema version.
- Export shows a counts-only manifest before presenting a native JSON save panel.
- The exported payload excludes titles, conversation text, URLs, source paths, event names, raw payloads, screenshots, and credentials.
- Independent retention values cover screenshots, extracted text, behavior records, task sessions, prompts, reviews and learning, and diagnostics with optional migration-safe policy fields.
- Deletion commands are agent-routed, confirmation-backed, and independently scoped for a behavior session, today, an inclusive date range, raw behavior metadata, AI request metadata, learned data, or every user table.
- Inclusive deletion derives local calendar midnights and preserves a full 23-hour DST transition day.
- Date-range deletion removes both canonical and projected plan records for matching days while preserving adjacent days.
- Source screenshot files are never removed because privacy deletion issues database statements only.
- Keychain credentials are never removed because the privacy service has no Keychain dependency or credential mutation path.
- Delete-all preserves `schema_migrations` and SQLite system tables, and the empty migrated database can be reopened by runtime stores.
- Successful Settings deletion refreshes both Today and the local data inventory.

## Direct verifier fix

The original slice deleted only `daily_plan_entries` for a selected date range.

The verifier added deletion of canonical `daily_plans` and `daily_plan_items` plus all associated day-keyed planning projections, with a regression test proving the selected day disappears and the adjacent day remains.

## Gates

- Focused privacy, DST, and retention tests pass.
- Full Swift suite passes 445 tests in four suites.
- Scenario registry Python suite passes 38 tests.
- Release build passes.

## Remaining acceptance boundary

No signed helper installation scripts were touched because the parallel SMAppService lane owns that runtime surface.

The destructive Settings journeys and exported file still require visible packaged-app acceptance before these scenarios can be checked as fully implemented.
