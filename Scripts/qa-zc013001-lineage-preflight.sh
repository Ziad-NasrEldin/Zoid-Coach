#!/bin/zsh

set -euo pipefail

readonly ROOT="${0:A:h:h}"
readonly CANONICAL_BASE="8b1782c6ee2c213a408360554f19bf231b0f3e19"
readonly REVIEWED_PATCH_COUNT=16
readonly TOTAL_LINEAGE_COMMIT_COUNT=17

readonly -a REQUIRED_PATCH_IDS=(
    56b15769cc032446b10cd2a37e03b72769df67c6
    aaf3630bdc5c3db28633347a1d406db6c8ed9b76
    e9e25ae7277cdcc20d3c33b1acaa15c61c9468cc
    e2ad8b6eccb78e2ae8aa6b68bdd434a897bd3bc6
    df51b058ea5f72067a1f3301be18494825525632
    9088f8ff55083b8da4301b2e4b6a671ab1d56b83
    fe6f663069895bb649045ed87cfdfe1b7320841f
    c4d787a24be79b519806251be3b9806d4d0d2184
    537fe7e1cb2c489487f45b2ce2e601d3974e0514
    f046c91276416b8580f95515d7d5b1606c6eaeb4
    b9cd8ba1869ba198c3f1d97ec8d8b823fc350821
    8e3149e9d5881ec0ca6fec152da57a9942b96960
    9f8c25b27bc7be031b52412f58ae4f7327d36967
    a89faa359e07623f58d8ce95b620465bdab91e1e
    3630ac213aa0ba2ee2787249ddf23414f44a9fcb
    ce867ca81fb0756910a293673bc3a2042456df5b
)

readonly -a REQUIRED_BLOBS=(
    "695a37111ff8c120b6bb891ad916129bd8718201:Scripts/qa-zc013001-day-state-fixture.sh"
    "3bff01d0f0ed11d1439a65cddfbae8ef5d717d68:Scripts/qa-zc013001-runbook-self-test.sh"
    "008421a3040e08cf5ec330db018008d16c55b034:Sources/ZoidCoachApp/AppModel.swift"
    "7cd6443547efe6f2db659e84dd6f9a4a3c8c2719:Sources/ZoidCoachApp/MenuBarCoachView.swift"
    "cdda965919644e308180f55eeb804fa515cf49d0:Sources/ZoidCoachApp/ReadOnlyTodaySnapshotLoader.swift"
    "99e92ff5f892d46bcd44551952046602eb5f5aab:Sources/ZoidCoachApp/Views/DashboardView.swift"
    "aecf91096b7deb7187eab5787b2c1e2bc4ca8108:Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift"
    "7e38728c1a53c309136d403c2b57f3160ca863bc:Sources/ZoidCoachApp/Views/TodayDayStateHeader.swift"
    "61b0c4c6fa51f8863cd7d5e3a86d9edd4abcb424:Tests/ZoidCoachAppTests/MenuBarCoachTests.swift"
    "6613f0cc0f21047f38c1a3a76fb8fb7ebdfb018b:Tests/ZoidCoachAppTests/TodayDayStatePresentationTests.swift"
    "47524d16fdec4a88da1d93419a12ba35942a1d2a:Tests/ZoidCoachAppTests/TodaySnapshotOwnershipTests.swift"
    "7ecb431ef3e3856374b067a5c44eb3abcc4a6f60:Scripts/qa-zc013001-day-state-ax-probe.swift"
    "f650b7f2948cbf3addbd9f421e397f98c443c3b9:docs/ZC-013-001-SIGNED-QA-RUNBOOK.md"
)

readonly -a INTENDED_PATHS=(
    Scripts/qa-zc013001-day-state-ax-probe.swift
    Scripts/qa-zc013001-day-state-fixture.sh
    Scripts/qa-zc013001-lineage-preflight.sh
    Scripts/qa-zc013001-runbook-self-test.sh
    Sources/ZoidCoachApp/AppModel.swift
    Sources/ZoidCoachApp/MenuBarCoachView.swift
    Sources/ZoidCoachApp/ReadOnlyTodaySnapshotLoader.swift
    Sources/ZoidCoachApp/Views/DashboardView.swift
    Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift
    Sources/ZoidCoachApp/Views/TodayDayStateHeader.swift
    Tests/ZoidCoachAppTests/MenuBarCoachTests.swift
    Tests/ZoidCoachAppTests/TodayDayStatePresentationTests.swift
    Tests/ZoidCoachAppTests/TodaySnapshotOwnershipTests.swift
    docs/ZC-013-001-SIGNED-QA-RUNBOOK.md
)

readonly -a HEAD_MAINTENANCE_PATHS=(
    Scripts/qa-zc013001-lineage-preflight.sh
)

fail() {
    print -u2 -- "FAIL: ZC-013-001 lineage preflight: $1"
    return 1
}

validate_exact_text() {
    local label="$1"
    local expected="$2"
    local observed="$3"
    [[ "$observed" == "$expected" ]] || fail "$label differs from the reviewed contract"
}

sorted_lines() {
    LC_ALL=C sort
}

patch_id_for_commit() {
    git show --pretty=format: "$1" | git patch-id --stable | awk '{ print $1 }'
}

run_self_test() {
    local expected_patches="$(print -l -- "${REQUIRED_PATCH_IDS[@]}")"
    local expected_paths="$(print -l -- "${INTENDED_PATHS[@]}" | sorted_lines)"
    local -a missing_patches=("${REQUIRED_PATCH_IDS[1,$REVIEWED_PATCH_COUNT - 1]}")
    local -a altered_patches=("${REQUIRED_PATCH_IDS[@]}")
    local -a extra_patches=("${REQUIRED_PATCH_IDS[@]}" ffffffffffffffffffffffffffffffffffffffff)
    local -a unrelated_paths=("${INTENDED_PATHS[@]}" docs/ZC-999-TRACKER.md)
    altered_patches[1]=0000000000000000000000000000000000000000

    if validate_exact_text patches "$expected_patches" "$(print -l -- "${missing_patches[@]}")" >/dev/null 2>&1; then
        fail "missing-patch negative was accepted"
    fi
    if validate_exact_text patches "$expected_patches" "$(print -l -- "${altered_patches[@]}")" >/dev/null 2>&1; then
        fail "altered-patch negative was accepted"
    fi
    if validate_exact_text patches "$expected_patches" "$(print -l -- "${extra_patches[@]}")" >/dev/null 2>&1; then
        fail "extra-patch negative was accepted"
    fi
    if validate_exact_text paths "$expected_paths" "$(print -l -- "${unrelated_paths[@]}" | sorted_lines)" >/dev/null 2>&1; then
        fail "unrelated-path negative was accepted"
    fi

    print -- "PASS: ZC-013-001 lineage preflight rejects missing, altered, extra, and unrelated changes"
}

if [[ "${1:-}" == "--self-test" ]]; then
    run_self_test
    exit $?
fi

[[ "${1:-}" == "--expected-commit" && -n "${2:-}" && $# == 2 ]] \
    || { print -u2 -- "usage: ${0:t} --expected-commit <full-40-character-commit> | --self-test"; exit 2; }

readonly EXPECTED_COMMIT="$2"
[[ ${#EXPECTED_COMMIT} == 40 && -z "${EXPECTED_COMMIT//[0-9a-f]/}" ]] \
    || { fail "expected commit must be a full lowercase 40-character SHA"; exit 1; }

cd "$ROOT"
[[ "$(git rev-parse HEAD)" == "$EXPECTED_COMMIT" ]] \
    || { fail "checked-out HEAD does not equal the expected signed commit"; exit 1; }
[[ -z "$(git status --porcelain)" ]] \
    || { fail "worktree is not clean"; exit 1; }
git merge-base --is-ancestor "$CANONICAL_BASE" "$EXPECTED_COMMIT" \
    || { fail "canonical base is not an ancestor of the expected commit"; exit 1; }
[[ -z "$(git rev-list --min-parents=2 "$CANONICAL_BASE..$EXPECTED_COMMIT")" ]] \
    || { fail "lineage contains a merge commit"; exit 1; }

typeset -a LINEAGE_COMMITS
typeset lineage_commit
while IFS= read -r lineage_commit; do
    LINEAGE_COMMITS+=("$lineage_commit")
done < <(git rev-list --reverse --first-parent "$CANONICAL_BASE..$EXPECTED_COMMIT")
readonly LINEAGE_COMMITS
(( ${#LINEAGE_COMMITS[@]} == TOTAL_LINEAGE_COMMIT_COUNT )) \
    || { fail "lineage must contain exactly $TOTAL_LINEAGE_COMMIT_COUNT commits"; exit 1; }
[[ "${LINEAGE_COMMITS[-1]}" == "$EXPECTED_COMMIT" ]] \
    || { fail "expected commit is not the lineage HEAD"; exit 1; }

typeset -a observed_patch_ids=()
typeset commit_index commit
for (( commit_index = 1; commit_index <= REVIEWED_PATCH_COUNT; commit_index += 1 )); do
    commit="${LINEAGE_COMMITS[$commit_index]}"
    observed_patch_ids+=("$(patch_id_for_commit "$commit")")
done
validate_exact_text \
    "reviewed patch sequence" \
    "$(print -l -- "${REQUIRED_PATCH_IDS[@]}")" \
    "$(print -l -- "${observed_patch_ids[@]}")" \
    || exit 1

readonly observed_paths="$(git diff --name-only "$CANONICAL_BASE..$EXPECTED_COMMIT" | sorted_lines)"
validate_exact_text \
    "cumulative file scope" \
    "$(print -l -- "${INTENDED_PATHS[@]}" | sorted_lines)" \
    "$observed_paths" \
    || exit 1

typeset observed_path
for observed_path in ${(f)observed_paths}; do
    case "${observed_path:l}" in
        *tracker*|*registry*|*backlog*)
            fail "tracker, registry, or backlog path escaped into the candidate: $observed_path"
            exit 1
            ;;
    esac
done

readonly head_paths="$(git diff-tree --no-commit-id --name-only -r "$EXPECTED_COMMIT" | sorted_lines)"
validate_exact_text \
    "HEAD maintenance scope" \
    "$(print -l -- "${HEAD_MAINTENANCE_PATHS[@]}" | sorted_lines)" \
    "$head_paths" \
    || exit 1

typeset blob_spec expected_blob blob_path observed_blob
for blob_spec in "${REQUIRED_BLOBS[@]}"; do
    expected_blob="${blob_spec%%:*}"
    blob_path="${blob_spec#*:}"
    observed_blob="$(git rev-parse "$EXPECTED_COMMIT:$blob_path")" \
        || { fail "required reviewed blob is missing: $blob_path"; exit 1; }
    [[ "$observed_blob" == "$expected_blob" ]] \
        || { fail "required reviewed blob changed: $blob_path"; exit 1; }
done

print -- "PASS: ZC-013-001 expected HEAD, canonical ancestry, reviewed patches, blobs, and exact scope are bound"
