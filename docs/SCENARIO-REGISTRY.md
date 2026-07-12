# Scenario registry

The file docs/scenario-registry.json is the machine-readable companion to the authoritative end-user scenario tracker.

The Markdown tracker remains the product and audit source of truth.

The registry gives every scenario a stable identifier and structured delivery, disposition, proof, capability, and verification fields for automation.

## Stable IDs

IDs use ZC-section-item with three-digit components.

For example, ZC-016-004 is the fourth scenario in section 16.

IDs remain stable while a scenario stays in the same section and item position.

The validator reports tracker drift when wording, ordering, section placement, checkbox state, or audit status changes without a registry sync.

## Dispositions

- required_now covers every scenario in sections 1 through 64.
- negative_invariant covers the six section 65 product boundaries that must remain absent.
- superseded_candidate marks the section 65 calendar auto-scheduling constraint because the current autonomous product direction conflicts with it.
- deferred_guardrail records the safety contract required before any future application-blocking feature can ship.

## Proof fields

The required_proof_classes field describes the kinds of proof expected before a scenario can be considered complete.

The evidence_paths field contains repository-relative files with optional line references.

The last_verified_commit and last_verified_build fields record the most recent installed-product verification.

Sync preserves valid manually added evidence and verification fields for an unchanged stable scenario.

## Commands

Regenerate the registry after an intentional tracker change:

    python3 Scripts/scenario_registry.py sync

Validate counts, IDs, statuses, dispositions, evidence fields, and tracker alignment:

    python3 Scripts/scenario_registry.py validate

Run the focused test suite:

    python3 -m unittest discover -s Tests/ScenarioRegistryTests -v

CI should run validation before accepting tracker or registry changes.

The sync command does not edit the authoritative tracker.
