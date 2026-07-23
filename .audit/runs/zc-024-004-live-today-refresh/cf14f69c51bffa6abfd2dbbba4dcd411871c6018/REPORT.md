# ZC-024-004 Signed Acceptance

## Verdict

`ZC-024-004` is fully qualified by exact signed candidate `cf14f69c51bffa6abfd2dbbba4dcd411871c6018`.
The open Today dashboard refreshes behavior totals as new Screenwatch activity is observed without requiring a user command, app relaunch, or navigation round trip.
Polling pauses while the application is inactive, resumes with one immediate refresh when the app becomes active, and does not create duplicate timers.

## Canonical lineage and scope

- Canonical base: `ed5d07a363e0f64049c07b0e1d309d754caa035b`.
- Exact signed candidate: `cf14f69c51bffa6abfd2dbbba4dcd411871c6018`.
- Authoritative application-active fix: `6a3fe19f148b4988370716d562eba5437df5e67d`.
- Combined canonical-to-candidate patch ID: `0d83e27f0efa52d8a7112b291588048c99b69abb`.
- The isolated integration reconstruction has the same combined patch ID.

The candidate changes exactly these eight files:

- `Scripts/qa-zc024004-live-refresh-ax-probe.swift`
- `Scripts/qa-zc024004-live-refresh-fixture.sh`
- `Scripts/verify-zc-024-004-live-today-refresh-static.sh`
- `Sources/ZoidCoachApp/AppModel.swift`
- `Sources/ZoidCoachApp/TodayLiveRefreshLoop.swift`
- `Sources/ZoidCoachApp/ZoidCoachApp.swift`
- `Tests/ZoidCoachAppTests/TodayLiveRefreshLoopTests.swift`
- `docs/ZC-024-004-SIGNED-QA-RUNBOOK.md`

No tracker, registry, Lavish, unrelated source, or production-runtime file belongs to the candidate patch.

## Signed journey

The evidence journey status is `passed`.
The signed package identity is `qa.ziadnasreldin.ZoidCoach`.
The static verifier, fixture self-test, and accessibility-probe self-test passed.
The documented post-registration bootstrap restart established the valid signed baseline.
The visible baseline showed 2 work minutes and stale limited Screenwatch coverage.
The open Today screen updated to 7 work minutes and current coverage after new activity arrived without a command or relaunch.
Returning from Settings showed 12 work minutes.
Returning from a backgrounded app showed 17 work minutes after the application-active restart path.
An ordinary relaunch showed 22 work minutes and current coverage.
The exact restored isolated root showed 0 work minutes and no observations today, matching its original state.

Settings navigation paused live polling.
Finder backgrounding paused live polling.
Foreground activation restarted polling and performed the immediate refresh.
Ordinary relaunch restored the current persisted snapshot.
Unchanged snapshots remained stable between expected transitions.

## Immutable evidence

The original evidence directory is `/private/tmp/zoid-zc024004-evidence/cf14f69c51bffa6abfd2dbbba4dcd411871c6018-r6`.
This acceptance report does not modify or replace that directory.
The evidence manifest contains exactly 60 file entries.
Every entry passed `shasum -a 256 -c evidence-manifest.sha256` during independent integration.
The full SHA-256 of `evidence-manifest.sha256` is `98a7ecef9c34ce8fc2d157a2349968a989582442067368985925e2263c0d6b56`.
The signed journey summary SHA-256 is `34588562966155f9abce745537733094f9bddf5d16321499cf65a95aed53362a`.
The static-gates log SHA-256 is `8079995e77888e5b58b0e83c90b091a9ffec3a5fdc9a92e858eb70cad6cf2307`.
The privacy-scan log SHA-256 is `b6d40dd570677d22f53b8c5f4af73000035fa20c04270c908de87ee1ca736b09`.

## Privacy, cleanup, and production integrity

The privacy scan found no fixture identifiers, private window markers, or private URL markers in the captured snapshot JSON.
Fixture cleanup left `0` fixture rows.
The isolated database root was restored byte-for-byte with matching path and SHA-256 manifests.
The signed QA app was uninstalled.
The QA LaunchAgent was unregistered.
The production app and agent remained running.
The production before and after manifests are byte-identical and both have SHA-256 `48efc216a210fd9ed25dda4d9b9ddb7d8769b2509ce55c09f61be49d107853a0`.

## Integration boundary

The root integrator independently reconstructed and compared the canonical-to-candidate patch, checked all 60 evidence hashes, verified every journey phase, and reran the candidate static and focused gates.
The tracker and registry promotion is a separate protected integration change and does not alter the original signed artifacts.
