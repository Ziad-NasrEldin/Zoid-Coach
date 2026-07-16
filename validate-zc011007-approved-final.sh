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
readonly EXPECTED_CANDIDATE="63a1215a1985288d02e6b3c86ac5e265cb0155a4"
readonly EXPECTED_PARENT="ad5784d6095167d1b353975e770e8c5dbe55ee3b"
readonly EXPECTED_TREE="4a8656df8cb66fc282837ee29004e4bdead64598"
readonly EXPECTED_RANGE_PATCH="8aede83294e7f8611537a68e26fa652c06a815b8"
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
    71278e451457d619f6d1c65f7f4ca45a114778d8
    7b60ebc4fd029a10f0f6d9f5b8fe20f624406974
    6ecd958523735157e6e3e0e58b84e4296e31fd3c
    5ec8485fb6dcbd84d5fefde36c0652021a0c9820
    6a2185c46ae0c315de069fa065b7fa3ddcb52726
    3278b7940015865d38ebc9c76668a61e89092e6c
    67f7a77d793eed4c197d4bc114d03d56e84ee8a7
    496b4e58b5926e5972f74264d42ce991375e31eb
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
    1177f6a2f2215ae21c525bac3478d5df14f80e00
    5d5626d469c0dca7520f074019b691d7747e613e
    ba087b3160098c9b37831ac42999889d3299a413
    14c6c2ae24442767e602c4a49c0043464537ee46
    aa9166f3f9d46c7a8a628a6490ea13c3cc11acc4
    0c69459f440dfe6f298d55be6cb230ac858820c7
    bc077c0b0eb769462e1564056ce77312538d0b8d
    41ce826ea533f537a7ed50c30069982b15aaff39
    376c6d1566b7a8dfc087268abf5fa9931f38d8e3
    ad5784d6095167d1b353975e770e8c5dbe55ee3b
    63a1215a1985288d02e6b3c86ac5e265cb0155a4
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
    4f0d450cdbdece37d72de86142ce2e743398e2ec
    65cdb58a97aee1cc9a9d69d50d2e0b0212a8fc70
    be09fdb24cb96af3a6eb7d11ae212a961628e260
    05ab76739f95442608d70fd55672927e14cb873c
    14827da591734eea318c45621fa6d3b4fbf7c71b
    b4cf65a5e281adced6d6b3cef18194374cd2c2e6
    1c89b9251ab8c30f4e2803250673b71d6e93dacc
    89e064f7ba39348409325eefe8b5ce8f8445e7bf
    36f1bbe7b251742da6248d2cc8adb126a7ed7bb2
    4e9f7e0a709ba286fb09ce6f8d5b5b20fc14d4b6
    0429aef9015292d6debe1e0b189543e2047e9ceb
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
    [[ "$(git -C "$repository" rev-list --count "$EXPECTED_CANONICAL..HEAD")" == "30" ]] || fail "candidate commit count drifted"

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
