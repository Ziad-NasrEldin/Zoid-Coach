#!/bin/zsh
set -euo pipefail
set -o pipefail

readonly SCRIPT_PATH="${0:A}"
readonly SAFE_PATH="/usr/bin:/bin"
readonly SAFE_TMPDIR="/private/tmp"
readonly SAFE_HOME="$(/usr/bin/dscl . -read "/Users/$(/usr/bin/id -un)" NFSHomeDirectory | /usr/bin/awk '{print $2}')"
readonly SCRUBBED_MARKER="zc011007-validator-v1"

environment_is_scrubbed() {
    [[ "${ZC011007_VALIDATOR_ENV_SCRUBBED:-}" == "$SCRUBBED_MARKER" \
        && "${PATH:-}" == "$SAFE_PATH" \
        && "${HOME:-}" == "$SAFE_HOME" \
        && "${TMPDIR:-}" == "$SAFE_TMPDIR" \
        && "${GIT_CONFIG_NOSYSTEM:-}" == "1" \
        && "${GIT_CONFIG_GLOBAL:-}" == "/dev/null" \
        && "${GIT_CONFIG_SYSTEM:-}" == "/dev/null" \
        && "${GIT_ATTR_NOSYSTEM:-}" == "1" ]] || return 1
    local entry name
    for entry in ${(f)"$(/usr/bin/env)"}; do
        name="${entry%%=*}"
        case "$name" in
            HOME|TMPDIR|PATH|ZC011007_VALIDATOR_ENV_SCRUBBED|GIT_CONFIG_NOSYSTEM|GIT_CONFIG_GLOBAL|GIT_CONFIG_SYSTEM|GIT_ATTR_NOSYSTEM|LOGNAME|SHLVL|PWD|OLDPWD|_) ;;
            *) return 1 ;;
        esac
    done
}

if ! environment_is_scrubbed; then
    exec /usr/bin/env -i \
        HOME="$SAFE_HOME" \
        TMPDIR="$SAFE_TMPDIR" \
        PATH="$SAFE_PATH" \
        ZC011007_VALIDATOR_ENV_SCRUBBED="$SCRUBBED_MARKER" \
        GIT_CONFIG_NOSYSTEM=1 \
        GIT_CONFIG_GLOBAL=/dev/null \
        GIT_CONFIG_SYSTEM=/dev/null \
        GIT_ATTR_NOSYSTEM=1 \
        /bin/zsh "$SCRIPT_PATH" "$@"
fi

readonly EXPECTED_CANONICAL="2cba674f8370fc16f9555cdb6f115f18df1f8ced"
readonly EXPECTED_CANDIDATE="c6ab1eca0be18bfed96d036b56e733a4efa5bda6"
readonly EXPECTED_PARENT="b10af13f7c1fce32113f8c9e60872ac7695a6c25"
readonly EXPECTED_TREE="89d45de492f9dfab82133c8f1f81613ee7cf3e59"
readonly EXPECTED_RANGE_PATCH="c5ad16214bfccaac4efbba90a73fd753ec2eb05c"
readonly EXPECTED_INPUT_BLOB="bed2a04559d1db66706622e9d8ec5288d458b138"
readonly EXPECTED_INPUT_TEST_BLOB="7858f5b20d1ddbb9f357a5f2d71beaeeb4c56180"

readonly EXPECTED_FILES=(
    Scripts/qa-zc011007-invalid-estimate-ax-probe.swift
    Scripts/qa-zc011007-invalid-estimate-fixture.sh
    Scripts/qa-zc011007-signed-preflight.sh
    Sources/ZoidCoachApp/Views/CustomEstimateEditor.swift
    Sources/ZoidCoachApp/Views/DashboardView.swift
    Sources/ZoidCoachApp/Views/TodayDashboardCommandOverview.swift
    Tests/ZoidCoachAppTests/CustomEstimateEditorStateTests.swift
    docs/ZC-011-007-SIGNED-QA-RUNBOOK.md
)

readonly EXPECTED_BLOBS=(
    0a5682d4afcc4ce6d962e425acae8dd033365dc5
    6b92890969128919e2e6d3173ac051ba03ed97f5
    58e8a3a4945ab50ea4fcaa519bdc3fa98dfc3ba1
    9c53a127893a2b3944c6d1bc23117e9ac4a04df7
    350d9d6226098fd33fb403e619d5894560865217
    890b4f8d00ed6841e678e2dbdf1808c75001eb42
    a7b434757b6a60cb33e8271dd20cd6d712cfb032
    262e8494a55528733da8f4783a2f5c0e83e60b4d
)

readonly EXPECTED_COMMITS=(
    c221005ea00f4be9efc895c8eccfd618a10501d1
    180367af761c0bd1abcdb952bd12e3077b7f300b
    917c653083727610005058d00e59bdab6efdb996
    04cde2d83343b10a55e3551df2945a9627d28733
    cae33ec99dca3ee4bbe500bab16bbcb4187edad2
    3fc3c83b645083edc5bea8fbc925a073c0ad5234
    e218cad2a1a252dfca0812c79b1b0b1f1f0a193d
    3b4a920f0acf80052b71e0448ce16f72eaab5947
    bbccded6d72e3529245f21c583551042c5f94855
    1fa545dada749d3509cea1e10f8ea961ec8310d5
    a552225d4c2866e1f37dacb11d36ed0acbfd205e
    ab9dd8df55f456502a9bdbabe3062b65a381aba7
    0aabac608845a23a2af92c65227d80a47dcf91a8
    ec05a17970d21ea0ec5cd5d814a03d7c58bd5c74
    53c5e0455efd30fbe886f817fcd5dc906cb9bbac
    3338b5b4a14627c27c767e09285f52d09e441a5f
    f5941ce9c70fe4576c1561afe5a03ff3a24a0511
    b10af13f7c1fce32113f8c9e60872ac7695a6c25
    c6ab1eca0be18bfed96d036b56e733a4efa5bda6
)

readonly EXPECTED_COMMIT_PATCHES=(
    54853a6c3d47fdbb9dec56ebc695e7143f7c5b92
    ca93eecc45fe7b252b3678a029aee68e79cc0477
    82b581cfbd27b79dc2119f9b1329fb3bb1ccdeef
    778a8a4dcd21980f0fc3d471d93e6dedb51fc112
    ebd2dba15be57765380568c220978af829b58f9f
    dc1671dcb7513e99ab90bc17cb57c6475df98ed2
    944f588c8473909f8166ae65d5f42eb680fd1f52
    5f82e2433a633e84cdea81bddc21c9025f0b8ff7
    d66cf2791fe4a9099281bebf6cfe05ce702e209c
    35bd98efbcca50bc0815ef0dfbeb35c2ae72c2f1
    b070d7660423c515625cb7bbf09646696e0c44e7
    550322faf6a5ccb978659b8df8917ed4b55ccfb0
    0e2238556584977a74658797b071ffc9c2c8c401
    630ca61c10e7e9cd37ff2715e7e2ed20efe49701
    d42177e9e41faa6ced4d8d41d56249e024d2ea3b
    148ee38cca8473b689ce60530e49463ab58ec1ee
    9e272159d3e7d0eaa7c89a7ab7b6962d109980f1
    0e7fb372c1e5ebc8095bc392f5803ee0409de27d
    ecde42e98885c667eef2ab22a7d063b919102ac3
)

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

normalized_lines() {
    print -r -- "$1" | sed '/^$/d' | LC_ALL=C sort -u
}

has_exact_lines() {
    [[ "$(normalized_lines "$1")" == "$(normalized_lines "$2")" ]]
}

commit_patch_id() {
    local repository="$1"
    local commit="$2"
    git -C "$repository" show --format= --no-ext-diff "$commit" \
        | git patch-id --stable \
        | awk '{print $1}'
}

assert_exact_candidate() {
    [[ "$1" == "$EXPECTED_CANDIDATE" ]] || fail "candidate SHA is not the immutable approved candidate"
}

assert_validator_checkout() {
    [[ "${SCRIPT_PATH:a}" == "$SCRIPT_PATH" && ! -L "$SCRIPT_PATH" ]] || fail "validator path traverses a symlink"
    local validator_repository="${SCRIPT_PATH:h}"
    [[ "$(git -C "$validator_repository" rev-parse --show-toplevel)" == "$validator_repository" ]] \
        || fail "validator must run from its repository root"
    [[ -z "$(git -C "$validator_repository" status --porcelain=v1 --untracked-files=all)" ]] \
        || fail "validator worktree is dirty"
    if git -C "$validator_repository" symbolic-ref -q HEAD >/dev/null 2>&1; then
        fail "validator must run from a detached immutable worktree"
    fi
}

validate_repository() {
    local argument="$1"
    local repository="${argument:a}"
    [[ "$repository" == "${argument:A}" && -d "$repository" ]] || fail "candidate repository path traverses a symlink or is missing"
    [[ "$(git -C "$repository" rev-parse --show-toplevel)" == "$repository" ]] || fail "candidate path is not its worktree root"
    [[ -z "$(git -C "$repository" status --porcelain=v1 --untracked-files=all)" ]] || fail "candidate worktree is dirty"
    if git -C "$repository" symbolic-ref -q HEAD >/dev/null 2>&1; then
        fail "candidate worktree must be detached"
    fi

    local head="$(git -C "$repository" rev-parse HEAD)"
    assert_exact_candidate "$head"
    [[ "$(git -C "$repository" rev-parse 'HEAD^{tree}')" == "$EXPECTED_TREE" ]] || fail "candidate tree drifted"
    [[ "$(git -C "$repository" rev-parse 'HEAD^')" == "$EXPECTED_PARENT" ]] || fail "candidate parent drifted"
    [[ "$(git -C "$repository" rev-list --count "$EXPECTED_CANONICAL..HEAD")" == "19" ]] || fail "candidate commit count drifted"

    local sequence="$(git -C "$repository" rev-list --reverse --first-parent "$EXPECTED_CANONICAL..HEAD")"
    [[ "$sequence" == "$(printf '%s\n' "${EXPECTED_COMMITS[@]}")" ]] || fail "candidate first-parent lineage drifted"

    local scope="$(git -C "$repository" diff --name-only "$EXPECTED_CANONICAL..HEAD")"
    has_exact_lines "$scope" "$(printf '%s\n' "${EXPECTED_FILES[@]}")" || fail "candidate scope is not the exact eight reviewed files"
    ! grep -Eq '(^|/)(scenario-registry\.json|zoid-coach-product-scenario-tracker\.md|666-BACKLOG\.md)$|^\.audit/|^\.lavish/' <<<"$scope" \
        || fail "candidate overlaps protected tracker, registry, audit, backlog, or Lavish state"

    local index
    for (( index = 1; index <= ${#EXPECTED_FILES[@]}; index++ )); do
        [[ "$(git -C "$repository" rev-parse "HEAD:${EXPECTED_FILES[$index]}")" == "${EXPECTED_BLOBS[$index]}" ]] \
            || fail "candidate blob drifted: ${EXPECTED_FILES[$index]}"
    done
    [[ "$(git -C "$repository" rev-parse HEAD:Sources/ZoidCoachApp/TaskEstimateInput.swift)" == "$EXPECTED_INPUT_BLOB" ]] \
        || fail "canonical estimate parser blob drifted"
    [[ "$(git -C "$repository" rev-parse HEAD:Tests/ZoidCoachAppTests/TaskEstimateInputTests.swift)" == "$EXPECTED_INPUT_TEST_BLOB" ]] \
        || fail "canonical estimate parser test blob drifted"

    local range_patch="$(git -C "$repository" diff "$EXPECTED_CANONICAL..HEAD" | git patch-id --stable | awk '{print $1}')"
    [[ "$range_patch" == "$EXPECTED_RANGE_PATCH" ]] || fail "candidate cumulative patch identity drifted"
    for (( index = 1; index <= ${#EXPECTED_COMMITS[@]}; index++ )); do
        [[ "$(commit_patch_id "$repository" "${EXPECTED_COMMITS[$index]}")" == "${EXPECTED_COMMIT_PATCHES[$index]}" ]] \
            || fail "candidate commit patch identity drifted: ${EXPECTED_COMMITS[$index]}"
    done

    local final_scope="$(git -C "$repository" diff-tree --no-commit-id --name-only -r HEAD)"
    has_exact_lines "$final_scope" $'Scripts/qa-zc011007-signed-preflight.sh\ndocs/ZC-011-007-SIGNED-QA-RUNBOOK.md' \
        || fail "final lineage commit scope drifted"
}

self_test() {
    local repository="$1"
    validate_repository "$repository"

    local common_directory="$(git -C "$repository" rev-parse --git-common-dir)"
    [[ "$common_directory" == /* ]] || common_directory="$repository/$common_directory"
    common_directory="${common_directory:A}"
    local temporary="$(mktemp -d /private/tmp/zc011007-validator-self-test.XXXXXX)"
    chmod 700 "$temporary"
    trap 'rm -rf -- "${temporary:-}"' EXIT
    mkdir -m 700 "$temporary/objects"

    local alternate
    alternate="$(env \
        GIT_OBJECT_DIRECTORY="$temporary/objects" \
        GIT_ALTERNATE_OBJECT_DIRECTORIES="$common_directory/objects" \
        GIT_AUTHOR_NAME='ZC-011-007 validator self-test' \
        GIT_AUTHOR_EMAIL='validator.invalid@example.invalid' \
        GIT_AUTHOR_DATE='2026-07-16T00:00:00Z' \
        GIT_COMMITTER_NAME='ZC-011-007 validator self-test' \
        GIT_COMMITTER_EMAIL='validator.invalid@example.invalid' \
        GIT_COMMITTER_DATE='2026-07-16T00:00:00Z' \
        git -C "$repository" commit-tree "$EXPECTED_TREE" -p "$EXPECTED_CANDIDATE" -m 'alternate same-tree child')"
    [[ "$alternate" != "$EXPECTED_CANDIDATE" ]] || fail "alternate-child self-test did not create a distinct commit"
    [[ "$(env GIT_OBJECT_DIRECTORY="$temporary/objects" GIT_ALTERNATE_OBJECT_DIRECTORIES="$common_directory/objects" git -C "$repository" rev-parse "$alternate^{tree}")" == "$EXPECTED_TREE" ]] \
        || fail "alternate-child self-test did not preserve the approved tree"
    [[ "$(env GIT_OBJECT_DIRECTORY="$temporary/objects" GIT_ALTERNATE_OBJECT_DIRECTORIES="$common_directory/objects" git -C "$repository" rev-parse "$alternate^")" == "$EXPECTED_CANDIDATE" ]] \
        || fail "alternate-child self-test did not create a direct child"
    if (assert_exact_candidate "$alternate") 2>/dev/null; then
        fail "validator accepted an alternate child of the approved candidate"
    fi

    /usr/bin/env -i \
        HOME=/private/tmp/zc011007-malicious-home \
        TMPDIR=/private/tmp/zc011007-malicious-tmp \
        PATH=/private/tmp/zc011007-malicious-bin \
        GIT_DIR=/private/tmp/zc011007-malicious.git \
        GIT_WORK_TREE=/private/tmp/zc011007-malicious-worktree \
        GIT_CONFIG_COUNT=1 \
        GIT_CONFIG_KEY_0=core.fsmonitor \
        GIT_CONFIG_VALUE_0=/private/tmp/zc011007-malicious-hook \
        ZOID_666_QA_ZC011007_DAY="2099-12-31'; SELECT malicious" \
        /bin/zsh "$SCRIPT_PATH" --assert-scrubbed-environment >/dev/null

    /usr/bin/env -i \
        HOME=/private/tmp/zc011007-malicious-home \
        TMPDIR=/private/tmp/zc011007-malicious-tmp \
        PATH=/private/tmp/zc011007-malicious-bin \
        GIT_DIR=/private/tmp/zc011007-malicious.git \
        GIT_WORK_TREE=/private/tmp/zc011007-malicious-worktree \
        GIT_CONFIG_COUNT=1 \
        GIT_CONFIG_KEY_0=core.fsmonitor \
        GIT_CONFIG_VALUE_0=/private/tmp/zc011007-malicious-hook \
        ZOID_666_QA_ZC011007_DAY="2099-12-31'; SELECT malicious" \
        /bin/zsh "$SCRIPT_PATH" "$repository/Scripts/qa-zc011007-signed-preflight.sh" --self-test >/dev/null

    rm -rf -- "$temporary"
    temporary=""
    trap - EXIT
    print -- "PASS: immutable ZC-011-007 candidate validator self-test"
}

assert_validator_checkout

if [[ "${1:-}" == "--assert-scrubbed-environment" ]]; then
    [[ $# == 1 ]] || fail "scrubbed-environment self-test accepts no arguments"
    environment_is_scrubbed || fail "validator environment was not scrubbed"
    [[ -z "${GIT_DIR:-}" && -z "${GIT_WORK_TREE:-}" && -z "${GIT_CONFIG_COUNT:-}" \
        && -z "${ZOID_666_QA_ZC011007_DAY:-}" && -z "${ZC011007_APPROVED_FINAL_COMMIT:-}" ]] \
        || fail "validator retained an injected Git, fixture, or approval variable"
    print -- "PASS: immutable validator environment scrubbed"
    exit 0
fi

if [[ "${1:-}" == "--self-test" ]]; then
    [[ $# == 2 ]] || fail "usage: $0 --self-test /absolute/detached/candidate-worktree"
    self_test "$2"
    exit 0
fi

[[ $# -ge 2 ]] || fail "usage: $0 /absolute/candidate/Scripts/qa-zc011007-signed-preflight.sh <preflight-arguments>"
readonly PREFLIGHT="${1:a}"
[[ "$PREFLIGHT" == "${1:A}" && ! -L "$PREFLIGHT" && -x "$PREFLIGHT" ]] || fail "preflight path traverses a symlink or is not executable"
readonly CANDIDATE_REPOSITORY="${PREFLIGHT:h:h}"
[[ "$PREFLIGHT" == "$CANDIDATE_REPOSITORY/Scripts/qa-zc011007-signed-preflight.sh" ]] || fail "preflight is not the candidate-owned ZC-011-007 preflight"
validate_repository "$CANDIDATE_REPOSITORY"
shift
/usr/bin/env -i \
    HOME="$SAFE_HOME" \
    TMPDIR="$SAFE_TMPDIR" \
    PATH="$SAFE_PATH" \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_SYSTEM=/dev/null \
    GIT_ATTR_NOSYSTEM=1 \
    ZC011007_APPROVED_FINAL_COMMIT="$EXPECTED_CANDIDATE" \
    /bin/zsh "$PREFLIGHT" "$@"
