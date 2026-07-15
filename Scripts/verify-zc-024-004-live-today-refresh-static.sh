#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="8b1782c6ee2c213a408360554f19bf231b0f3e19"

readonly OWNED_PATHS=(
    "Sources/ZoidCoachApp/AppModel.swift"
    "Sources/ZoidCoachApp/ZoidCoachApp.swift"
    "Sources/ZoidCoachApp/TodayLiveRefreshLoop.swift"
    "Tests/ZoidCoachAppTests/TodayLiveRefreshLoopTests.swift"
    "Scripts/verify-zc-024-004-live-today-refresh-static.sh"
    "Scripts/qa-zc024004-live-refresh-ax-probe.swift"
    "Scripts/qa-zc024004-live-refresh-fixture.sh"
    "docs/ZC-024-004-SIGNED-QA-RUNBOOK.md"
)

is_owned() {
    local owned_path
    for owned_path in "${OWNED_PATHS[@]}"; do
        [[ "$1" == "$owned_path" ]] && return 0
    done
    return 1
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
    local expected_path
    local expected_paths=(
        "Sources/ZoidCoachApp/AppModel.swift"
        "Sources/ZoidCoachApp/ZoidCoachApp.swift"
        "Sources/ZoidCoachApp/TodayLiveRefreshLoop.swift"
        "Tests/ZoidCoachAppTests/TodayLiveRefreshLoopTests.swift"
        "Scripts/verify-zc-024-004-live-today-refresh-static.sh"
        "Scripts/qa-zc024004-live-refresh-ax-probe.swift"
        "Scripts/qa-zc024004-live-refresh-fixture.sh"
        "docs/ZC-024-004-SIGNED-QA-RUNBOOK.md"
    )
    [[ "${#OWNED_PATHS[@]}" == "${#expected_paths[@]}" ]]
    for expected_path in "${expected_paths[@]}"; do
        is_owned "$expected_path"
    done
    ! is_owned "Scripts/qa-zc024004-live-refresh-extra.sh"
    ! is_owned "docs/ZC-024-004-SIGNED-QA-RUNBOOK-copy.md"
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
    "&& model.selectedSection == .today"
assert_contains "Sources/ZoidCoachApp/ZoidCoachApp.swift" \
    "&& scenePhase == .active"
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
