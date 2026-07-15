#!/bin/zsh
set -euo pipefail

readonly COMMAND="${1:-}"
readonly SCRIPT_DIR="${0:A:h}"
readonly TEMPLATE="${ZC006001_TEMPLATE:-$SCRIPT_DIR/fixtures/zc-006-001-planning-invitation-ready-state.json}"
readonly JQ="/usr/bin/jq"
readonly SQLITE3="/usr/bin/sqlite3"

fail() {
    print -u2 -- "FAIL: $*"
    exit 1
}

usage() {
    print -u2 -- "usage: $0 <materialize|assert-manifest|seed-policy|configure-boundary|assert-database|assert-notification|self-test> ..."
    exit 2
}

seed_policy() {
    local source_database="$1" target_database="$2"
    [[ -f "$source_database" && ! -L "$source_database" ]] || fail "baseline policy database is unavailable or unsafe"
    [[ -f "$target_database" && ! -L "$target_database" ]] || fail "isolated target database is unavailable or unsafe"
    [[ "$source_database" != *[\?\#\']* && "$target_database" != *"'"* ]] \
        || fail "database paths contain unsupported URI characters"
    local source_uri="file:$source_database?immutable=1" source_valid target_empty
    source_valid="$("$SQLITE3" -batch -noheader "$source_uri" <<'SQL'
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
    [[ "$source_valid" == 1 ]] || fail "baseline does not contain one linked active policy"
    target_empty="$("$SQLITE3" -batch -noheader "$target_database" \
        "SELECT (SELECT COUNT(*) FROM settings WHERE key='user_policy') + (SELECT COUNT(*) FROM policy_versions WHERE policy_type='user_policy');")"
    [[ "$target_empty" == 0 ]] || fail "isolated target already contains policy state"
    "$SQLITE3" -batch "$target_database" <<SQL
ATTACH DATABASE '$source_uri' AS baseline;
BEGIN IMMEDIATE;
INSERT INTO policy_versions(policy_type, version, payload_json, created_at_utc, is_active)
SELECT policy_type, version, payload_json, created_at_utc, is_active
FROM baseline.policy_versions
WHERE policy_type = 'user_policy' AND is_active = 1;
INSERT INTO settings(key, value_json, policy_version, updated_at_utc)
SELECT key, value_json, policy_version, updated_at_utc
FROM baseline.settings
WHERE key = 'user_policy';
COMMIT;
DETACH DATABASE baseline;
SQL
    local copied
    copied="$("$SQLITE3" -batch -noheader "$target_database" <<'SQL'
SELECT CASE WHEN
    (SELECT COUNT(*) FROM settings WHERE key = 'user_policy') = 1
    AND (SELECT COUNT(*) FROM policy_versions WHERE policy_type = 'user_policy' AND is_active = 1) = 1
    AND (SELECT policy_version FROM settings WHERE key = 'user_policy') =
        (SELECT version FROM policy_versions WHERE policy_type = 'user_policy' AND is_active = 1)
    AND (SELECT value_json FROM settings WHERE key = 'user_policy') =
        (SELECT payload_json FROM policy_versions WHERE policy_type = 'user_policy' AND is_active = 1)
THEN 1 ELSE 0 END;
SQL
)"
    [[ "$copied" == 1 ]] || fail "seeded policy lost active-version linkage"
    print -- "PASS: package-created active policy seeded byte-for-byte while runtime stopped"
}

configure_boundary() {
    local mode="$1" database="$2" offset hour minute
    [[ -f "$database" && ! -L "$database" ]] || fail "isolated database is unavailable or unsafe"
    case "$mode" in
        future) offset="+5M" ;;
        past) offset="-5M" ;;
        *) fail "boundary mode must be future or past" ;;
    esac
    hour="$(TZ=Africa/Cairo /bin/date -v"$offset" '+%H')"
    minute="$(TZ=Africa/Cairo /bin/date -v"$offset" '+%M')"
    "$SQLITE3" -batch "$database" <<SQL
BEGIN IMMEDIATE;
UPDATE settings
SET value_json = json_set(
        value_json,
        '$.schedule.timeZoneIdentifier', 'Africa/Cairo',
        '$.schedule.morningConfirmationTime.hour', CAST('$hour' AS INTEGER),
        '$.schedule.morningConfirmationTime.minute', CAST('$minute' AS INTEGER)
    ),
    updated_at_utc = strftime('%Y-%m-%dT%H:%M:%SZ', 'now')
WHERE key = 'user_policy';
UPDATE policy_versions
SET payload_json = (SELECT value_json FROM settings WHERE key = 'user_policy')
WHERE policy_type = 'user_policy'
  AND version = (SELECT policy_version FROM settings WHERE key = 'user_policy');
COMMIT;
SQL
    local actual
    actual="$("$SQLITE3" -batch -noheader "$database" "SELECT printf('%02d:%02d', json_extract(value_json, '$.schedule.morningConfirmationTime.hour'), json_extract(value_json, '$.schedule.morningConfirmationTime.minute')) FROM settings WHERE key = 'user_policy';")"
    [[ "$actual" == "$hour:$minute" ]] || fail "configured morning boundary did not persist"
    print -- "BOUNDARY_LOCAL_TIME=$actual"
    print -- "PASS: ZC-006-001 $mode configured planning boundary"
}

expected_count() {
    case "$1" in
        zero) print 0 ;;
        one) print 1 ;;
        many) print 3 ;;
        *) fail "cardinality must be zero, one, or many" ;;
    esac
}

expected_summary() {
    case "$1" in
        0) print -- "You can make a small plan, or start without one. You can snooze or dismiss this invitation for now. Nothing is blocked." ;;
        1) print -- "You can review 1 suggested commitment, or start without a plan. You can snooze or dismiss this invitation for now. Nothing is blocked." ;;
        3) print -- "You can review 3 suggested commitments, or start without a plan. You can snooze or dismiss this invitation for now. Nothing is blocked." ;;
        *) fail "unsupported expected count: $1" ;;
    esac
}

assert_manifest() {
    local cardinality="$1" manifest="$2" count
    count="$(expected_count "$cardinality")"
    [[ -f "$manifest" && ! -L "$manifest" ]] || fail "manifest is unavailable or unsafe"
    "$JQ" -e --argjson count "$count" '
        .schemaVersion == 1
        and (.osFixture.reminders | length) == $count
        and (.osFixture.notifications | length) == 0
        and .osFixture.permissions.notifications == "granted"
        and .onboarding.notificationAccess == "granted"
        and ([.osFixture.reminders[].id] | length == (unique | length))
        and ([.osFixture.reminders[].title] | all(test("private|https?://"; "i") | not))
        and ([.screenwatch.days[].records[].window] | any(. == "qa-zc006001-private-window-title"))
        and ([.screenwatch.days[].records[].url] | any(. == "https://qa-zc006001-private.invalid/client"))
    ' "$manifest" >/dev/null || fail "materialized manifest does not satisfy ZC-006-001"
}

materialize() {
    local cardinality="$1" output="$2" count parent
    count="$(expected_count "$cardinality")"
    [[ -f "$TEMPLATE" && ! -L "$TEMPLATE" ]] || fail "template is unavailable or unsafe"
    parent="${output:h}"
    /bin/mkdir -p "$parent"
    [[ ! -L "$parent" && ! -L "$output" ]] || fail "output path cannot use symbolic links"
    local temporary="$output.tmp.$$"
    if ! "$JQ" --argjson count "$count" '.osFixture.reminders = .osFixture.reminders[:$count]' "$TEMPLATE" > "$temporary"; then
        /bin/rm -f -- "$temporary"
        fail "could not materialize ready-state manifest"
    fi
    /bin/chmod 600 "$temporary"
    /bin/mv -f -- "$temporary" "$output"
    assert_manifest "$cardinality" "$output"
    print -- "PASS: ZC-006-001 $cardinality ready-state manifest materialized"
}

assert_database() {
    local cardinality="$1" database="$2" count summary
    count="$(expected_count "$cardinality")"
    summary="$(expected_summary "$count")"
    [[ -f "$database" && ! -L "$database" ]] || fail "isolated database is unavailable or unsafe"
    local where="prompt_type = 'PLAN_READY' AND state IN ('queued', 'presented')"
    local rows
    rows="$("$SQLITE3" -batch -noheader "$database" "SELECT COUNT(*) FROM prompt_episodes WHERE $where;")"
    [[ "$rows" == "1" ]] || fail "expected exactly one unresolved PLAN_READY prompt, got $rows"
    "$SQLITE3" -batch -noheader "$database" <<SQL | /usr/bin/grep -Fxq '1' || fail "canonical invitation content or action contract mismatch"
SELECT CASE WHEN
    title = 'Planning is available when you are ready'
    AND summary = replace('$summary', '''', '''''')
    AND json_extract(payload_json, '$.payload.itemCount') = '$count'
    AND json_extract(payload_json, '$.actions[0].kind') = 'review_plan'
    AND json_extract(payload_json, '$.actions[1].kind') = 'accept_plan'
    AND json_extract(payload_json, '$.actions[2].kind') = 'snooze_planning'
    AND json_extract(payload_json, '$.actions[3].kind') = 'work_unplanned'
    AND json_extract(payload_json, '$.actions[4].kind') = 'dismiss_planning'
    AND json_array_length(json_extract(payload_json, '$.actions')) = 5
    AND instr(title || ' ' || summary, 'qa-zc006001-private') = 0
    AND instr(title || ' ' || summary, 'private.invalid') = 0
THEN 1 ELSE 0 END
FROM prompt_episodes
WHERE $where;
SQL
    print -- "PASS: ZC-006-001 $cardinality canonical prompt and stable actions persisted"
}

assert_notification() {
    local mode="$1" cardinality="$2" state_file="$3" count summary
    count="$(expected_count "$cardinality")"
    summary="$(expected_summary "$count")"
    [[ -f "$state_file" && ! -L "$state_file" ]] || fail "OS fixture state is unavailable or unsafe"
    "$JQ" -e --arg title "Planning is available when you are ready" --arg body "$summary" --arg mode "$mode" '
        [.notifications[] | select(.desired.title == $title and .desired.body == $body)] as $matching
        | ($matching | length) == 1
        and ($matching[0].desired.category | endswith("PLAN_READY"))
        and (if $mode == "future"
             then $matching[0].status == "scheduled"
                  and ($matching[0].desired.deliveryDate > now)
                  and ($matching[0].deliveredAt == null)
             else $matching[0].status == "delivered"
                  and ($matching[0].desired.deliveryDate == null or $matching[0].desired.deliveryDate <= now)
             end)
        and ([.audit[] | select(.subsystem == "notifications" and .operation == "schedule")] | length) >= 1
    ' "$state_file" >/dev/null || fail "$mode notification boundary assertion failed"
    print -- "PASS: ZC-006-001 $cardinality notification respects the $mode configured boundary"
}

self_test() (
    local root="${TMPDIR:-/private/tmp}/zc006001-fixture-self-test.$$"
    /bin/mkdir -m 700 "$root"
    trap '/bin/rm -rf -- "$root"' EXIT
    local cardinality
    for cardinality in zero one many; do
        materialize "$cardinality" "$root/$cardinality.json" >/dev/null
        assert_manifest "$cardinality" "$root/$cardinality.json"
    done
    if "$JQ" -e '(.osFixture.reminders | length) == 3' "$root/one.json" >/dev/null; then
        fail "wrong cardinality was accepted"
    fi
    "$JQ" '.osFixture.reminders[0].title = "https://private.invalid"' "$root/one.json" > "$root/private.json"
    if "$JQ" -e '([.osFixture.reminders[].title] | all(test("private|https?://"; "i") | not))' "$root/private.json" >/dev/null; then
        fail "private-looking Reminder title was accepted"
    fi
    local source_database="$root/source.sqlite" target_database="$root/target.sqlite"
    for database in "$source_database" "$target_database"; do
        "$SQLITE3" "$database" <<'SQL'
CREATE TABLE settings(key TEXT PRIMARY KEY, value_json TEXT NOT NULL, policy_version INTEGER NOT NULL, updated_at_utc TEXT NOT NULL);
CREATE TABLE policy_versions(policy_type TEXT NOT NULL, version INTEGER NOT NULL, payload_json TEXT NOT NULL, created_at_utc TEXT NOT NULL, is_active INTEGER NOT NULL);
SQL
    done
    "$SQLITE3" "$source_database" <<'SQL'
INSERT INTO settings VALUES('user_policy','{"schemaVersion":5}',7,'baseline-time');
INSERT INTO policy_versions VALUES('user_policy',7,'{"schemaVersion":5}','baseline-time',1);
SQL
    seed_policy "$source_database" "$target_database" >/dev/null
    [[ "$("$SQLITE3" "$target_database" "SELECT policy_version || '|' || value_json || '|' || updated_at_utc FROM settings WHERE key='user_policy';")" == '7|{"schemaVersion":5}|baseline-time' ]] \
        || fail "policy seed did not preserve baseline bytes and IDs"
    print -- "PASS: ZC-006-001 fixture self-test covered 0/1/many, uniqueness, and privacy sentinels"
)

case "$COMMAND" in
    materialize) (( $# == 3 )) || usage; materialize "$2" "$3" ;;
    assert-manifest) (( $# == 3 )) || usage; assert_manifest "$2" "$3" ;;
    seed-policy) (( $# == 3 )) || usage; seed_policy "$2" "$3" ;;
    configure-boundary) (( $# == 3 )) || usage; configure_boundary "$2" "$3" ;;
    assert-database) (( $# == 3 )) || usage; assert_database "$2" "$3" ;;
    assert-notification) (( $# == 4 )) || usage; assert_notification "$2" "$3" "$4" ;;
    self-test) (( $# == 1 )) || usage; self_test ;;
    *) usage ;;
esac
