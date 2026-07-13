# Launch at login conservative verifier

## Result

`ZC-044-001` is now **Touches remaining**.
The installed signed QA app visibly separates Launch at Login registration from runtime heartbeat health, exposes truthful reversible controls, and preserves the explicit disabled choice in focused relaunch proof.
The actual installed Disable and Enable actions were not activated because changing Launch at Login through Computer Use requires action-time user confirmation.

## Verified implementation

- `AgentLaunchService` exposes registration independently as Enabled, Waiting for Approval, Disabled, Unavailable, or Unknown.
- Enabled registration requires a fresh canonical local heartbeat before runtime health becomes Healthy.
- A stale or missing heartbeat reports Attention while Launch at Login remains Enabled and Disable remains available.
- Disable unregisters enabled and approval-pending registrations without deleting the local database.
- An explicit Disabled choice persists separately from the registration fingerprint.
- Foreground relaunch reconciles the explicit choice and no longer silently re-registers a user-disabled helper.
- Re-enable restores the existing registration and fingerprint reconciliation path.
- Disabled state no longer shows misleading macOS approval guidance.
- Approval-pending state gives the exact Login Items path, while enabled stale state gives repair guidance instead.

## Focused proof

- `swift test --filter "AgentLifecycleController|AgentLaunchService"` passed after the verifier fixes.
- The new relaunch regression disables registration, constructs a fresh launch service, proves zero re-registration, re-enables once, relaunches Enabled, and proves byte-identical local data throughout.
- The final rebased signed QA package passed release application and agent builds, LaunchAgent and Mach-service validation, signing-identity validation, strict on-disk signature validation, and designated-requirement validation.
- The signed Background Agent window visibly showed `HEALTHY` and `LAUNCH AT LOGIN ENABLED` with a fresh helper heartbeat.
- After the QA helper was frozen and only its isolated heartbeat was aged, the same signed window visibly showed `ATTENTION`, retained `LAUNCH AT LOGIN ENABLED`, displayed stale-helper repair copy, and kept `DISABLE LAUNCH AT LOGIN` available.
- The signed confirmation sheet explicitly stated that automatic background work stops while local plans, reviews, and history remain on this Mac.
- One seeded `task_history` record remained present before the confirmation and immediately before cleanup.
- The confirmation was cancelled, so no Launch at Login setting was changed.

## Evidence

- `current-enabled-healthy.jpeg` shows fresh runtime health and Enabled registration as separate facts.
- `stale-enabled-attention.jpeg` shows stale runtime Attention while registration remains Enabled and reversible.
- `disable-confirmation.jpeg` shows the local-data preservation and automatic-work impact copy.

## Exact remaining acceptance

1. Obtain action-time user confirmation to change Launch at Login through the installed UI.
2. Open the signed stale-Enabled state and accept Disable Launch at Login.
3. Prove the visible state becomes Disabled, the QA registration is removed, and seeded local history remains.
4. Terminate and relaunch the foreground app and prove Disabled persists without automatic registration.
5. Accept Enable Launch at Login, complete macOS approval if requested, and prove Enabled plus a fresh Healthy heartbeat.
6. Prove seeded local history remains after the complete disable and re-enable cycle.

The QA alert was cancelled, the frozen helper was resumed, the QA LaunchAgent was unregistered, and the installed QA app and isolated data root were removed.
