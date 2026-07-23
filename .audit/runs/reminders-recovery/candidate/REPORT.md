# Reminders Refresh And Recovery Candidate

Commit under test: pending candidate commit from `1d2652fc6a4d`.

## User Flow

- Settings > Signals now exposes an Apple Reminders connection card before list policy controls.
- Opening the chapter checks current authorization and reads incomplete task metadata without changing a Reminder or opening a permission prompt.
- A successful read shows the exact task count and stores the last successful sync time in the runtime-isolated defaults domain.
- A denied or revoked permission shows Access Needed, an explicit Request Access action, a direct System Settings repair action, and a one-click persisted local-only planning fallback.
- A connected EventKit adapter that fails to return task data shows Refresh Failed while retaining the prior successful sync time.
- Refresh Reminders retries the failed read and only advances the displayed successful-sync time after task data is actually returned.
- Passive refresh never calls the permission-request API, so a declined user does not see the macOS prompt repeatedly.

## Scenario Coverage

- `ZC-007-012` - Understand when Reminders could not be refreshed.
- `ZC-044-007` - See current permission and connection states.
- `ZC-048-001` - See Reminders permission and last successful sync.
- `ZC-051-001` - Continue manual planning after Reminders access is denied or revoked.
- `ZC-051-003` - Retry Reminders synchronization.

## Automated Proof

- `swift test --filter RemindersConnectionControllerTests` passed six deterministic journey tests.
- The tests cover success and reconstruction, repeated passive checks after denial, one explicit access request, failed refresh with retained prior success, successful retry, and explicit System Settings opening.
- `swift test --filter SettingsPolicyDraftTests` passed and confirms the affected local-only policy draft seam still behaves correctly.
- `git diff --check` passed.

## Integration Proof Remaining

- The fresh verifier should rebase or cherry-pick the candidate onto the current authoritative branch and run the full suite under the root-owned lease.
- The fresh verifier should use signed QA fixtures to click through connected, denied, refresh-failed, recovered, restart, and local-only fallback states.
- Tracker, registry, backlog, and Lavish files remain exclusively owned by the root verifier and were not edited here.
