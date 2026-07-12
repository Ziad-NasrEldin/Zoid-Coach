# Zoid Coach Active Work Ledger

This file is owned by the root integrator.

Builders and verifiers must read it before editing, but must not modify it unless explicitly assigned ownership.

## Integration state

| Field | Value |
| --- | --- |
| Integration branch | `codex/full-system` |
| Current integration baseline | `0091652ff15c` after the verifier-driven tracker alignment |
| Program | `docs/ZOID-COACH-666-IMPLEMENTATION-PROGRAM.md` |
| Acceptance tracker | `docs/zoid-coach-product-scenario-tracker.md` |
| Phase | Phase 0: acceptance foundation |

## Active assignments

| Lane | Branch | Worktree | Scope | Status |
| --- | --- | --- | --- | --- |
| Runtime consumers | `codex/zc-runtime-consumers` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/runtime-consumers` | Wire UserDefaults, Keychain, export, and capture consumers through the isolated runtime | In progress from `0091652` |
| Deterministic fixtures | `codex/zc-deterministic-fixtures` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/deterministic-fixtures` | Deterministic clock, identifiers, fixture workspace, containment tests, and consumer inventory | In progress from `0091652` |
| Phase 0 verifier | `codex/zc-phase0-verifier` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/phase0-verifier` | Adversarial independent verification of runtime isolation and the scenario registry | In progress from `0091652` |

## Exclusive file locks

| Path | Owner | Intended change | Baseline | Expires |
| --- | --- | --- | --- | --- |
| `Sources/ZoidCoachApp/AppModel.swift` | Root integrator | Runtime environment slice integrated; future composition remains serialized | `e9aecdb` | Permanent unless temporarily granted |
| `Sources/ZoidCoachAgent/AgentMain.swift` | Runtime consumers | Native-capture path derivation only; temporary narrow grant from root | `0091652` | Current Phase 0 wave |
| `Sources/ZoidCoachApp/Voice/VoiceConversationModel.swift` | Runtime consumers | Runtime-scoped preferences and keychain construction only | `0091652` | Current Phase 0 wave |
| `Sources/ZoidCoachCore/ZoidCoachStorage.swift` | Root integrator | Runtime storage helper integrated | `e9aecdb` | Permanent unless temporarily granted |
| Runtime preference, keychain, export, and capture consumers outside root-owned hotspots | Runtime consumers | Complete isolated runtime consumer wiring and focused tests | `0091652` | Current Phase 0 wave |
| New deterministic fixture and test-control files | Deterministic fixtures | Add production-safe deterministic foundations without broad consumer wiring | `0091652` | Current Phase 0 wave |
| `.audit/runs/phase0-foundation/0091652/` | Phase 0 verifier | Independent commands, evidence, and findings only | `0091652` | Current Phase 0 wave |
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
