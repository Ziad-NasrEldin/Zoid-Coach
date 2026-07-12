# Background Agent Lifecycle Candidate Evidence

## Scope

This candidate implements backlog slice 19, background-agent lifecycle and Login Items repair.
It gives the user a dedicated Background Agent window reachable from the application menu with Command-Shift-L.
It does not change planning, weekly review, Settings, app classification, migrations, or the scenario tracker.

## End-user behavior implemented

- The window displays the current SMAppService-backed agent health, evidence, and last inspection time.
- A disconnected user can enable the signed local helper.
- An approval-required user receives an exact Login Items repair path and can open the correct System Settings pane.
- A stale or unhealthy registration can be reconciled without deleting local plans, reviews, or history.
- A healthy agent can be disabled only after a destructive confirmation that explains what stops and what remains.
- Check Again exposes recovery after an agent exit or macOS approval without restarting the foreground app.
- Every primary control and status surface has a stable accessibility identifier.

## Automated proof

- `swift test --filter AgentLifecycleControllerTests` passed four focused lifecycle, recovery, disable, and Login Items tests.
- `swift test --filter AgentLaunchServiceTests` passed the existing registration, approval, build-replacement, and disable suite.
- `git diff --check` passed.

## Scenario impact

- `ZC-023-011` gains a complete, discoverable source-health window and repair controls.
- `ZC-062-009` gains an in-app check-and-repair path for the agent portion of degraded-mode recovery.

## Remaining acceptance boundary

A fresh verifier must run the signed packaged app through enabled, approval-required, repaired, disabled, and re-enabled states after the shared package/runtime lease is available.
The authoritative tracker must not mark these scenarios fully implemented until that installed-product evidence passes.
