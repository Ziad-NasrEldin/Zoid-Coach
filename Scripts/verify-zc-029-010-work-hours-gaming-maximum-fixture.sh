#!/bin/zsh
set -euo pipefail

readonly FIXTURE="${1:-$(cd "$(dirname "$0")" && pwd)/fixtures/zc-029-010-work-hours-gaming-maximum.json}"
readonly READY_STATE="${2:-$(cd "$(dirname "$0")" && pwd)/fixtures/zc-029-010-work-hours-gaming-maximum-ready-state.json}"
readonly PROBE="$(cd "$(dirname "$0")" && pwd)/zc-029-010-work-hours-gaming-maximum-ax-probe.swift"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"
[[ -f "$FIXTURE" ]] || fail "fixture does not exist: $FIXTURE"
[[ -f "$READY_STATE" ]] || fail "ready-state fixture does not exist: $READY_STATE"
[[ -x "$PROBE" ]] || fail "accessibility probe is missing or not executable: $PROBE"
jq -e . "$FIXTURE" >/dev/null || fail "fixture is not valid JSON"
jq -e . "$READY_STATE" >/dev/null || fail "ready-state fixture is not valid JSON"

[[ "$(jq -r '.scenarioID' "$FIXTURE")" == "ZC-029-010" ]] || fail "scenario ID mismatch"
[[ "$(jq -r '.policy.dailyBudgetMinutes' "$FIXTURE")" == "60" ]] || fail "daily budget mismatch"
[[ "$(jq -r '.policy.priorityTaskRewardMinutes' "$FIXTURE")" == "15" ]] || fail "reward mismatch"
[[ "$(jq -r '.policy.workHoursDailyMaximumMinutes' "$FIXTURE")" == "30" ]] || fail "work-hours maximum mismatch"
[[ "$(jq -r '.observation.meaningfulGamingMinutes' "$FIXTURE")" == "20" ]] || fail "observation mismatch"

jq -e '
  .policy.workHoursDailyMaximumMinutes >= 0 and
  .policy.workHoursDailyMaximumMinutes <= 1440 and
  .states.withinWorkWindow.gamingStatus == {
    budgetMinutes: 30, earnedMinutes: 0, manualAdjustmentMinutes: 0,
    usedMinutes: 20, unlockedRemainingMinutes: 10, lockedMinutes: 0,
    overageMinutes: 0,
    nextUnlockReason: "Work-hours gaming is capped at 30 minutes. The normal daily allowance returns outside configured work hours.",
    confidenceIsLimited: false, budgetEnabled: true
  } and
  .states.withinWorkWindow.renderedStatus == "Base 30m · Earned 0m · Used 20m · Locked 0m · Remaining 10m · Same-day overage 0m" and
  .states.outsideWorkWindow.renderedStatus == "Base 60m · Earned 15m · Used 20m · Locked 0m · Remaining 55m · Same-day overage 0m" and
  .states.maximumDisabled.gamingStatus == .states.outsideWorkWindow.gamingStatus and
  .states.maximumDisabled.renderedStatus == .states.outsideWorkWindow.renderedStatus and
  .states.partialLockedReward.workHoursDailyMaximumMinutes == 70 and
  .states.partialLockedReward.workHoursDailyMaximumMinutes > .policy.dailyBudgetMinutes and
  .states.partialLockedReward.gamingStatus.lockedMinutes == 10 and
  .states.partialLockedReward.renderedStatus == "Base 60m · Earned 0m · Used 0m · Locked 10m · Remaining 60m · Same-day overage 0m" and
  (.settings.toggleIdentifier | startswith("settings.gaming.")) and
  (.settings.controlIdentifier | startswith("settings.gaming.")) and
  (.settings.detailIdentifier | startswith("settings.gaming.")) and
  .menu.containerIdentifier == "menu-bar.gaming.work-hours" and
  .menu.maximumIdentifier == "menu-bar.gaming.work-hours.maximum" and
  .menu.statusIdentifier == "menu-bar.gaming.work-hours.status" and
  .menu.withinWorkWindowStatus == "Active in the current work window · 10m remaining" and
  .menu.outsideWorkWindowStatus == "Not active now · Normal allowance has 55m remaining" and
  .menu.awaitingRefreshStatus == "Current allowance is awaiting a work-hours policy refresh"
' "$FIXTURE" >/dev/null || fail "fixture contract mismatch"

jq -e '
  .schemaVersion == 1 and
  .onboarding.coachingMode == "rulesOnly" and
  .onboarding.reminderListDecisions == [{listID: "zc-029-010-work", isIncluded: true}] and
  .osFixture.reminderLists == [{id: "zc-029-010-work", name: "ZC-029-010 Work"}] and
  (.osFixture.reminders | length) == 1 and
  .osFixture.reminders[0].id == "zc-029-010-priority-task" and
  .screenwatch.state == "healthy" and
  .screenwatch.rebaseToNow == true and
  .screenwatch.timeZoneIdentifier == "Africa/Cairo" and
  (.screenwatch.days | length) == 1 and
  (.screenwatch.days[0].records | length) == 5 and
  .screenwatch.days[0].records[0].app == "Steam" and
  (.screenwatch.days[0].records | all(.window == "PRIVATE-ZC029010-WINDOW-SENTINEL")) and
  (.screenwatch.days[0].records | all(.url == "https://private-zc029010.invalid/raw?secret=sentinel")) and
  (.screenwatch.days[0].records[-1].epoch - .screenwatch.days[0].records[0].epoch) == 1200 and
  ([range(1; (.screenwatch.days[0].records | length)) as $index |
    .screenwatch.days[0].records[$index].epoch - .screenwatch.days[0].records[$index - 1].epoch]
    | all(. > 0 and . <= 300))
' "$READY_STATE" >/dev/null || fail "ready-state production fixture contract mismatch"

"$PROBE" --self-test >/dev/null || fail "accessibility probe self-test failed"

print -- "PASS: ZC-029-010 production-policy and rendered-snapshot expectations are internally consistent"
