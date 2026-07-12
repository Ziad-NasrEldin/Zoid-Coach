# Zoid Coach Active Work Ledger

This file is owned by the root integrator.

Builders and verifiers must read it before editing, but must not modify it unless explicitly assigned ownership.

## Integration state

| Field | Value |
| --- | --- |
| Integration branch | `codex/full-system` |
| Current integration baseline | `a068d2786c7725204cefa270a736e02f1a910b52` |
| Program | `docs/ZOID-COACH-666-IMPLEMENTATION-PROGRAM.md` |
| Acceptance tracker | `docs/zoid-coach-product-scenario-tracker.md` |
| Phase | Phase 0: acceptance foundation |

## Active assignments

| Lane | Branch | Worktree | Scope | Status |
| --- | --- | --- | --- | --- |
| Runtime environment | `codex/zc-runtime-environment` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/runtime-environment` | Isolated runtime paths, configuration, safety guard, and focused tests | In implementation |
| Scenario registry | `codex/zc-scenario-registry` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/scenario-registry` | Stable IDs, machine-readable registry, evidence schema, drift validation, and tests | In implementation |
| Baseline verifier | `codex/zc-baseline-verifier` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/baseline-verifier` | Independent evidence for the 21 currently checked scenarios | Verification in progress |

## Exclusive file locks

| Path | Owner | Intended change | Baseline | Expires |
| --- | --- | --- | --- | --- |
| `Sources/ZoidCoachApp/AppModel.swift` | Runtime environment lane | Inject runtime database and Screenwatch paths | `a068d27` | Builder handoff |
| `Sources/ZoidCoachAgent/AgentMain.swift` | Runtime environment lane | Parse and apply isolated runtime configuration | `a068d27` | Builder handoff |
| `Sources/ZoidCoachCore/ZoidCoachStorage.swift` | Runtime environment lane | Preserve production defaults and expose isolated storage roots | `a068d27` | Builder handoff |
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
