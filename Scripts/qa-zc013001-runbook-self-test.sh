#!/bin/zsh

set -euo pipefail

readonly ROOT="${0:A:h:h}"
readonly RUNBOOK="$ROOT/docs/ZC-013-001-SIGNED-QA-RUNBOOK.md"
readonly LINEAGE_PREFLIGHT="$ROOT/Scripts/qa-zc013001-lineage-preflight.sh"
readonly DECLARED_SHELL="zsh"

fail() {
    print -u2 -- "FAIL: ZC-013-001 runbook self-test: $1"
    exit 1
}

readonly TEMP_ROOT="$(mktemp -d /private/tmp/zoid-666-zc013001-runbook.XXXXXX)"
trap 'rm -rf "$TEMP_ROOT"' EXIT

awk -v root="$TEMP_ROOT" '
    /^```zsh$/ {
        block += 1
        output = root "/block-" block ".zsh"
        inside = 1
        next
    }
    /^```$/ && inside {
        inside = 0
        close(output)
        next
    }
    inside { print > output }
    END {
        if (inside) exit 2
        print block > (root "/block-count")
    }
' "$RUNBOOK" || fail "could not extract complete $DECLARED_SHELL blocks"

readonly BLOCK_COUNT="$(<"$TEMP_ROOT/block-count")"
(( BLOCK_COUNT > 0 )) || fail "runbook declares no $DECLARED_SHELL blocks"
! grep -Fqx '```sh' "$RUNBOOK" || fail "runbook contains an undeclared generic sh block"

typeset block
typeset syntax_output
for block in "$TEMP_ROOT"/block-*.zsh(N); do
    {
        cat "$block"
        print -- "true"
    } > "$TEMP_ROOT/check-${block:t}"
    syntax_output="$(/bin/zsh -n "$TEMP_ROOT/check-${block:t}" 2>&1)" || {
        [[ -z "$syntax_output" ]] \
            || fail "declared $DECLARED_SHELL block is not valid zsh: ${block:t}: $syntax_output"
    }
done

contains_zero_based_array_index() {
    grep -En '\$\{?[A-Za-z_][A-Za-z0-9_]*\[0\]\}?' "$1"
}

if contains_zero_based_array_index "$RUNBOOK" > "$TEMP_ROOT/zero-index.txt"; then
    cat "$TEMP_ROOT/zero-index.txt" >&2
    fail "runbook uses zero-based array indexing under zsh"
fi

cp "$RUNBOOK" "$TEMP_ROOT/invalid-zero-index.md"
print -r -- '${AGENT_PLISTS[0]}' >> "$TEMP_ROOT/invalid-zero-index.md"
contains_zero_based_array_index "$TEMP_ROOT/invalid-zero-index.md" >/dev/null \
    || fail "zero-based zsh array guard did not reject a known-invalid fixture"

contains_unsafe_test_glob() {
    grep -En '(^|[[:space:]])test[[:space:]].*(=|!=)[[:space:]]+\*' "$1"
}

if contains_unsafe_test_glob "$RUNBOOK" > "$TEMP_ROOT/unsafe-test-glob.txt"; then
    cat "$TEMP_ROOT/unsafe-test-glob.txt" >&2
    fail "runbook uses an unquoted glob operand with test under zsh"
fi

cp "$RUNBOOK" "$TEMP_ROOT/invalid-test-glob.md"
print -r -- 'test "$command_line" != *--qa-open-main*' >> "$TEMP_ROOT/invalid-test-glob.md"
contains_unsafe_test_glob "$TEMP_ROOT/invalid-test-glob.md" >/dev/null \
    || fail "unsafe test glob guard did not reject a known-invalid fixture"

awk '
    /^# BEGIN RUNBOOK SELF-TEST: launch-agent-array$/ { inside = 1; next }
    /^# END RUNBOOK SELF-TEST: launch-agent-array$/ { inside = 0; exit }
    inside { print }
' "$RUNBOOK" > "$TEMP_ROOT/launch-agent-array.zsh"
test -s "$TEMP_ROOT/launch-agent-array.zsh" || fail "portable LaunchAgent block was not found"

readonly FAKE_APP="$TEMP_ROOT/Test.app"
mkdir -p "$FAKE_APP/Contents/Library/LaunchAgents"
touch "$FAKE_APP/Contents/Library/LaunchAgents/test.agent.plist"
{
    print -r -- "APP=${(q)FAKE_APP}"
    cat "$TEMP_ROOT/launch-agent-array.zsh"
    print -r -- 'test "$AGENT_PLIST" = "$APP/Contents/Library/LaunchAgents/test.agent.plist"'
} > "$TEMP_ROOT/execute-launch-agent-array.zsh"
/bin/zsh "$TEMP_ROOT/execute-launch-agent-array.zsh" \
    || fail "extracted LaunchAgent block failed under declared $DECLARED_SHELL"

awk '
    /^# BEGIN RUNBOOK SELF-TEST: ordinary-launch-command$/ { inside = 1; next }
    /^# END RUNBOOK SELF-TEST: ordinary-launch-command$/ { inside = 0; exit }
    inside { print }
' "$RUNBOOK" > "$TEMP_ROOT/ordinary-launch-command.zsh"
test -s "$TEMP_ROOT/ordinary-launch-command.zsh" || fail "ordinary-launch command predicate was not found"
{
    cat "$TEMP_ROOT/ordinary-launch-command.zsh"
    print -r -- 'ordinary_launch_command_is_valid "/Applications/Zoid 666 QA.app/Contents/MacOS/ZoidCoachQA"'
    print -r -- '! ordinary_launch_command_is_valid "/Applications/Zoid 666 QA.app/Contents/MacOS/ZoidCoachQA --qa-open-main"'
    print -r -- '! ordinary_launch_command_is_valid "/Applications/Zoid 666 QA.app/Contents/MacOS/ZoidCoachQA --background-schedule"'
    print -r -- '! ordinary_launch_command_is_valid "/Applications/Zoid 666 QA.app/Contents/MacOS/ZoidCoachQA --qa-open-main --background-schedule"'
} > "$TEMP_ROOT/execute-ordinary-launch-command.zsh"
/bin/zsh "$TEMP_ROOT/execute-ordinary-launch-command.zsh" \
    || fail "ordinary-launch predicate did not accept and reject representative command lines under zsh"

awk '
    /^# BEGIN RUNBOOK SELF-TEST: database-readiness$/ { inside = 1; next }
    /^# END RUNBOOK SELF-TEST: database-readiness$/ { inside = 0; exit }
    inside { print }
' "$RUNBOOK" > "$TEMP_ROOT/database-readiness.zsh"
test -s "$TEMP_ROOT/database-readiness.zsh" || fail "database readiness helper was not found"
readonly DATABASE_WAIT_CALLS="$(grep -Fxc '  wait_for_exact_database "$pid" "$DATABASE"' "$RUNBOOK")"
(( DATABASE_WAIT_CALLS == 2 )) \
    || fail "database readiness helper must guard every ordinary state and relaunch path"

{
    cat "$TEMP_ROOT/database-readiness.zsh"
    cat <<'ZSH'
EXPECTED_DATABASE="/private/tmp/expected/Application Support/Zoid 666/zoid-coach.sqlite"
COUNTER_FILE="$TEST_ROOT/counter"
print 0 > "$COUNTER_FILE"
process_is_alive() { [[ "$1" == 4242 ]] }
open_zoid_databases() {
    local count="$(<"$COUNTER_FILE")"
    (( count += 1 ))
    print "$count" > "$COUNTER_FILE"
    (( count >= 3 )) && print -r -- "$EXPECTED_DATABASE"
    return 0
}
sleep() { : }
wait_for_exact_database 4242 "$EXPECTED_DATABASE" 4 0

open_zoid_databases() { return 0 }
! wait_for_exact_database 4242 "$EXPECTED_DATABASE" 2 0

process_is_alive() { return 1 }
! wait_for_exact_database 4242 "$EXPECTED_DATABASE" 2 0

process_is_alive() { return 0 }
open_zoid_databases() { print -r -- "/private/tmp/wrong/Application Support/Zoid 666/zoid-coach.sqlite" }
! wait_for_exact_database 4242 "$EXPECTED_DATABASE" 2 0
ZSH
} > "$TEMP_ROOT/execute-database-readiness.zsh"
TEST_ROOT="$TEMP_ROOT" /bin/zsh "$TEMP_ROOT/execute-database-readiness.zsh" \
    || fail "database readiness helper failed delayed-open or rejection cases under zsh"

awk '
    /^# BEGIN RUNBOOK SELF-TEST: database-quiescence$/ { inside = 1; next }
    /^# END RUNBOOK SELF-TEST: database-quiescence$/ { inside = 0; exit }
    inside { print }
' "$RUNBOOK" > "$TEMP_ROOT/database-quiescence.zsh"
test -s "$TEMP_ROOT/database-quiescence.zsh" || fail "database quiescence helper was not found"
readonly STOP_CALLS="$(grep -Ec '^[[:space:]]*stop_exact_app$' "$RUNBOOK")"
readonly QUIESCENCE_CALLS="$(grep -Ec '^[[:space:]]*wait_for_database_quiescence "\$DATABASE"$' "$RUNBOOK")"
(( STOP_CALLS == QUIESCENCE_CALLS )) \
    || fail "every exact app stop must wait for isolated database quiescence"
{
    cat "$TEMP_ROOT/database-quiescence.zsh"
    cat <<'ZSH'
COUNTER_FILE="$TEST_ROOT/quiescence-counter"
print 0 > "$COUNTER_FILE"
database_has_open_process() {
    local count="$(<"$COUNTER_FILE")"
    (( count += 1 ))
    print "$count" > "$COUNTER_FILE"
    (( count < 3 ))
}
sleep() { : }
wait_for_database_quiescence "/private/tmp/expected/zoid-coach.sqlite" 4 0

database_has_open_process() { return 0 }
! wait_for_database_quiescence "/private/tmp/expected/zoid-coach.sqlite" 2 0
ZSH
} > "$TEMP_ROOT/execute-database-quiescence.zsh"
TEST_ROOT="$TEMP_ROOT" /bin/zsh "$TEMP_ROOT/execute-database-quiescence.zsh" \
    || fail "database quiescence helper failed delayed-release or timeout cases under zsh"

awk '
    /^# BEGIN RUNBOOK SELF-TEST: failure-cleanup$/ { inside = 1; next }
    /^# END RUNBOOK SELF-TEST: failure-cleanup$/ { inside = 0; exit }
    inside { print }
' "$RUNBOOK" > "$TEMP_ROOT/failure-cleanup.zsh"
test -s "$TEMP_ROOT/failure-cleanup.zsh" || fail "failure cleanup trap was not found"
grep -Fq 'local exit_code=$?' "$TEMP_ROOT/failure-cleanup.zsh" \
    || fail "failure cleanup must preserve the incoming exit code in a non-reserved variable"
! grep -Eq '(^|[[:space:]])(local|typeset)[[:space:]]+status=' "$TEMP_ROOT/failure-cleanup.zsh" \
    || fail "failure cleanup assigns zsh reserved variable status"

cp "$TEMP_ROOT/failure-cleanup.zsh" "$TEMP_ROOT/invalid-failure-cleanup.zsh"
print -r -- 'cleanup_invalid() { local status=$?; }' >> "$TEMP_ROOT/invalid-failure-cleanup.zsh"
grep -Eq '(^|[[:space:]])(local|typeset)[[:space:]]+status=' "$TEMP_ROOT/invalid-failure-cleanup.zsh" \
    || fail "reserved cleanup variable guard did not reject a known-invalid fixture"

grep -Fq '"$LINEAGE_PREFLIGHT" --expected-commit "$EXPECTED_SIGNED_COMMIT"' "$RUNBOOK" \
    || fail "runbook does not bind the exact signed commit through the lineage preflight"
"$LINEAGE_PREFLIGHT" --self-test >/dev/null \
    || fail "lineage preflight negative cases failed"

print -- "PASS: ZC-013-001 runbook validates lineage, zsh portability, launch predicates, database readiness, quiescence, and failure cleanup"
