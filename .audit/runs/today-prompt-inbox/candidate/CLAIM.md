# Today Prompt Inbox Lifecycle Claim

## Baseline

This isolated implementation lane starts from authoritative commit `b452949`.

## Owned scenarios

- `ZC-006-006` - Dismiss planning temporarily without being trapped in repeated prompts.
- `ZC-013-009` - See recent coach decisions.
- `ZC-033-011` - Find the same unresolved prompt in the dashboard if the initial surface disappears.
- `ZC-034-013` - Ignore or dismiss the prompt.
- `ZC-034-015` - See a refreshed state instead of applying an action from an outdated prompt.
- `ZC-038-003` - Find every unresolved prompt in the dashboard.
- `ZC-041-011` - See coaching prompts and responses.
- `ZC-053-007` - Restart with an unresolved prompt and see its current valid state.

## Boundaries

This lane owns the local prompt-inbox timeline model, store query, Today XPC fetch, a dedicated Today inbox view, focused tests, and candidate evidence.
It does not modify Reminders recovery, onboarding composition, the authoritative tracker, registry, Lavish artifact, shared runtime, migrations, or notification delivery.
