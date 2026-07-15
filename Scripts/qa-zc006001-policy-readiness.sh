#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly SQLITE3=/usr/bin/sqlite3
readonly LSOF=/usr/sbin/lsof

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

helper_is_registered() {
    local label="$1"
    if [[ -n "${ZC006001_HELPER_CHECK:-}" ]]; then
        "$ZC006001_HELPER_CHECK" "$label"
    else
        /bin/launchctl print "gui/$(/usr/bin/id -u)/$label" >/dev/null 2>&1
    fi
}

policy_snapshot() {
    local database="$1"
    "$SQLITE3" -batch -noheader "$database" <<'SQL'
WITH active AS (
    SELECT version, payload_json
    FROM policy_versions
    WHERE policy_type = 'user_policy' AND is_active = 1
), current AS (
    SELECT policy_version, value_json
    FROM settings
    WHERE key = 'user_policy'
)
SELECT printf('%d|%s', current.policy_version, hex(current.value_json))
FROM current, active
WHERE (SELECT COUNT(*) FROM current) = 1
  AND (SELECT COUNT(*) FROM active) = 1
  AND current.policy_version = active.version
  AND current.value_json = active.payload_json
  AND json_valid(current.value_json)
  AND json_valid(active.payload_json);
SQL
}

wait_ready() {
    local database="$1" pid="$2" label="$3" decoder="$4"
    [[ -f "$database" && ! -L "$database" ]] || fail "isolated database is unavailable or unsafe"
    [[ "$pid" == <-> ]] || fail "foreground PID must be numeric"
    [[ -x "$decoder" ]] || fail "production policy decoder is unavailable"
    local temporary="${TMPDIR:-/private/tmp}/zc006001-policy.$$.json"
    trap "/bin/rm -f -- ${(q)temporary}" EXIT
    local previous="" stable=0 snapshot attempt
    for (( attempt = 1; attempt <= ${ZC006001_POLICY_ATTEMPTS:-80}; attempt += 1 )); do
        kill -0 "$pid" 2>/dev/null || fail "signed foreground PID exited before policy readiness"
        helper_is_registered "$label" && fail "QA helper registered before policy readiness"
        "$LSOF" -a -p "$pid" "$database" >/dev/null 2>&1 \
            || fail "signed foreground PID does not own the exact isolated database"
        snapshot="$(policy_snapshot "$database")"
        if [[ -n "$snapshot" ]]; then
            "$SQLITE3" -batch -noheader "$database" \
                "SELECT value_json FROM settings WHERE key = 'user_policy';" > "$temporary"
            "$decoder" "$temporary" >/dev/null 2>&1 || fail "active policy failed production decode"
            if [[ "$snapshot" == "$previous" ]]; then
                (( stable += 1 ))
            else
                previous="$snapshot"
                stable=1
            fi
            if (( stable >= 3 )); then
                print -- "POLICY_VERSION=${snapshot%%|*}"
                print -- "PASS: active production policy is linked, decoded, foreground-owned, and stable"
                return 0
            fi
        else
            previous=""
            stable=0
        fi
        /bin/sleep "${ZC006001_POLICY_INTERVAL:-0.25}"
    done
    fail "timed out waiting for a stable active production policy"
}

self_test() (
    local root="${TMPDIR:-/private/tmp}/zc006001-policy-readiness.$$"
    /bin/mkdir -m 700 "$root"
    trap '/bin/rm -rf -- "$root"' EXIT
    local database="$root/policy.sqlite" decoder="$root/decoder" helper="$root/helper" holder
    "$SQLITE3" "$database" <<'SQL'
CREATE TABLE settings(key TEXT PRIMARY KEY, value_json TEXT NOT NULL, policy_version INTEGER NOT NULL, updated_at_utc TEXT NOT NULL);
CREATE TABLE policy_versions(policy_type TEXT NOT NULL, version INTEGER NOT NULL, payload_json TEXT NOT NULL, created_at_utc TEXT NOT NULL, is_active INTEGER NOT NULL);
SQL
    print -r -- '#!/bin/zsh
/usr/bin/jq -e '\''.schemaVersion == 5'\'' "$1" >/dev/null' > "$decoder"
    print -r -- '#!/bin/zsh
exit "${ZC006001_TEST_HELPER_PRESENT:-1}"' > "$helper"
    /bin/chmod 700 "$decoder" "$helper"
    /usr/bin/tail -f "$database" >/dev/null 2>&1 &
    holder=$!
    /bin/sleep 0.1
    if ( ZC006001_POLICY_ATTEMPTS=1 ZC006001_POLICY_INTERVAL=0 ZC006001_HELPER_CHECK="$helper" \
        wait_ready "$database" "$holder" qa.test "$decoder" >/dev/null 2>&1 ); then
        fail "missing settings was accepted"
    fi
    "$SQLITE3" "$database" "INSERT INTO settings VALUES('user_policy','{\"schemaVersion\":5}',1,'now');"
    if ( ZC006001_POLICY_ATTEMPTS=1 ZC006001_POLICY_INTERVAL=0 ZC006001_HELPER_CHECK="$helper" \
        wait_ready "$database" "$holder" qa.test "$decoder" >/dev/null 2>&1 ); then
        fail "missing active version was accepted"
    fi
    "$SQLITE3" "$database" "INSERT INTO policy_versions VALUES('user_policy',2,'{\"schemaVersion\":5}','now',1);"
    if ( ZC006001_POLICY_ATTEMPTS=1 ZC006001_POLICY_INTERVAL=0 ZC006001_HELPER_CHECK="$helper" \
        wait_ready "$database" "$holder" qa.test "$decoder" >/dev/null 2>&1 ); then
        fail "version mismatch was accepted"
    fi
    "$SQLITE3" "$database" "UPDATE policy_versions SET version=1,payload_json='{}';"
    if ( ZC006001_POLICY_ATTEMPTS=1 ZC006001_POLICY_INTERVAL=0 ZC006001_HELPER_CHECK="$helper" \
        wait_ready "$database" "$holder" qa.test "$decoder" >/dev/null 2>&1 ); then
        fail "payload mismatch was accepted"
    fi
    "$SQLITE3" "$database" "UPDATE settings SET value_json='{}'; UPDATE policy_versions SET payload_json='{}';"
    if ( ZC006001_POLICY_ATTEMPTS=1 ZC006001_POLICY_INTERVAL=0 ZC006001_HELPER_CHECK="$helper" \
        wait_ready "$database" "$holder" qa.test "$decoder" >/dev/null 2>&1 ); then
        fail "production-invalid JSON was accepted"
    fi
    "$SQLITE3" "$database" "UPDATE settings SET value_json='{\"schemaVersion\":5}'; UPDATE policy_versions SET payload_json='{\"schemaVersion\":5}';"
    ( ZC006001_TEST_HELPER_PRESENT=0 ZC006001_POLICY_ATTEMPTS=1 ZC006001_POLICY_INTERVAL=0 \
        ZC006001_HELPER_CHECK="$helper" wait_ready "$database" "$holder" qa.test "$decoder" >/dev/null 2>&1 \
    ) && fail "registered helper was accepted"
    kill "$holder"
    wait "$holder" 2>/dev/null || true
    ( ZC006001_POLICY_ATTEMPTS=1 ZC006001_POLICY_INTERVAL=0 ZC006001_HELPER_CHECK="$helper" \
        wait_ready "$database" "$holder" qa.test "$decoder" >/dev/null 2>&1 \
    ) && fail "exited foreground PID was accepted"
    : > "$root/not-the-database"
    /usr/bin/tail -f "$root/not-the-database" >/dev/null 2>&1 &
    holder=$!
    /bin/sleep 0.1
    ( ZC006001_POLICY_ATTEMPTS=1 ZC006001_POLICY_INTERVAL=0 ZC006001_HELPER_CHECK="$helper" \
        wait_ready "$database" "$holder" qa.test "$decoder" >/dev/null 2>&1 \
    ) && fail "wrong database ownership was accepted"
    kill "$holder"
    wait "$holder" 2>/dev/null || true
    /usr/bin/tail -f "$database" >/dev/null 2>&1 &
    holder=$!
    /bin/sleep 0.1
    ZC006001_POLICY_ATTEMPTS=3 ZC006001_POLICY_INTERVAL=0 ZC006001_HELPER_CHECK="$helper" \
        wait_ready "$database" "$holder" qa.test "$decoder" >/dev/null
    kill "$holder"
    wait "$holder" 2>/dev/null || true
    print -- "PASS: ZC-006-001 policy readiness rejects missing, mismatched, malformed, exited, helper-present, and wrong-owner states"
)

case "$COMMAND" in
    wait) (( $# == 5 )) || fail "usage: $0 wait <database> <pid> <agent-label> <decoder>"; wait_ready "$2" "$3" "$4" "$5" ;;
    --self-test) (( $# == 1 )) || fail "self-test takes no arguments"; self_test ;;
    *) fail "usage: $0 <wait|--self-test>" ;;
esac
