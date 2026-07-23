# Menu bar coaching pause verifier report

## Decision

`ZC-023-004` and `ZC-023-009` advance from Not implemented to Touches remaining.
The durable pause, intervention suppression, continued work, restart persistence, resume, newest-policy handling, and accessibility contract are verified.
The actual macOS status-item popover remained absent from the available Computer Use accessibility tree, so neither scenario qualifies as fully implemented.

## Lineage

- Authoritative base: `ef4de54666eb9b5a2b53b03e0023214680d19154`.
- Rebased implementation: `3fa6d2871a3d4d80ec0c0bfa5a42f88626e6ca5d`.
- Installed build identity: `zoid-coach-3fa6d2871a3d4d80ec0c0bfa5a42f88626e6ca5d-clean`.

## Automated proof

`swift test --filter MenuBarCoachTests` passed ten tests in one focused run.
The tests cover paused-state precedence, durable pause, durable resume, newest-policy reload, preservation of every unrelated policy field, version advancement, audited system origin, exact request identity, canonical payload digest, and invalid-receipt rejection.
Static inspection confirmed that the live client reads the canonical policy database and writes only through the background-agent XPC mutation boundary.
Release build passed.
The exact rebased QA package passed package, LaunchAgent, Mach-service, nested-signing, on-disk signature, and designated-requirement validation.

## Signed pause and work continuity

The installed signed app reported build `3fa6d28` and policy v1 running.
Settings paused coaching indefinitely through the live background agent and visibly advanced to policy v2 with saved confirmation.
Today remained usable while paused.
The user created `Verify paused coaching keeps work usable`, added it to Today, started it, and visibly retained the active task and tracked time.

The verifier seeded seven complete baseline days and sixty-one fresh continuous Steam observations against an unfinished active task and an exhausted sixty-minute allowance.
The live helper produced zero prompts while policy v2 was paused.
Today visibly showed the complete baseline, sixty-one used gaming minutes, zero allowance remaining, the active task, and no waiting decisions.

The app was quit and relaunched, and the signed helper was killed and relaunched by its registered service.
After both restarts, Today restored the same active task with advanced tracked time and no prompt.
Settings restored `PAUSED INDEFINITELY`, policy v2, and the accessible Resume control.
Resuming through the live agent visibly advanced to running policy v3.
The same eligible evidence then produced one queued `Ready for an easy return?` prompt naming Steam, sixty-one observed minutes, and the unfinished task.

## Menu accessibility boundary

The menu implementation publishes stable accessibility identifiers for the coaching container, pause action, resume action, progress, success, and failure states.
The Pause and Resume buttons have explicit labels and disabled loading or saving states, so keyboard activation follows native Button semantics.
Computer Use could inspect the installed app window and application menu bar but could not address the separate macOS status item or its popover.
This is the same external acceptance boundary recorded by prior menu-bar verifiers.

## Remaining acceptance

1. Address the actual macOS status item with a harness that exposes MenuBarExtra content.
2. Open the popover and visibly confirm the running label, paused label, paused icon, current task, explanatory copy, and native focus order.
3. Activate Pause and Resume directly from that popover with keyboard input.
4. Exercise an XPC failure while the popover is open and visibly confirm the last durable state and recovery copy.
