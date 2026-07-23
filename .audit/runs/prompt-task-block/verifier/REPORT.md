# Prompt Task Block Verification

## Decision

`ZC-034-011` advances from Barely started to Partially implemented.

The focused implementation is present and release-safe, but the installed signed application did not expose any prompt action buttons to the end user.

The scenario is not usable end to end and is not accepted as complete.

## Verified lineage

The verifier cherry-picked candidate `0bab648` onto authoritative root `c085451` as `f7a7b1ccb586cbaf59d0c0c46d1bb6f07183148a`.

The signed package identified itself as `zoid-coach-f7a7b1ccb586cbaf59d0c0c46d1bb6f07183148a-clean`, version 0.1.0 Build 8.

## Focused proof

One combined run of `PromptTaskBlockStateTests`, `GamingDriftPromptServiceTests`, and `TodayDashboardAgentTests` passed.

The inspected implementation provides the `Mark blocked` gaming-drift action, a dedicated reason sheet, trimmed 3-to-240-character validation, Cancel, stable accessibility identifiers, local task mutation before prompt resolution, prompt preservation on task failure, reconciliation copy on prompt-response failure, and replacement-main promotion.

The task execution store makes repeated block application safe, while replacement promotion exits after the blocked task is no longer the main objective.

## Release and signed runtime proof

The single release package attempt passed compilation, deep signing, nested helper validation, and designated-requirement validation.

The exact installed helper ran from `/private/tmp/zoid-666-prompt-task-block-install/Zoid 666 QA E2E.app/Contents/MacOS/ZoidCoachAgentQA` with isolated state under `/private/tmp/zoid-666-prompt-task-block-qa`.

Through the signed UI, the verifier created `Ship client proposal` and `Prepare launch notes`, added both to Today, and started `Ship client proposal` as the active main objective.

A deterministic valid `GAMING_DRIFT` episode then stored six actions: return to the active task, start a work sprint, take a break, reschedule, mark blocked, and continue intentionally.

After relaunch, Today visibly showed `DECISIONS 1 WAITING`, the `Gaming drift detected` card, its summary, and an accessibility `collection` for the actions.

The collection had no actionable children, and the rendered card contained no visible action buttons between its summary and the following Automatic Actions section.

Because `Mark blocked` was unreachable, the verifier stopped at the strict UI cap without attempting coordinate guesses or claiming the sheet and durable mutation path as end-to-end proof.

## Remaining acceptance

First fix the empty prompt-action collection so every generated action is visible, keyboard reachable, and exposed through accessibility in the adaptive grid.

Then repeat one capped signed journey covering a too-short reason, Cancel with the active task and prompt unchanged, a meaningful blocker reason, the original task blocked with its pause reason, `Prepare launch notes` promoted as main, answered prompt history, app and helper relaunch durability, and an unavailable-agent attempt that leaves both task and prompt unchanged.

## Cleanup

The QA app and helper were unregistered and stopped, both isolated roots were removed, and `launchctl` confirmed the QA service was absent before the runtime lease was released.
