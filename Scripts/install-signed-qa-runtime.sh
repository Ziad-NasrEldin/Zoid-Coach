#!/bin/zsh

set -euo pipefail

QA_LAST_OPEN_STATUS=0

qa_logged_open_attempt() {
    local open_command="$1"
    local app_path="$2"
    local attempt_log="$3"
    local -a statuses

    if "$open_command" "$app_path" 2>&1 | tee "$attempt_log"; then
        statuses=("${pipestatus[@]}")
    else
        statuses=("${pipestatus[@]}")
    fi
    QA_LAST_OPEN_STATUS="${statuses[1]:-1}"
    return "$QA_LAST_OPEN_STATUS"
}

qa_installed_app_process_probe() {
    local executable_name="$1"
    local expected_path="$2"
    local -a pids
    pids=("${(@f)$(pgrep -x "$executable_name" 2>/dev/null || true)}")
    local pid executable
    for pid in "${pids[@]}"; do
        [[ -n "$pid" ]] || continue
        executable="$(lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' | head -n 1)"
        if [[ "$executable" == "$expected_path" ]]; then
            print -r -- "pid=$pid executable=$executable"
            return 0
        fi
    done
    return 1
}

qa_wait_for_launchservices_readiness() {
    local app_path="$1"
    local executable_name="$2"
    local executable_path="$app_path/Contents/MacOS/$executable_name"
    local open_command="${ZOID_COACH_QA_OPEN_COMMAND:-/usr/bin/open}"
    local process_probe="${ZOID_COACH_QA_PROCESS_PROBE_COMMAND:-qa_installed_app_process_probe}"
    local attempts="${ZOID_COACH_QA_OPEN_ATTEMPTS:-20}"
    local delay="${ZOID_COACH_QA_OPEN_DELAY_SECONDS:-0.25}"
    local log_root="${ZOID_COACH_QA_OPEN_LOG_ROOT:-${TMPDIR:-/private/tmp}}"
    local last_observation="not attempted"
    local last_log=""
    local attempt observation

    [[ "$attempts" == <-> && "$attempts" -gt 0 ]] \
        || { print -u2 "FAIL: invalid QA app-open attempt bound: $attempts"; return 1; }
    mkdir -p "$log_root"

    for attempt in {1..$attempts}; do
        last_log="$log_root/zoid-666-qa-open-attempt-$attempt.log"
        print -- "QA app-open attempt=$attempt/$attempts app=$app_path"
        if qa_logged_open_attempt "$open_command" "$app_path" "$last_log"; then
            last_observation="LaunchServices accepted open; installed process not yet observable"
            if observation="$($process_probe "$executable_name" "$executable_path" 2>&1)"; then
                print -r -- "PASS: LaunchServices opened installed signed QA app $observation"
                return 0
            fi
            [[ -n "$observation" ]] && last_observation="$observation"
        else
            last_observation="LaunchServices open failed with status $QA_LAST_OPEN_STATUS"
        fi
        [[ "$attempt" == "$attempts" ]] || sleep "$delay"
    done

    print -u2 -- "FAIL: installed signed QA app did not become LaunchServices-ready after $attempts attempts; last_open_status=$QA_LAST_OPEN_STATUS; last_observation=$last_observation; last_log=$last_log"
    return 1
}

qa_register_agent_with_readiness_retry() {
    local registration_command="$1"
    local exact_identity_probe="$2"
    local attempts="${ZOID_COACH_QA_REGISTRATION_ATTEMPTS:-2}"
    local retry_delay="${ZOID_COACH_QA_REGISTRATION_RETRY_DELAY_SECONDS:-1}"
    local pass_message="PASS: QA XPC runtime is writable and prompt timeline is available"

    [[ "$attempts" == <-> && "$attempts" -ge 1 && "$attempts" -le 3 ]] \
        || { print -u2 -- "FAIL: invalid QA registration attempt bound: $attempts"; return 2; }
    [[ "$retry_delay" =~ '^[0-9]+([.][0-9]+)?$' ]] \
        || { print -u2 -- "FAIL: invalid QA registration retry delay: $retry_delay"; return 2; }

    local attempt output command_status identity_output
    for attempt in {1..$attempts}; do
        print -- "QA registration_attempt=$attempt/$attempts"
        command_status=0
        output="$($registration_command 2>&1)" || command_status=$?
        print -r -- "$output"
        if (( command_status == 0 )) && grep -Fq "$pass_message" <<<"$output"; then
            return 0
        fi

        print -u2 -- "QA registration attempt $attempt did not become ready; command_status=$command_status"
        if (( attempt < attempts )); then
            if ! identity_output="$($exact_identity_probe 2>&1)"; then
                print -u2 -- "FAIL: refusing QA registration retry because exact helper identity/root could not be proven"
                [[ -n "$identity_output" ]] && print -u2 -r -- "$identity_output"
                return 1
            fi
            print -- "PASS: exact QA helper identity/root confirmed before retry $identity_output"
            sleep "$retry_delay"
        fi
    done

    print -u2 -- "FAIL: QA registration readiness exhausted after $attempts attempts"
    return 1
}

qa_installer_self_test() {
    local root
    root="$(mktemp -d /private/tmp/zoid-666-qa-installer-self-test.XXXXXX)"
    trap 'rm -rf "$root"' EXIT
    local success_open="$root/open-success"
    local failure_open="$root/open-609"
    local success_probe="$root/probe-success"
    local failure_probe="$root/probe-failure"

    print -r -- '#!/bin/zsh
exit 0' > "$success_open"
    print -r -- '#!/bin/zsh
print -u2 "_LSOpenURLsWithCompletionHandler() failed with error -609."
exit 73' > "$failure_open"
    print -r -- '#!/bin/zsh
print -r -- "pid=4242 executable=$2"
exit 0' > "$success_probe"
    print -r -- '#!/bin/zsh
exit 1' > "$failure_probe"
    chmod +x "$success_open" "$failure_open" "$success_probe" "$failure_probe"

    local success_output failure_output pipeline_status
    success_output="$(
        ZOID_COACH_QA_OPEN_COMMAND="$success_open" \
        ZOID_COACH_QA_PROCESS_PROBE_COMMAND="$success_probe" \
        ZOID_COACH_QA_OPEN_ATTEMPTS=1 \
        ZOID_COACH_QA_OPEN_DELAY_SECONDS=0 \
        ZOID_COACH_QA_OPEN_LOG_ROOT="$root/success-logs" \
        qa_wait_for_launchservices_readiness "$root/Test.app" TestExecutable
    )" || { print -u2 "SELF-TEST FAIL: success path"; return 1; }
    [[ "$success_output" == *"PASS: LaunchServices opened installed signed QA app"* ]] \
        || { print -u2 "SELF-TEST FAIL: success evidence"; return 1; }

    if qa_logged_open_attempt "$failure_open" "$root/Test.app" "$root/pipeline.log" >/dev/null; then
        print -u2 "SELF-TEST FAIL: failing open pipeline returned success"
        return 1
    else
        pipeline_status=$?
    fi
    [[ "$pipeline_status" == "73" && "$QA_LAST_OPEN_STATUS" == "73" ]] \
        || { print -u2 "SELF-TEST FAIL: underlying pipeline status was masked"; return 1; }

    if failure_output="$(
        ZOID_COACH_QA_OPEN_COMMAND="$failure_open" \
        ZOID_COACH_QA_PROCESS_PROBE_COMMAND="$failure_probe" \
        ZOID_COACH_QA_OPEN_ATTEMPTS=2 \
        ZOID_COACH_QA_OPEN_DELAY_SECONDS=0 \
        ZOID_COACH_QA_OPEN_LOG_ROOT="$root/failure-logs" \
        qa_wait_for_launchservices_readiness "$root/Test.app" TestExecutable 2>&1
    )"; then
        print -u2 "SELF-TEST FAIL: -609 path returned success"
        return 1
    fi
    [[ "$failure_output" == *"error -609"* && "$failure_output" == *"last_open_status=73"* ]] \
        || { print -u2 "SELF-TEST FAIL: -609 evidence or status missing"; return 1; }

    local delayed_calls="$root/delayed-registration-calls"
    print -r -- 0 > "$delayed_calls"
    qa_delayed_registration() {
        local calls="$(<"$delayed_calls")"
        (( calls += 1 ))
        print -r -- "$calls" > "$delayed_calls"
        if (( calls == 1 )); then
            print -u2 -- "FAIL: QA agent registered but did not expose a writable XPC prompt timeline and heartbeat"
            return 5
        fi
        print -- "PASS: QA XPC runtime is writable and prompt timeline is available"
    }
    qa_exact_delayed_identity() {
        print -- "pid=4242 executable=$root/ZoidCoachAgentQA qa_root=$root/qa"
    }
    local delayed_output
    if ! delayed_output="$(
        ZOID_COACH_QA_REGISTRATION_ATTEMPTS=2 \
        ZOID_COACH_QA_REGISTRATION_RETRY_DELAY_SECONDS=0 \
            qa_register_agent_with_readiness_retry \
                qa_delayed_registration qa_exact_delayed_identity
    )"; then
        print -u2 "SELF-TEST FAIL: delayed exact helper readiness was not recovered"
        return 1
    fi
    [[ "$(<"$delayed_calls")" == 2 ]] \
        || { print -u2 "SELF-TEST FAIL: delayed readiness did not use exactly two attempts"; return 1; }
    [[ "$delayed_output" == *"registration_attempt=1"* \
        && "$delayed_output" == *"registration_attempt=2"* \
        && "$delayed_output" == *"PASS: QA XPC runtime is writable and prompt timeline is available"* ]] \
        || { print -u2 "SELF-TEST FAIL: delayed readiness diagnostics are incomplete"; return 1; }

    print -r -- 0 > "$delayed_calls"
    qa_never_ready_registration() {
        local calls="$(<"$delayed_calls")"
        (( calls += 1 ))
        print -r -- "$calls" > "$delayed_calls"
        print -u2 -- "FAIL: simulated canceled XPC client"
        return 5
    }
    qa_wrong_identity() {
        print -u2 -- "pid=31337 executable=/tmp/wrong-agent qa_root=/tmp/wrong-root"
        return 1
    }
    if ZOID_COACH_QA_REGISTRATION_ATTEMPTS=2 \
        ZOID_COACH_QA_REGISTRATION_RETRY_DELAY_SECONDS=0 \
        qa_register_agent_with_readiness_retry \
            qa_never_ready_registration qa_wrong_identity >/dev/null 2>&1; then
        print -u2 "SELF-TEST FAIL: mismatched helper identity was accepted"
        return 1
    fi
    [[ "$(<"$delayed_calls")" == 1 ]] \
        || { print -u2 "SELF-TEST FAIL: registration retried after identity mismatch"; return 1; }

    qa_false_pass_registration() {
        print -- "PASS: QA XPC runtime is writable and prompt timeline is available"
        return 7
    }
    if ZOID_COACH_QA_REGISTRATION_ATTEMPTS=1 \
        qa_register_agent_with_readiness_retry \
            qa_false_pass_registration qa_exact_delayed_identity >/dev/null 2>&1; then
        print -u2 "SELF-TEST FAIL: nonzero registration command false-passed"
        return 1
    fi

    rm -rf "$root"
    trap - EXIT
    print -- "PASS: signed QA installer readiness self-tests"
}

if [[ "${1:-}" == "--self-test" ]]; then
    qa_installer_self_test
    exit $?
fi

ROOT="${0:A:h:h}"
source "$ROOT/Scripts/lib/signed-qa-runtime-lifecycle.sh"
IDENTITIES="$ROOT/App/PackageIdentities.plist"
QA_ROOT="${ZOID_COACH_QA_RUN_ROOT:-/private/tmp/zoid-666-signed-qa}"
INSTALL_ROOT="${ZOID_COACH_QA_INSTALL_ROOT:-$HOME/Applications}"
QA_ROOT="${QA_ROOT:A}"
INSTALL_ROOT="${INSTALL_ROOT:A}"
KEEP_EXISTING_DATA="${ZOID_COACH_QA_KEEP_DATA:-false}"
USER_DOMAIN="gui/$(id -u)"

identity_value() {
    /usr/libexec/PlistBuddy -c "Print :qa:$1" "$IDENTITIES"
}

PACKAGED_RELATIVE_PATH="$(identity_value appPath)"
PACKAGED_APP="$ROOT/$PACKAGED_RELATIVE_PATH"
DISPLAY_NAME="$(identity_value appDisplayName)"
APP_EXECUTABLE="$(identity_value appExecutableName)"
AGENT_EXECUTABLE="$(identity_value agentExecutableName)"
AGENT_LABEL="$(identity_value launchAgentLabel)"
INSTALLED_APP="$INSTALL_ROOT/$DISPLAY_NAME E2E.app"
STAGED_APP="$INSTALL_ROOT/.$DISPLAY_NAME E2E.installing.app"
BACKUP_APP="$INSTALL_ROOT/.$DISPLAY_NAME E2E.previous.app"

qa_recover_interrupted_replacement "$INSTALLED_APP" "$STAGED_APP" "$BACKUP_APP"

if [[ "$KEEP_EXISTING_DATA" != "true" ]]; then
    rm -rf "$QA_ROOT"
fi
mkdir -p "$QA_ROOT" "$INSTALL_ROOT"

ZOID_COACH_PACKAGE_MODE=qa ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" \
    "$ROOT/Scripts/package-app.sh" >/dev/null
qa_stage_app_replacement "$PACKAGED_APP" "$STAGED_APP"
codesign --verify --deep --strict --verbose=2 "$STAGED_APP" >/dev/null

qa_unregister_installed_agent "$INSTALLED_APP" "$APP_EXECUTABLE"
launchctl bootout "$USER_DOMAIN/$AGENT_LABEL" >/dev/null 2>&1 || true
pkill -x "$APP_EXECUTABLE" >/dev/null 2>&1 || true
qa_commit_app_replacement "$INSTALLED_APP" "$STAGED_APP" "$BACKUP_APP"

qa_invoke_installed_registration() {
    "$INSTALLED_APP/Contents/MacOS/$APP_EXECUTABLE" --qa-register-agent
}

qa_probe_exact_registered_agent() {
    local agent_path="$INSTALLED_APP/Contents/MacOS/$AGENT_EXECUTABLE"
    local service pid executable process_environment
    for _ in {1..30}; do
        service="$(launchctl print "$USER_DOMAIN/$AGENT_LABEL" 2>/dev/null || true)"
        pid="$(awk '/pid =/{print $3; exit}' <<<"$service")"
        if [[ -n "$pid" ]]; then
            executable="$(lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' | head -n 1)"
            process_environment="$(ps eww -p "$pid" -o command= 2>/dev/null || true)"
            [[ "$executable" == "$agent_path" ]] \
                || { print -u2 -- "helper executable mismatch: pid=$pid executable=$executable expected=$agent_path"; return 1; }
            grep -Fq "name = $AGENT_LABEL" <<<"$service" \
                || { print -u2 -- "helper service label mismatch: expected=$AGENT_LABEL"; return 1; }
            [[ " $process_environment " == *" ZOID_COACH_QA_RUN_ROOT=$QA_ROOT "* ]] \
                || { print -u2 -- "helper QA root mismatch: pid=$pid expected=$QA_ROOT"; return 1; }
            print -- "pid=$pid executable=$executable qa_root=$QA_ROOT"
            return 0
        fi
        sleep 0.2
    done
    print -u2 -- "exact QA helper process did not become available for readiness retry"
    return 1
}

registration_output=""
if ! registration_output="$(
    qa_register_agent_with_readiness_retry \
        qa_invoke_installed_registration qa_probe_exact_registered_agent
)"; then
    "$INSTALLED_APP/Contents/MacOS/$APP_EXECUTABLE" --qa-unregister-agent || true
    qa_rollback_app_replacement "$INSTALLED_APP" "$BACKUP_APP"
    if [[ -x "$INSTALLED_APP/Contents/MacOS/$APP_EXECUTABLE" ]]; then
        "$INSTALLED_APP/Contents/MacOS/$APP_EXECUTABLE" --qa-register-agent || true
    fi
    print -u2 "FAIL: QA LaunchAgent registration failed; the previous installed app was restored"
    exit 1
fi
print -r -- "$registration_output"
if ! grep -Fq "PASS: QA XPC runtime is writable and prompt timeline is available" <<<"$registration_output"; then
    "$INSTALLED_APP/Contents/MacOS/$APP_EXECUTABLE" --qa-unregister-agent || true
    qa_rollback_app_replacement "$INSTALLED_APP" "$BACKUP_APP"
    print -u2 "FAIL: QA LaunchAgent registered without a writable XPC prompt timeline"
    exit 1
fi

agent_path="$INSTALLED_APP/Contents/MacOS/$AGENT_EXECUTABLE"
service=""
for _ in {1..30}; do
    service="$(launchctl print "$USER_DOMAIN/$AGENT_LABEL" 2>/dev/null || true)"
    pid="$(awk '/pid =/{print $3; exit}' <<<"$service")"
    if [[ -n "$pid" ]]; then
        executable="$(lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -F "$AGENT_EXECUTABLE" || true)"
        if [[ "$executable" == "$agent_path" ]] && grep -Fq "name = $AGENT_LABEL" <<<"$service"; then
            break
        fi
    fi
    sleep 0.2
done

if [[ "${executable:-}" != "$agent_path" ]]; then
    "$INSTALLED_APP/Contents/MacOS/$APP_EXECUTABLE" --qa-unregister-agent || true
    qa_rollback_app_replacement "$INSTALLED_APP" "$BACKUP_APP"
    print -u2 "FAIL: QA LaunchAgent did not start from the installed signed app"
    print -u2 "$service"
    exit 1
fi

database="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
heartbeat=""
for _ in {1..30}; do
    if [[ -f "$database" ]]; then
        heartbeat="$(sqlite3 "$database" "SELECT last_success_at_utc FROM processing_checkpoints WHERE source_id = 'agent-runtime' LIMIT 1;" 2>/dev/null || true)"
        [[ -n "$heartbeat" ]] && break
    fi
    sleep 0.2
done
if [[ -z "$heartbeat" ]]; then
    "$INSTALLED_APP/Contents/MacOS/$APP_EXECUTABLE" --qa-unregister-agent || true
    qa_rollback_app_replacement "$INSTALLED_APP" "$BACKUP_APP"
    print -u2 "FAIL: QA LaunchAgent did not publish a canonical runtime heartbeat"
    exit 1
fi
if ! qa_wait_for_launchservices_readiness "$INSTALLED_APP" "$APP_EXECUTABLE"; then
    pkill -x "$APP_EXECUTABLE" >/dev/null 2>&1 || true
    "$INSTALLED_APP/Contents/MacOS/$APP_EXECUTABLE" --qa-unregister-agent || true
    qa_rollback_app_replacement "$INSTALLED_APP" "$BACKUP_APP"
    if [[ -x "$INSTALLED_APP/Contents/MacOS/$APP_EXECUTABLE" ]]; then
        "$INSTALLED_APP/Contents/MacOS/$APP_EXECUTABLE" --qa-register-agent || true
    fi
    print -u2 "FAIL: QA runtime installation rolled back because the installed app was not LaunchServices-ready"
    exit 1
fi

rm -rf "$BACKUP_APP"

cat <<EOF
PASS: signed QA runtime installed
app=$INSTALLED_APP
qa_root=$QA_ROOT
agent_label=$AGENT_LABEL
agent_executable=$agent_path
EOF
