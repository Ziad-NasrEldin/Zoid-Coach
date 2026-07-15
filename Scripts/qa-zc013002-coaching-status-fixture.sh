#!/bin/zsh
set -euo pipefail

fail() { print -u2 -- "FAIL: $*"; exit 1 }
is_safe() { [[ "$1" == /private/tmp/zoid-zc013002-* ]]; }
database_ok() { is_safe "$1" && [[ "$1" == */Application\ Support/Zoid\ 666/zoid-coach.sqlite ]]; }

snapshot_root() {
    local root="${1:A}" snapshot="${2:A}"
    is_safe "$root" && is_safe "$snapshot" || fail "snapshot paths must remain in the ZC-013-002 QA namespace"
    rm -rf -- "$snapshot"
    mkdir -p -- "${snapshot:h}"
    ditto --noqtn "$root" "$snapshot"
}

restore_root() {
    local root="${1:A}" snapshot="${2:A}"
    is_safe "$root" && is_safe "$snapshot" || fail "restore paths must remain in the ZC-013-002 QA namespace"
    [[ -d "$snapshot" ]] || fail "snapshot is missing"
    rm -rf -- "$root"
    ditto --noqtn "$snapshot" "$root"
}

root_digest() {
    local root="${1:A}"
    [[ -d "$root" ]] || fail "root is missing"
    (cd "$root" && find . -type f -print | LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 "$file"; done) | shasum -a 256 | awk '{print $1}'
}

prepare_state() {
    local database="${1:A}" state="$2" complete_days paused resumes level
    database_ok "$database" || fail "database must be the isolated ZC-013-002 QA database"
    [[ -f "$database" ]] || fail "database is missing"
    case "$state" in
        observation) complete_days=0; paused=0; resumes=null; level=gentle ;;
        gentle) complete_days=7; paused=0; resumes=null; level=gentle ;;
        accountability) complete_days=7; paused=0; resumes=null; level=accountability ;;
        paused-indefinite) complete_days=7; paused=1; resumes=null; level=accountability ;;
        paused-timed) complete_days=7; paused=1; resumes='"2099-07-15T12:00:00Z"'; level=gentle ;;
        *) fail "unknown state: $state" ;;
    esac
    sqlite3 "$database" "BEGIN IMMEDIATE;
      UPDATE policy_versions SET payload_json=json_set(payload_json,'$.automationPause.isPaused',$paused,'$.automationPause.resumesAtUTC',$resumes,'$.gaming.coachingLevel','$level') WHERE policy_type='user_policy' AND is_active=1;
      UPDATE settings SET value_json=json_set(value_json,'$.automationPause.isPaused',$paused,'$.automationPause.resumesAtUTC',$resumes,'$.gaming.coachingLevel','$level') WHERE key='user_policy';
      DELETE FROM baseline_observation_days;
      COMMIT;"
    if (( complete_days == 7 )); then
        sqlite3 "$database" "WITH RECURSIVE n(value) AS (VALUES(1) UNION ALL SELECT value+1 FROM n WHERE value<7)
          INSERT INTO baseline_observation_days(local_day,observed_minutes,work_minutes,gaming_minutes,distracting_minutes,unknown_minutes,eligible_drift_count,coverage,recorded_at_utc)
          SELECT printf('2099-07-%02d',value),60,45,0,0,15,0,'complete','2099-07-15T00:00:00Z' FROM n;"
    fi
}

self_test() {
    local root=/private/tmp/zoid-zc013002-fixture-selftest-$$ snapshot=/private/tmp/zoid-zc013002-fixture-snapshot-$$ before database
    trap "rm -rf -- '$root' '$snapshot'" EXIT
    mkdir -p "$root/Application Support/Zoid 666"
    print -n -- 'private fixture bytes' > "$root/Application Support/Zoid 666/sentinel"
    before="$(root_digest "$root")"
    snapshot_root "$root" "$snapshot"
    print -n -- changed > "$root/Application Support/Zoid 666/sentinel"
    restore_root "$root" "$snapshot"
    [[ "$(root_digest "$root")" == "$before" ]] || fail "byte restoration changed fixture content"
    database="$root/Application Support/Zoid 666/zoid-coach.sqlite"
    sqlite3 "$database" "CREATE TABLE policy_versions(policy_type TEXT, payload_json TEXT, is_active INTEGER); CREATE TABLE settings(key TEXT, value_json TEXT); CREATE TABLE baseline_observation_days(local_day TEXT PRIMARY KEY, observed_minutes INTEGER, work_minutes INTEGER, gaming_minutes INTEGER, distracting_minutes INTEGER, unknown_minutes INTEGER, eligible_drift_count INTEGER, coverage TEXT, recorded_at_utc TEXT); INSERT INTO policy_versions VALUES('user_policy','{\"automationPause\":{\"isPaused\":false},\"gaming\":{\"coachingLevel\":\"gentle\"}}',1); INSERT INTO settings VALUES('user_policy','{\"automationPause\":{\"isPaused\":false},\"gaming\":{\"coachingLevel\":\"gentle\"}}');"
    for state in observation gentle accountability paused-indefinite paused-timed; do
        prepare_state "$database" "$state"
    done
    [[ "$(sqlite3 "$database" "SELECT count(*) FROM baseline_observation_days;")" == 7 ]] || fail "complete baseline fixture was not installed"
    [[ "$(sqlite3 "$database" "SELECT json_extract(payload_json,'$.automationPause.isPaused') FROM policy_versions WHERE is_active=1;")" == 1 ]] || fail "paused fixture policy was not installed"
    [[ "$(sqlite3 "$database" "SELECT json_extract(payload_json,'$.automationPause.resumesAtUTC') FROM policy_versions WHERE is_active=1;")" == "2099-07-15T12:00:00Z" ]] || fail "timed pause evidence was not installed"
    ! is_safe /tmp/unrelated || fail "unsafe path accepted"
    print -- "PASS: ZC-013-002 fixture state, path safety, and byte restoration self-test"
}

case "${1:-}" in
    prepare) [[ $# == 3 ]] || fail "usage: prepare DATABASE STATE"; prepare_state "$2" "$3" ;;
    snapshot-root) [[ $# == 3 ]] || fail "usage: snapshot-root ROOT SNAPSHOT"; snapshot_root "$2" "$3" ;;
    restore-root) [[ $# == 3 ]] || fail "usage: restore-root ROOT SNAPSHOT"; restore_root "$2" "$3" ;;
    digest-root) [[ $# == 2 ]] || fail "usage: digest-root ROOT"; root_digest "$2" ;;
    self-test) self_test ;;
    *) fail "usage: $0 <prepare|snapshot-root|restore-root|digest-root|self-test> ..." ;;
esac
