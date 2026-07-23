# Phase 0 proof-chain independent verification

Target commit: `fde4f3f0b7b83ea561a02e879c407edff489506b`

Branch: `codex/zc-proof-reverify`

Completed: `2026-07-12T02:38:40Z`

Overall result: **FAILED - proof substrate is not safe for downstream identity or OS-fixture builders.**

No app was launched or installed.

No production service or production data was accessed or mutated.

## Confirmed controls

- The committed registry contains exactly 666 scenarios and 666 unique stable IDs.
- The tracker hash and every tracker-derived registry field validate with no drift.
- Registry status counts are 6 fully implemented, 120 touches remaining, 27 frontend only left, 156 partially implemented, 49 barely started, 275 not implemented, and 33 blocked from verification.
- Registry dispositions are 658 required now, 6 negative invariants, 1 superseded candidate, and 1 deferred guardrail.
- All 29 Python registry, evidence, and build-identity tests pass.
- The committed registry validates against the strict Draft 2020-12 JSON Schema.
- Schema and manual-validator top-level fields, scenario fields, enums, count, version, and tracker path are aligned.
- A release build succeeds at the target commit.
- A production-identity app package builds and signs without being launched or installed.
- The package records commit `fde4f3f0b7b83ea561a02e879c407edff489506b`, state `clean`, and identity `zoid-coach-fde4f3f0b7b83ea561a02e879c407edff489506b-clean`.
- The signed app identifier is `com.ziadnasreldin.ZoidCoach` and the signed helper identifier is `com.ziadnasreldin.ZoidCoach.agent`.
- App and helper signatures have the same team identifier.
- Package verification accepts the exact expected commit and clean requirement.
- Package verification rejects a wrong expected commit.
- Build identity verification rejects a dirty package when clean proof is required.
- Settings renders a visible `BUILD` fact, exposes the exact identity through its accessibility label and help text, and uses accessibility identifier `settings.buildIdentity`.
- The signed production binary contains `settings.buildIdentity`.

## Findings

### P1 - Ambient Git variables can forge repository and build commit binding

`Scripts/scenario_evidence.py` inherits `GIT_DIR`, `GIT_WORK_TREE`, and related Git variables when checking whether a commit exists.

A commit that exists only in a foreign temporary repository was accepted by `create_manifest` as a commit in this repository.

`Scripts/stamp-build-identity.sh` has the same trust boundary problem.

When invoked for this worktree with foreign `GIT_DIR` and `GIT_WORK_TREE` values, it stamped the foreign commit and reported it clean instead of the target commit.

`Scripts/package-app.sh` obtains its pre-build identity, expected commit, and final stamp through the same ambient Git environment, so the resulting package can be internally coherent while bound to the wrong repository.

The registry validator already demonstrates the required defense by removing foreign Git variables before commit lookup.

### P1 - Evidence artifact containment can be bypassed through a symlinked parent directory

`Scripts/scenario_evidence.py` rejects `..`, absolute artifact paths, and a final artifact that is itself a symlink.

It does not resolve the complete artifact path and prove that the result remains below the evidence run directory.

A manifest using `escape/proof.txt`, where `escape` was a directory symlink to a location outside the run, validated with no errors when its checksum matched.

The registry linkage validator has the missing resolved-containment check, but the standalone evidence validator advertised by the evidence workflow does not.

### P1 - Passed evidence can use a meaningless assertion

Both `Scripts/scenario_evidence.py` and the registry linkage check require only that the assertions array be non-empty.

A passed manifest containing `"assertions": [null]` validated successfully and is also acceptable to the scenario-bound registry linkage path.

This permits a completion proof with no named assertion, expected value, actual value, or passed result.

### P1 - The full Swift test suite is red at the integrated commit

The full suite runs 221 tests and fails one test.

`extraProtectedRootsCannotReplaceRealProductionRoots` throws `qaRunRootOverlapsProductionPath` while creating its QA runtime on line 123, before reaching the fixture-builder rejection asserted by the test.

The underlying runtime guard is stricter, but the committed acceptance suite is stale and cannot serve as a green Phase 0 baseline.

### P2 - JSON Schema and manual validation are not semantically equivalent

The schema and manual validator agree on field sets and enums, and the committed registry passes both.

However, the schema does not express tracker-derived relationships such as the required mapping between audit status and delivery status.

Changing the first scenario's delivery status to another schema-valid enum remains valid under the JSON Schema while the manual validator rejects it as tracker drift.

Strict semantic schema/manual parity is therefore not established.

## Non-blocking build observations

- The release build reports an immutable-local warning in `CodexJobCoordinator.swift`.
- The release build reports Swift concurrency capture warnings in `VoiceAudioEngine.swift`.

## Builder gate

Identity and OS-fixture builders must not build proof claims on this substrate yet.

The minimum gate is to sanitize Git environment variables in all commit-binding scripts, enforce resolved artifact containment, define and validate assertion records, restore a green full Swift suite, and either make schema semantics equivalent or document the manual validator as the sole authoritative semantic gate.
