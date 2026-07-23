# Baseline verification commands and results

## Worktree identity

```sh
pwd
git branch --show-current
git rev-parse HEAD
git status --short --branch
```

Result:

```text
/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/baseline-verifier
codex/zc-baseline-verifier
a068d2786c7725204cefa270a736e02f1a910b52
## codex/zc-baseline-verifier
```

## Checked scenario inventory

```sh
awk '/^- \[x\]/ {print NR ":" $0}' docs/zoid-coach-product-scenario-tracker.md
```

Result: exactly 21 checked scenarios at tracker lines 69, 75, 110, 128, 131, 206, 207, 208, 211, 228, 232, 233, 234, 809, 810, 900, 901, 902, 903, 905, and 906.

## Swift tests

```sh
swift test
swift test --skip-build --quiet
```

Result:

```text
Test Suite 'All tests' passed.
Test run with 188 tests in 4 suites passed after 0.868 seconds.
```

## Release build

```sh
swift build -c release
swift build -c release --quiet
```

Result: both commands exited 0.

## Package and signing

```sh
./Scripts/verify-package.sh "$HOME/Applications/Zoid Coach.app"
codesign --verify --deep --strict --verbose=2 "$HOME/Applications/Zoid Coach.app"
codesign -d --verbose=4 "$HOME/Applications/Zoid Coach.app/Contents/MacOS/ZoidCoach"
codesign -d --verbose=4 "$HOME/Applications/Zoid Coach.app/Contents/MacOS/ZoidCoachAgent"
```

Result:

```text
PASS: packaged app, LaunchAgent, Mach service, and signing identities are coherent
App identifier: com.ziadnasreldin.ZoidCoach
Agent identifier: com.ziadnasreldin.ZoidCoach.agent
Team identifier: 377QC32T9T
App CDHash: d76e35fb38e52e8733f563e13a65450718fc8871
Agent CDHash: 3364ec2db4035e3b93700326a476621fdb129815
```

## Installed identity

```sh
plutil -p "$HOME/Applications/Zoid Coach.app/Contents/Info.plist"
```

Result:

```text
CFBundleShortVersionString = 0.1.0
CFBundleVersion = 8
CFBundleIdentifier = com.ziadnasreldin.ZoidCoach
```

## LaunchAgent and canonical file handles

```sh
launchctl print "gui/$(id -u)/com.ziadnasreldin.ZoidCoach.agent"
lsof -p 41612 | rg 'Zoid Coach.app|zoid-coach.sqlite|zoid-coach.sqlite-wal|deleted|Trash'
```

Result:

```text
LaunchAgent state = running
parent bundle version = 8
pid = 41612
Mach service active = 1
Agent executable is inside /Users/ziadnasreldin/Applications/Zoid Coach.app
Database and WAL handles use /Users/ziadnasreldin/Library/Application Support/Zoid Coach
No deleted or Trash database handle was observed
```

## Canonical database

```sh
sqlite3 -readonly "$HOME/Library/Application Support/Zoid Coach/zoid-coach.sqlite" \
  "PRAGMA integrity_check; SELECT COUNT(*) FROM sqlite_master WHERE type='table';"
```

Result:

```text
ok
44
```

Read-only relation counts:

```text
source_tasks        316
daily_plan_items    0
behavior_records    15141
today_snapshots     1
prompt_episodes     12
policy_versions     1
source_checkpoints  2
task_history        0
```

## Live background verification

```sh
./Scripts/verify-background-services.sh
```

Result:

```text
PASS: packaged app, LaunchAgent, Mach service, and signing identities are coherent
PASS: Screenwatch and Zoid Coach are loaded, running, and fresh
```

## Accessibility boundary

```sh
osascript -e 'tell application "System Events" to return exists process "Zoid Coach"'
pgrep -x ZoidCoach
```

Result:

```text
false
No main-app PID
```

The app was not launched because that would refresh real EventKit and XPC state.

## Negative-invariant search

```sh
rg -n 'import CloudKit|NSUbiquitous|CKContainer|NWListener|Vapor|Hummingbird|FamilyControls|ManagedSettings|DeviceActivity|\.iOS\(|\.watchOS\(|website blocking|application blocking|decompose' Sources App Package.swift Tests Scripts
```

Result: no matches.

Additional source and package inspection found no team, multi-tenant, manager, shared-permission, remote-admin, public-web, cloud-sync, mobile-companion, cross-device, decomposition, or hard-blocking implementation.
