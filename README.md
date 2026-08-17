# Zoid 666

A local-first macOS productivity coach that plans the day from Apple Reminders, watches real work through Screenwatch, and puts the next action on a Today dashboard — even after you close the app.

Built for you on your own Mac: software, design, client work, and admin in one day, without sending behavioral data to a cloud coach.

- Start the priority task earlier, with a persistent active-task clock and a deterministic next recommendation
- Notice drift from Screenwatch sessions, then recover without shame copy or fake focus scores
- Let the background agent keep the daily plan after sleep, reboot, or a closed window
- Confirm Calendar and Reminder writes (or stay in observe/suggest) with audited, undoable actions
- Talk to Zoid Voice from the menu bar when you want it — local by default, Gemini Live only with a Keychain key and a hard monthly cap

## Try it

Needs macOS 14+, Swift 6, Screenwatch with its two user LaunchAgents, and an Apple Development signing identity to package the app.

```sh
swift test
swift build --configuration release
./Scripts/install-app.sh
```

The default install is `~/Applications/Zoid 666.app`. After first open, the `com.ziadnasreldin.ZoidCoach.agent` launchd service stays up with the UI closed.

Verify the Screenwatch + Zoid background chain with `./Scripts/verify-background-services.sh`.

Build, voice, rollout modes, trust gates, and storage notes live in [`docs/SETUP.md`](docs/SETUP.md). Product specs stay in [`docs/`](docs/).

## How it works

A Swift package: `ZoidCoachApp` (Today dashboard and settings), `ZoidCoachAgent` (launchd planner), `ZoidCoachCore`, and `ZoidCoachInfrastructure`. Screenwatch is read-only source material. Durable state is a local SQLite store under Application Support. Remote models stay off until you enable them.

---

Built by [Ziad Ahmed](https://github.com/Ziad-NasrEldin) at [MaVoid](https://mavoid.com).

[Website](https://mavoid.com) · [LinkedIn](https://linkedin.com/in/ziad-ahmed-634202332) · [GitHub](https://github.com/Ziad-NasrEldin)
