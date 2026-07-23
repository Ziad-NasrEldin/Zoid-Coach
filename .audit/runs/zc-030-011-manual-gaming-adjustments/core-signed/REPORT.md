# ZC-030-011 combined signed verification

## Candidate

- Combined branch: `codex/verify-zc030011-combined`.
- Combined commit: `27601ab8c7879b0b837bb40519b83dd268dce525`.
- Base: `60fa73c1c8803a944b021fd1e5f6b78492a4402f`.
- Original gaming candidate: `8cfeda1622c4202a8141a579d0452ec9e02d74ee`.
- Gaming repair: `6fd281cee82aec6f86300f0a4baa98d054ff427d`.

## Integration union

- Review hypothesis promotions remain migration 47.
- Gaming manual adjustments are migration 48.
- `AutonomousDatabaseMigrator.currentVersion` is 48.
- Migration expectations are contiguous through 48.
- Review privacy inventory and deletion remain present.
- Gaming adjustment privacy inventory and date-range deletion are added.

## Automated gates

- 87 focused affected tests passed.
- The gate included migrations, gaming manual adjustments, gaming-drift suppression, privacy, review promotion persistence, and Weekly Review.
- Signed package creation passed.
- Nested and deep signing passed.
- Installed signature verification passed.
- LaunchAgent registration passed.
- Mach service and writable XPC verification passed.
- The canonical QA heartbeat passed.

## Signed end-user proof

- Today exposed an enabled `Adjust manually granted gaming time` action.
- The initial signed UI showed 60 minutes remaining.
- Selecting removal before any grant showed validation and left Save disabled.
- Adding the default 15 minutes with note `qa-grant` created one visible positive history entry.
- SQLite recorded one row with a unique request ID, local day `2026-07-14`, `15` minutes, the note, and a UTC timestamp.
- The signed UI recomputed allowance to 75 minutes and exposed `Manual +15m` in the breakdown.
- App and helper relaunch preserved exactly one entry and the 75-minute allowance.
- Removing 15 minutes with note `qa-remove` created one visible negative history entry.
- SQLite recorded exactly two append-only rows with values `15` and `-15`.
- A second app and helper relaunch preserved exactly two entries and a net adjustment of zero.
- The signed UI returned to 60 minutes remaining.

## Strict scenario classification at the time of this run

Status: touches remaining before the later negative-path and helper probes.

- The signed UI and database proved discoverability, invalid removal blocking, positive adjustment, negative adjustment, allowance recomputation, timestamps, append-only history, exactly-once persistence, and net persistence across app/helper relaunches.
- The focused production service test proved a manually granted allowance suppresses a gaming-drift prompt after store restart.
- The bounded signed run did not seed a complete real-agent gaming-drift episode and directly observe the helper suppressing that prompt.
- The focused tests proved stale-day rejection, time-zone rejection, and unavailable-ledger fail-closed behavior.
- Those three negative paths were not activated through the signed UI during this bounded run.

## Cleanup

- The QA LaunchAgent was unregistered and booted out.
- QA app and helper processes were absent after cleanup.
- QA data, install, ready-state, and build roots were removed.
- Production executable SHA-256 remained `111dca9ed4f31eef667ad0d497e454f51b5ea395ede6ff0116759f0f1bb3ea75`.
- Production CDHash remained `d76e35fb38e52e8733f563e13a65450718fc8871`.
- Production agent PID 53195 remained running with no recorded exit.
