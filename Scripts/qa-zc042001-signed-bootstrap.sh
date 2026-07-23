#!/bin/zsh
set -euo pipefail

readonly SCRIPT_DIR="${0:A:h}"
readonly REPOSITORY="${SCRIPT_DIR:h}"
readonly INSTALLER="$SCRIPT_DIR/install-signed-qa-runtime.sh"
readonly EVIDENCE_PARENT="/private/tmp/zoid-zc042001-evidence"

fail() { print -u2 -- "FAIL: $*"; exit 1; }
is_sha() { [[ "$1" =~ '^[0-9a-f]{40}$' ]]; }
evidence_root() { print -- "$EVIDENCE_PARENT/$1"; }

assert_external_evidence_root() {
    local candidate="${1:A}"
    [[ "$candidate" == "$EVIDENCE_PARENT"/* ]] \
        || fail "evidence root must remain under $EVIDENCE_PARENT"
    [[ "$candidate" != "$REPOSITORY" && "$candidate" != "$REPOSITORY"/* ]] \
        || fail "evidence root must not be inside the repository"
}

assert_clean_repository_identity() {
    [[ -z "$(git -C "$REPOSITORY" status --porcelain=v1 --untracked-files=all)" ]] \
        || fail "repository must be clean before any evidence path is created"
}

assert_bootstrap_order() {
    local script="$SCRIPT_DIR/qa-zc042001-signed-bootstrap.sh"
    local clean_line mkdir_line install_line
    clean_line="$(grep -n '^assert_clean_repository_identity$' "$script" | cut -d: -f1)"
    mkdir_line="$(grep -n '^mkdir -p -- "\$EVIDENCE_ROOT"$' "$script" | cut -d: -f1)"
    install_line="$(grep -n '^ZOID_COACH_QA_RUN_ROOT=' "$script" | cut -d: -f1)"
    [[ "$clean_line" == <-> && "$mkdir_line" == <-> && "$install_line" == <-> \
        && clean_line -lt mkdir_line && mkdir_line -lt install_line ]] \
        || fail "clean identity, external evidence creation, and installer order regressed"
}

assert_runbook_external_evidence_contract() {
    local runbook="$REPOSITORY/docs/ZC-042-001-SIGNED-QA-RUNBOOK.md"
    grep -Fq 'EVIDENCE_ROOT="/private/tmp/zoid-zc042001-evidence/$EXPECTED_SIGNED_COMMIT"' "$runbook" \
        || fail "runbook does not bind the external evidence root"
    ! grep -Fq '.audit/' "$runbook" \
        || fail "runbook directs generated evidence into the repository"
    ! grep -Eq '(mkdir -p|tee|screencapture).*(\$PWD|\$REPOSITORY)' "$runbook" \
        || fail "runbook creates generated evidence below a repository variable"
}

if [[ "${1:-}" == "--self-test" ]]; then
    readonly BEFORE_STATUS="$(git -C "$REPOSITORY" status --porcelain=v1 --untracked-files=all)"
    readonly SAMPLE_COMMIT="8cc9f2187e74787c183e444140b8696b8e37e52f"
    readonly SAMPLE_ROOT="$(evidence_root "$SAMPLE_COMMIT")"
    is_sha "$SAMPLE_COMMIT" || fail "valid SHA rejected"
    [[ "$SAMPLE_ROOT" == "/private/tmp/zoid-zc042001-evidence/$SAMPLE_COMMIT" ]] \
        || fail "external evidence path is not deterministic"
    assert_external_evidence_root "$SAMPLE_ROOT"
    assert_bootstrap_order
    assert_runbook_external_evidence_contract
    [[ "$(git -C "$REPOSITORY" status --porcelain=v1 --untracked-files=all)" == "$BEFORE_STATUS" ]] \
        || fail "bootstrap self-test created a repository path"
    print -- "PASS: ZC-042-001 signed bootstrap self-test"
    exit 0
fi

readonly EXPECTED_COMMIT="${1:-}"
readonly QA_ROOT="${2:-}"
readonly INSTALL_ROOT="${3:-}"
is_sha "$EXPECTED_COMMIT" || fail "expected commit must be a full lowercase SHA"
[[ -n "$QA_ROOT" && -n "$INSTALL_ROOT" ]] \
    || fail "usage: $0 <expected-commit> <qa-root> <install-root>"
[[ "$(git -C "$REPOSITORY" rev-parse HEAD)" == "$EXPECTED_COMMIT" ]] \
    || fail "worktree HEAD does not match expected signed commit"

assert_clean_repository_identity
readonly EVIDENCE_ROOT="$(evidence_root "$EXPECTED_COMMIT")"
assert_external_evidence_root "$EVIDENCE_ROOT"
mkdir -p -- "$EVIDENCE_ROOT"
print -- "EVIDENCE_ROOT=$EVIDENCE_ROOT"
ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" ZOID_COACH_QA_INSTALL_ROOT="$INSTALL_ROOT" \
    "$INSTALLER" 2>&1 | tee "$EVIDENCE_ROOT/install.log"
