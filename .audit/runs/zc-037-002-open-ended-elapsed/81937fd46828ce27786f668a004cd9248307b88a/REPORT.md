# ZC-037-002 signed open-ended elapsed evidence reconciliation

Status: PASS

This reconciliation binds ZC-037-002 to the already accepted clean signed candidate `81937fd46828ce27786f668a004cd9248307b88a` without claiming a new runtime execution.
ZC-037-002, "See elapsed time for an open-ended task," is semantically identical to the accepted ZC-017-007 contract, "See elapsed time for an open-ended session," on the same installed Today surface.
Both scenarios require exactly `installed_app_e2e`, `ui_automation`, and `unit_rule` proof.

The signed runbook was dual-scoped before execution: its title is `ZC-017-007 and ZC-037-002 signed QA runbook`, its opening contract says the same journey accepts both scenarios, and its final promotion condition names both scenarios.
At signed commit `81937fd46828ce27786f668a004cd9248307b88a`, the runbook SHA-256 was `de0f214dac96b6542e3b493519a95b943c27e7ad1b412fe82295d1d4a937afbb` and its Git blob ID was `dd39eeab7e38f4e7291ed1725f655ed545ebb143`.
The same runbook blob remains present at canonical base `b97c2ce3177ccf89f60225c475062608db1920ad`.

The original immutable ZC-017-007 report SHA-256 is `992aa9dcd0af51f3c2b581d950ff6a2e64c14591fbc1277dc189c77e407dfa6f`.
The original immutable ZC-017-007 evidence manifest SHA-256 is `b1c71f3a746b97fd8f241bb42e748e6897930bcba7b035c0f32e7936660471aa`.
That accepted repository evidence proves the installed signed Today UI rendered one semantic live elapsed indicator, survived an ordinary relaunch, advanced from two to three minutes without timed-phase interaction, resisted clock rollback, exposed an honest last-refresh fallback, excluded bounded and paused tasks, rejected private fixture text, restored the isolated QA state exactly, and preserved production and protected shared state.

The accepted implementation blob for `Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift` is `43e8d5b55007493403d1d27dd787441ac29e7305` at both the signed commit and canonical base.
The accepted test blob for `Tests/ZoidCoachAppTests/TodayDashboardCommandOverviewTests.swift` is `3233bfa704606438a0b0a6df44d751c4a4004955` at both the signed commit and canonical base.
No implementation or test drift separates the signed ZC-017-007 proof from the ZC-037-002 dashboard contract.

A new signed runtime run would repeat the same Today element, state transitions, accessibility assertions, persistence boundary, privacy scan, cleanup, and proof classes without exercising any additional user behavior.
Reusing the dual-scoped signed execution is therefore the narrower and more accurate evidence action.
This record reconciles scenario ownership only; it does not alter or replace the original ZC-017-007 report or manifest.

The original report references the external package `/private/tmp/zoid-zc017007-evidence/81937fd46828ce27786f668a004cd9248307b88a-full`, which is no longer present.
This reconciliation does not claim that temporary package is available and depends only on the immutable repository report, manifest, dual-scoped runbook, accepted source and test blobs, and their recorded identities.
