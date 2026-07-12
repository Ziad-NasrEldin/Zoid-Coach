# Zoid Coach Active Work Ledger

This file is owned by the root integrator.

Builders and verifiers must read it before editing, but must not modify it unless explicitly assigned ownership.

## Integration state

| Field | Value |
| --- | --- |
| Integration branch | `codex/full-system` |
| Current integration baseline | `515016a` after deterministic fixture integration and independent review |
| Program | `docs/ZOID-COACH-666-IMPLEMENTATION-PROGRAM.md` |
| Acceptance tracker | `docs/zoid-coach-product-scenario-tracker.md` |
| Phase | Phase 0: acceptance foundation |

## Active assignments

| Lane | Branch | Worktree | Scope | Status |
| --- | --- | --- | --- | --- |
| Runtime consumers | `codex/zc-runtime-consumers` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/runtime-consumers` | Correct review findings, enforce fail-closed QA launchd/XPC behavior, and finish consumer isolation | Corrective commit in progress after `c65460b8` was rejected |
| Registry hardening | `codex/zc-registry-hardening` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/registry-hardening` | Reject malformed, incoherent, nonexistent, or escaping verification evidence | In progress from `515016a` |
| Fixture verifier | `codex/zc-foundation-reverify` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/foundation-reverify` | Independently reproduce the integrated deterministic fixture safety contract | In progress from `515016a` |

## Exclusive file locks

| Path | Owner | Intended change | Baseline | Expires |
| --- | --- | --- | --- | --- |
| `Sources/ZoidCoachApp/AppModel.swift` | Runtime consumers | Propagate QA runtime identity into launch-service composition only | `515016a` | Current corrective wave |
| `Sources/ZoidCoachAgent/AgentMain.swift` | Runtime consumers | Native-capture path derivation only; temporary narrow grant from root | `0091652` | Current Phase 0 wave |
| `Sources/ZoidCoachApp/Voice/VoiceConversationModel.swift` | Runtime consumers | Runtime-scoped preferences, keychain, and fail-closed QA XPC composition only | `515016a` | Current corrective wave |
| `Sources/ZoidCoachCore/ZoidCoachStorage.swift` | Root integrator | Runtime storage helper integrated | `e9aecdb` | Permanent unless temporarily granted |
| Runtime preference, keychain, export, and capture consumers outside root-owned hotspots | Runtime consumers | Complete isolated runtime consumer wiring and focused tests | `0091652` | Current Phase 0 wave |
| `Scripts/scenario_registry.py`, registry schema, and registry tests | Registry hardening | Enforce strict proof coherence without changing scenario status | `515016a` | Current Phase 0 wave |
| `.audit/runs/deterministic-fixture/515016a/` | Fixture verifier | Independent commands, evidence, and findings only | `515016a` | Current Phase 0 wave |
| `docs/zoid-coach-product-scenario-tracker.md` | Root integrator | Authoritative status and later stable-ID composition | `a068d27` | Permanent |
| `Package.swift` | Root integrator | Integration and future UI-test composition | `a068d27` | Permanent unless temporarily granted |
| Migration registration and schema versions | Root integrator | Serialized append-only migrations | `a068d27` | Permanent unless temporarily granted |

## Runtime leases

| Runtime | Owner | Permission |
| --- | --- | --- |
| Production installed app and user data | Root integrator | Read-only verification unless the user explicitly authorizes a controlled mutation |
| Packaged Build 8 inspection | Baseline verifier | Read-only UI, accessibility, database, and service inspection |
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
