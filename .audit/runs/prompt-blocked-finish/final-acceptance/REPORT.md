# ZC-034-011 Final Acceptance Attempt

## Verdict

`ZC-034-011` remains `Touches remaining` after this capped independent run.
The tracker must not be promoted from this evidence.

## Authoritative candidate

The verifier created a fresh isolated worktree at exact commit `5ad35b9df47e59aafa77b65d0df42751405f9680` on branch `codex/verify-zc034011-final`.
No product source file was changed.

## Build proof

`swift test --filter PromptTaskBlockStateTests` passed with exit status zero.
The focused suite covers the eleven blocker-interface, form-state, exactly-once, history, and failure-preservation cases recorded by the candidate.
An incremental `swift test --skip-build --filter PromptTaskBlockStateTests` recheck also passed with exit status zero.
`swift build -c release` passed with exit status zero.
The signed QA package passed app and helper signing validation plus its designated requirement.

## Runtime proof completed

The isolated installer reported `PASS: QA XPC runtime is writable and prompt timeline is available`.
It also reported that the QA LaunchAgent was registered and left enabled before the runtime journey.
The verifier prepared an isolated ready-state root and reinstalled it with data retention.
The retained installer again passed writable-XPC and prompt-timeline validation.
Raw SQLite then contained `qa-block-1` as a presented `GAMING_DRIFT` prompt with six actions, zero responses, an active original task, an open activity interval, and a two-task plan whose main objective was `Ship client proposal` followed by `Prepare launch notes`.

## Acceptance proof not completed

The ten-minute runtime lease expired immediately after the exact canonical fixture was seeded and the foreground app was relaunched.
This run did not independently activate the six direct accessibility actions.
It did not activate the valid `Waiting for approval.` preset and `Save Blocker`.
It did not prove exactly one response, the exact blocked reason, closed interval, replacement-main promotion, answered history, app and helper relaunch persistence, or the separate helper-unavailable unchanged-database path.
Those are required before this scenario can become fully implemented.

## Cleanup

The verifier stopped at the lease cap without extending the signed journey.
`Scripts/uninstall-signed-qa-runtime.sh` reported `PASS: signed QA runtime removed` for the isolated install and data roots.
The verifier removed its generated build products and temporary accessibility-driver binary after preserving this report.

