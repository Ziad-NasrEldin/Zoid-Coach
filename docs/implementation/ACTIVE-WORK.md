# Zoid Coach Active Work Ledger

This file is owned by the root integrator.

Builders and verifiers must read it before editing, but must not modify it unless explicitly assigned ownership.

## Integration state

| Field | Value |
| --- | --- |
| Integration branch | `codex/full-system` |
| Current integration baseline | `a8c8420` after strict proof, isolated QA identities, deterministic OS fixtures, production wiring, and hardened onboarding persistence |
| Program | `docs/ZOID-COACH-666-IMPLEMENTATION-PROGRAM.md` |
| Acceptance tracker | `docs/zoid-coach-product-scenario-tracker.md` |
| Phase | Phase 1: first-launch onboarding and first daily-plan usability |

## Active assignments

| Lane | Branch | Worktree | Scope | Status |
| --- | --- | --- | --- | --- |
| First-launch acceptance audit | Read-only root audit | Root checkout at `a8c8420` | Map the 12-step first-launch journey to scenario IDs, UI/service gaps, and E2E hooks | Complete, with no status upgrades |
| Integrated OS-fixture verification | Read-only root verification | Root checkout at `a8c8420` | Reproduce full suites, signed packaging, bounded agent behavior, and exactly-once replay | Passed: 321 Swift, 38 Python, 666 registry, release, signed QA replay |
| First-launch builder | `codex/zc-onboarding-ui` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/onboarding-ui` | Implement resumable 12-step onboarding and first daily-plan handoff | In progress from `a8c8420` |
| Screenwatch setup builder | `codex/zc-screenwatch-setup` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/screenwatch-setup` | Add privacy-safe default and security-scoped alternate-folder setup with repair and restart persistence | In progress from `a8c8420` |

## Exclusive file locks

| Path | Owner | Intended change | Baseline | Expires |
| --- | --- | --- | --- | --- |
| `Sources/ZoidCoachApp/AppModel.swift` | Root integrator | Runtime composition integrated; future composition remains serialized | `4a2bd85` | Permanent unless temporarily granted |
| `Sources/ZoidCoachAgent/AgentMain.swift` | Root integrator | QA OS-adapter refusal integrated; future composition remains serialized | `46f635f` | Permanent unless temporarily granted |
| `Sources/ZoidCoachApp/Voice/VoiceConversationModel.swift` | Root integrator | QA external-boundary refusal integrated | `46f635f` | Permanent unless temporarily granted |
| `Sources/ZoidCoachCore/ZoidCoachStorage.swift` | Root integrator | Runtime storage helper integrated | `e9aecdb` | Permanent unless temporarily granted |
| QA package scripts, copied plist identities, XPC identity composition, Settings XPC consumers, notification IDs, and parent launcher | Root integrator | Integrated dedicated QA identity plane | `61b3e43` | Permanent unless temporarily granted |
| Deterministic OS fixture adapters and composition wiring | Root integrator | Integrated signed-QA Reminders, Calendar, notification, permission, and action fixtures | `a8c8420` | Permanent unless temporarily granted |
| `.audit/runs/phase0-proof/` | Root integrator | Immutable independent proof evidence | `8ce11dc` | Permanent |
| Onboarding progress model, store, and descriptor-relative state directory | Root integrator | Integrated hardened resumable persistence | `712ff71` | Permanent unless temporarily granted |
| New onboarding coordinator, dependencies, views, and focused tests | First-launch builder | Add complete first-launch UI without changing proof or persistence primitives | `a8c8420` | Current Phase 1 wave |
| `Sources/ZoidCoachApp/ZoidCoachApp.swift` root-view hunk only | First-launch builder | Gate Dashboard behind persisted onboarding completion | `a8c8420` | Current Phase 1 wave |
| New Screenwatch onboarding setup service and focused tests | Screenwatch setup builder | Add health, bookmark, repair, and QA-isolation boundaries without UI integration | `a8c8420` | Current Phase 1 wave |
| Runtime preference, keychain, export, capture, OS-adapter, and evidence-cipher consumers | Root integrator | Integrated and independently reviewed | `4a2bd85` | Permanent unless temporarily granted |
| `Scripts/scenario_registry.py`, registry schema, and registry tests | Root integrator | Strict proof coherence integrated | `1223680` | Permanent unless temporarily granted |
| `.audit/runs/deterministic-fixture/515016a/` | Root integrator | Immutable independent evidence | `3031040` | Permanent |
| `docs/zoid-coach-product-scenario-tracker.md` | Root integrator | Authoritative status and later stable-ID composition | `a068d27` | Permanent |
| `Package.swift` | Root integrator | Integration and future UI-test composition | `a068d27` | Permanent unless temporarily granted |
| Migration registration and schema versions | Root integrator | Serialized append-only migrations | `a068d27` | Permanent unless temporarily granted |

## Runtime leases

| Runtime | Owner | Permission |
| --- | --- | --- |
| Production installed app and user data | Root integrator | Read-only verification unless the user explicitly authorizes a controlled mutation |
| Signed clean QA package | Root integrator and assigned verifier | Deterministic fixture-backed E2E only within the embedded run-specific QA root |
| Real Reminders and Calendar | None | No destructive or test mutations |
| TCC and System Settings | None | No permission changes during this wave |

## Handoff gate

A lane is not ready for merge until it provides:

- Final commit SHA
- Clean worktree status
- Files changed
- Focused test output
- Full test output where applicable
- Release build output where applicable
- Known gaps
- Exact integration instructions
- Evidence path
- Rollback instructions

The root merges one lane at a time and reruns the integrated gates after each merge.
