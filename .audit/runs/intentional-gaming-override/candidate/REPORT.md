# Intentional Gaming Override Candidate

## Scope

This candidate implements the intentional override lifecycle for `ZC-036-001`, `ZC-036-002`, `ZC-036-003`, `ZC-036-007`, and `ZC-036-008`.

## End-user behavior

The existing accountability prompt already exposes Continue intentionally as a visible secondary action.
Choosing it resolves the current prompt immediately through the canonical prompt store.
The response now creates a durable override without adding a parallel state table or migration.
Equivalent coaching remains suppressed for the configured coaching cooldown.
The override survives service and prompt-store restart because it is derived from the persisted prompt response.
A corrected or observed non-gaming row ends the override early.
After the override expires, continued eligible gaming can create a new decision for the same continuing session instead of remaining permanently deduplicated.

## Safety

The override is factual and local.
It does not stop Screenwatch accounting, hide the unfinished priority task, alter gaming totals, mutate the plan, or disable future coaching permanently.
Normal work-window, pause, baseline, coverage, gaming-allowance, daily-limit, and cooldown gates remain authoritative.

## Focused proof

`swift test --filter GamingDriftPromptServiceTests` passed.
The focused suite proves immediate durable suppression, restart persistence, early termination when work resumes, expiry, renewed coaching after expiry, and a distinct replacement prompt.

## Verifier plan

A fresh verifier should rebase this candidate onto the latest authoritative root and rerun the focused gaming-drift suite once.
Using the serialized signed-QA runtime, seed a post-baseline accountability prompt, choose Continue intentionally in Today, confirm immediate closure, confirm the factual response row, advance the deterministic clock within and beyond the cooldown, insert a work observation for early termination, and verify gaming totals and the incomplete task remain visible throughout.
Keep `ZC-036-004`, `ZC-036-005`, and `ZC-036-006` conservative because review presentation and broader intentional-context UI are not owned here.
