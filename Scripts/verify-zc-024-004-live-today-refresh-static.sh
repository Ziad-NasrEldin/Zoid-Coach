#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="6dfb5886f4ca2d157745f10b5d737988a08d596a"

is_owned() {
    case "$1" in
        Sources/ZoidCoachApp/AppModel.swift | \
        Sources/ZoidCoachApp/ZoidCoachApp.swift | \
        Sources/ZoidCoachApp/TodayLiveRefreshLoop.swift | \
        Tests/ZoidCoachAppTests/TodayLiveRefreshLoopTests.swift | \
        Scripts/verify-zc-024-004-live-today-refresh-static.sh)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

is_forbidden() {
    case "$1" in
        Scripts/qa-zc013001-day-state-ax-probe.swift | \
        Scripts/qa-zc013001-day-state-fixture.sh | \
        Scripts/qa-zc041005-work-categories-ax-probe.swift | \
        Scripts/qa-zc042001-evidence-layers-ax-probe.swift | \
        Scripts/qa-zc042001-evidence-layers-fixture.sh | \
        Scripts/qa-zc042001-signed-bootstrap.sh | \
        Scripts/qa-zc042001-signed-preflight.sh | \
        Scripts/qa-zc044004-signed-preflight.sh | \
        Sources/ZoidCoachApp/DailyReviewEvidenceLayersState.swift | \
        Sources/ZoidCoachApp/PolicyMutationXPCProbe.swift | \
        Sources/ZoidCoachApp/Services/AgentLaunchService.swift | \
        Sources/ZoidCoachApp/Views/DailyReviewView.swift | \
        Sources/ZoidCoachApp/Views/DashboardView.swift | \
        Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift | \
        Sources/ZoidCoachApp/Views/TodayDayStateHeader.swift | \
        Sources/ZoidCoachInfrastructure/DailyReviewStore.swift | \
        Tests/ZoidCoachAppTests/AgentLaunchServiceTests.swift | \
        Tests/ZoidCoachAppTests/DailyReviewEvidenceLayersStateTests.swift | \
        Tests/ZoidCoachAppTests/DailyReviewTests.swift | \
        Tests/ZoidCoachAppTests/TodayDayStatePresentationTests.swift | \
        docs/ZC-013-001-SIGNED-QA-RUNBOOK.md | \
        docs/ZC-042-001-SIGNED-QA-RUNBOOK.md | \
        docs/ZC-044-004-SIGNED-QA-RUNBOOK.md)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

assert_contains() {
    local file="$1"
    local text="$2"
    if ! rg -Fq "$text" "$ROOT/$file"; then
        echo "missing required wiring in $file: $text" >&2
        exit 1
    fi
}

run_self_test() {
    is_owned "Sources/ZoidCoachApp/AppModel.swift"
    ! is_owned "Sources/ZoidCoachApp/Views/DashboardView.swift"
    is_forbidden "Sources/ZoidCoachApp/Views/DashboardView.swift"
    ! is_forbidden "Sources/ZoidCoachApp/AppModel.swift"
    echo "ZC-024-004 verifier self-test: pass"
}

if [[ "${1:-}" == "--self-test" ]]; then
    run_self_test
    exit 0
fi

cd "$ROOT"

if [[ "$(git rev-parse "$BASE")" != "$BASE" ]]; then
    echo "required base is unavailable: $BASE" >&2
    exit 1
fi

while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    if is_forbidden "$path"; then
        echo "forbidden overlap detected: $path" >&2
        exit 1
    fi
    if ! is_owned "$path"; then
        echo "out-of-scope changed path detected: $path" >&2
        exit 1
    fi
done < <(
    {
        git diff --name-only "$BASE"
        git ls-files --others --exclude-standard
    } | sort -u
)

assert_contains "Sources/ZoidCoachApp/AppModel.swift" \
    "func setTodayLiveRefreshEnabled(_ isEnabled: Bool)"
assert_contains "Sources/ZoidCoachApp/AppModel.swift" \
    "await self?.refreshTodaySnapshot()"
assert_contains "Sources/ZoidCoachApp/ZoidCoachApp.swift" \
    "onboarding.route == .today && scenePhase == .active"
assert_contains "Sources/ZoidCoachApp/TodayLiveRefreshLoop.swift" \
    "interval: Duration = .seconds(15)"
assert_contains "Tests/ZoidCoachAppTests/TodayLiveRefreshLoopTests.swift" \
    "func todayLiveRefreshRunsOnceForEachTickAndStopsWithoutAnotherRefresh()"
assert_contains "Tests/ZoidCoachAppTests/TodayLiveRefreshLoopTests.swift" \
    "func todayLiveRefreshStartIsIdempotent()"

swiftc -typecheck Sources/ZoidCoachApp/TodayLiveRefreshLoop.swift
swiftc -parse \
    Sources/ZoidCoachApp/AppModel.swift \
    Sources/ZoidCoachApp/ZoidCoachApp.swift \
    Tests/ZoidCoachAppTests/TodayLiveRefreshLoopTests.swift
git diff --check "$BASE"
run_self_test
echo "ZC-024-004 static verification: pass"
