# Zoid Coach

Zoid Coach is a local-first macOS productivity coach built on Screenwatch, Apple Reminders, Apple Calendar, notifications, and Atoll notch prompts.
Its background agent prepares and maintains a daily plan, compares intended work with observed behavior, and exposes an action-first Today dashboard even when the main app has been closed.

## Current capabilities

- Daily and nightly planning with missed-run recovery after sleep or downtime.
- A persistent active-task lifecycle with elapsed work intervals and deterministic next-task recommendations.
- Screenwatch behavior sessionization, telemetry coverage warnings, and source freshness.
- Audited and idempotent Calendar and Reminder actions with recovery and undo support.
- Local WhatsApp screenshot OCR for meeting proposals, conflict checks, and exact-once Calendar creation after confirmation.
- Estimate and preferred-work-window learning from completed work.
- Gaming budgets and rewards backed by a durable ledger.
- Notifications, the Today dashboard, and Atoll prompts backed by the same agent-owned snapshot over launchd XPC.
- Privacy retention, deletion, redacted export, policy rollback, permission health, and low-power or thermal throttling.

Zoid Coach reads Screenwatch's source archive but never deletes Screenwatch-owned files.

## Requirements

- macOS 14 or later.
- Swift 6 toolchain.
- Screenwatch installed with its `com.screenwatch` and `com.screenwatch.timer` user LaunchAgents.
- A valid Apple Development signing identity when packaging the app.
- Reminders and Calendar access for the actions you enable.
- Screen Recording access for Screenwatch.

## Build and test

```sh
swift test
swift build --configuration release
```

Package, sign, install, and open the native app with:

```sh
./Scripts/install-app.sh
```

The default install destination is `~/Applications/Zoid Coach.app`.
Set `ZOID_COACH_INSTALL_ROOT` to choose another destination and `SIGNING_IDENTITY` to override the development identity used by the package script.

## Background startup

The packaged app contains a launchd agent named `com.ziadnasreldin.ZoidCoach.agent` with both `RunAtLoad` and `KeepAlive` enabled.
Opening the installed app registers that service through `SMAppService`, after which the agent continues while the UI is closed and starts again after login or reboot.

Screenwatch is a separate service and must also have its two LaunchAgents installed, enabled, and configured with `RunAtLoad` and `KeepAlive`.
After installation or a restart, verify the complete background chain with:

```sh
./Scripts/verify-background-services.sh
```

The verification checks that Screenwatch and Zoid Coach are loaded and running, that today's Screenwatch log is fresh, and that Zoid Coach ingestion is keeping up.
If macOS reports that the Zoid Coach agent requires approval, enable it under System Settings > General > Login Items and run the verification again.

## Rollout modes

The shared policy store exposes four explicit operating modes:

1. `observe` ingests evidence and records proposed actions without performing external writes.
2. `suggest` presents plans and meeting candidates without automatic Apple writes.
3. `assist` performs writes only after plan-level confirmation.
4. `autonomous` maintains Zoid-owned Reminder fields and Calendar blocks automatically.

Older persisted values are migrated when decoded: `suggestionsOnly` becomes `suggest`, `approvalRequired` becomes `assist`, and `fullyAutomatic` becomes `autonomous`.
The one-step automation pause remains independent of the selected mode and prevents new autonomous actions without deleting plans or evidence.

## Trust gates

Automatic plan writes remain disabled until seven qualifying shadow planning cycles have completed with external writes suppressed and capacity rules respected.
Wake interventions have a separate fourteen-cycle trust gate and still require deliberate user activation.
These gates are safety prerequisites, not substitutes for selecting the desired rollout mode.

## Storage and privacy

Zoid Coach stores its durable state at `~/Library/Application Support/Zoid Coach/zoid-coach.sqlite`.
Screenwatch normally writes observations under `~/screenwatch/days/YYYY-MM-DD/`.
The app stores normalized evidence and derived coaching state in its own database and treats the Screenwatch archive as read-only source material.

Remote model use is never silently enabled.
The default provider policy is local, and privacy controls define screenshot analysis and retention behavior.

## Documentation

- [Autonomous coach specification](docs/AUTONOMOUS-COACH-SPEC.md)
- [Autonomous coach implementation plan](docs/AUTONOMOUS-COACH-IMPLEMENTATION-PLAN.md)
- [Daily dashboard agent delta](docs/DAILY-DASHBOARD-AGENT-DELTA.md)
- [Full product specification](docs/ZOID-COACH-PRODUCT-SPEC.md)
- [MVP specification](docs/ZOID-COACH-MVP.md)
- [Visual MVP specification](docs/zoid-coach-mvp.html)
