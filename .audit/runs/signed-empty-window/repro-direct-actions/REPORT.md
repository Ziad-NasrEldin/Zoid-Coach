# Signed Empty Window Reproduction - Direct Prompt Actions

## Identity

- Captured at `2026-07-13T17:59:10Z` UTC.
- Candidate commit: `625dd38625db47d463639896e8ce0890300bc68b`.
- Authoritative base: `07ffb22`.
- Packaged app: `/private/tmp/zoid-666-verify-direct-prompt-actions/.build/app-qa/Zoid 666 QA.app`.
- Installed app: `/private/tmp/zoid-666-direct-prompt-actions-install/Zoid 666 QA E2E.app`.
- Isolated QA root: `/private/tmp/zoid-666-direct-prompt-actions-qa`.
- LaunchAgent label: `qa.ziadnasreldin.ZoidCoach.agent`.

## Exact commands

The release package was created with:

```zsh
CONFIGURATION=release ZOID_COACH_PACKAGE_MODE=qa ZOID_COACH_QA_RUN_ROOT=/private/tmp/zoid-666-direct-prompt-actions-qa Scripts/package-app.sh
```

The signed runtime was installed with:

```zsh
ZOID_COACH_QA_RUN_ROOT=/private/tmp/zoid-666-direct-prompt-actions-qa ZOID_COACH_QA_INSTALL_ROOT=/private/tmp/zoid-666-direct-prompt-actions-install Scripts/install-signed-qa-runtime.sh
```

The package command passed package identity, LaunchAgent identity, Mach service identity, and deep code-sign validation.
The install command reported `PASS: QA LaunchAgent registered and left enabled` and `PASS: signed QA runtime installed`.

## Raw accessibility and window probe

Immediately after installation, the raw System Events result was:

```text
Zoid 666, 730, 193, 1180, 760, 0
```

The fields are window name, x position, y position, width, height, and count of `entire contents`.
The window was non-minimized and had zero accessibility descendants.
After moving the window to `{80,80}` and reopening the exact installed app, the raw result remained:

```text
80, 80, 1180, 760, 0
```

No further UI retry was performed.

At `2026-07-13T17:59:10Z`, the same probe returned:

```text
System Events got an error: Can't get process "ZoidCoachQA". (-1728)
```

The app process had exited while the helper remained running.

## Process and LaunchAgent metadata

The process snapshot at capture time contained:

```text
75808     1 S          02:43 Contents/MacOS/ZoidCoachAgentQA
```

The LaunchAgent probe returned:

```text
state = running
program identifier = Contents/MacOS/ZoidCoachAgentQA (mode: 2)
pid = 75808
last exit code = (never exited)
job state = running
```

## Unified logs

The exact log command was:

```zsh
/usr/bin/log show --style compact --last 8m --predicate 'process == "ZoidCoachQA" OR process == "ZoidCoachAgentQA"'
```

The returned interval contained helper activity but no `ZoidCoachQA` app entries.
Representative helper entries repeated every few seconds:

```text
2026-07-13 20:59:20.347 A  ZoidCoachAgentQA[75808:963dea] (TCC) TCCAccessRequest() IPC
2026-07-13 20:59:20.871 Df ZoidCoachAgentQA[75808:963dea] [com.apple.libsqlite3:logging] automatic index on screenshot_artifacts(behavior_day)
2026-07-13 20:59:20.888 Df ZoidCoachAgentQA[75808:9612d9] [com.apple.xpc:connection] activating connection: mach=true listener=false peer=false name=com.apple.remindd
2026-07-13 20:59:20.962 E  ZoidCoachAgentQA[75808:9641aa] [com.apple.reminderkit:xpc] XPC connection was invalidated
```

The absence of app log entries is part of the reproduction result and must not be interpreted as a successful app launch.

## Screenshot

`app-absent-after-empty-window.png` captures the desktop after the empty window disappeared and the app process exited.
Its SHA-256 is `eb84b2a7cc47f537876daa2e658a45f9daec05fa018cb69698aeab182a77b9e0`.

