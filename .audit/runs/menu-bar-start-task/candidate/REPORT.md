# Menu-bar task start candidate report

## Scope

This candidate implements scenario `ZC-016-002`, which lets the user start the current ready recommendation from the menu bar.

The menu continues to show the recommended task title, its Recommended Next state, and one clear Start action when no task is active or paused.

The Start action now has a task-specific accessibility label, a stable identifier, and a hint that explains its freshness check.

Immediately before mutation, the controller fetches a fresh agent snapshot.

The command is refused when another task became active, a paused task needs attention, or the ready recommendation changed.

A stale refusal shows the latest menu state, performs zero task mutation, and tells the user to review it before trying again.

When the recommendation remains current, the flow sends exactly one durable `start` command for that task.

Success is accepted only when the returned snapshot identifies the same task as active and its task row has the active state.

An unchanged or malformed agent response keeps the last fresh state visible, tells the user that the start was not confirmed, and asks for a refresh before retrying.

After confirmed success, the menu switches to the active-task controls and the main Today snapshot refreshes.

The existing canonical-agent journey now starts through this guarded menu path before exercising break, resume, end-workday, and restart persistence.

## Automated evidence

`swift test --filter MenuBarCoachTests` passed all 14 focused menu tests.

The focused suite covers explicit recommendation selection, non-optional fallback selection, exact successful start identity, stale recommendation refusal with zero mutation, invalid response refusal, active-state presentation, command failure preservation, and canonical-agent persistence.

`swift build -c release` completed successfully.

`git diff --check` completed successfully.

## Verifier plan

The verifier should rebase this candidate onto the latest authoritative tip.

The verifier should rerun the focused menu tests and release build after the rebase.

The verifier should acquire the runtime lease and install a signed QA build with an addressable menu-bar status item.

The verifier should create a ready plan with no active or paused task and confirm that the menu names the recommendation and exposes one task-specific Start action.

The verifier should cancel the popover, change the recommendation through Today, reopen the stale menu state if possible, select Start, and confirm that no stale task starts and the latest recommendation replaces it.

The verifier should select Start for the current recommendation and confirm that the same task becomes active in the menu and Today with exactly one open activity interval.

The verifier should rapidly activate Start more than once and confirm that the in-flight guard produces no duplicate interval or second mutation.

The verifier should restart the app and helper and confirm that the same task remains active with preserved elapsed time.

The verifier should disconnect the helper, attempt Start from a fresh ready state, and confirm that the last state remains visible with actionable failure copy.

The verifier should inspect the accessibility tree and confirm the task-specific label, freshness hint, stable Start identifier, active state, and error state.

The tracker should change only after the signed runtime proof is captured.
