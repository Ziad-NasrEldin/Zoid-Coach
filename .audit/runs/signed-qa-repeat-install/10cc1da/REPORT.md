# Signed-QA Repeat-Install Lifecycle Proof

## Scope

This run verifies the dedicated signed Zoid 666 QA app and SMAppService helper lifecycle at commit `10cc1da`.

The runtime used `/private/tmp/zoid-666-repeat-lifecycle` and `/Users/ziadnasreldin/Applications/Zoid666RepeatLifecycle/Zoid 666 QA E2E.app`.

The production app and `com.ziadnasreldin.ZoidCoach.agent` registration were not changed.

## Automated Proof

- `zsh -n Scripts/install-signed-qa-runtime.sh Scripts/uninstall-signed-qa-runtime.sh Scripts/lib/signed-qa-runtime-lifecycle.sh` passed.
- `swift test --filter QAAgentRegistrationLifecycleTests` passed 5 tests.
- `python3 -m unittest Tests/ScenarioRegistryTests/test_signed_qa_runtime_lifecycle.py` passed 3 tests.
- `swift test` passed the full Swift suite.
- `python3 -m unittest discover -s Tests/ScenarioRegistryTests -p "test_*.py"` passed 41 tests.
- `git diff --check` passed.

The deterministic tests cover first install, repeat install, delayed stale-enabled unregistration, interrupted registration retry, atomic app replacement, bundled-helper path replacement, interrupted replacement recovery, and uninstall/reinstall idempotence.

## Signed Runtime Proof

The first clean signed install registered `qa.ziadnasreldin.ZoidCoach.agent`, started it, and verified the installed app signature.

The second install against the same path printed `PASS: QA LaunchAgent unregistered` before replacing the app, then printed `PASS: QA LaunchAgent registered and left enabled` and started the replacement helper without a transient failure.

`lsof` proved the QA process executable was `/Users/ziadnasreldin/Applications/Zoid666RepeatLifecycle/Zoid 666 QA E2E.app/Contents/MacOS/ZoidCoachAgentQA`.

At the same time, the production process executable remained `/Users/ziadnasreldin/Applications/Zoid Coach.app/Contents/MacOS/ZoidCoachAgent` and its launchd job remained running.

The uninstall command explicitly unregistered the QA SMAppService registration, removed the installed QA app, and left the production launchd job running.

A clean reinstall after uninstall again registered and ran the QA helper successfully.

The final cleanup unregistered and removed the isolated QA runtime while the production agent remained running.

## Result

PASS.

Signed-QA install, repeat install, app replacement, helper path reconciliation, interrupted replacement recovery, uninstall, and reinstall are now idempotent and isolated from production.
