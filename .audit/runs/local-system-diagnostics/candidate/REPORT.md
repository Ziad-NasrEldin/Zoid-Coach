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

## Independent acceptance still required

- A fresh verifier must open Source Health in the signed QA app, inspect both rows, trigger Refresh, and confirm the visible values survive application restart.
- The root integrator owns tracker and registry status changes after that installed-app proof.

## File boundary

- `Sources/ZoidCoachApp/Services/LocalSystemDiagnosticsService.swift`
- `Sources/ZoidCoachApp/Views/LocalSystemDiagnosticsView.swift`
- `Sources/ZoidCoachApp/Views/DashboardView.swift` - one component insertion only.
- `Tests/ZoidCoachAppTests/LocalSystemDiagnosticsServiceTests.swift`
