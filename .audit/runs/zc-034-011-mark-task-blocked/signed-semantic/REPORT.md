# ZC-034-011 Signed Semantic Verification

## Verdict

Strict Full eligibility was not reached.
The signed blocker workflow passed its successful, persistence, and helper-unavailable paths, but the native status-item prerequisite remained unverified and the exact invalid value `no` was not independently proven.

## Signed passes

- Verifier commit `9adf6f466d760569016ead93db6199366b1a39f1` passed standalone Swift typechecking and self-tests before runtime.
- The exact signed QA package passed package, nested signing, designated-requirement, helper registration, and isolated ready-state checks.
- Today exposed `today.prompt-inbox.empty` before prompt insertion.
- The delayed fixture inserted one waiting prompt with exactly six native `today.prompt.qa-zero-actions-block-1.action.*` buttons.
- Mark blocked opened the blocker sheet through native accessibility activation.
- The too-short validation message appeared and SQLite retained a presented prompt with zero responses.
- Cancel returned to the prompt with the prompt still presented and zero responses.
- Selecting `Waiting for approval.` and saving produced exactly one response, blocked the original task, persisted the exact reason, closed the open activity interval, and promoted the replacement main objective.
- Today exposed `today.prompt.qa-zero-actions-block-1.history.blocked-reason` with `BLOCKER · Waiting for approval.`.
- App relaunch preserved the blocked history and database state.
- Helper relaunch preserved the blocked history and database state.
- With the helper unregistered before Save Blocker, Today showed `The blocker was not saved. The last confirmed task and plan state are still shown.`.
- The helper-unavailable database remained presented with zero responses, the original task active, no blocked reason, and one open activity interval.

## Remaining gaps

- The signed background process was unhidden and windowless, but exact-PID accessibility exposed only the normal application menu.
- ControlCenter `AXExtrasMenuBar` exposed OS items and anonymous zero-frame extras without a semantic Zoid 666 candidate.
- System Events exposed only the normal application menu bar.
- No native status item could therefore be semantically matched, pressed, and tied to an `AXSystemDialog` containing `menu-bar.coach`.
- The before-and-after menu-bar screenshot differential was not completed before the hard cap.
- The temporary text setter failed, so the exact invalid input `no` was not independently proven even though the required too-short validation and zero database mutation were observed.

## Cleanup

- QA application process count was zero.
- The QA LaunchAgent was absent.
- The isolated install root, QA data root, temporary driver, and worktree build artifacts were removed.
- Product source, canonical tracker, production data, and user permissions were not changed.

## Evidence

The sibling files in this directory preserve signing, fixture, accessibility, database, registration, and helper-unavailable logs from the capped run.
No screenshots were captured during this run.
