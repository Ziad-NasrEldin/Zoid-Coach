# Local System Diagnostics Acceptance Evidence

## Scope

- `ZC-048-005` - See local database health, size, and last migration.
- `ZC-048-006` - See the current AI mode and recent provider failures.

## Implemented end-user behavior

- Source Health includes a Sumi-Ink Local System panel without requiring Settings or an external diagnostic tool.
- The database row reports a read-only integrity result, aggregate SQLite store size, current and expected schema versions, and the last migration time.
- A missing database is reported as not ready without creating a file.
- A corrupt or unreadable database fails closed, remains unchanged, and reports that it could not be verified.
- The AI row reports rules-only, local, CLI, on-device, or remote mode and explains the processing boundary.
- The five latest provider failures show only provider, state, time, and the already-redacted bounded diagnostic.
- Refresh reruns the read-only inspection and stable accessibility identifiers expose the loading, refresh, database, and AI states.

## Automated proof

- Focused tests: `swift test --filter LocalSystemDiagnosticsServiceTests` passed 3 tests.
- Full suite: `swift test` passed 465 tests in 5 suites.
- Release build: `swift build -c release` passed.
- Registry and evidence gates: `python3 -m unittest discover -s Tests/ScenarioRegistryTests -p "test_*.py"` passed 41 tests.
- Clean signed-QA packaging passed package, LaunchAgent, Mach-service, signing-identity, designated-requirement, and embedded clean-build-identity checks with run root `/tmp/zoid-666-local-diagnostics`.

## Independent installed-app acceptance

- The verifier packaged the exact candidate as signed-QA build `zoid-coach-79a4079ca989ebc0621fcbd602f524164b57150b-clean` with isolated root `/private/tmp/zoid-666-local-diagnostics-verifier`.
- The verifier opened the signed app through visible controls, exited setup to Today, and selected Source Health.
- Before storage existed, the Local System panel truthfully showed `NOT READY`, zero size, unavailable schema and migration, and unavailable AI policy without creating the database.
- After the signed agent initialized the isolated runtime, clicking the visible `REFRESH` control changed the database row to `HEALTHY`, `660 KB`, schema `29 of 29`, and the exact latest migration time.
- The AI row simultaneously reported `LOCAL OLLAMA`, `Processing stays on this Mac`, and no recorded provider failures.
- Closing and reopening the signed app returned directly to Source Health and preserved `HEALTHY`, schema `29 of 29`, the same migration time, and `LOCAL OLLAMA`; the aggregate store size truthfully advanced to `685 KB` as the running local runtime wrote additional state.
- Accessibility inspection exposed `source-health.local-system.refresh`, `source-health.local-database`, and `source-health.ai-mode`, and all text remained readable in the visible Source Health scroll surface.

## Independent verification gates

- Focused diagnostics tests passed 3 tests.
- The full four-worker Swift suite passed 469 tests in 5 suites.
- The Python registry and evidence suite passed all 41 tests.
- The release build passed.
- No correctness, privacy, accessibility, refresh, or restart blocker remained after the single lean verification pass.

## File boundary

- `Sources/ZoidCoachApp/Services/LocalSystemDiagnosticsService.swift`
- `Sources/ZoidCoachApp/Views/LocalSystemDiagnosticsView.swift`
- `Sources/ZoidCoachApp/Views/DashboardView.swift` - one component insertion only.
- `Tests/ZoidCoachAppTests/LocalSystemDiagnosticsServiceTests.swift`
