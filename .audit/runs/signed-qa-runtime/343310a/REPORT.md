# Signed-QA Persistent Runtime Evidence

## Subject

- Commit: `343310a`
- Branch: `codex/full-system`
- QA runtime root: `/private/tmp/zoid-666-signed-qa`
- Installed app: `/Users/ziadnasreldin/Applications/Zoid Coach QA E2E.app`
- Dedicated helper label: `qa.ziadnasreldin.ZoidCoach.agent`

## Acceptance Evidence

`Scripts/install-signed-qa-runtime.sh` completed successfully from a clean repository identity.

The package passed deep strict code-sign verification before and after installation.

The installed app reports signing identifier `qa.ziadnasreldin.ZoidCoach` and Team ID `377QC32T9T`.

The installed app's stamped QA root is `/private/tmp/zoid-666-signed-qa`.

The app process launched from `/Users/ziadnasreldin/Applications/Zoid Coach QA E2E.app/Contents/MacOS/ZoidCoachQA`.

The dedicated QA LaunchAgent was registered through `SMAppService`, reached `running`, and published the active `qa.ziadnasreldin.ZoidCoach.agent` Mach service.

The installer verified that the running helper executable exactly matched `/Users/ziadnasreldin/Applications/Zoid Coach QA E2E.app/Contents/MacOS/ZoidCoachAgentQA` before reporting success.

The production LaunchAgent identity was not booted out, registered, or mutated by this workflow.

## Automated Proof

- `zsh -n Scripts/install-signed-qa-runtime.sh Scripts/uninstall-signed-qa-runtime.sh` passed.
- `swift test --filter XPCSigningIdentityTests` passed.
- `swift test --filter AgentLaunchServiceTests` passed.

## Remaining Parallel Acceptance Check

The signed runtime is now suitable for the visible onboarding journey that previously failed at app classification because its helper was not registered.

A parallel verifier must complete the classification save and the rest of the 12-step onboarding before the affected end-user scenarios are upgraded to fully implemented.
