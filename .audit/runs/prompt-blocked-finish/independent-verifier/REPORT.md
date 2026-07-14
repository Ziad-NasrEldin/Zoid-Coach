# ZC-034-011 Independent Verification

## Verdict

The candidate is not independently accepted by this verifier.
The focused tests, release build, signed package, native launch, code lineage, and direct source inspection passed.
The required independent end-to-end prompt journey was not reached before the runtime lease cap because the independently inserted `presented` prompt remained durable in SQLite but did not appear in the running app's prompt inbox.
The prior verifier evidence was not reused as independent acceptance evidence.

## Candidate lineage

The verifier started from canonical `2596f6e9c60bb6a7fad8f85003ccf17dea765236` in a fresh isolated worktree.
The candidate sequence was transplanted without conflicts as `8d93a09`, `0e0b4d5`, and `d2fe7cb`.
The exact blobs for `AppModel.swift`, `PromptTaskBlockState.swift`, `TodayPromptInboxLedger.swift`, and `PromptTaskBlockStateTests.swift` matched candidate `f83c7e8bd97655e06bcb9d9cc8ba85002f626dba`.

## Static and build proof

`swift test --filter PromptTaskBlockStateTests` passed all 8 selected tests.
The tests cover six direct stable action identifiers, form validation, duplicate-submit prevention, Cancel reset, blocked history, and replacement-main behavior.
`swift build -c release` passed.
The signed QA installer passed nested app and helper signing plus designated-requirement validation.

## Independent runtime attempt

The verifier prepared a new isolated QA root and installed the signed app at `/private/tmp/zc034011-independent-install/Zoid 666 QA E2E.app`.
The exact installed app and helper launched from that location.
The verifier inserted a two-task daily plan, an active execution interval, and `qa-block-1` as a six-action `GAMING_DRIFT` prompt in `presented` state.
Raw SQLite immediately showed the prompt, both plan entries, the active task, and the open interval.

The native accessibility tree showed the Today surface and the direct manual plan blocker, but `today.prompt-inbox` reported `0 WAITING` and exposed none of the six prompt action identifiers.
Rechecking the native UI did not change the inbox.
Raw SQLite still showed `qa-block-1` in `presented` state with the full six-action payload.

Because the prompt never became reachable from the user interface, this verifier did not claim independent proof for invalid reason, Cancel, valid Confirm, exactly-once response, blocked history, replacement-main promotion, app/helper relaunch, or helper-down failure preservation.

## Cleanup

The signed runtime was uninstalled at the lease cap.
The QA LaunchAgent was absent after uninstall.
The isolated QA root and install directory were removed.
Free disk after cleanup was 2.8 GiB.

