# ZC-037-006 Compact Active Task Finish Candidate

## Verdict

The candidate closes concrete compact-surface usability gaps without changing the tracker, registry, Lavish artifact, runtime fixtures, or shared application model.

The scenario remains at Touches remaining until an independent signed run opens the actual macOS status item and completes the visible control journey.

## Authoritative Base

- Base commit: `2596f6e9c60bb6a7fad8f85003ccf17dea765236`.
- Branch: `codex/zc-037-006-compact-active-finish`.
- Worktree: `/private/tmp/zoid-666-compact-active-finish`.

## End-User Fixes

- The initial loading state no longer claims that no task is active before the helper answers.
- A first-load failure now says that task state is unavailable because no confirmed background-agent state could be loaded.
- A later refresh or mutation failure preserves the last confirmed task and marks the compact state stale instead of showing false success.
- Active, paused, break, and recommended states derive one deduplicated action list with stable VoiceOver labels.
- Active tasks expose Pause, Break 15, Complete, Blocked, Open Today, and End Workday exactly once.
- Paused tasks expose Resume or End Break, Blocked, and Open Today without active-only controls.
- Blocked opens the existing required-reason sheet, trims the reason, enforces the 3-to-240-character boundary, and accepts only an agent response that confirms the exact task, blocked state, and reason.
- The compact controls use a two-column grid so the additional action does not overflow the 360-point menu surface.
- Open-ended elapsed time now advances from the real open-interval start while retaining elapsed time accumulated before the current interval.
- Backward clock movement cannot reduce the last confirmed elapsed duration, and paused durations remain stable.
- The status-item accessibility label stays generic and never includes the private task title, while the opened compact summary retains the title for the signed-in local user and VoiceOver.
- Canonical agent persistence is reloaded through a newly created controller after the helper-equivalent agent is reopened.

## Automated Evidence

- The red test first failed because `MenuBarCoachState` had no action contract and the controller had no explicit sync or block boundary.
- The focused filter covering all menu, compact, unavailable-notification, active-menu, block, and end-workday tests passed 23 tests after the fixes.
- The advancing-clock test proves 20 previously accumulated minutes plus a live 12-minute interval becomes 34 minutes after 125 seconds.
- The persistence test reopens `TodayDashboardAgent` and a new `MenuBarCoachController`, then restores the exact ended-workday task, Resume action, and saved duration.
- The block tests prove valid confirmation, invalid reason rejection without a request, and fail-closed handling of an unconfirmed response.
- `swift build -c release --scratch-path /tmp/zoid-compact-release` completed and produced the release executable.
- `git diff --check` passed.

## Remaining Signed Acceptance

- Install the candidate as a signed QA package under the runtime lease.
- Seed one deterministic active task through the public QA flow.
- Open the actual SwiftUI `MenuBarExtra` through a corrected native status-item coordinate or accessibility boundary.
- Capture compact-popover pixels and native accessibility nodes for title, live timing, task facts, and the six active actions.
- Click Pause, Resume, Blocked with a reason, and one terminal action through the compact surface.
- Relaunch the app and helper, reopen the status item, and prove the exact task state and duration persist.
- Confirm the macOS status item and any delivered notification use only the generic privacy-safe label.

No Full implementation claim is made before that signed journey succeeds.
