# Screenwatch Recovery UX Candidate

## Scope

This candidate owns `ZC-003-001` through `ZC-003-008`, `ZC-044-009`, `ZC-048-003`, and `ZC-049-006`.
It deliberately excludes `ZC-003-009`, which remains part of the separate screenshot-analysis policy surface.

## End-user behavior

- Settings now contains a dedicated Screenwatch Connection card available after onboarding.
- The card names whether the expected location or a chosen folder is authoritative.
- Healthy, stale, missing, malformed, expired bookmark, inaccessible, and unsafe path states use readable labels rather than internal enum names.
- Every state explains what is known, what remains limited, and the smallest useful recovery action.
- Recheck uses the existing canonical no-follow source boundary.
- Choose Folder validates a direct days directory, stores the canonical security-scoped bookmark, and never shows captured content or file locations in status or errors.
- Use Expected Folder clears the alternate selection and immediately re-inspects the default source.
- Returning to the app rechecks the confirmed source without creating a second selection or silently changing folders.
- A failed selection preserves the prior confirmed status and provides redacted actionable copy.

## Focused proof

- `swift test --filter ScreenwatchConnectionController` passed three controller journeys covering invalid default to healthy alternate to default, foreground recovery without reselection, and redacted selection failure with confirmed-state retention.
- `swift test --filter ScreenwatchSetup` passed the existing setup, schema, security-scoped bookmark, unsafe-path, malformed-record, missing-log, stale-log, and privacy tests.
- The application target compiled through both focused runs.
- No root, installed runtime, tracker status, registry, or Lavish artifact was changed.

## Fresh verifier instructions

1. Rebase `1fde15e` and the documentation handoff commit onto the authoritative integration tip.
2. Run the focused controller and setup suites once, then one release build.
3. Install a clean signed QA package with a dedicated run root.
4. Open Settings and inspect Screenwatch Connection with no source, a valid current default source, a stale source, and malformed JSONL.
5. Choose a valid alternate days folder inside the QA root and confirm the card changes to Chosen Folder and Healthy without displaying captured titles, URLs, screenshots, or the selected path.
6. Relaunch and confirm the same alternate source remains authoritative.
7. Move or invalidate the selected folder, relaunch, confirm Folder Access Expired or Folder Unavailable, choose it again, and verify recovery.
8. Use Expected Folder and confirm the alternate bookmark is cleared and default-source truth is restored after restart.
9. Attempt a file, symlink, and outside-QA-root selection and confirm the last healthy status remains while only redacted repair copy appears.
10. Update the tracker and registry only for states visibly proven by the signed journey.

## Lineage and integration

- Authoritative base: `55c86bb`.
- Claim commit: `59688bc`.
- Implementation candidate: `1fde15e`.
- Cherry-pick the claim, implementation, and documentation handoff commits in order.
- Rollback by reverting those commits; no migration or durable schema change is involved.
