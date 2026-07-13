# Settings time-zone policy candidate report

## Revisions

- Base: `4cc05de`.
- Claim: `8423906`.
- Implementation: `389ed26`.
- Candidate tip: this report commit.

## Implemented behavior

- Settings now exposes the persisted policy time zone rather than describing every schedule as tied permanently to the Mac's current zone.
- The user can choose any known IANA time-zone identifier or restore the Mac's current zone directly.
- The visible explanation shows the selected UTC offset, whether it matches this Mac, and the boundary that historical event instants remain unchanged.
- Saving rebuilds `SchedulePolicy` with the selected zone, so planning, review, gaming, and other existing local-day consumers automatically use the new policy value.
- Time-zone edits participate in the existing three-way Settings conflict resolver.
- An independent concurrent Settings edit is merged safely, while competing time-zone choices surface as an explicit overlap with current values preserved until deliberate reapply.
- Existing task-history timestamps remain stored as the same UTC instant across policy mutation and database restart.

## Automated evidence

- `swift test --filter SettingsPolicyDraftTests` passed after the final implementation.
- The focused suite covers draft round-trip, valid policy output, independent merge, overlapping time-zone conflict, policy persistence, database restart, and exact historical event-instant preservation.
- The complete app target compiled as part of the focused Swift test run.
- `git diff --check` passed before commit.
- A release QA package completed successfully.
- The package verifier reported coherent app, LaunchAgent, Mach service, and signing identities.
- The signed candidate is available at `.build/app-qa/Zoid 666 QA.app`.

## Independent verifier plan

1. Rebase or cherry-pick the candidate onto the current authoritative root.
2. Install the freshly signed isolated QA app without replacing the normal installed app.
3. Open Settings and verify that the persisted policy zone, UTC offset, Mac-zone comparison, `USE MAC TIME ZONE`, and stable accessibility identifiers are visible.
4. Select `America/Los_Angeles`, save through the background agent, close Settings, reopen it, and verify that the exact selection remains.
5. Restart the app and helper, then verify the same selection again and confirm that Today uses the selected policy zone for its local date.
6. Create and complete a local task before the zone change, record its exact UTC completion instant, change zones, and verify that Daily Review and storage still reference the same historical instant.
7. Apply an independent concurrent Settings change while changing the zone and verify that both changes survive without a conflict.
8. Apply a competing time-zone mutation from another policy client and verify that the conflict panel names `Time zone`, keeps the winning current value, and offers deliberate reapply.
9. Use `USE MAC TIME ZONE`, save, restart, and verify that the policy returns to this Mac's current identifier.
10. Keep `ZC-053-010` conservative because explicit confirmation before moving an existing plan across local-day boundaries remains a separate implementation slice.
11. Let the verifier alone update the tracker, registry, backlog, and Lavish audit after installed proof passes.
