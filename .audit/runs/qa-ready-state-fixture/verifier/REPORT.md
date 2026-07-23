# QA ready-state fixture verifier report

## Verdict

NOT READY.

The isolated compiler, schema tests, probe typecheck, package, signing, and malformed-input safety checks pass.
The installed signed app does not reach Today from the prepared root, so this fixture must not be offered to other signed scenario verifiers yet.

## Candidate and environment

- Authoritative base: `2427302`.
- Candidate: `280e3c4`, cherry-picked as `c2dd251` in the verifier worktree.
- QA root: `/private/tmp/zoid-666-qa-ready-verify-2204`.
- Isolated install root: `/private/tmp/zoid-666-qa-ready-install-2204`.
- Runtime lease was granted and the installed runtime was unregistered and removed immediately after the failed probe.

No production root, production application, real Reminder, Calendar event, notification, Screenwatch source, or system permission was mutated.

## Passing foundation checks

- `swift test --filter QAReadyStateFixtureTests` passed all three focused tests.
- `python3 -m py_compile Scripts/prepare-qa-ready-state.py` passed.
- `swiftc -typecheck Scripts/qa-window-content-probe.swift` passed.
- Release QA packaging passed for both app and helper.
- Package coherence, strict code-sign verification, and Designated Requirement validation passed.
- The signed runtime installer registered and started the exact isolated helper from the installed package.

The generated example artifacts had these SHA-256 values:

- Onboarding progress: `ef885b6ea8b225b8246d5a5e526f5a427df8c093f59383a9dab53ec708398d69`.
- OS fixture request: `f510e30562aaba4d0348e558375c50a50abb8360af46878837af7dea301212af`.
- Normalized manifest: `f32f68c76abe28a13bb0c5c8e5258f8cfa6c8d808e835891cd332521100bf41d`.

The versioned example request contained request ID `qa-ready-state-seed-v1`, granted Calendar, notification, and Reminder permissions, one Reminder list, one active Reminder, one Calendar commitment, and one scheduled notification.
The prepared onboarding file represented completed 12-of-12 onboarding with granted Reminders, notifications, and Screenwatch plus the included `work` Reminder list.

## Signed blocker

The installer preserved the prepared root with `ZOID_COACH_QA_KEEP_DATA=true` and launched the signed foreground app and registered helper.
The helper was reported running from the exact isolated installed package.
The control file moved from `os-fixture-request.json` to `os-fixture-request.processing.json` but never completed.
`OS Fixtures/state.json` remained the empty schema version 1 state with no permissions, Reminder lists, Reminders, Calendar commitments, notifications, receipts, or audit entries.

The exact processing request encoded the permissions as the existing fixture pair sequence `calendar, granted, notifications, granted, reminders, granted` and carried the expected configured records.
The equivalent focused in-process test decoded and applied that request successfully, so this run did not establish a deterministic manifest-schema defect.

Native Accessibility produced these terminal results:

- `--expect-today`: `SETUP_FAIL: Accessibility inspection failed: Today did not appear`.
- Generic launch probe: `SETUP_FAIL: Accessibility inspection failed: onboarding.continue did not appear in a non-empty launch window`.

The application therefore proved neither Today nor a usable onboarding fallback.
Relaunch acceptance was not attempted because the first signed launch failed and the runtime cap required stopping.
Unified logs showed the signed app and helper launch plus AppKit window restoration, but no product-level fixture decoding error was emitted.

## Malformed-root safety

An explicit malformed manifest was run with `--replace` against an existing isolated root containing `sentinel.txt`.
The preparer exited 2 with `SETUP_FAIL: manifest is missing: onboarding, osFixture, screenwatch`.
The root still contained only the 12-byte sentinel with SHA-256 `d4383fc33176254b2abac7cb3c14bcaae5701681537db3d69adf740b1feb1b9c`.

## Required next fix and acceptance

The top priority is to reproduce the installed app/helper startup path with product-level control-processing diagnostics.
The fix must guarantee one process owns the prepared request, commits the configured OS fixture state, writes a receipt and snapshot, and removes the processing file before Today depends on it.
The fresh signed acceptance must then prove configured Reminders, Calendar, notification, and Screenwatch state, direct Today geometry and content, pixel evidence, and Today again after relaunch.
