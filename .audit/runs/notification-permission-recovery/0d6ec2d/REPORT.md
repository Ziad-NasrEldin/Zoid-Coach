# Notification permission and Today fallback recovery candidate

## Scope

This candidate owns `ZC-004-002`, `ZC-004-004`, `ZC-050-002`, `ZC-050-005`, and `ZC-050-007`.
It completes the notification grant, denial, repair, replacement, and interrupted-response foundation without changing onboarding, Today, Screenwatch, or agent-lifecycle surfaces.

## End-user behavior

- A first explicit request can grant timely notification delivery.
- A denied request clearly states that every unresolved coaching choice remains available in Today.
- Denial prevents repeated permission requests from the controller.
- System Settings repair reports a successful handoff or gives the exact manual Notifications path.
- Returning to the app automatically rechecks authorization without requesting permission again.
- The repaired state immediately reflects that notifications are available.
- Re-delivery of the same prompt removes pending and delivered requests with the same stable identifier before adding the latest content.
- The deterministic QA adapter likewise keeps one notification record for the same decision.
- A response interrupted after local persistence can be processed again without invoking the response effect twice.
- Delivery history continues to show authorization fallback and replacement attempts without storing prompt content.

## Focused proof

- `NotificationDeliveryHealth` focused tests passed.
- `PromptNotificationCoordinatorTests` passed.
- `deniedFallbackRepairReplacementAndInterruptedResponseRemainOneJourney` passed.
- The end-to-end deterministic journey starts denied, keeps one unresolved Today prompt, repairs permission, schedules the same prompt twice as one notification, responds once, replays response processing, and applies the effect exactly once.
- The focused build compiled app, infrastructure, and test targets.
- `git diff --check` passed.

## Verifier handoff

A fresh verifier should rebase this candidate onto the current integration tip and rerun the three focused groups.
Using the serialized signed-QA runtime, verify denied onboarding continuation, the same prompt in Today, Settings repair failure and success copy, automatic foreground authorization refresh, one latest notification after repeated delivery, response resolution, agent restart, and no duplicated effect.
The tracker, registry, Lavish report, shared runtime, and root worktree remain untouched by this candidate.

## Independent verifier result

The candidate was rebased once onto lifecycle integration `d0e11f6` as verifier tip `9a13467`.
The focused notification health and recovery tests passed, and the release build passed.
Clean signed-QA packaging, signing verification, exact helper registration, and launch passed from `/private/tmp/zoid-666-notification-recovery-installed/Zoid 666 QA E2E.app`.
The installed app visibly reached Notifications with denied fixture authorization, reported Attention, explained that every important action remains available in Today, disabled the repeated Request Notification Access action after the denied request, and enabled Continue.
The visible journey then stopped at activity-classification persistence because the running signed helper did not answer the XPC policy write within three seconds.
A single retry was followed by ScreenCaptureKit error `-3811`, so the verifier stopped within the capped UI window.
The signed repair, foreground refresh, latest-only delivery, response, and restart legs remain unqualified, and no scenario was promoted to fully implemented from this run.
