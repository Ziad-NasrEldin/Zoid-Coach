# ZC-048-010 signed QA runbook

This runbook verifies that a user can review and export a privacy-safe diagnostic package from one exact installed signed Zoid 666 candidate.
Every log, screenshot, fixture package, and generated manifest remains outside the repository.
Do not create `.audit`, `.lavish`, tracker, registry, or other repository evidence while running this acceptance flow.

## Prepare the isolated signed candidate

Start from a clean repository containing the exact signed commit.
The candidate must descend from canonical base `ed5d07a363e0f64049c07b0e1d309d754caa035b` and contain the exact reviewed raw patch sequence enforced by the signed preflight.
Grant Accessibility permission to the terminal that runs the AX probe.

```sh
QA_ROOT="/private/tmp/zoid-666-zc048010-runtime"
INSTALL_ROOT="/private/tmp/zoid-666-zc048010-install"
EXPECTED_SIGNED_COMMIT="FULL_40_CHARACTER_SIGNED_COMMIT"
EVIDENCE_ROOT="/private/tmp/zoid-zc048010-evidence/$EXPECTED_SIGNED_COMMIT"
APP="$INSTALL_ROOT/Zoid 666 QA E2E.app"
DATABASE="$QA_ROOT/Application Support/Zoid 666/zoid-coach.sqlite"
PACKAGE="$EVIDENCE_ROOT/Fresh.zoiddiagnostics"
EXISTING_PACKAGE="$EVIDENCE_ROOT/Existing.zoiddiagnostics"
RETRY_PACKAGE="$EVIDENCE_ROOT/Retry.zoiddiagnostics"
FIXTURE="$PWD/Scripts/qa-zc048010-diagnostic-package-fixture.sh"
PROBE="$PWD/Scripts/qa-zc048010-diagnostic-package-ax-probe.swift"
PREFLIGHT="$PWD/Scripts/qa-zc048010-signed-preflight.sh"
READY_STATE="$PWD/Scripts/prepare-qa-ready-state.py"
READY_MANIFEST="$PWD/Scripts/fixtures/qa-ready-state.example.json"
test "${EVIDENCE_ROOT#"$PWD"/}" = "$EVIDENCE_ROOT"
"$FIXTURE" self-test
"$PROBE" --self-test
"$PREFLIGHT" --self-test
git status --short --branch
test -z "$(git status --porcelain)"
mkdir -p "$EVIDENCE_ROOT"
exec > >(tee -a "$EVIDENCE_ROOT/runbook.log") 2>&1
ZOID_COACH_QA_RUN_ROOT="$QA_ROOT" \
ZOID_COACH_QA_INSTALL_ROOT="$INSTALL_ROOT" \
  Scripts/install-signed-qa-runtime.sh
APP_EXECUTABLE_NAME="$(plutil -extract CFBundleExecutable raw -o - "$APP/Contents/Info.plist")"
APP_EXECUTABLE="$APP/Contents/MacOS/$APP_EXECUTABLE_NAME"
"$APP_EXECUTABLE" --qa-unregister-agent
for candidate in $(pgrep -x "$APP_EXECUTABLE_NAME" 2>/dev/null); do
  if lsof -Fn -a -p "$candidate" -d txt 2>/dev/null | sed -n 's/^n//p' | grep -Fqx "$APP_EXECUTABLE"; then
    kill "$candidate"
    while kill -0 "$candidate" 2>/dev/null; do sleep 0.1; done
  fi
done
"$READY_STATE" "$READY_MANIFEST" "$QA_ROOT" --replace
open "$APP" --args --qa-open-main
PREFLIGHT_OUTPUT="$("$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" "$EVIDENCE_ROOT" \
  --require-qa-open-main --require-helper-unregistered \
  --wait-for-foreground-database)"
printf '%s\n' "$PREFLIGHT_OUTPUT"
PID="$(printf '%s\n' "$PREFLIGHT_OUTPUT" | sed -n 's/^APP_PID=//p')"
test -n "$PID"
"$APP_EXECUTABLE" --qa-register-agent
"$PREFLIGHT" "$APP" "$DATABASE" "$EXPECTED_SIGNED_COMMIT" "$EVIDENCE_ROOT" \
  --require-qa-open-main --expected-app-pid "$PID"
```

The initial helper-absent preflight waits up to 30 seconds for the exact foreground PID to create the isolated database and for SQLite to open it read-only.
It fails immediately if the PID exits, changes executable identity, or points at a database outside the embedded QA root, and it fails at the bounded timeout if the database never becomes readable.

Do not continue unless the preflight binds the foreground app, helper, database, QA root, signed commit, and external evidence root.

## Review the complete package contract

Open Settings and Records through normal accessible controls.
The preview must name all three files and every privacy exclusion before the save action becomes relevant.

```sh
swift "$PROBE" --pid "$PID" --phase preview
screencapture -x "$EVIDENCE_ROOT/01-preview.png"
```

Acceptance requires `README.txt`, `manifest.json`, and `counts.json` in the preview.
Acceptance also requires Task and event titles, Conversation text, URLs and file paths, Screenshots, Request payloads, and Credentials in the exclusion label.

## VoiceOver contract and cancellation

Turn VoiceOver on and navigate to the diagnostic package preview and save button without using the pointer.
VoiceOver must announce the three-file summary, every exclusion, and `Save reviewed diagnostic package` in a logical order.
Record the spoken result in an external note and capture the visible focus state.

```sh
printf '%s\n' "VoiceOver announced the complete preview and reviewed save action." >"$EVIDENCE_ROOT/voiceover.txt"
screencapture -x "$EVIDENCE_ROOT/02-voiceover-focus.png"
rm -rf "$PACKAGE"
swift "$PROBE" --pid "$PID" --phase cancel
test ! -e "$PACKAGE"
screencapture -x "$EVIDENCE_ROOT/03-cancelled.png"
```

Cancellation must dismiss the native save panel without creating a package or sending an export request.

## Seed private local evidence

The fixture writes only namespaced records to the isolated QA database.
These private sentinel values must remain absent from every package file.

```sh
"$FIXTURE" prepare "$DATABASE"
"$FIXTURE" assert-prepared "$DATABASE"
```

## Save a fresh package through the signed helper

The AX probe invokes the visible Settings action, chooses the external destination, and waits for the signed helper XPC export to create the package.

```sh
rm -rf "$PACKAGE"
swift "$PROBE" --pid "$PID" --phase save --destination "$PACKAGE"
"$FIXTURE" assert-package "$DATABASE" "$PACKAGE"
find "$PACKAGE" -maxdepth 1 -type f -print -exec shasum -a 256 {} \; \
  | tee "$EVIDENCE_ROOT/04-package-hashes.txt"
screencapture -x "$EVIDENCE_ROOT/04-exported.png"
```

The package must contain exactly three reviewed files.
The manifest must list the same files, the counts file must remain valid JSON, and no fixture sentinel may appear anywhere in the package.

## Existing-destination rejection

Create an existing namespaced destination and prove that the export fails without modifying or deleting it.

```sh
rm -rf "$EXISTING_PACKAGE"
mkdir "$EXISTING_PACKAGE"
printf '%s\n' "preserve me" >"$EXISTING_PACKAGE/existing-sentinel.txt"
BEFORE_HASH="$(shasum -a 256 "$EXISTING_PACKAGE/existing-sentinel.txt" | awk '{print $1}')"
swift "$PROBE" --pid "$PID" --phase existing --destination "$EXISTING_PACKAGE"
AFTER_HASH="$(shasum -a 256 "$EXISTING_PACKAGE/existing-sentinel.txt" | awk '{print $1}')"
test "$BEFORE_HASH" = "$AFTER_HASH"
screencapture -x "$EVIDENCE_ROOT/05-existing-rejected.png"
```

The Settings status must report that the background request could not complete.
The pre-existing sentinel must remain byte-identical.

## Fresh retry

Remove only the rejected namespaced destination and retry with a new path.

```sh
rm -rf "$EXISTING_PACKAGE" "$RETRY_PACKAGE"
swift "$PROBE" --pid "$PID" --phase save --destination "$RETRY_PACKAGE"
"$FIXTURE" assert-package "$DATABASE" "$RETRY_PACKAGE"
screencapture -x "$EVIDENCE_ROOT/06-retry-succeeded.png"
```

The fresh retry must succeed without restarting the app or helper.

## Finder reveal

The successful export must activate Finder and select the exact package produced by the signed helper.

```sh
swift "$PROBE" --pid "$PID" --phase finder --destination "$RETRY_PACKAGE"
screencapture -x "$EVIDENCE_ROOT/07-finder-reveal.png"
```

Do not accept a Finder window that merely shows the parent directory without exposing the exact package name.

## Cleanup and acceptance boundary

Remove only the namespaced database rows and temporary packages after copying required hashes and screenshots to the external evidence root.

```sh
"$FIXTURE" cleanup "$DATABASE"
rm -rf "$PACKAGE" "$EXISTING_PACKAGE" "$RETRY_PACKAGE"
"$APP_EXECUTABLE" --qa-unregister-agent
kill "$PID"
git status --short --branch | tee "$EVIDENCE_ROOT/final-git-status.txt"
test -z "$(git status --porcelain)"
```

Do not mark ZC-048-010 fully usable unless the same signed commit passes identity binding, preview, VoiceOver, cancellation, private fixture, fresh export, exact package inspection, existing-destination rejection, fresh retry, Finder reveal, and cleanup without repository evidence or source changes.
