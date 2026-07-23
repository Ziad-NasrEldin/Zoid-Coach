# Phase 0 foundation verification commands

## Identity and cleanliness

```sh
pwd
git branch --show-current
git rev-parse HEAD
git status --short --branch
```

Result:

```text
/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/phase0-verifier
codex/zc-phase0-verifier
0091652ff15ca9e7f31e6428e4220f71d06348c9
## codex/zc-phase0-verifier
```

## Registry validation

```sh
python3 Scripts/scenario_registry.py validate
python3 -m unittest discover -s Tests/ScenarioRegistryTests -v
```

Result:

```text
Validated 666 scenarios with no tracker drift
Ran 7 tests
OK
```

Independent counts were computed by parsing `docs/scenario-registry.json` without using the registry generator.

Result:

```text
scenario_count 666
unique_ids 666
section_range 1 through 65
section_count 65
checkbox checked=6 unchecked=660
disposition required_now=658 negative_invariant=6 superseded_candidate=1 deferred_guardrail=1
delivery fully_implemented=6 touches_remaining=120 frontend_only_left=27 partially_implemented=156 barely_started=49 not_implemented=275 blocked_from_verification=33
```

## Tracker digest

```sh
shasum -a 256 docs/zoid-coach-product-scenario-tracker.md
jq -r .tracker_sha256 docs/scenario-registry.json
```

Both returned:

```text
2732d57baef4a31a86507b858cd9660a3f3dfcef167fb4d87fa65c4c4326710a
```

## Runtime tests

```sh
swift test --filter RuntimeEnvironment
swift test --skip-build --filter RuntimeEnvironment --quiet
```

Result:

```text
Test run with 5 tests passed.
```

## Adversarial runtime probe

A temporary Swift Testing file was added under the existing test target, run, and removed before commit.

It called the production `RuntimeEnvironment.resolve` implementation directly.

```sh
swift test --filter adversarialProbe
swift test --skip-build --filter adversarialProbe --quiet
```

Final result after matching actual behavior:

```text
Test run with 4 tests passed.
```

The probe confirmed the parent-symlink escape with temporary paths and a real write outside the temporary QA root.

It also confirmed the production-root and UserDefaults collision cases and the sibling-prefix and filesystem-root defenses.

## Adversarial registry probe

The verifier imported `Scripts/scenario_registry.py`, deep-copied the committed payload in memory, mutated one field per case, and called `validate_registry`.

Result:

```text
schema_version_999: ACCEPTED
evil_schema_uri: ACCEPTED
wrong_tracker_path: ACCEPTED
unexpected_top_level: ACCEPTED
nonexistent_verified_commit: ACCEPTED
arbitrary_verified_build: ACCEPTED
out_of_range_evidence_line: ACCEPTED
```

## Full test suite

```sh
swift test
swift test --skip-build --quiet
```

Result:

```text
Test run with 193 tests in 4 suites passed after 0.896 seconds.
```

## Release build

```sh
swift build -c release --quiet
```

Result: exit code 0.

## Installed package and service safety

```sh
./Scripts/verify-package.sh "$HOME/Applications/Zoid Coach.app"
./Scripts/verify-background-services.sh
launchctl print "gui/$(id -u)/com.ziadnasreldin.ZoidCoach.agent"
```

Result:

```text
PASS: packaged app, LaunchAgent, Mach service, and signing identities are coherent
PASS: Screenwatch and Zoid Coach are loaded, running, and fresh
Installed parent bundle version = 8
Agent state = running
Mach service state = active
```

These checks were read-only.

No service was installed, registered, restarted, stopped, or reconfigured.

## Consumer audit

```sh
rg -n 'userDefaultsSuiteName|keychainServiceSuffix|exportRoot' Sources
rg -n 'runtimeEnvironment' Sources
rg -n 'SettingsPolicyController\(|AppInventoryService\(|NativeCaptureConfigurationStore\(|GeminiAPIKeyStore\(|TodayDashboardXPCClient\(|UserDefaults.standard|ZoidCoachStorage.databaseURL\(\)' Sources/ZoidCoachApp Sources/ZoidCoachAgent
```

Result:

- `userDefaultsSuiteName`, `keychainServiceSuffix`, and `exportRoot` are only parsed and stored in `RuntimeEnvironment.swift`.
- AppModel consumes only the QA database and Screenwatch paths.
- AgentConfiguration consumes only the QA database and Screenwatch paths.
- Settings, App inventory, voice, native capture configuration, XPC, UserDefaults, Keychain, notifications, EventKit, and ServiceManagement retain production-default construction.
