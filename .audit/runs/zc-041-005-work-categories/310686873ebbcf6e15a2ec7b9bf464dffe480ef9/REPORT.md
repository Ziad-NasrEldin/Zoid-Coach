# ZC-041-005 work-category ledger composite verification

## Verdict

ZC-041-005 is Touches Remaining at integration tip `310686873ebbcf6e15a2ec7b9bf464dffe480ef9`.

The six-category product implementation, persisted correction and merge reconstruction, focused tests, signed packaging, exact isolated runtime binding, foreground launch ordering, visible Today prerequisite, and empty fixture database assertions passed.
The installed empty-ledger UI assertion did not run because the final AX probe rejected an unrelated auxiliary non-minimized window instead of selecting the stable visible Today main window.

This report does not qualify the scenario as fully usable end to end.

## Integrated identity

- Canonical base before integration: `5eae9182b2ea03aa3831f04b377faf8590e7f087`.
- Product candidate: `330fe53ba2bebb819686a688a961eb3c5a5acf50`.
- Current-base product and verifier tip: `310686873ebbcf6e15a2ec7b9bf464dffe480ef9`.
- The final tip is a fast-forward descendant of the canonical base.

## Product functionality now present

- Daily Review contains a dedicated corrected-work category ledger.
- The ledger has six stable categories: Deep work, Creative work, Research, Communication, Administration, and Uncategorized work.
- Category totals are derived conservatively from effective corrected Work sessions.
- Persisted corrections reconstruct after store reopen.
- Persisted merges use the chosen left session as classification authority.
- Mixed or ambiguous application evidence remains Uncategorized instead of being guessed.
- Gaming and other non-work sessions are excluded.
- The ledger, detail, empty state, and each category row expose stable accessibility identifiers.
- The namespaced fixture owns only `qa-zc041005-*` corrections, merges, and observations in its bounded time range.

## Passed focused tests

The independent current-base run executed seven focused tests in one suite with zero failures.

The four `DailyReviewWorkCategoryStateTests` covered:

- Conservative corrected-work grouping and non-work exclusion.
- Honest no-work and ambiguous-only states.
- Mixed-application merged sessions remaining Uncategorized.
- Stable ledger, detail, empty, and category accessibility identifiers.

Three persisted-store tests covered:

- Reconstructing category totals after store reopen.
- Preserving Work-left merge authority after reopen.
- Excluding a non-work-left merge after reopen.

## Passed signed package and runtime proof

Across the independent and corrected signed runs, the following gates passed:

- Clean release QA packaging.
- Nested helper and app signing.
- Deep strict code-sign verification.
- Exact package and build identity verification.
- LaunchAgent and Mach service coherence.
- Writable isolated XPC runtime and prompt timeline.
- Exact installed app executable binding.
- Exact helper executable binding.
- Exact embedded QA root binding.
- Exact isolated database binding.
- Proof that the helper held the isolated database open.
- Supported 12-of-12 post-onboarding ready-state preparation.

## Corrected foreground launch proof

The original run registered the helper before opening the app.
The helper started the parent with `--background-schedule`, and the normal menu-bar Open Today action could not keep a main window visible under that lifecycle policy.

The final verifier corrected the ordering.
It kept the helper unregistered, launched the exact installed QA app with the packaged `--qa-open-main` presentation route, and bound PID 15065 before helper registration.
It then registered the helper and proved that the same foreground PID remained bound to helper PID 15156 and the exact isolated database.
The Today probe passed with one visible 1180 by 760 main window and 106 accessibility content nodes.

## Passed empty fixture database proof

The fixture prepared and asserted the namespaced non-work-only state successfully.
That database state contained three persisted Gaming observations and no corrected Work rows eligible for category presentation.
The exact foreground app relaunched with `--qa-open-main` and passed app, helper, database, root, and build preflight again.
An independent Today probe passed after relaunch with the visible 1180 by 760 Today window and 112 accessibility content nodes.

## Remaining signed acceptance gate

The category AX probe currently collects every non-minimized AX window and requires the total count to equal one.
The signed app exposed an auxiliary non-minimized AX window alongside the valid Today window, so the probe failed with `expected exactly one non-minimized app window`.
The probe must select the one visible stable main Today window by its main-window identity or verified Today content, ignore unrelated auxiliary windows, and still fail when the main candidate is absent or ambiguous.

After that verifier correction, one signed installed-app run must prove all of the following:

- Normal Reviews navigation opens the Daily Review from Today.
- The non-work-only fixture exposes the honest `NO CORRECTED WORK TO CATEGORIZE` state.
- No category rows appear for the non-work-only fixture.
- The full 33-observation, 10-correction, and four-merge fixture passes its database assertions.
- The ledger exposes exactly Deep work 2, Creative work 3, Research 4, Communication 5, Administration 6, and Uncategorized work 8 minutes.
- The six visible rows total exactly 28 corrected Work minutes.
- Detail copy explains saved corrected-session authority and the chosen left session after a merge.
- The Gaming-left merge and standalone non-work observations remain excluded.
- Raw fixture application names, fixture IDs, private titles, and private URLs remain absent from the recursive accessibility tree.
- App and helper relaunch without database mutation reconstructs the same six rows and totals.
- Cleanup removes only the owned corrections, merges, and observations.

## Cleanup and isolation

- The full fixture was never prepared because the empty UI verifier failed first.
- The empty fixture cleanup completed successfully.
- The final signed QA runtime was uninstalled.
- The QA LaunchAgent was absent after cleanup.
- The isolated installed app was absent after cleanup.
- The isolated worktree was removed.
- Production app and database state were not changed.

## Durable evidence

- `initial-install.log` records the first release package, signing, XPC, LaunchAgent, and installed-app proof.
- `initial-runtime-binding.txt` records the exact helper executable, PID, isolated database binding, and background parent command from the first run.
- `final-install.log` records final-tip release packaging, signing, XPC, LaunchAgent, and installed-app proof.
- `final-empty-probe-failure.log` records the honest auxiliary-window verifier failure.
- `Tests/ZoidCoachAppTests/DailyReviewWorkCategoryStateTests.swift` contains the four focused presentation tests.
- `Tests/ZoidCoachAppTests/DailyReviewTests.swift` contains the three focused persisted reconstruction and merge-authority tests.
- `docs/ZC-041-005-SIGNED-QA-RUNBOOK.md` records the exact signed acceptance contract.

## Tracker decision

The previous Barely Started description is no longer accurate because the category model, historical review presentation, persistence semantics, focused tests, signed runtime binding, foreground Today route, and empty fixture database proof now exist.
Fully Implemented would also be inaccurate because the installed ledger rows, privacy tree, and relaunch reconstruction have not passed the corrected AX journey.
Touches Remaining is therefore the strict supported status.
