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

## Infrastructure repair recheck

Candidate `6122a87249364712d6fef5b0bd3700f6f10c5f73` removed the degraded-helper mismatch in a fresh signed runtime.
The installer refused PID-only acceptance and reported both `PASS: QA XPC runtime is writable and prompt timeline is available` and a canonical `agent-runtime` heartbeat.
The QA defaults domain stored the canonical build-and-bundle fingerprint and enabled choice.
The installed helper stayed on PID `73610` across a foreground app termination and relaunch, proving that the app no longer unregistered and registered the installer-created helper.

After the verifier inserted the same presented six-action prompt into the canonical database and relaunched only the app, Today exposed `1 WAITING` and six direct native buttons with the stable `today.prompt.qa-block-1.action.*` identifiers.
This confirms that the prior `0 WAITING` result came from the degraded XPC service rather than PromptInboxStore filtering or a database identity mismatch.

The independent native flow opened the blocker sheet, entered `no`, submitted it, and exposed `Explain the blocker in at least 3 characters.`.
SQLite remained presented with zero responses, an active task, and no blocked reason.
Cancel closed the sheet and restored the reachable prompt action.
The verifier reopened the sheet and selected the `Waiting for approval.` preset, which populated the editable field with 21 characters.

The runtime lease cap arrived before the verifier activated the final valid Save Blocker control.
Therefore this recheck still does not independently claim valid confirmation, exactly-once response, blocked history, replacement-main promotion, post-success relaunch, or helper-down state preservation.
The runtime and owned build artifacts were removed at the cap, and free disk returned to 2.8 GiB.
