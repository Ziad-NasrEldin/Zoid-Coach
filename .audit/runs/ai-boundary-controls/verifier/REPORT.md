# Optional AI Boundary Verification

## Truth blocker fixed

The candidate preview originally showed fields that did not match the actual automatic Codex planning payload.
It also labeled screenshots as never included, even though the separate voice screen-context action can transmit selected images after explicit user intent and records each transmission locally.

The verifier changed the redacted and private examples to mirror the real encoded planning fields.
The exclusion label is now scoped to automatic planning requests.
The preview explicitly discloses the separate user-requested, audited voice-image boundary.

## Deletion boundary

Clear AI Cache and Request History reuses the existing destructive confirmation and authenticated background-agent data command.
The command deletes only `model_runs`, `codex_jobs`, and `screen_context_transmissions`.
It does not delete Keychain credentials or non-AI local product data.

## Proof

- `swift test --filter RemoteEvidencePreviewTests` passed after the truth fix.
- One release build passed.
- `git diff --check` passed.

## Signed acceptance pending

The signed three-policy preview and seeded scoped-deletion journey remains pending the package step.
