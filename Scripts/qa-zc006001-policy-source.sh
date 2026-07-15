#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly SQLITE3=/usr/bin/sqlite3
readonly SHASUM=/usr/bin/shasum

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

file_digests() {
    local database="$1"
    "$SHASUM" -a 256 "$database" "$database-wal" "$database-shm" | /usr/bin/awk '{print $1}'
}

materialize() {
    local source_database="$1" clone_root="$2" decoder="$3"
    [[ "$source_database" == /* && "$clone_root" == /* ]] || fail "policy source paths must be absolute"
    [[ ! -L "$source_database" && ! -L "$source_database-wal" && ! -L "$source_database-shm" ]] \
        || fail "policy source cannot contain symbolic links"
    [[ -f "$source_database" && -f "$source_database-wal" && -f "$source_database-shm" ]] \
        || fail "package policy source requires database, WAL, and SHM"
    [[ ! -e "$clone_root" && ! -L "$clone_root" ]] || fail "policy clone root must not exist"
    [[ -x "$decoder" ]] || fail "production policy decoder is unavailable"
    local source_before="$clone_root.source-before" source_after="$clone_root.source-after"
    local clone_before="$clone_root.clone-before" clone_database="$clone_root/zoid-coach.sqlite"
    file_digests "$source_database" > "$source_before"
    /bin/mkdir -m 700 "$clone_root"
    print -- "zc006001-policy-source-v1" > "$clone_root/.zc006001-policy-source"
    /bin/cp -p "$source_database" "$clone_database"
    /bin/cp -p "$source_database-wal" "$clone_database-wal"
    /bin/cp -p "$source_database-shm" "$clone_database-shm"
    if [[ "${ZC006001_CORRUPT_POLICY_CLONE:-0}" == 1 ]]; then
        print -n -- x >> "$clone_database-wal"
    fi
    file_digests "$clone_database" > "$clone_before"
    /usr/bin/cmp "$source_before" "$clone_before" >/dev/null \
        || fail "policy clone bytes do not match the stopped package source"
    if [[ "${ZC006001_MUTATE_POLICY_SOURCE:-0}" == 1 ]]; then
        print -n -- x >> "$source_database-wal"
    fi
    "$SQLITE3" -batch "$clone_database" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null \
        || fail "policy clone WAL checkpoint failed"
    local parity
    parity="$("$SQLITE3" -batch -noheader "file:$clone_database?immutable=1" <<'SQL'
SELECT CASE WHEN
    (SELECT COUNT(*) FROM settings WHERE key = 'user_policy') = 1
    AND (SELECT COUNT(*) FROM policy_versions WHERE policy_type = 'user_policy' AND is_active = 1) = 1
    AND (SELECT policy_version FROM settings WHERE key = 'user_policy') =
        (SELECT version FROM policy_versions WHERE policy_type = 'user_policy' AND is_active = 1)
    AND (SELECT value_json FROM settings WHERE key = 'user_policy') =
        (SELECT payload_json FROM policy_versions WHERE policy_type = 'user_policy' AND is_active = 1)
    AND json_valid((SELECT value_json FROM settings WHERE key = 'user_policy'))
THEN 1 ELSE 0 END;
SQL
)"
    [[ "$parity" == 1 ]] || fail "checkpointed policy clone lacks linked active policy parity"
    local policy_json="$clone_root/policy.json"
    "$SQLITE3" -batch -noheader "file:$clone_database?immutable=1" \
        "SELECT value_json FROM settings WHERE key = 'user_policy';" > "$policy_json"
    "$decoder" "$policy_json" >/dev/null || fail "checkpointed policy clone failed production decode"
    /bin/rm -f -- "$policy_json"
    file_digests "$source_database" > "$source_after"
    /usr/bin/cmp "$source_before" "$source_after" >/dev/null \
        || fail "pristine package policy source bytes changed"
    /bin/rm -f -- "$source_before" "$source_after" "$clone_before"
    print -- "POLICY_SOURCE_DATABASE=$clone_database"
    print -- "PASS: WAL policy cloned, byte-matched, checkpointed, decoded, and source-preserving"
}

delete_clone() {
    local clone_root="$1"
    [[ "$clone_root" == /* && -d "$clone_root" && ! -L "$clone_root" ]] || fail "policy clone root is unavailable or unsafe"
    [[ "$(<"$clone_root/.zc006001-policy-source")" == zc006001-policy-source-v1 ]] \
        || fail "policy clone marker is missing"
    /bin/rm -rf -- "$clone_root"
    [[ ! -e "$clone_root" ]] || fail "policy clone was not removed"
    print -- "PASS: disposable policy clone removed"
}

create_wal_only_source() {
    local database="$1" settings_version="$2" active_version="$3"
    "$SQLITE3" "$database" <<'SQL'
CREATE TABLE settings(key TEXT PRIMARY KEY, value_json TEXT NOT NULL, policy_version INTEGER NOT NULL, updated_at_utc TEXT NOT NULL);
CREATE TABLE policy_versions(policy_type TEXT NOT NULL, version INTEGER NOT NULL, payload_json TEXT NOT NULL, created_at_utc TEXT NOT NULL, is_active INTEGER NOT NULL);
SQL
    local fifo="$database.fifo" output="$database.output" writer
    /usr/bin/mkfifo "$fifo"
    "$SQLITE3" "$database" < "$fifo" > "$output" 2>&1 &
    writer=$!
    exec 7> "$fifo"
    print -u7 -- "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; BEGIN IMMEDIATE; INSERT INTO settings VALUES('user_policy','{\"schemaVersion\":5}',$settings_version,'baseline'); INSERT INTO policy_versions VALUES('user_policy',$active_version,'{\"schemaVersion\":5}','baseline',1); COMMIT; SELECT 'WAL_READY';"
    local ready=0
    for _ in {1..40}; do
        /usr/bin/grep -Fq WAL_READY "$output" && { ready=1; break; }
        /bin/sleep 0.05
    done
    [[ "$ready" == 1 ]] || fail "could not create WAL-only self-test policy"
    /bin/kill -KILL "$writer" 2>/dev/null || true
    exec 7>&-
    wait "$writer" 2>/dev/null || true
    /bin/rm -f -- "$fifo" "$output"
    [[ -f "$database-wal" && -f "$database-shm" ]] || fail "self-test WAL files are unavailable"
    [[ "$("$SQLITE3" -batch -noheader "file:$database?immutable=1" "SELECT COUNT(*) FROM settings WHERE key='user_policy';")" == 0 ]] \
        || fail "self-test policy was not WAL-only"
}

self_test() (
    local root="${TMPDIR:-/private/tmp}/zc006001-policy-source.$$"
    /bin/mkdir -m 700 "$root"
    trap '/bin/rm -rf -- "$root"' EXIT
    local decoder="$root/decoder" source="$root/source.sqlite"
    print -r -- '#!/bin/zsh
/usr/bin/jq -e '\''.schemaVersion == 5'\'' "$1" >/dev/null' > "$decoder"
    /bin/chmod 700 "$decoder"
    create_wal_only_source "$source" 7 7
    local source_hashes="$root/source-hashes"
    file_digests "$source" > "$source_hashes"
    materialize "$source" "$root/success-clone" "$decoder" >/dev/null
    /usr/bin/cmp "$source_hashes" <(file_digests "$source") >/dev/null \
        || fail "successful materialization changed source hashes"
    delete_clone "$root/success-clone" >/dev/null
    /bin/cp -p "$source" "$root/missing-wal.sqlite"
    /bin/cp -p "$source-shm" "$root/missing-wal.sqlite-shm"
    if ( materialize "$root/missing-wal.sqlite" "$root/missing-wal-clone" "$decoder" >/dev/null 2>&1 ); then
        fail "missing WAL was accepted"
    fi
    if ( ZC006001_CORRUPT_POLICY_CLONE=1 materialize "$source" "$root/corrupt-clone" "$decoder" >/dev/null 2>&1 ); then
        fail "corrupted clone was accepted"
    fi
    /bin/rm -rf -- "$root/corrupt-clone" "$root/corrupt-clone.source-before" "$root/corrupt-clone.clone-before"
    local mutation_source="$root/mutation.sqlite"
    /bin/cp -p "$source" "$mutation_source"
    /bin/cp -p "$source-wal" "$mutation_source-wal"
    /bin/cp -p "$source-shm" "$mutation_source-shm"
    if ( ZC006001_MUTATE_POLICY_SOURCE=1 materialize "$mutation_source" "$root/mutation-clone" "$decoder" >/dev/null 2>&1 ); then
        fail "source hash mutation was accepted"
    fi
    local mismatch="$root/mismatch.sqlite"
    create_wal_only_source "$mismatch" 7 8
    if ( materialize "$mismatch" "$root/mismatch-clone" "$decoder" >/dev/null 2>&1 ); then
        fail "active-version parity mismatch was accepted"
    fi
    print -- "PASS: policy source self-test covers WAL-only success, missing WAL, corrupt clone, source mutation, and parity mismatch"
)

case "$COMMAND" in
    materialize) (( $# == 4 )) || fail "usage: $0 materialize <source-db> <clone-root> <decoder>"; materialize "$2" "$3" "$4" ;;
    delete) (( $# == 2 )) || fail "usage: $0 delete <clone-root>"; delete_clone "$2" ;;
    --self-test) (( $# == 1 )) || fail "self-test takes no arguments"; self_test ;;
    *) fail "usage: $0 <materialize|delete|--self-test>" ;;
esac
