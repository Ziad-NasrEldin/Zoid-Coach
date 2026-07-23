# Signed-QA onboarding visible verification

Date: 2026-07-12

Branch: `codex/full-system`

Verified commit: `3269ee8ec1c447b6133900741b99d7d9d5a5b20c`

Application: `.build/app-qa/Zoid Coach QA.app`

QA root: `/tmp/zoid-visible-e2e-3269ee8`

## Visible end-user results

- A clean launch opened the Welcome step without a storage error.
- Welcome explicitly explained intended work in Reminders, actual computer activity, Today persistence, recovery without shame, and no blocking or punishment by default.
- Continue opened the Local Truth step, which explained on-Mac storage and optional AI.
- Continue opened the Reminders step.
- Killing and relaunching the application restored the exact Reminders step.
- Exit For Now opened Today.
- Relaunching after Exit For Now still restored the exact Reminders step.
- Not Now on Reminders enabled continuation and advanced to Screenwatch.
- Screenwatch displayed current source health, Check Expected Folder, Recheck, Choose Folder, Not Now, and privacy copy.
- Not Now on Screenwatch advanced to Notifications.
- Notifications explained that Today remains available without notification permission.
- Not Now on Notifications advanced to application inventory.
- Application inventory scanned the actual Mac and displayed 114 applications before categorization.
- Continue opened application classification with Automatic, Work, and Gaming choices.
- Activity Monitor was selected as Work and Atoll was selected as Gaming.

## Verified persistence boundary

The manually launched QA application could not persist the classification draft because its helper application had not been registered with launchd.

No scenario requiring durable completion after application classification is marked Fully implemented from this visible run.

## Automated supporting results

- The full Swift suite passed after the clean-first-launch fix.
- The scenario registry contained exactly 666 scenarios before this tracker refresh.
- Reminder-list filtering, rename, all-excluded local fallback, restart, and exact opaque identifier tests passed in the signed-QA lane.
- Onboarding progress, policy conflict, canonical Screenwatch bookmark, gaming-policy, and durable first-plan tests passed.
