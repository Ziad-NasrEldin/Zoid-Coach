# Background-agent lifecycle recovery candidate

## Scope

This candidate owns `ZC-048-007` through `ZC-048-009` and `ZC-057-008`.
It makes the existing Background Agent window distinguish a macOS registration from a helper that is actually checking in.

## End-user behavior

- An enabled Login Items registration is no longer presented as healthy by itself.
- A fresh canonical `agent-runtime` heartbeat presents the helper as running.
- A missing heartbeat presents an enabled-but-not-yet-checked-in state with a direct repair action.
- A stale heartbeat reports how many minutes have elapsed and explains that repair preserves local data.
- Repair now deliberately unregisters and registers the installed helper even when ServiceManagement still reports it enabled.
- The window checks again every five seconds while visible, so a repaired or launchd-restarted helper becomes healthy without reopening the window.
- Disable still removes only the registration fingerprint and helper registration.
- Plans, reviews, history, and the foreground app remain untouched.
- Login Items failure still gives the exact manual System Settings path.
- The resource explanation names bounded polling, resource-constrained backoff, and the absence of duplicate screenshot storage without claiming a sustained energy measurement.

## Safety and implementation

- Heartbeat inspection opens the existing database read-only.
- It never creates a missing database, runs migrations, or writes a checkpoint.
- SQLite lock waiting is capped at 250 milliseconds.
- Production and signed-QA identities continue to use their existing isolated registration services and database roots.
- Development bundles remain unable to take ownership from an installed app.

## Focused proof

- `AgentLaunchServiceTests` passed.
- `agentLifecycleController` focused tests passed.
- The tests cover current, missing, and five-minute-stale heartbeats, forced re-registration, QA isolation, enable, disable, repair, Login Items failure, fingerprint behavior, and controller refresh.
- A filesystem fixture proves the heartbeat reader returns the canonical checkpoint and does not create a missing database.
- The focused build compiled the app and test targets.
- `git diff --check` passed.

## Verifier handoff

A fresh verifier should rebase this candidate on the current integration tip and rerun both focused groups.
Using the serialized signed-QA runtime, the verifier should then observe missing, current, stale, force-repaired, disabled, re-enabled, and restart-recovered states while confirming the database checksum and production helper identity remain unchanged.
A short bounded CPU, resident-memory, handle-count, and database-growth sample is still required before `ZC-057-008` can be marked fully implemented.
The tracker, registry, Lavish report, shared runtime, and root worktree remain untouched by this candidate.

