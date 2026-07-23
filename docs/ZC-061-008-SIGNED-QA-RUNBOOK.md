# ZC-061-008 signed QA runbook

This runbook proves that a persisted Safari to Work future rule classifies only later matching Screenwatch observations ingested by the installed helper.
The signed candidate must be a direct child of `8c9e007d467fe2b5388e151914a559a8245d18ed` and contain exactly the six proof-tooling paths enforced by the static verifier.
Historical raw activity must remain Unknown while its saved correction remains Work.
Never invent or display a Research classification.
Stop on the first failed assertion.

## Bind the candidate and isolated helper runtime

Use a clean signed QA app with a new `/private/tmp/zoid-666-zc061008-*` root.
Close unrelated copies of Zoid 666 and grant Accessibility permission to the terminal running the probe.

```sh
set -euo pipefail
APP="/absolute/path/to/Zoid 666 QA E2E.app"
CANDIDATE_REPOSITORY="/absolute/path/to/clean/detached/ZC-061-008-candidate"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_CANDIDATE_COMMIT"
QA_ROOT="/private/tmp/zoid-666-zc061008-installed-proof"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
SCREENWATCH_ROOT="$QA_ROOT/Screenwatch/days"
BASELINE_ROOT="/private/tmp/zoid-666-zc061008-baseline"
FIXTURE="$PWD/Scripts/qa-zc061008-future-rule-fixture.sh"
PROBE="$PWD/Scripts/qa-zc061008-future-rule-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc061008-signed-preflight.sh"
STATIC="$PWD/Scripts/verify-zc-061-008-future-rule-static.sh"
"$STATIC"
"$PREFLIGHT" --candidate-repository "$CANDIDATE_REPOSITORY" --validate-candidate "$EXPECTED_SIGNED_COMMIT"
OUTPUT="$("$PREFLIGHT" --candidate-repository "$CANDIDATE_REPOSITORY" "$APP" "$DATABASE" "$SCREENWATCH_ROOT" "$EXPECTED_SIGNED_COMMIT")"
printf '%s\n' "$OUTPUT"
AGENT_EXECUTABLE="$(printf '%s\n' "$OUTPUT" | sed -n 's/^AGENT_EXECUTABLE=//p')"
test -x "$AGENT_EXECUTABLE"
```

The validator may live in a later review checkout, but `CANDIDATE_REPOSITORY` must be the clean detached worktree at the reviewed corrected tip.
The preflight binds the required parent, exact six-file commit scope, embedded database, Screenwatch source, QA root, and installed helper identity.
It also confirms that the existing installed helper exposes the bounded `--once` path.

## Stop the app and capture the byte baseline

The baseline is authoritative for final restoration.

```sh
set -euo pipefail
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
"$APP_EXECUTABLE" --qa-unregister-agent || true
pkill -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true
rm -rf -- "$BASELINE_ROOT" "$BASELINE_ROOT.zc061008-target" "$BASELINE_ROOT.zc061008-manifest" "$BASELINE_ROOT.zc061008-restored-manifest"
"$FIXTURE" snapshot-root "$QA_ROOT" "$BASELINE_ROOT"
```

The fixture refuses roots outside the isolated ZC-061-008 namespace and records file hashes and symlink targets.

## Define the installed-helper phases

Every phase restores the same byte baseline before seeding evidence.
The private title and URL sentinels must remain absent from prompt and AX output.

```sh
set -euo pipefail
run_phase() {
  local phase="$1"
  local helper_runs="${2:-1}"
  "$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
  "$FIXTURE" prepare "$phase" "$DATABASE" "$SCREENWATCH_ROOT"
  for _ in $(seq 1 "$helper_runs"); do
    env -i HOME="$HOME" PATH="/usr/bin:/bin" "$AGENT_EXECUTABLE" --once
  done
  "$FIXTURE" assert-result "$phase" "$DATABASE" "$SCREENWATCH_ROOT"
}

find_app_pid() {
  local pid
  for _ in {1..50}; do
    for pid in ${(f)"$(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true)"}; do
      if lsof -Fn -a -p "$pid" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
        printf '%s\n' "$pid"
        return 0
      fi
    done
    sleep 0.1
  done
  return 1
}
```

The helper invocation above is the installed production executable, not a test double.

## Prove the qualifying rule and UI

Run the helper twice over the same later Safari observation.
The second run must insert nothing.

```sh
set -euo pipefail
run_phase qualifying 2
open -n "$APP" --args --qa-open-main
PID="$(find_app_pid)"
swift "$PROBE" --pid "$PID"
kill "$PID"
while kill -0 "$PID" 2>/dev/null; do sleep 0.1; done
```

The database must contain one historical raw Unknown observation, one historical Work correction, one active Safari to Work rule, and one later raw Work observation.
The Reviews UI must show two distinct Safari Work sessions plus the visible active future-rule badge and `Historical records are unchanged.`
The AX probe rejects raw title or URL sentinels and any Research wording.

## Prove temporal, matching, and removal boundaries

Each boundary must ingest exactly one future fixture row as raw Unknown while preserving the historical raw observation and correction.

```sh
set -euo pipefail
run_phase pre-effective
run_phase nonmatching
run_phase removed-rule
```

The pre-effective Safari observation predates the rule.
The nonmatching observation uses another application.
The removed-rule phase persists a newer tombstone before ingestion and requires zero active rules.

## Run the focused source journey

This is a focused future test only, not a broad build, package, install, or release gate.

```sh
set -euo pipefail
swift test --filter zc061008
```

The focused test covers later matching ingestion, a second idempotent ingestion, pre-effective, nonmatching, removed-rule, and invalid-rule-schema failure behavior.

## Restore the exact root

Stop every process using the isolated root before restoration.

```sh
set -euo pipefail
"$APP_EXECUTABLE" --qa-unregister-agent || true
pkill -x "$APP_EXECUTABLE_NAME" 2>/dev/null || true
"$FIXTURE" restore-root "$QA_ROOT" "$BASELINE_ROOT"
"$FIXTURE" assert-root-restored "$QA_ROOT" "$BASELINE_ROOT"
rm -rf -- "$BASELINE_ROOT" "$BASELINE_ROOT.zc061008-target" "$BASELINE_ROOT.zc061008-manifest" "$BASELINE_ROOT.zc061008-restored-manifest"
```

Do not update the scenario registry or tracker from an incomplete run.
This proof tooling does not claim the signed installed-app journey until every database, helper, AX, privacy, and exact-restoration assertion passes.
