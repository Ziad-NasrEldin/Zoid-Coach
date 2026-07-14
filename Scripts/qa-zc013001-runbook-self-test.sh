#!/bin/zsh

set -euo pipefail

readonly ROOT="${0:A:h:h}"
readonly RUNBOOK="$ROOT/docs/ZC-013-001-SIGNED-QA-RUNBOOK.md"
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

print -- "PASS: ZC-013-001 runbook declares executable zsh blocks and portable one-based array indexing"
