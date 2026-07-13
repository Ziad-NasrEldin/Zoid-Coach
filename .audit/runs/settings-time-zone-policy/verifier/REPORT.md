# Settings time-zone policy verifier report

## Rebase and source gate

The candidate commits `8423906`, `389ed26`, and `5375024` cherry-picked cleanly onto authoritative commit `4cc05de` as `33f5bda`, `409e3ae`, and `aedc669`.

The implementation presents the sorted `TimeZone.knownTimeZoneIdentifiers` collection, persists the selected identifier in `SchedulePolicy`, and provides a direct action that restores `TimeZone.current.identifier`.

The visible detail derives the selected zone's current UTC offset with hour and minute precision, identifies whether it matches the Mac, and explains that historical instants remain unchanged.

Time-zone edits participate in the existing three-way Settings merge so an independent concurrent edit survives, a competing zone keeps the current winner, and deliberate reapply retains the user's proposed zone.

The persistence test reopens both `PolicyStore` and `TaskHistoryStore` after a zone mutation and confirms that the exact historical completion `Date` remains unchanged.

No source blocker was found.

## Automated evidence

`swift test --filter SettingsPolicyDraftTests` passed all 29 selected tests in the verifier's single focused run.

The single signed QA package completed successfully at `.build/app-qa/Zoid 666 QA.app`.

Package verification confirmed coherent application, LaunchAgent, Mach service, and signing identities.

The verifier worktree was clean after packaging.

## Signed installed acceptance

The exclusive runtime lease was granted after the review-reminder verifier removed its application, helper, and runtime root.

The signed QA application ran from `/private/tmp/zoid-settings-time-zone-installed/Zoid 666 QA E2E.app` with isolated root `/private/tmp/zoid-qa-settings-time-zone-verifier` and build identity `zoid-coach-aedc669a5cc5da5457684a670b690f8bcb060de4-clean`.

Settings visibly presented the full IANA picker, `Africa/Cairo`, `UTC+03:00`, the Mac match explanation, the historical-instant explanation, and `USE MAC TIME ZONE`.

The user selected `America/Los_Angeles`, saw `UTC-07:00`, saved policy version 2 through the live helper, reopened Settings, restarted the application and helper, and saw the exact selection persist.

A proper concurrent `PolicyStore` client changed the saved zone to `Europe/London` while the user held a Los Angeles draft.

The signed interface named `Time zone` under both changed-elsewhere and needs-decision copy, preserved the London winner, retained the Los Angeles proposal, and saved Los Angeles as policy version 6 only after deliberate `REAPPLY MY CHANGES`.

A second proper concurrent client changed planning capacity to 55 percent while the user held a Tokyo zone draft.

The signed interface named only `Planning capacity`, kept the Tokyo draft ready, showed 55 percent, and saved policy version 8 with both `Asia/Tokyo` and 55 percent intact.

The user created, started, and completed `Historical instant proof` in the signed application.

Daily Review visibly retained the completed local task and displayed its completion record.

Storage recorded the completion as the exact UTC instant `2026-07-13T11:21:36Z`.

After additional zone changes, `USE MAC TIME ZONE`, save, application restart, and helper restart, storage still contained the byte-identical UTC value and Settings restored `Africa/Cairo`, `UTC+03:00`, the Mac match, and the independently merged 55 percent capacity.

Today visibly remained Monday, 13 July during the run because Cairo, Los Angeles, and Tokyo shared the same calendar date at the actual verification instant.

The application has no installed QA clock fixture, so this run does not claim a signed divergent-local-date boundary for Today.

The QA helper was unregistered, the application and helper were stopped, both isolated roots were removed, and the runtime lease was released.

`ZC-053-010` remains outside this candidate because moving an existing plan across local-day boundaries still requires a separate explicit-confirmation implementation.
