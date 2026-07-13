# Screenwatch Recovery UX Claim

## Baseline

This isolated implementation lane starts from authoritative commit `b452949`.

## Owned scenarios

- `ZC-003-002` - See whether the detected Screenwatch source is healthy.
- `ZC-003-003` - Select another Screenwatch folder when the default location is unavailable.
- `ZC-003-004` - Understand why a selected folder is invalid without seeing sensitive captured content.
- `ZC-003-006` - Open the repair path when folder access is denied.
- `ZC-003-007` - Return after repairing access and see Screenwatch become connected.
- `ZC-003-008` - Understand that screenshots are not routinely inspected.
- `ZC-003-009` - Choose whether screenshot analysis may be used for genuinely ambiguous situations.

## Boundaries

This lane owns only a cohesive end-user Screenwatch setup and recovery surface plus focused tests and candidate evidence.
It does not modify Reminders recovery, root composition locks, the authoritative tracker, registry, Lavish artifact, shared runtime, migrations, or canonical Screenwatch repository and ingestion services.

## Released before implementation

The claim was released immediately after file-ownership inspection showed that completing the end-user flow would overlap the active Reminders recovery lane in onboarding composition files.
No product source or test file was modified under this claim.
