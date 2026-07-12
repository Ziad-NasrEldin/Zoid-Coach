# Zoid Coach Active Work Ledger

This file is owned by the root integrator.

Builders and verifiers must read it before editing, but must not modify it unless explicitly assigned ownership.

## Integration state

| Field | Value |
| --- | --- |
| Integration branch | `codex/full-system` |
| Current integration baseline | `b5596a04a2f7` before the verifier-driven tracker update |
| Program | `docs/ZOID-COACH-666-IMPLEMENTATION-PROGRAM.md` |
| Acceptance tracker | `docs/zoid-coach-product-scenario-tracker.md` |
| Phase | Phase 0: acceptance foundation |

## Active assignments

| Lane | Branch | Worktree | Scope | Status |
| --- | --- | --- | --- | --- |
| Runtime environment | `codex/zc-runtime-environment` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/runtime-environment` | Isolated runtime paths, configuration, safety guard, and focused tests | Integrated from `e9aecdb` |
| Scenario registry | `codex/zc-scenario-registry` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/scenario-registry` | Stable IDs, machine-readable registry, evidence schema, drift validation, and tests | Integrated from `6291c30` |
| Baseline verifier | `codex/zc-baseline-verifier` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/baseline-verifier` | Independent evidence for the 21 initially checked scenarios | Integrated from `521dc62`; 6 retained and 15 downgraded pending isolated UI proof |

## Exclusive file locks

| Path | Owner | Intended change | Baseline | Expires |
| --- | --- | --- | --- | --- |
| `Sources/ZoidCoachApp/AppModel.swift` | Root integrator | Runtime environment slice integrated; future composition remains serialized | `e9aecdb` | Permanent unless temporarily granted |
| `Sources/ZoidCoachAgent/AgentMain.swift` | Root integrator | Runtime environment slice integrated; future composition remains serialized | `e9aecdb` | Permanent unless temporarily granted |
| `Sources/ZoidCoachCore/ZoidCoachStorage.swift` | Root integrator | Runtime storage helper integrated | `e9aecdb` | Permanent unless temporarily granted |
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
