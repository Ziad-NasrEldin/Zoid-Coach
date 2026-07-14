# ZC-044-004 manual workday composite verification

## Verdict

ZC-044-004 is Touches Remaining at integration tip `6ca83f4103f6470bb788b7ef4534b35accfdd242`.

The product implementation and focused automated coverage are present.
The signed package, helper, isolated runtime, exact database binding, and supported post-onboarding ready state also passed.
The complete installed-app journey did not run because the final verifier registered the helper before launching the foreground app.
The helper therefore started the app with `--background-schedule`, and LaunchServices reused that process instead of starting it with `--qa-open-main`.

This report does not qualify the scenario as fully usable end to end.

## Integrated identity

- Canonical base before integration: `36bc8e48b5ea5258320e543be10e49737f63d49c`.
- Product candidate: `03ed2a3ef6e14bd91cb0903d4c8b98be6ecdfa87`.
- Final product and verifier tip: `6ca83f4103f6470bb788b7ef4534b35accfdd242`.
- The final tip is a fast-forward descendant of the canonical base.

## Product functionality now present

- Settings exposes a scheduled or manual workday-control choice.
- Manual mode disables fixed workday-hour controls while preserving planning windows.
- Settings save and conflict resolution carry the manual-workday choice through the versioned policy model.
- The menu-bar task surface exposes stable Start Workday and End Workday accessibility identifiers.
- End Workday uses an explicit destructive confirmation before changing task state.
- The product has stale-state handling intended to reject changed Start and End actions without applying an illegal mutation.
- The verifier fixture owns only the `qa-zc044004-*` namespace and restores the original policy payload during cleanup.

## Passed focused proof

`swift test --filter ManualWorkdayControlTests` passed five of five focused tests on the original independent candidate run.

Those tests covered:

- Legacy policies defaulting to scheduled workday control.
- Manual Settings draft behavior and disabled fixed-hours semantics.
- Versioned persistence of the manual-workday choice.
- Menu-bar Start and End accessibility identities.
- Conflict resolution preserving the independent manual-workday choice.

## Passed signed package and runtime proof

Across the independent and corrected signed runs, the following gates passed:

- Clean release QA packaging.
- Nested helper and app signing.
- Deep strict code-sign verification.
- Exact package and build identity verification.
- LaunchAgent registration and installed helper identity.
- Mach service validation.
- Writable isolated XPC runtime and prompt timeline.
- Exact installed app executable binding.
- Exact helper executable binding.
- Exact isolated database binding.
- Proof that the helper held the isolated database open.
- Supported 12-of-12 post-onboarding ready-state preparation.
- QA LaunchAgent unregister and register operations.
- Cleanup of each isolated signed runtime.

## Signed verifier progression

The first independent run reached the installed signed app but did not establish a supported normal route to the Command Settings chapter before its cap.

The corrected rerun established the supported 12-of-12 ready state.
Its plain LaunchServices reopen retained a windowless scene, so the Today probe honestly failed with `SETUP_FAIL: Zoid window did not appear`.

The final verifier used the existing QA-only `--qa-open-main` foreground presentation argument and required preflight proof that the exact installed PID received it.
That preflight exposed a launch-order race before any scenario fixture mutation.
The helper had already started PID 57664 as:

```text
/private/tmp/zoid-666-zc044004-final-install/Zoid 666 QA E2E.app/Contents/MacOS/ZoidCoachQA --background-schedule
```

LaunchServices reused that process, so the expected `--qa-open-main` argument was absent.
The preflight rejected the run rather than treating a background process as foreground acceptance evidence.

## Remaining signed acceptance gate

The verifier must keep the helper unregistered while preparing the ready state, launch the exact installed QA app with `--qa-open-main`, bind that foreground PID, and then register the helper while the foreground app is already running.

After that ordering correction, one signed installed-app run must prove all of the following without interruption:

- The normal Today window is visible after the supported ready-state preparation.
- Normal user navigation opens Settings and the Command policy section.
- The user selects Manual start and end.
- Fixed workday-hour controls become disabled.
- Save completes with visible success feedback.
- Manual mode and disabled fixed-hours controls persist after app and helper relaunch.
- A ready owned task exposes Start Workday and omits End Workday.
- Start Workday produces one active task and one open activity interval.
- The active state exposes End Workday and omits Start Workday.
- Confirmed End Workday closes the interval and produces the ended resume state.
- The ended state persists after app and helper relaunch.
- A stale Start action is rejected honestly without mutation.
- A stale End confirmation is rejected honestly without mutation.
- Invalid Start and End controls remain omitted in every lifecycle state.
- Recursive accessibility scans expose no fixture IDs, fixture notes, database paths, or private QA-root paths.
- Cleanup restores the original policy and removes every fixture-owned row.

## Cleanup and isolation

- No final-run fixture mutation occurred because foreground preflight failed first.
- The final signed QA runtime was uninstalled.
- The QA LaunchAgent was absent after cleanup.
- The isolated installed app was absent after cleanup.
- The isolated worktree was removed.
- Production app and database state were not changed.

## Durable evidence

- `initial-independent-report.md` records the five focused tests, original package proof, first signed attempt, and cleanup.
- `rerun-install.log` records corrected-tip package signing, XPC readiness, LaunchAgent registration, and installed-app launch.
- `rerun-window-probe.log` records the honest missing Today-window prerequisite.
- `final-install.log` records final-tip package signing, XPC readiness, LaunchAgent registration, and installed-app launch.
- `final-foreground-preflight-failure.txt` records the exact background process command that blocked foreground acceptance.

## Tracker decision

The previous Not Implemented description is no longer accurate because the source-ready product, focused tests, signed packaging, runtime binding, and ready-state setup now exist.
Fully Implemented would also be inaccurate because no signed run completed the user journey.
Touches Remaining is therefore the strict supported status.
