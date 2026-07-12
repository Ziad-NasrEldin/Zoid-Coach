# Zoid Coach Active Work Ledger

This file is owned by the root integrator.

Builders and verifiers must read it before editing, but must not modify it unless explicitly assigned ownership.

## Integration state

| Field | Value |
| --- | --- |
| Integration branch | `codex/full-system` |
| Current integration baseline | `6b4624b` after isolated runtime, strict proof registry, and build-provenance integration |
| Program | `docs/ZOID-COACH-666-IMPLEMENTATION-PROGRAM.md` |
| Acceptance tracker | `docs/zoid-coach-product-scenario-tracker.md` |
| Phase | Phase 0: acceptance foundation |

## Active assignments

| Lane | Branch | Worktree | Scope | Status |
| --- | --- | --- | --- | --- |
| QA identities | `codex/zc-qa-identities` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/qa-identities` | Dedicated signed QA bundle, launchd, Mach/XPC, notification, and parent-app identity plane | In progress from `fde4f3f` |
| OS fixtures | `codex/zc-os-fixtures` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/os-fixtures` | Deterministic persisted Reminders, Calendar, notification, permission, and action fixtures | In progress from `fde4f3f` |
| Proof verifier | `codex/zc-proof-reverify` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/proof-reverify` | Independent registry, manifest, package-provenance, and signed-package reproduction | In progress from `fde4f3f` |

## Exclusive file locks

| Path | Owner | Intended change | Baseline | Expires |
| --- | --- | --- | --- | --- |
| `Sources/ZoidCoachApp/AppModel.swift` | Root integrator | Runtime composition integrated; future composition remains serialized | `4a2bd85` | Permanent unless temporarily granted |
| `Sources/ZoidCoachAgent/AgentMain.swift` | Root integrator | QA OS-adapter refusal integrated; future composition remains serialized | `46f635f` | Permanent unless temporarily granted |
| `Sources/ZoidCoachApp/Voice/VoiceConversationModel.swift` | Root integrator | QA external-boundary refusal integrated | `46f635f` | Permanent unless temporarily granted |
| `Sources/ZoidCoachCore/ZoidCoachStorage.swift` | Root integrator | Runtime storage helper integrated | `e9aecdb` | Permanent unless temporarily granted |
| QA package scripts, copied plist identities, XPC identity composition, Settings XPC consumers, notification IDs, and parent launcher | QA identities | Replace every remaining shared runtime identity while preserving production defaults | `fde4f3f` | Current Phase 0 wave |
| New deterministic OS fixture adapter and test files | OS fixtures | Add persisted fixture adapters without composition-root wiring | `fde4f3f` | Current Phase 0 wave |
| `.audit/runs/phase0-proof/fde4f3f/` | Proof verifier | Immutable independent evidence only | `fde4f3f` | Current Phase 0 wave |
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
| Signed clean QA package | Root integrator | Package and structural verification only until remaining QA identities are isolated |
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
