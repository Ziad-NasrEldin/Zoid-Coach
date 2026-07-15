#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="ed5d07a363e0f64049c07b0e1d309d754caa035b"
REVIEWED_LINEAGE_TIP="1bb3c27866bc3acbfd449d680371b0b340710738"
REASSEMBLY_COMMIT="44c1bca116525709d7c4708b4f4a7089fa11c70f"
TOOLING_COMMIT="fa95aeab65fb23a1971e6a7c3464ae87d51febf7"
TOOLING_PATCH_ID="e984850a3645bdb51518fe98745104bb8a20aa7d"

readonly REVIEWED_PATCH_IDS=(
    "5b1d785b5676c1d5d33b02ea4d9cfa01940be0c8"
    "efe25d1a4433de623c8f273ec7e92dd60fb44469"
    "16647b99b75776af46b29a0d4d4d03df195323a8"
    "d6d19cea420d9fc549d8e48768f282469dc76f9c"
)

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

normalized_lines() {
    sed '/^$/d' | LC_ALL=C sort -u
}

reviewed_patch_ids() {
    local commit
    while IFS= read -r commit; do
        git show --pretty=email --no-ext-diff "$commit" \
            | git patch-id --stable \
            | awk '{print $1}'
    done < <(git rev-list --reverse --topo-order "$BASE..$REVIEWED_LINEAGE_TIP")
}

verify_candidate_lineage() {
    local head expected_scope actual_scope expected_rebind_scope actual_rebind_scope
    local expected_patch_ids actual_patch_ids tooling_patch_id
    head="$(git rev-parse HEAD)"
    [[ "$(git show -s --format='%P' "$REASSEMBLY_COMMIT")" == "$BASE $REVIEWED_LINEAGE_TIP" ]]
    [[ "$(git rev-parse "$TOOLING_COMMIT^")" == "$REASSEMBLY_COMMIT" ]]
    [[ "$(git rev-parse "$head^")" == "$TOOLING_COMMIT" ]]

    expected_scope="$(printf '%s\n' "${OWNED_PATHS[@]}" | normalized_lines)"
    actual_scope="$(git diff --name-only "$BASE" "$head" | normalized_lines)"
    [[ "$actual_scope" == "$expected_scope" ]]
    [[ "$(git diff --name-only "$BASE" "$REASSEMBLY_COMMIT" | normalized_lines)" == "$expected_scope" ]]
    [[ "$(git diff-tree --no-commit-id --name-only -r "$TOOLING_COMMIT" | normalized_lines)" == "Scripts/qa-zc024004-live-refresh-ax-probe.swift" ]]

    expected_rebind_scope="$(printf '%s\n' \
        Scripts/verify-zc-024-004-live-today-refresh-static.sh \
        docs/ZC-024-004-SIGNED-QA-RUNBOOK.md | normalized_lines)"
    actual_rebind_scope="$(git diff --name-only "$TOOLING_COMMIT" "$head" | normalized_lines)"
    [[ "$actual_rebind_scope" == "$expected_rebind_scope" ]]

    actual_patch_ids="$(reviewed_patch_ids)"
    expected_patch_ids="$(printf '%s\n' "${REVIEWED_PATCH_IDS[@]}")"
    [[ "$actual_patch_ids" == "$expected_patch_ids" ]]
    tooling_patch_id="$(git show --pretty=email --no-ext-diff "$TOOLING_COMMIT" \
        | git patch-id --stable \
        | awk '{print $1}')"
    [[ "$tooling_patch_id" == "$TOOLING_PATCH_ID" ]]
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
    verify_candidate_lineage
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

verify_candidate_lineage

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
assert_contains "Scripts/qa-zc024004-live-refresh-ax-probe.swift" \
    "let freshWindow = try mainWindow()"
assert_contains "Scripts/qa-zc024004-live-refresh-ax-probe.swift" \
    "Working and Screenwatch are unavailable after bounded Today scrolling"
assert_contains "Scripts/qa-zc024004-live-refresh-ax-probe.swift" \
    "stale Today Accessibility tree was reused during bounded scrolling"
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
