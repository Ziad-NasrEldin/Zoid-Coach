# Phase 0 proof-fix re-verification

Target commit: `0eb22f8311d5a00cda29ebc6a4b4b8068d393236`

Completed: `2026-07-12T02:47:53Z`

Verdict: **FAIL - four P1 findings are closed, but one P2 proof-consumer gap remains.**

## Closed findings

- Ambient `GIT_DIR` and `GIT_WORK_TREE` redirection is ignored by build stamping and scenario-evidence commit lookup.
- A foreign commit that does not exist in this repository is rejected by scenario-evidence creation.
- Artifact paths reached through a symlinked parent directory are rejected as escaping the evidence run.
- Null assertions and named failed assertions are rejected by both scenario-evidence validation and registry evidence linkage.
- The formerly failing runtime production-root guard test passes.
- All 33 Python proof tests pass.
- The full Swift suite passes all 227 tests.

## Retained finding

### P2 - The scenario-evidence CLI consumes a registry without enforcing tracker semantics

The JSON Schema is structurally correct.

The committed registry passes the strict Draft 2020-12 schema and the documented authoritative `scenario_registry.py validate` CLI.

The schema intentionally validates structure, while the registry CLI enforces tracker-derived semantic relationships.

However, `scenario_evidence.py` loads and trusts a supplied registry without invoking the authoritative semantic validator.

An exact CLI probe changed `ZC-001-001` from its required `installed_app_e2e` and `ui_automation` proof classes to schema-valid `unit_rule` only.

The authoritative registry CLI rejected that registry as tracker drift.

The scenario-evidence CLI nevertheless created a manifest with only `unit_rule` and validated the resulting passed manifest successfully.

This is a documented proof consumer that can accept materially weakened proof requirements without running the semantic gate.

## Recommendation

Do not treat the proof substrate as complete yet.

Make scenario-evidence creation and validation call the authoritative registry validator, or make successful registry validation a machine-enforced prerequisite that cannot be skipped by consumers.
