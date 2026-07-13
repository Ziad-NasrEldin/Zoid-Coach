# QA ready-state repair verifier report

## Verdict

READY.

The repaired fixture now creates a completed isolated QA root, is consumed exactly once by the signed installed helper, and opens the signed foreground app directly at Today before and after relaunch.
This report supersedes the runtime-readiness verdict in the historical failure report while preserving that report as root-cause evidence.

## Scope and commits

- Authoritative base: `e086394`.
- Original foundation: `ecff514`, already represented by the earlier integrated candidate history but absent as files on the authoritative tree.
- Repair candidate: `04bf032`.
- Verifier repair/foundation resolution: `1605daf` before the probe heading fix and this report.
- QA root: `/private/tmp/zoid-666-qa-ready-repair-2229`.
- Isolated install root: `/private/tmp/zoid-666-qa-ready-repair-install-2229`.

The verifier restored only the claimed manifest, preparer, native probe, focused tests, guide, candidate report, and backlog surfaces.
No tracker, registry, Lavish artifact, production root, production app, real Reminder, Calendar event, notification, Screenwatch source, or system permission was changed.

## Foundation proof

- One `swift test --filter QAReadyStateFixtureTests` invocation passed all focused granted, deferred, independent-helper, exact-artifact, and fail-closed mismatch tests.
- `python3 -m py_compile Scripts/prepare-qa-ready-state.py` passed.
- `swiftc -typecheck Scripts/qa-window-content-probe.swift` passed before signed acceptance.
- One release QA package built the app and helper successfully.
- Package structure, LaunchAgent identity, Mach service identity, strict signatures, and Designated Requirements passed.

The corrected example uses `qa-ready-notification` for both the notification ID and nested prompt ID.
The preparer rejects a mismatched identity before staging or replacing the destination root.

## Exact signed install and helper consumption

The exact already-built signed package was copied to the isolated install root without rebuilding.
The installed app registered the QA LaunchAgent, and the helper ran from that exact package with the prepared QA root.

The helper consumed the request exactly once:

- `os-fixture-request.json` was removed.
- `os-fixture-request.processing.json` was removed.
- `os-fixture-snapshot.json` was written.
- The canonical state recorded one successful `qa-ready-state-seed-v1` receipt and audit event.
- Calendar, Reminders, and notifications permissions were granted.
- The `work` Reminder list and `qa-ready-task` Reminder were present.
- The `qa-ready-calendar` commitment was present.
- The corrected `qa-ready-notification` was scheduled with the matching nested prompt ID.
- The healthy Screenwatch fixture contained one versioned record.

The focused deferred-state journey separately proved finished onboarding with deferred Reminders, Screenwatch, and notifications plus their canonical not-determined fixture permissions.

Artifact SHA-256 values after signed consumption:

- Canonical OS fixture state: `c0ca3239b1130cf732a1dbfa49f8b601f63adbcd8f0746877dd620e38336028f`.
- Helper snapshot: `1db372230f6eeb4bad1b7aabd1589e1eb5b63ac396780476a06f9e2d34fb10ea`.
- Completed onboarding progress: `ef885b6ea8b225b8246d5a5e526f5a427df8c093f59383a9dab53ec708398d69`.
- Screenwatch record: `d15d9327b2a7e9cf90f601aeb845936fea8d41efa1b00a1b403df285ed090d33`.

## Today and pixel acceptance

The initial probe exposed a probe-only stale heading expectation.
Pixel and native AX diagnostics showed the current production heading is `TODAY / INBOX`, while the probe still required the unused `ZOID 666 - TODAY` string.
The verifier updated only the probe and guide to require the current heading without weakening geometry or content thresholds.

First foreground launch passed:

`GREEN: Today is visible in a non-minimized 1180x760 window with 119 AX content nodes`

After terminating only the foreground app and launching the same installed package again, relaunch passed:

`GREEN: Today is visible in a non-minimized 1180x760 window with 118 AX content nodes`

Pixel evidence:

- `today-first-launch.png`, SHA-256 `811d8641f313a841cafb84de73381c0041d25e8c93903dee804b9475b16d6868`.
- `today-relaunch.png`, SHA-256 `d8d2cbc993b70524c9aa246a84c7efcfa493e63e0a9bbec5c92e104ead6cadcc`.

Both images show Today selected, the `TODAY / INBOX` heading, a usable unplanned-day decision surface, first-week observation, and the Today task area without onboarding.

## Mismatch safety

An explicit manifest with notification ID `qa-ready-notification` and nested prompt ID `mismatched-prompt-id` was run with `--replace` against an existing isolated root.
The preparer exited 2 with `SETUP_FAIL: notification qa-ready-notification desired.promptID must match its id`.
The destination still contained only its 12-byte sentinel with SHA-256 `d4383fc33176254b2abac7cb3c14bcaae5701681537db3d69adf740b1feb1b9c`.

## Runtime cleanup

The verifier unregisters the QA LaunchAgent, removes the isolated installed package, confirms no QA app or helper remains, releases the runtime lease, and removes temporary roots after integration.
