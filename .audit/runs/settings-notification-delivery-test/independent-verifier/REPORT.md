# Settings Send Test Notification Independent Verification

## Scope

This lane independently verified candidate `a9a5011a2cfd01aca3fa38fcf3574bbd9f0e657a` against authoritative base `27f034a779aef110a93942a51b25d71643a0c0d3`.
The verifier repair commit is `ad91b549123ea95612a26722e295fe214e3481e1`.
No tracker, registry, Lavish, gaming, or unrelated mutation files were changed.

## Source Review

The live Settings path reads the existing `UNUserNotificationCenter` authorization state and never requests permission.
The live signed-QA path requires the QA package mode, QA runtime identity, and one explicit marker inside the isolated QA root.
Unpackaged QA remains unable to call the production notification center.
Denied authorization schedules nothing and returns an exact manual System Settings route plus the usable Today fallback.
Scheduling failures expose fixed privacy-safe copy while the local ledger applies path and address redaction.
Every terminal path attempts one durable ledger event and the existing ledger enforces the 30-day retention boundary.

## Defects Found And Repaired

The candidate initially failed to compile because the notification-authorization switch expression could not infer its result enum.
The verifier made all three result values type-explicit.
The verifier consumed the two best-effort `try?` ledger results to remove new unused-result warnings.
The candidate tests initially failed to compile because they referenced `RuntimeEnvironment` without importing `ZoidCoachCore`.
The verifier added only that missing test import.

## Automated Verification

`git diff --check` passed.
The focused Settings notification command ran seven tests and all seven passed.
Those tests cover retry, duplicate suppression, the signed-QA marker boundary, unpackaged-QA refusal, authorized scheduling and ledger reopen, denied authorization without scheduling, privacy-safe visible failure copy, and redacted diagnostics.
One `swift build -c release` completed successfully in 73.51 seconds.
Both release executables were present after the build.
The remaining compiler warnings came from pre-existing unrelated files.

## Signed Native Journey

The clean signed QA package identified build `zoid-coach-ad91b549123ea95612a26722e295fe214e3481e1-clean`.
The package and helper were installed under `/private/tmp/zoid-666-send-test-install` with isolated data under `/private/tmp/zoid-666-send-test-qa-root`.
The native visibility probe found a non-minimized 1180 by 760 Today window with 112 accessibility content nodes.
The verifier navigated from Today to Settings and then Signals using native AX button actions.
The stable control `settings.notifications.send-test` was present with the visible action `SEND TEST NOTIFICATION`.
The verifier issued two immediate AX press requests.
The controller produced exactly one ledger event, proving the duplicate action did not create a second effect.
The Mac reported the existing signed-QA notification authorization as unavailable.
No permission request was opened, no System Settings process was opened, and no system setting was changed.
The terminal native AX state was `TEST UNAVAILABLE - USE TODAY`.
The terminal detail was `Notifications are not enabled. Open System Settings > Notifications > Zoid 666 > Allow Notifications. Coaching choices remain available in Today.`
The detail contains no private path, address, notification content, or other user data.
The local ledger stored one `authorization_unavailable` event for `settings-notification-delivery-test`, with attempt `1`, no replacement flag, and no error payload.
After killing and relaunching both the app and helper, Settings Signals exposed `settings.notifications.delivery-history` and the exact persisted row `TODAY FALLBACK, Onboarding Test, The unresolved choice remains available in Today, TRY 1`.

## Pixel Evidence

`today-ready-state.png` proves the clean signed app opened on the expected Today surface.
`settings-signals-before.png` proves native navigation reached the installed Settings Signals surface.
`settings-signals-denied.png` records the same installed Settings Signals surface after the denied Send Test action.
The result card was below the visible viewport, so the terminal result is proven by stable native AX identifiers and the persisted ledger rather than a readable result-card screenshot.

## Verdict

The denied and unavailable end-user journey is fully usable, truthful, privacy-safe, duplicate-safe, and durable across app and helper relaunch.
The source and focused automated gates pass after verifier repair commit `ad91b549123ea95612a26722e295fe214e3481e1`.
`ZC-044-012` should remain `Touches remaining` under the strict positive-scenario bar because this Mac's existing authorization prevented an actual macOS scheduling and visible-delivery run.
The only remaining acceptance gap is one already-authorized signed identity proving real system acceptance and visible notification appearance without changing authorization during the verifier run.
