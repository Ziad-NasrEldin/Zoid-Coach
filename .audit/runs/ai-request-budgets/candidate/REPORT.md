# AI Request Budgets Candidate

## Scope

This candidate implements the user-facing and runtime portions of `ZC-046-006` without changing tracker status.

## User behavior

Settings exposes separate daily and monthly limits for general AI requests.

Both controls explain that the first reached limit stops new requests and that zero disables general AI requests without disabling deterministic local product behavior.

The values persist in the versioned user policy, preserve legacy defaults of 100 requests per day and 3,000 per month, and participate independently in concurrent Settings conflict recovery.

## Runtime enforcement

The model-run ledger checks both the UTC day boundary and UTC calendar-month boundary.

Budgets use one provider-independent general-AI bucket, so changing providers cannot reset the allowance.

Every allowed request is atomically reserved as a pending ledger row before provider execution, preventing concurrent callers from overshooting the last available slot.

The automatic planning advisor reads the latest saved policy each time it chooses a provider and applies both limits to local Ollama and Codex CLI planning requests.

When a limit is reached, AI advice is skipped and the existing deterministic planner continues.

The structured-generation audit wrapper also enforces both limits for future general AI consumers.

## Verification

- Settings policy round-trip and conflict recovery pass.
- Daily and monthly model-run boundary tests pass.
- Atomic reservation and cross-provider budget tests pass.
- Structured generation rejects a request at the monthly limit.
- Existing daily budget enforcement tests continue to pass.
- `swift build -c release` passes.

## Verifier handoff

A verifier should save distinct daily and monthly values in the signed Settings app, restart the app and helper, and confirm both values remain visible.

The runtime acceptance should seed prior model-run records, prove the first reached limit suppresses the next AI request, and prove deterministic planning still produces a usable plan.
