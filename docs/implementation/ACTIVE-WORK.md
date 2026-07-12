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
| Runtime consumers | `codex/zc-runtime-consumers` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/runtime-consumers` | Isolated paths, preferences, Keychain, launchd/XPC fail-closed behavior, OS adapters, voice, and evidence cipher | Integrated through `4a2bd85`; 209 branch tests passed |
| Registry hardening | `codex/zc-registry-hardening` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/registry-hardening` | Strict scenario, manifest, commit, clean-build, assertion, artifact, and checksum coherence | Integrated from `1223680` |
| Fixture verifier | `codex/zc-foundation-reverify` | `/Users/ziadnasreldin/Documents/GitHub/Zoid-Coach-Worktrees/foundation-reverify` | Independent deterministic fixture reproduction and immutable evidence | Integrated from `3031040` with no findings |
| Build provenance | Root integrator | Main worktree | Git-derived signed package identity, expected-commit check, clean-proof mode, and visible Settings identity | Integrated through `34623ee`; both review axes clean |

## Exclusive file locks

| Path | Owner | Intended change | Baseline | Expires |
| --- | --- | --- | --- | --- |
| `Sources/ZoidCoachApp/AppModel.swift` | Root integrator | Runtime composition integrated; future composition remains serialized | `4a2bd85` | Permanent unless temporarily granted |
| `Sources/ZoidCoachAgent/AgentMain.swift` | Root integrator | QA OS-adapter refusal integrated; future composition remains serialized | `46f635f` | Permanent unless temporarily granted |
| `Sources/ZoidCoachApp/Voice/VoiceConversationModel.swift` | Root integrator | QA external-boundary refusal integrated | `46f635f` | Permanent unless temporarily granted |
| `Sources/ZoidCoachCore/ZoidCoachStorage.swift` | Root integrator | Runtime storage helper integrated | `e9aecdb` | Permanent unless temporarily granted |
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
